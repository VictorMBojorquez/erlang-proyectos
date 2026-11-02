-module(p56_sismos_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% one_for_one: cada etapa del pipeline es independiente para
%% reiniciarse. La dependencia entre etapas es de MENSAJES (cast), no de
%% referencias, asi que basta con el arranque de cada gen_server por
%% nombre local y el mensaje simplemente se encola.
%% Si un dia ingesta y dedupe compartieran estado interno (ej. una ETS
%% creada por dedupe), la estrategia correcta seria rest_for_one por
%% orden de arranque.
init([]) ->
  Children = [
    #{id => p56_sismos_server,
      start => {p56_sismos_server, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker},
    #{id => p56_ingesta,
      start => {p56_ingesta, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker},
    #{id => p56_dedupe,
      start => {p56_dedupe, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker},
    #{id => p56_alertas,
      start => {p56_alertas, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker},
    #{id => p56_fuentes,
      start => {p56_fuentes, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker},
    #{id => p56_api_http,
      start => {p56_api_http, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker}
  ],
  {ok, {#{strategy => one_for_one, intensity => 10, period => 60},
        Children}}.
