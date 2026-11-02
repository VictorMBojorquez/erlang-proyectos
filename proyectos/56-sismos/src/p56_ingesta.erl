-module(p56_ingesta).
-behaviour(gen_server).

%% Receptor de la tuberia de eventos: valida, incrementa metricas y
%% entrega el evento canonico al dedupe. El buffer (ultimos eventos,
%% ventana tipo SeedLink) alimenta el feed en vivo del dashboard.

-export([start_link/0,
         evento/1,
         buffer/1,
         metricas/0,
         resumen/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(BUFFER_MAX, 240).

%% ------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Entrada de un evento en bruto (map cualquiera; se valida aqui).
evento(Raw) ->
  gen_server:cast(?MODULE, {evento, Raw}).

%% Ultimos N eventos en bruto (para GET /api/eventos_raw).
buffer(N) ->
  gen_server:call(?MODULE, {buffer, N}).

%% Resumen para GET /api/procesos.
metricas() ->
  gen_server:call(?MODULE, metricas).

%% Contadores acumulados para el dashboard.
resumen() ->
  gen_server:call(?MODULE, resumen).

%% ------------------------------------------------------------------
%% gen_server
%% ------------------------------------------------------------------

init([]) ->
  logger:info("~s iniciado", [?MODULE], #{proyecto => p56_sismos}),
  {ok, #{buffer => [], recibidos => 0, rechazados => 0}}.

handle_call({buffer, N}, _From, Estado = #{buffer := B}) ->
  {reply, lists:sublist(B, N), Estado};
handle_call(metricas, _From, Estado = #{buffer := B}) ->
  {reply, #{buffer_len => length(B), buffer_max => ?BUFFER_MAX}, Estado};
handle_call(resumen, _From, Estado = #{buffer := B}) ->
  {reply, #{recibidos => maps:get(recibidos, Estado, 0),
            rechazados => maps:get(rechazados, Estado, 0),
            buffer_len => length(B),
            buffer_max => ?BUFFER_MAX}, Estado};
handle_call(_, _From, Estado) ->
  {reply, {error, desconocido}, Estado}.

%% Un evento entrante pasa por p56_eventos:validar/1; si es valido se
%% cuenta la metrica por fuente, se agrega al buffer en vivo y se
%% entrega al dedupe; si no, se cuenta un rechazo y se loguea.
handle_cast({evento, Raw}, Estado = #{buffer := B}) ->
  case p56_eventos:validar(Raw) of
    {ok, Ev} ->
      p56_metrics:evento_recibido(maps:get(source, Ev)),
      cast_dedupe(Ev),
      Recibidos = maps:get(recibidos, Estado, 0) + 1,
      {noreply, Estado#{buffer := push(Ev, B), recibidos := Recibidos}};
    {error, Razon} ->
      logger:warning("ingesta rechazo evento: ~s", [Razon],
        #{proyecto => p56_sismos}),
      p56_metrics:evento_rechazado(Razon),
      Rechazados = maps:get(rechazados, Estado, 0) + 1,
      {noreply, Estado#{rechazados := Rechazados}}
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

%% El buffer guarda {epoch, EventoCanonico} con el mas reciente primero.
push(Ev, B) ->
  [{os:system_time(second), Ev} | recorta(B)].

recorta(B) when length(B) =< ?BUFFER_MAX -> B;
recorta(B) -> lists:sublist(B, ?BUFFER_MAX).

cast_dedupe(Ev) ->
  gen_server:cast(p56_dedupe, {evento, Ev}).
