-module(p56_alertas).
-behaviour(gen_statem).

%% Despachador de alertas escalonadas con deduplicacion.
%% Los "casos dificiles" del problema se resuelven aqui:
%%
%%  - Silencio en enjambres: eventos con nivel none solo entran al
%%    catalogo (bitacora sin aviso); no generan alerta.
%%  - Falsas alarmas evitadas: una revision que NO sube el nivel no
%%    reactiva el aviso (decidir(_Prev, _Nivel) -> silencio).
%%  - Reaviso justificado: si la revision sube el nivel (ej. M4.6 ->
%%    M5.2), se emite reaviso con la nueva severidad.
%%
%% La bitacora alimenta la pantalla Historial y el canal WebSocket
%% /ws/alertas empuja todo en vivo (feed del dashboard).

-export([start_link/0,
         bitacora/1,
         resumen/0,
         metricas/0]).

-export([init/1, callback_mode/0, terminate/3]).
-export([handle_event/4]).

-define(BITACORA_MAX, 300).

%% ------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------

start_link() ->
  gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Ultimas N entradas de la bitacora (GET /api/alertas).
bitacora(N) ->
  gen_statem:call(?MODULE, {bitacora, N}).

%% Resumen para GET /api/procesos.
metricas() ->
  gen_statem:call(?MODULE, metricas).

%% Conteos de la bitacora para el panel del dashboard.
resumen() ->
  gen_statem:call(?MODULE, resumen).

%% ------------------------------------------------------------------
%% gen_statem
%% ------------------------------------------------------------------

callback_mode() ->
  handle_event_function.

init([]) ->
  logger:info("~s iniciado", [?MODULE], #{proyecto => p56_sismos}),
  Data = #{bitacora => [], niveles => #{}, suscriptores => []},
  {ok, activo, Data}.

terminate(_Razon, _Estado, _Data) ->
  ok.

handle_event({call, De}, {bitacora, N}, activo, Data) ->
  {keep_state, Data, [{reply, De, ultimas(Data, N)}]};

handle_event({call, De}, metricas, activo, Data) ->
  Entradas = length(maps:get(bitacora, Data)),
  {keep_state, Data, [{reply, De, #{bitacora_len => Entradas}}]};

handle_event({call, De}, resumen, activo, Data) ->
  {keep_state, Data, [{reply, De, resumen_bitacora(Data)}]};

%% gen_statem entrega los cast con EventType = cast (atomo) y el
%% contenido como segundo argumento; los call usan {call, From}.
handle_event(cast, {suscribir, Pid}, activo, Data) ->
  {keep_state, suscribir(Pid, Data)};

handle_event(cast, {desuscribir, Pid}, activo, Data) ->
  {keep_state, desuscribir(Pid, Data)};

%% Monitoreo de clientes WebSocket que se van sin desuscribirse
handle_event(info, {'DOWN', Ref, process, _Pid, _}, activo, Data) ->
  Sus = lists:keydelete(Ref, 2, maps:get(suscriptores, Data)),
  {keep_state, Data#{suscriptores := Sus}};

%% Notificacion desde p56_dedupe: sismo nuevo o revisado
handle_event(cast, {sismo, Sismo, Tipo}, activo, Data) ->
  {keep_state, procesar_sismo(Sismo, Tipo, Data)};

handle_event(_, _, _, Data) ->
  {keep_state, Data}.

%% ------------------------------------------------------------------
%% Logica del despachador
%% ------------------------------------------------------------------

procesar_sismo(Sismo, Tipo, Data) ->
  Nivel = nivel(Sismo),
  Id = maps:get(id, Sismo),
  Niveles = maps:get(niveles, Data, #{}),
  Prev = maps:get(Id, Niveles, undefined),
  %% maps:put/3 y no #{Id := Nivel}: el id puede no existir todavia
  %% (primer aviso de ese sismo) y := exige la llave presente.
  Data1 = Data#{niveles := maps:put(Id, Nivel, Niveles)},

  case Nivel of
    %% Sin severidad: solo catalogo (enjambres, sismos lejos)
    none ->
      Entrada = entrada(Sismo, none, <<"catalogo, sin alerta">>),
      difundir(entrada_json_sismo(Sismo), Data1),
      bitacora_push(Entrada#{aviso => false}, Data1);
    %% Con severidad: decidir entre nueva / reaviso / silencio
    Niv when is_atom(Niv) ->
      case p56_niveles:decidir(Prev, Niv) of
        nueva ->
          Entrada = entrada(Sismo, Niv, <<"severidad nueva">>),
          p56_metrics:alerta(Niv),
          p56_metrics:latencia_alerta(maps:get(t, Sismo)),
          difundir(entrada_json(Entrada, Sismo), Data1),
          bitacora_push(Entrada, Data1);
        reaviso ->
          Entrada = entrada(Sismo, Niv,
            <<"revision eleva la magnitud, se reavisa">>),
          p56_metrics:alerta(Niv),
          p56_metrics:latencia_alerta(maps:get(t, Sismo)),
          difundir(entrada_json(Entrada, Sismo), Data1),
          bitacora_push(Entrada, Data1);
        silencio ->
          Nota = case Tipo of
                   revision -> <<"revision sin cambio de nivel">>;
                   nuevo    -> <<"reenvio posterior del mismo sismo">>
                 end,
          Entrada = entrada(Sismo, Niv, Nota),
          difundir(entrada_json_sismo(Sismo), Data1),
          bitacora_push(Entrada#{aviso => false}, Data1)
      end
  end.

%% Entrada de bitacora canonica
entrada(Sismo, Nivel, Razon) ->
  #{
    id        => maps:get(id, Sismo),
    tipo      => event_type(maps:get(nivel, Sismo, none)),
    nivel     => Nivel,
    mag       => maps:get(mag, Sismo),
    lugar     => maps:get(lugar, Sismo),
    prof_km   => maps:get(prof_km, Sismo, 0),
    sitio     => maps:get(sitio, Sismo, none),
    sitio_dist_km => maps:get(sitio_dist_km, Sismo, 0),
    t         => os:system_time(second),
    t_evento  => maps:get(t, Sismo),
    razon     => Razon,
    revisiones => maps:get(revisiones, Sismo, 0)
  }.

event_type(_Nivel) -> <<"sismo">>.

nivel(Sismo) ->
  p56_niveles:calcular(Sismo).

bitacora_push(Entrada, Data) ->
  B = [Entrada | lists:sublist(maps:get(bitacora, Data), ?BITACORA_MAX - 1)],
  Data#{bitacora := B}.

ultimas(Data, N) ->
  lists:sublist(maps:get(bitacora, Data), N).

%% Conteo por nivel y numero de entradas que si emitieron aviso.
resumen_bitacora(Data) ->
  Bitacora = maps:get(bitacora, Data),
  PorNivel = lists:foldl(
    fun(Entrada, Acc) ->
      Nivel = maps:get(nivel, Entrada, none),
      maps:update_with(Nivel, fun(V) -> V + 1 end, 1, Acc)
    end, #{}, Bitacora),
  Avisos = length([E || E <- Bitacora, maps:get(aviso, E, true)]),
  #{total => length(Bitacora), por_nivel => PorNivel, avisos => Avisos}.

%% ------------------------------------------------------------------
%% Suscriptores WebSocket (/ws/alertas)
%% ------------------------------------------------------------------

suscribir(Pid, Data = #{suscriptores := Sus}) ->
  %% monitor para limpiar clientes que se van sin desuscribirse
  Ref = erlang:monitor(process, Pid),
  Data#{suscriptores := [{Pid, Ref} | Sus]}.

desuscribir(Pid, Data = #{suscriptores := Sus}) ->
  {Propios, Reste} =
    lists:partition(fun({P, _}) -> P =:= Pid end, Sus),
  lists:foreach(fun({_, Ref}) -> true = erlang:demonitor(Ref, [flush]) end,
                Propios),
  Data#{suscriptores := Reste}.

%% Difusion por WebSocket: cada cliente es el proceso handler de cowboy
%% (p56_ws) que entiende {evento_json, Bin}.
difundir(EntBin, Data) ->
  Sus = maps:get(suscriptores, Data, []),
  [catch begin Pid ! {evento_json, EntBin}, ok end
   || {Pid, _Ref} <- Sus],
  Data.

%% ------------------------------------------------------------------
%% JSON (canonico en la UI)
%% ------------------------------------------------------------------

entrada_json(Entrada, Sismo) ->
  json:encode(#{
    tipo => <<"alerta">>,
    nivel => nivel_a_texto(maps:get(nivel, Entrada)),
    mag => maps:get(mag, Entrada),
    mag_max => maps:get(mag_max, Sismo, maps:get(mag, Sismo)),
    id => maps:get(id, Entrada),
    lugar => maps:get(lugar, Entrada),
    prof_km => maps:get(prof_km, Entrada),
    sitio => maps:get(sitio, Entrada),
    sitio_dist_km => maps:get(sitio_dist_km, Entrada),
    t => maps:get(t, Entrada),
    t_evento => maps:get(t_evento, Entrada),
    razon => maps:get(razon, Entrada),
    revisiones => maps:get(revisiones, Entrada)
  }).

entrada_json_sismo(Sismo) ->
  json:encode(#{
    tipo => <<"sismo">>,
    nivel => nivel_a_texto(maps:get(nivel, Sismo, none)),
    mag => maps:get(mag, Sismo),
    mag_max => maps:get(mag_max, Sismo, maps:get(mag, Sismo)),
    id => maps:get(id, Sismo),
    lugar => maps:get(lugar, Sismo),
    prof_km => maps:get(prof_km, Sismo, 0),
    lat => maps:get(lat, Sismo),
    lon => maps:get(lon, Sismo),
    sitio => maps:get(sitio, Sismo, none),
    sitio_dist_km => maps:get(sitio_dist_km, Sismo, 0),
    t => maps:get(t, Sismo),
    revisiones => maps:get(revisiones, Sismo, 0),
    %% el codificador json de OTP no admite listas de binarios
    %% (las interpreta como texto), por eso se unen a un string
    fuentes => unir_binarios(maps:get(fuentes, Sismo, []))
  }).

unir_binarios([Bin]) -> Bin;
unir_binarios([Bin | Resto]) ->
  <<Bin/binary,
    ", ",
    (unir_binarios(Resto))/binary>>;
unir_binarios([]) -> <<>>.

nivel_a_texto(none) -> <<"none">>;
nivel_a_texto(info) -> <<"info">>;
nivel_a_texto(media) -> <<"media">>;
nivel_a_texto(alta) -> <<"alta">>;
nivel_a_texto(critica) -> <<"critica">>.
