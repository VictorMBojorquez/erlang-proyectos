-module(p56_dedupe).
-behaviour(gen_server).

%% Identidad del sismo: es el proceso que responde las preguntas guia
%% del problema.
%%   1) "Cual es la identidad de un sismo si las fuentes discrepan?"
%%      -> un sismo es el mismo reporte/reporte-revisado si el evento
%%         nuevo llega a <= 50 km del consolidado y dentro de una
%%         ventana de <= 120 s respecto a la ultima actualizacion.
%%   2) "Cuando una revision amerita volver a avisar?"
%%      -> el dedupe no decide: entrega el sismo consolidado (con las
%%         revisiones) a p56_alertas, decidir reaviso/silencio.
%%
%% Solo guarda vivos los ultimos ?CATALOGO_MAX sismos; es memoria de
%% trabajo, la bitacora de alertas vive en p56_alertas.

-export([start_link/0,
         evento/1,
         listar/1,
         obtener/1,
         metricas/0,
         resumen/0,
         match/2,
         unir/2,
         nuevo/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(CATALOGO_MAX, 300).
-define(UNIR_KM, 50.0).
-define(UNIR_S, 120).

%% ------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

evento(Ev) ->
  gen_server:cast(?MODULE, {evento, Ev}).

%% Catalogo con filtro opcional de magnitud minima (GET /api/sismos).
listar(min_mag) ->
  gen_server:call(?MODULE, {listar, none});
listar(Filtro) when is_number(Filtro) ->
  gen_server:call(?MODULE, {listar, Filtro});
listar(_) ->
  gen_server:call(?MODULE, {listar, none}).

obtener(Id) ->
  gen_server:call(?MODULE, {obtener, Id}).

%% Resumen para GET /api/procesos.
metricas() ->
  gen_server:call(?MODULE, metricas).

%% Contadores acumulados para el dashboard.
resumen() ->
  gen_server:call(?MODULE, resumen).

%% ------------------------------------------------------------------
%% Logica pura (eunit)
%% ------------------------------------------------------------------

%% Match de identidad: ventana espacio-temporal del problema.
%% Distancia <= 50 km del epicentro consolidado y <= 120 s desde la
%% ultima actualizacion del sismo.
-spec match(map(), map()) -> boolean().
match(Sismo, Ev) ->
  UltimaT = maps:get(ultima_t, Sismo),
  Dist = p56_geo:distancia_km(
           maps:get(lat, Sismo), maps:get(lon, Sismo),
           maps:get(lat, Ev),    maps:get(lon, Ev)),
  abs(maps:get(t, Ev) - UltimaT) =< ?UNIR_S
    andalso Dist =< ?UNIR_KM.

%% Union de una revision a un sismo existente: la magnitud y el tiempo
%% mas recientes ganan; se conserva la maxima historica y el conteo.
-spec unir(map(), map()) -> map().
unir(Sismo, Ev) ->
  Mag = maps:get(mag, Ev),
  Revision = maps:get(revisiones, Sismo, 0) + 1,
  Fuente = maps:get(source, Ev),
  Fuentes = maps:get(fuentes, Sismo, []),
  {Sitio, DistKm} = p56_niveles:sitio_cercano(
                       maps:get(lat, Ev), maps:get(lon, Ev)),
  Sismo#{mag      := Mag,
         mag_max  := max(maps:get(mag_max, Sismo, Mag), Mag),
         lat      := maps:get(lat, Ev),
         lon      := maps:get(lon, Ev),
         prof_km  := maps:get(prof_km, Ev),
         lugar    := maps:get(lugar, Ev),
         ultima_t := maps:get(t, Ev),
         revisiones := Revision,
         fuentes  := listas_unicas([Fuente | Fuentes]),
         sitio    := Sitio,
         sitio_dist_km => DistKm}.

%% Nuevo sismo consolidado a partir del primer evento.
-spec nuevo(map(), pos_integer()) -> map().
nuevo(Ev, N) ->
  {Sitio, DistKm} = p56_niveles:sitio_cercano(
                       maps:get(lat, Ev), maps:get(lon, Ev)),
  #{
    id        => unicode:characters_to_binary(
      io_lib:format("SIM-~p", [N])),
    mag       => maps:get(mag, Ev),
    mag_max   => maps:get(mag, Ev),
    lat       => maps:get(lat, Ev),
    lon       => maps:get(lon, Ev),
    prof_km   => maps:get(prof_km, Ev),
    lugar     => maps:get(lugar, Ev),
    t         => maps:get(t, Ev),
    ultima_t  => maps:get(t, Ev),
    revisiones => 0,
    fuentes   => [maps:get(source, Ev)],
    sitio     => Sitio,
    sitio_dist_km => DistKm
  }.

listas_unicas(L) ->
  listas_unicas_(L, []).

listas_unicas_([], Unicas) ->
  lists:reverse(Unicas);
listas_unicas_([X | Resto], Acc) ->
  case lists:member(X, Acc) of
    true  -> listas_unicas_(Resto, Acc);
    false -> listas_unicas_(Resto, [X | Acc])
  end.

%% ------------------------------------------------------------------
%% gen_server
%% ------------------------------------------------------------------

init([]) ->
  logger:info("~s iniciado", [?MODULE], #{proyecto => p56_sismos}),
  {ok, #{sismos => #{}, orden => [], contador => 0, revisiones => 0}}.

handle_call({listar, MinMag}, _From, Estado = #{sismos := S, orden := Ord}) ->
  Sismos = [maps:get(Id, S) || Id <- Ord],
  SismosF =
    case MinMag of
      none -> Sismos;
      MM    -> [Si || Si <- Sismos, maps:get(mag, Si, 0) >= MM]
    end,
  {reply, SismosF, Estado};
handle_call({obtener, Id}, _From, Estado = #{sismos := S}) ->
  case maps:find(Id, S) of
    {ok, Sismo} -> {reply, Sismo, Estado};
    error -> {reply, {error, no_encontrado}, Estado}
  end;
handle_call(metricas, _From, Estado = #{sismos := S}) ->
  {reply, #{catalogo => maps:size(S)}, Estado};
handle_call(resumen, _From, Estado = #{sismos := S}) ->
  Sismos = maps:values(S),
  MaxMag = lists:max([0 | [maps:get(mag_max, Si, 0) || Si <- Sismos]]),
  {reply, #{catalogo => maps:size(S),
            revisiones => maps:get(revisiones, Estado, 0),
            max_mag => MaxMag}, Estado};
handle_call(_, _From, Estado) ->
  {reply, {error, desconocido}, Estado}.

%% El evento puede unirse a un sismo conocido (revision) o crear uno
%% nuevo; en ambos casos el consolidado se manda a p56_alertas, que
%% decide aviso/reaviso y notifica a los clientes WebSocket.
handle_cast({evento, Ev}, Estado = #{sismos := S, orden := Ord, contador := N}) ->
  SismoPrev = buscar_match(Ord, S, Ev),
  case SismoPrev of
    {ok, Sismo} ->
      SismoNuevo = unir(Sismo, Ev),
      p56_metrics:revision(),
      ConNivel = SismoNuevo#{nivel => nivel(SismoNuevo)},
      gen_server:cast(p56_alertas, {sismo, ConNivel, revision}),
      Revs = maps:get(revisiones, Estado, 0) + 1,
      {noreply, Estado#{sismos := maps:put(id(Sismo), ConNivel, S),
                        revisiones := Revs}};
    ninguno ->
      SismoNuevo = nuevo(Ev, N + 1),
      ConNivel = SismoNuevo#{nivel => nivel(SismoNuevo)},
      gen_server:cast(p56_alertas, {sismo, ConNivel, nuevo}),
      p56_metrics:sismos_catalogo(maps:size(S) + 1),
      {noreply, Estado#{sismos := maps:put(maps:get(id, ConNivel), ConNivel, S),
                        orden := encolar(Ord, maps:get(id, ConNivel)),
                        contador := N + 1}}
  end;
handle_cast(_, Estado) ->
  {noreply, Estado}.

handle_info(_, Estado) ->
  {noreply, Estado}.

terminate(_Razon, _Estado) ->
  ok.

%% ------------------------------------------------------------------
%% Internas
%% ------------------------------------------------------------------

id(Sismo) -> maps:get(id, Sismo).

buscar_match([Id | Resto], S, Ev) ->
  case maps:find(Id, S) of
    {ok, Sismo} ->
      case match(Sismo, Ev) of
        true -> {ok, Sismo};
        false -> buscar_match(Resto, S, Ev)
      end;
    error -> buscar_match(Resto, S, Ev)
  end;
buscar_match([], _, _) ->
  ninguno.

encolar(Ord, Id) ->
  Ord2 = [Id | Ord],
  case length(Ord2) < ?CATALOGO_MAX of
    true  -> Ord2;
    false -> lists:sublist(Ord2, ?CATALOGO_MAX)
  end.

nivel(Sismo) ->
  p56_niveles:calcular(Sismo).
