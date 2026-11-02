-module(p56_api).
%% Handlers REST de la API. Despachados desde p56_router:init/2.

-export([handle/2]).

handle(Req, metrics) ->
  metrics(Req);
handle(Req, sismos) ->
  sismos(Req);
handle(Req, eventos_raw) ->
  eventos_raw(Req);
handle(Req, alertas) ->
  alertas(Req);
handle(Req, procesos) ->
  procesos(Req);
handle(Req, resumen) ->
  resumen(Req);
handle(Req, fuentes) ->
  fuentes(Req);
handle(Req, api_eventos) ->
  api_eventos(Req);
handle(Req, api_simular) ->
  api_simular(Req);
handle(Req, _) ->
  p56_router:error_resp(404, <<"ruta no conocida">>, Req).

%% ------------------------------------------------------------------
%% GET /metrics
%% ------------------------------------------------------------------

metrics(Req) ->
  Bin = prometheus_text_format:format(),
  cowboy_req:reply(
    200,
    #{<<"content-type">> => <<"text/plain; version=0.0.4; charset=utf-8">>},
    Bin, Req).

%% ------------------------------------------------------------------
%% GET /api/sismos?min_mag=M
%% ------------------------------------------------------------------

sismos(Req) ->
  MinMag = p56_router:float_qs(Req, <<"min_mag">>),
  Sismos = p56_dedupe:listar(MinMag),
  Json = json:encode(#{ok => true, sismos => [sismo_json(S) || S <- Sismos]}),
  p56_router:json_resp(Json, Req).

sismo_json(Sismo) ->
  Mag = maps:get(mag, Sismo),
  Dist = maps:get(sitio_dist_km, Sismo, 0.0),
  #{id           => maps:get(id, Sismo),
    mag          => Mag,
    mag_max      => maps:get(mag_max, Sismo, Mag),
    lugar        => maps:get(lugar, Sismo),
    prof_km      => maps:get(prof_km, Sismo, 0),
    lat          => maps:get(lat, Sismo),
    lon          => maps:get(lon, Sismo),
    t            => maps:get(t, Sismo),
    revisiones   => maps:get(revisiones, Sismo, 0),
    fuentes      => maps:get(fuentes, Sismo, []),
    sitio        => maps:get(sitio, Sismo, none),
    sitio_dist_km => Dist,
    nivel        => maps:get(nivel, Sismo, none),
    pga_g        => round2(p56_niveles:pga_g(Mag, Dist)),
    mercalli     => p56_niveles:mercalli(p56_niveles:pga_g(Mag, Dist))}.

round2(X) ->
  round(X * 100) / 100.

%% ------------------------------------------------------------------
%% GET /api/eventos_raw?limit= (buffer vivo del dashboard)
%% ------------------------------------------------------------------

eventos_raw(Req) ->
  N = p56_router:int_qs(Req, <<"limit">>, 60),
  Buffer = p56_ingesta:buffer(N),
  Json = json:encode(#{
    ok => true,
    eventos => [#{t => Ts, ev => buffer_json(E)} || {Ts, E} <- Buffer]}),
  p56_router:json_resp(Json, Req).

buffer_json(E) ->
  #{source    => maps:get(source, E),
    source_id => maps:get(source_id, E, none),
    mag       => maps:get(mag, E),
    prof_km   => maps:get(prof_km, E, 0),
    lat       => maps:get(lat, E),
    lon       => maps:get(lon, E),
    t         => maps:get(t, E),
    lugar     => maps:get(lugar, E)}.

%% ------------------------------------------------------------------
%% GET /api/alertas?limit= (bitacora de alertas)
%% ------------------------------------------------------------------

alertas(Req) ->
  N = p56_router:int_qs(Req, <<"limit">>, 200),
  Lista = p56_alertas:bitacora(N),
  Json = json:encode(#{
    ok => true,
    alertas => [#{id          => maps:get(id, Entrada),
                  nivel       => p56_router:nivel_texto(maps:get(nivel, Entrada)),
                  mag         => maps:get(mag, Entrada),
                  lugar       => maps:get(lugar, Entrada),
                  prof_km     => maps:get(prof_km, Entrada, 0),
                  sitio       => maps:get(sitio, Entrada, none),
                  sitio_dist_km => maps:get(sitio_dist_km, Entrada, 0),
                  t           => maps:get(t, Entrada),
                  t_evento    => maps:get(t_evento, Entrada),
                  razon       => maps:get(razon, Entrada),
                  aviso       => maps:get(aviso, Entrada, true),
                  revisiones  => maps:get(revisiones, Entrada, 0)}
                 || Entrada <- Lista]}),
  p56_router:json_resp(Json, Req).

%% ------------------------------------------------------------------
%% GET /api/procesos (pantalla detalle de proceso)
%% ------------------------------------------------------------------

procesos(Req) ->
  Json = json:encode(#{
    ok => true,
    procesos => [
      proceso_info(p56_ingesta, p56_ingesta:metricas()),
      proceso_info(p56_dedupe,  p56_dedupe:metricas()),
      proceso_info(p56_alertas, p56_alertas:metricas()),
      proceso_info(p56_fuentes, p56_fuentes:estado()),
      proceso_info(p56_sismos_server, #{})
    ],
    nodo => #{
      memoria_mb => round(erlang:memory(processes_used) / (1024 * 1024)),
      procesos => length(erlang:processes())
    }}),
  p56_router:json_resp(Json, Req).

proceso_info(Nombre, Detalles) ->
  case whereis(Nombre) of
    undefined ->
      #{alive => false, nombre => atom_to_binary(Nombre, utf8)};
    Pid ->
      Info = process_info(Pid, [memory, message_queue_len, reductions]),
      #{alive => true,
        nombre => atom_to_binary(Nombre, utf8),
        pid => list_to_binary(pid_to_list(Pid)),
        memoria_bytes => val(Info, memory),
        cola => val(Info, message_queue_len),
        reducciones => val(Info, reductions),
        detalles => json_seguro(Detalles)}
  end.

val(Info, K) ->
  case lists:keyfind(K, 1, Info) of
    {_, V} when is_number(V) -> V;
    _ -> 0
  end.

%% json:encode/1 devuelve iodata (lista profunda), no un binario: anidar
%% su resultado dentro de otro encode produce listas impropias y revienta
%% el codificador. Por eso aqui solo se normalizan los valores a tipos
%% JSON seguros (mapas, listas propias, binarios y numeros).
json_seguro(Mapa) when is_map(Mapa) ->
  maps:from_list([{clave_texto(K), json_seguro(V)}
                  || {K, V} <- maps:to_list(Mapa)]);
json_seguro(Lista) when is_list(Lista) ->
  [json_seguro(V) || V <- Lista];
json_seguro(true) -> true;
json_seguro(false) -> false;
json_seguro(null) -> null;
json_seguro(Atomo) when is_atom(Atomo) ->
  atom_to_binary(Atomo, utf8);
json_seguro(V) when is_binary(V); is_number(V) ->
  V;
json_seguro(Tupla) ->
  unicode:characters_to_binary(io_lib:format("~p", [Tupla])).

clave_texto(K) when is_binary(K) -> K;
clave_texto(K) when is_atom(K) -> atom_to_binary(K, utf8);
clave_texto(K) when is_integer(K) -> integer_to_binary(K);
clave_texto(K) -> unicode:characters_to_binary(io_lib:format("~p", [K])).

%% ------------------------------------------------------------------
%% GET /api/resumen (KPIs del dashboard)
%% ------------------------------------------------------------------

resumen(Req) ->
  Ingesta = p56_ingesta:resumen(),
  Catalogo = p56_dedupe:resumen(),
  Alertas = p56_alertas:resumen(),
  Fuentes = p56_fuentes:estado(),
  Nodo = p56_sismos_server:state(),
  Iniciado = maps:get(iniciado_en, Nodo, os:system_time(second)),
  Json = json:encode(#{
    ok => true,
    eventos => maps:get(recibidos, Ingesta, 0),
    rechazados => maps:get(rechazados, Ingesta, 0),
    buffer => maps:get(buffer_len, Ingesta, 0),
    sismos => maps:get(catalogo, Catalogo, 0),
    revisiones => maps:get(revisiones, Catalogo, 0),
    max_mag => maps:get(max_mag, Catalogo, 0),
    alertas => maps:get(total, Alertas, 0),
    avisos => maps:get(avisos, Alertas, 0),
    por_nivel => maps:get(por_nivel, Alertas, #{}),
    fuentes => maps:get(estado_fuentes, Fuentes, #{}),
    ticks => maps:get(tick, Fuentes, 0),
    uptime_s => erlang:max(0, os:system_time(second) - Iniciado),
    nodo => #{memoria_mb => round(erlang:memory(processes_used) / (1024 * 1024)),
              procesos => length(erlang:processes())}
  }),
  p56_router:json_resp(Json, Req).

%% ------------------------------------------------------------------
%% GET /api/fuentes (estado del simulador)
%% ------------------------------------------------------------------

fuentes(Req) ->
  E = p56_fuentes:estado(),
  Json = json:encode(#{
    ok => true,
    fuentes => maps:get(estado_fuentes, E, #{}),
    ticks => maps:get(tick, E, 0)}),
  p56_router:json_resp(Json, Req).

%% ------------------------------------------------------------------
%% POST /api/eventos (ingesta de un evento externo)
%% ------------------------------------------------------------------

api_eventos(Req) ->
  case p56_router:leer_json(Req) of
    {ok, Campos} ->
      p56_ingesta:evento(Campos),
      p56_router:json_resp(json:encode(#{ok => true}), Req);
    {error, Msg} ->
      p56_router:error_resp(400, Msg, Req)
  end.

%% ------------------------------------------------------------------
%% POST /api/simular (disparo manual del escenario)
%% ------------------------------------------------------------------

api_simular(Req) ->
  case p56_router:leer_json(Req) of
    {ok, Campos} ->
      case maps:find(<<"modo">>, Campos) of
        {ok, ModoB} ->
          Modo = modo_de(ModoB),
          p56_fuentes:burst(Modo),
          p56_router:json_resp(
            json:encode(#{ok => true, modo => atom_to_binary(Modo, utf8)}), Req);
        error ->
          p56_router:error_resp(
            400, <<"falta modo (enjambre/revision/atraso/caida)">>, Req)
      end;
    {error, Msg} ->
      p56_router:error_resp(400, Msg, Req)
  end.

modo_de(<<"enjambre">>) -> enjambre;
modo_de(<<"revision">>) -> revision;
modo_de(<<"atraso">>)   -> atraso;
modo_de(<<"caida">>)    -> caida;
modo_de(_)              -> enjambre.
