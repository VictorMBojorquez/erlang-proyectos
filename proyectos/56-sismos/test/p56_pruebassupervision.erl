%% Prueba de supervision: al hacer fallar un hijo el supervisor lo
%% reinicia (one_for_one) y el proceso vuelve a estar disponible.
-module(p56_pruebassupervision).

-include_lib("eunit/include/eunit.hrl").

arranque_sup_test_() ->
  {setup,
   fun() ->
     %% La app completa (con cowboy/ranch y metricas), no el supervisor
     %% aislado: los hijos dependen de que la app este arriba.
     {ok, _} = application:ensure_all_started(p56_sismos),
     completa
   end,
   fun(_) ->
     application:stop(p56_sismos)
   end,
   fun(_) ->
     [?_test(chaos_verificacion())]
   end}.

%% Mata el dedupe (exit brutal) y verifica que el supervisor lo trae
%% de vuelta; esta es la prueba de caos minima del README.
chaos_verificacion() ->
  Pid0 = whereis(p56_dedupe),
  ?assert(is_pid(Pid0)),
  exit(Pid0, kill),
  Pid1 = esperando_cambio(Pid0, 50),
  ?assert(is_pid(Pid1)),
  ?assertNot(Pid1 =:= Pid0),
  %% el proceso nuevo esta vivo y responde consultas
  M = p56_dedupe:metricas(),
  ?assert(is_map(M)).

esperando_cambio(_Anterior, 0) -> whereis(p56_dedupe);
esperando_cambio(Anterior, N) ->
  case whereis(p56_dedupe) of
    P when is_pid(P), P =/= Anterior -> P;
    _ ->
      timer:sleep(100),
      esperando_cambio(Anterior, N - 1)
  end.
