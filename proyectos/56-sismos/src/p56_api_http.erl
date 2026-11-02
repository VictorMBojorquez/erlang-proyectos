-module(p56_api_http).
-behaviour(gen_server).

%% Arranque y apagado del listener cowboy. El enrutado detallado vive
%% en p56_router (handlers de la API) y p56_ws (websocket).

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  Puerto = puerto(),
  Rutas = p56_router:rutas(),
  {ok, _} = cowboy:start_clear(p56_http, [{port, Puerto}], #{
    env => #{dispatch => Rutas}
  }),
  logger:info("p56_api_http escuchando en puerto ~p", [Puerto],
    #{proyecto => p56_sismos}),
  {ok, #{puerto => Puerto}}.

handle_call(_, _From, Estado) ->
  {reply, {error, desconocido}, Estado}.

handle_cast(_, Estado) ->
  {noreply, Estado}.

handle_info(_, Estado) ->
  {noreply, Estado}.

terminate(_Razon, _Estado) ->
  catch cowboy:stop_listener(puerto()),
  ok.

puerto() ->
  application:get_env(p56_sismos, puerto_http, 8081).
