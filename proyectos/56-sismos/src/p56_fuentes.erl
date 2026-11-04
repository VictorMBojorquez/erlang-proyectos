-module(p56_fuentes).
-behaviour(gen_server).

%% Simulador de fuentes sismicas (el 'generador' del escenario del
%% problema):
%%   - flujo base de varias fuentes con eventos nuevos,
%%   - duplicados del mismo reporte (la red lo reenvia sin cambios),
%%   - revisiones: el mismo evento vuelve con magnitud corregida,
%%   - enjambres: decenas de eventos pequenos en pocas horas,
%%   - eventos atrasados (t = now - 15 min) y una fuente que se cae
%%     (sus paquetes se dejan de enviar mientras esta 'off').
%%
%% La GENERACION es funciones puras (probadas en eunit); el gen_server
%% solo agenda (erlang:send_after) y manda los eventos a p56_ingesta.

-export([start_link/0,
         burst/1,
         estado/0,
         evento_base/3,
         revision_de/3,
         duplicado/1,
         enjambre/2,
         atrasado/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SITIOS_SIM, [
  {"Rumorosa", 32.5661, -116.1019},
  {"San Vicente", 32.2564, -116.7267},
  {"Volcan Cerro Prieto", 32.6167, -115.5000},
  {"Golfo de California", 30.5000, -114.5000},
  {"Sierra San Pedro Martir", 31.0264, -115.4436},
  {"Imperial Valley", 32.7975, -115.5603}
]).

-define(FUENTES, [<<"usgs">>, <<"csn">>, <<"redlocal">>]).

%% Limites fisicos para que el simulador no se desboque: la mayor
%% magnitud plausible en el Golfo de California es ~7.2 (El Mayor-
%% Cucapah fue Mw 7.2); con margen, 8.2 cubre hasta un mega-terremoto
%% plausiblemente reportado con error temprano. Y ninguna red reporta
%% correcciones infinitas: techo de revisiones por evento.
-define(MAG_MAX, 8.2).
-define(MAG_MIN, 1.0).
-define(REV_MAX, 6).

tasa_ms() ->
  application:get_env(p56_sismos, fuentes_tasa_ms, 2500).

activas() ->
  application:get_env(p56_sismos, fuentes_activas, true).

%% ------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Disparo manual de un modo del escenario (POST /api/simular).
burst(Modo) ->
  gen_server:cast(?MODULE, {burst, Modo}).

estado() ->
  gen_server:call(?MODULE, estado).

%% ------------------------------------------------------------------
%% Generadores puras (eunit)
%% ------------------------------------------------------------------

%% Eleccion determinista de un elemento de una lista a partir de Seed.
pick(Seed, Lista) ->
  lists:nth((abs(Seed) rem length(Lista)) + 1, Lista).

jitter(Seed) ->
  ((abs(Seed) rem 21) - 10) * 0.008.

round1(X) ->
  round(X * 10) / 10.

%% Un evento nuevo: sitio de la lista, magnitud y tiempos coherentes.
%% Determinista con respecto a Seed para poder reproducirlo en pruebas.
evento_base(Seed, Epoch, Contador) ->
  {Nombre, Lat, Lon} = pick(Seed, ?SITIOS_SIM),
  Mag = 2.8 + (abs(Seed) rem 150) / 40.0,
  #{
    source   => pick(Seed, ?FUENTES),
    source_id => unicode:characters_to_binary(
      io_lib:format("f-~p", [Contador])),
    mag      => round1(Mag),
    prof_km  => 5 + (abs(Seed) rem 120) / 4.0,
    lat      => Lat + jitter(Seed),
    lon      => Lon + jitter(Seed),
    t        => Epoch + (abs(Seed) rem 3) - 1,
    lugar    => unicode:characters_to_binary(Nombre),
    revs     => 0
  }.

%% Revision del mismo reporte: cambia la magnitud con la correccion
%% tipica del problema (hasta +/-0.3) y conserva la identidad. La
%% magnitud queda acotada a [?MAG_MIN, ?MAG_MAX] (fisica) y se cuenta
%% cuantas revisiones lleva el evento (revs), para que las redes no
%% revisen un mismo reporte mas de ?REV_MAX veces.
revision_de(Ev, Delta, Epoch) ->
  Mag = maps:get(mag, Ev, 3.0),
  Mag2 = max(?MAG_MIN, min(?MAG_MAX, round1(Mag + Delta))),
  Ev#{mag := Mag2,
      t := Epoch,
      revs := maps:get(revs, Ev, 0) + 1}.

%% Duplicado: la red reenvia el mismo reporte sin cambios.
duplicado(Ev) ->
  Ev.

%% Lote de enjambre: K eventos pequenos cerca de Centro {Lat, Lon}.
enjambre({Lat, Lon}, K) when K > 0 ->
  T = os:system_time(second),
  [ #{
      source   => <<"csn">>,
      source_id => unicode:characters_to_binary(
        io_lib:format("enj-~p", [I])),
      mag      => round1(1.9 + (I rem 20) / 14.0),
      prof_km  => 6 + I / 3.0,
      lat      => Lat + (I rem 7 - 3) * 0.04,
      lon      => Lon + (I rem 5 - 2) * 0.05,
      t        => T - (I rem 40) * 9,
      lugar    => <<"enjambre sismico">>
    }
    || I <- lists:seq(1, K) ].

%% Evento atrasado: llega 15 min tarde (fuente con cola lenta).
atrasado(Seed, Epoch) ->
  Ev = evento_base(Seed, Epoch, 0),
  Ev#{t := Epoch - 900}.

%% ------------------------------------------------------------------
%% gen_server
%% ------------------------------------------------------------------

init([]) ->
  logger:info("~s iniciado (tasa ~p ms)", [?MODULE, tasa_ms()],
    #{proyecto => p56_sismos}),
  Estado = #{cont => 1, tick => 0, ultimo => none,
             estado_fuentes => #{<<"usgs">> => on, <<"csn">> => on,
                                 <<"redlocal">> => on},
             rand => rand:seed(exsss)},
  case activas() of
    true  -> {ok, agenda(Estado)};
    false -> {ok, Estado}
  end.

handle_call(estado, _From, Estado) ->
  %% se expone solo el resumen publico: el estado interno trae el ref
  %% del temporizador y la semilla del rand (tuples) que crashean el
  %% codificador JSON
  {reply, #{estado_fuentes => maps:get(estado_fuentes, Estado, #{}),
            tick => maps:get(tick, Estado, 0)}, Estado};
handle_call(_, _From, Estado) ->
  {reply, {error, desconocido}, Estado}.

handle_cast({burst, Modo}, Estado) ->
  Estado1 = burst_modo(Modo, Estado),
  Estado2 = agenda(Estado1),
  {noreply, Estado2};
handle_cast(_, Estado) ->
  {noreply, Estado}.

handle_info(tick, Estado = #{tick := T, cont := C,
                             estado_fuentes := EF, rand := RS,
                             ultimo := Ultimo}) ->
  Epoch = os:system_time(second),
  {RS1, Az1, Az2, Az3} = tres_azar(RS),

  %% Fluido base: 1 o 2 eventos nuevos por tick
  Lote0 = [evento_base(Az1, Epoch, C),
           evento_base(Az2, Epoch, C + 1)],

  %% Duplicado periodico: la red reenvia el ultimo evento
  Lote1 =
    case Ultimo =/= none andalso T rem 4 =:= 0 of
      true  -> [duplicado(Ultimo) | Lote0];
      false -> Lote0
    end,

  %% Eventos atrasados con poca probabilidad
  Lote2 =
    case Az3 rem 11 =:= 0 of
      true  -> [atrasado(Az1, Epoch) | Lote1];
      false -> Lote1
    end,

  %% Revision del ultimo evento, cada ~9 ticks, correccion tipica;
  %% sin pasarse del tope de revisiones (las redes no corrigen eterno).
  Lote3 =
    case Ultimo =/= none andalso T rem 9 =:= 5
         andalso maps:get(revs, Ultimo, 0) < ?REV_MAX of
      true ->
        Delta = case Az3 rem 2 of 0 -> 0.3; _ -> -0.2 end,
        [revision_de(Ultimo, Delta, Epoch) | Lote2];
      false -> Lote2
    end,

  %% Fuente caida: mientras <<"redlocal">> este off, sus paquetes no
  %% salen del generador.
  Lote4 = [E || E <- Lote3, puede_salir(maps:get(source, E), EF)],

  enviar_lote(Lote4),
  UltimoNuevo = caso_max_mag(Lote4, Ultimo),
  Estado1 = Estado#{tick := T + 1, cont := C + 2, rand := RS1},
  Estado2 = agenda(Estado1#{ultimo := UltimoNuevo}),
  {noreply, Estado2};
handle_info(_, Estado) ->
  {noreply, Estado}.

terminate(_Razon, _Estado) ->
  ok.

%% ------------------------------------------------------------------
%% Internas
%% ------------------------------------------------------------------

agenda(Estado) ->
  R = erlang:send_after(tasa_ms(), self(), tick),
  Estado#{ref => R}.

%% Tres enteros deterministas con el estado del rand, para el flujo vivo.
tres_azar(RS) ->
  {A, RS1} = rand:uniform_s(1000000, RS),
  {B, RS2} = rand:uniform_s(1000000, RS1),
  {_, RS3} = rand:uniform_s(1000000, RS2),
  {RS3, A, B, (A + B)}.

%% El ultimo evento, si hubo, guarda ElementRef para programar la revision.
caso_max_mag(L, Ultimo) ->
  caso_max_mag_([E || E <- L, maps:is_key(mag, E)], Ultimo).

caso_max_mag_([], Ultimo) ->
  Ultimo;
caso_max_mag_(Evs, Ultimo) ->
  case [E || E <- Evs, maps:get(mag, E) >= mag_de(Ultimo)] of
    []    -> Ultimo;
    Mayores -> hd(Mayores)
  end.

mag_de(none) -> 0;
mag_de(E) -> maps:get(mag, E, 0).

puede_salir(Fuente, EF) ->
  case maps:find(Fuente, EF) of
    {ok, off} -> false;
    _ -> true
  end.

enviar_lote(Lote) ->
  [p56_ingesta:evento(E) || E <- Lote].

%% ------------------------------------------------------------------
%% Modos de prueba del escenario (POST /api/simular)
%%   enjambre:  lote de 40 eventos pequenos cerca de la grieta Golfo
%%   revision:  sube y baja la magnitud del ultimo evento respecto al
%%              umbral (prueba del reaviso)
%%   atraso:    un evento con t = now - 15 min
%%   caida:     alterna 'off' y 'on' de la fuente redlocal
%% ------------------------------------------------------------------

burst_modo(enjambre, Estado) ->
  enviar_lote(enjambre({30.85, -114.60}, 40)),
  Estado;
burst_modo(revision, Estado) ->
  case maps:get(ultimo, Estado, none) of
    none -> Estado;
    Ultimo ->
      case maps:get(revs, Ultimo, 0) < ?REV_MAX of
        true ->
          Delta = case rand:uniform(2) of 1 -> 0.35; _ -> -0.15 end,
          Rev = revision_de(Ultimo, Delta, os:system_time(second)),
          enviar_lote([Rev]),
          Estado#{ultimo := Rev};
        false -> Estado
      end
  end;
burst_modo(atraso, Estado) ->
  Ev = atrasado(rand:uniform(1000), os:system_time(second)),
  enviar_lote([Ev]),
  Estado;
burst_modo(caida, Estado) ->
  EF = maps:get(estado_fuentes, Estado, #{}),
  case maps:find(<<"redlocal">>, EF) of
    {ok, on} ->
      logger:warning("~s: fuente redlocal caida (off)", [?MODULE],
        #{proyecto => p56_sismos}),
      Estado#{estado_fuentes := maps:put(<<"redlocal">>, off, EF)};
    _ ->
      Estado#{estado_fuentes := maps:put(<<"redlocal">>, on, EF)}
  end;
burst_modo(_, Estado) ->
  %% revision del ultimo evento ya la expone la API (POST /api/simular)
  Estado.
