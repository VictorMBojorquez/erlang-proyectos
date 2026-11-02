-module(p56_sismos_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
  {ok, _} = application:ensure_all_started(prometheus),
  ok = p56_metrics:iniciar(),
  p56_sismos_sup:start_link().

stop(_State) ->
  ok.
