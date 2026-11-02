-module(p56_pruebaspuros).
%% Pruebas de las partes puras del pipeline: geo, niveles, validacion,
%% deduplicacion (identidad del sismo) y decision de alertas.

-include_lib("eunit/include/eunit.hrl").

evento_lugar(Lat, Lon, Mag) ->
  #{source => <<"usgs">>, source_id => <<"e-1">>,
    mag => Mag, prof_km => 12.0, lat => Lat, lon => Lon,
    t => 1700000000, lugar => <<"Lugar">>}.

%% ------------------------------------------------------------------
%% geografia
%% ------------------------------------------------------------------

distancia_test() ->
  %% Mexicali <-> Tijuana, alrededor de 150 km de Referencia
  D = p56_geo:distancia_km(32.6669, -115.4673, 32.5144, -117.0382),
  ?assert(D > 100), ?assert(D < 200).

distancia_mismo_punto_test() ->
  ?assertEqual(0.0, p56_geo:distancia_km(32.0, -115.0, 32.0, -115.0)).

%% ------------------------------------------------------------------
%% niveles por magnitud/distancia
%% ------------------------------------------------------------------

niveles_limite_test() ->
  ?assertEqual(none,    p56_niveles:calcular(2.4, 30)),
  ?assertEqual(info,    p56_niveles:calcular(2.6, 30)),
  ?assertEqual(media,   p56_niveles:calcular(3.6, 200)),
  ?assertEqual(info,    p56_niveles:calcular(3.6, 400)),
  ?assertEqual(alta,    p56_niveles:calcular(4.6, 200)),
  ?assertEqual(media,   p56_niveles:calcular(4.6, 900)),
  ?assertEqual(critica, p56_niveles:calcular(5.8, 1200)).

niveles_sismo_mapa_test() ->
  %% con coords reales se calcula la distancia al sitio mas cercano
  S = maps:merge(evento_lugar(32.52, -115.44, 5.6), #{nivel => none}),
  ?assertEqual(critica, p56_niveles:calcular(S)).

decidir_test() ->
  ?assertEqual(nueva,   p56_niveles:decidir(undefined, media)),
  ?assertEqual(reaviso, p56_niveles:decidir(media, alta)),
  ?assertEqual(silencio, p56_niveles:decidir(alta, media)),
  ?assertEqual(silencio, p56_niveles:decidir(alta, alta)).

mercalli_creciente_test() ->
  ?assert(p56_niveles:mercalli(p56_niveles:pga_g(6.0, 40)) >=
          p56_niveles:mercalli(p56_niveles:pga_g(3.0, 40))).

%% ------------------------------------------------------------------
%% validacion de eventos
%% ------------------------------------------------------------------

eventos_validar_ok_test() ->
  {ok, Ev} = p56_eventos:validar(evento_lugar(32.5, -115.4, 4.2)),
  ?assertEqual(4.2, maps:get(mag, Ev)),
  ?_assert(is_binary(maps:get(source, Ev))).

eventos_validar_sin_magnitud_test() ->
  Mal = maps:without([mag], evento_lugar(32.5, -115.4, 4.2)),
  {error, _} = p56_eventos:validar(Mal),
  ok.

eventos_validar_lat_fuera_test() ->
  {error, _} = p56_eventos:validar(evento_lugar(99.0, -115.4, 4.2)),
  ok.

%% ------------------------------------------------------------------
%% identidad del sismo (casos dificiles del problema)
%% ------------------------------------------------------------------

sismo_ref() ->
  #{id => <<"SIM-1">>, mag => 4.0, mag_max => 4.0,
    lat => 32.52, lon => -115.44, prof_km => 10.0,
    lugar => <<"Mexicali">>, t => 1700000000, ultima_t => 1700000000,
    revisiones => 0, fuentes => [<<"usgs">>],
    sitio => none, sitio_dist_km => 5.0, nivel => media}.

rev() ->
  evento_lugar(32.53, -115.45, 4.3).

mismo_reporte_se_unifica_test() ->
  ?assert(p56_dedupe:match(sismo_ref(), rev())).

evento_lejano_es_otro_test() ->
  Ev = evento_lugar(31.0, -116.6, 3.0),
  ?_assertNot(p56_dedupe:match(sismo_ref(), Ev)).

evento_tarde_es_otro_test() ->
  Ev = (rev())#{t := 1700000500},
  ?_assertNot(p56_dedupe:match(sismo_ref(), Ev)).

unir_revision_test() ->
  S = p56_dedupe:unir(sismo_ref(), rev()),
  ?assertEqual(4.3, maps:get(mag, S)),
  ?assertEqual(4.3, maps:get(mag_max, S)),
  ?assertEqual(1, maps:get(revisiones, S)),
  ?assertEqual([<<"usgs">>], maps:get(fuentes, S)).

unir_con_dos_fuentes_test() ->
  S = p56_dedupe:unir(sismo_ref(), rev()),
  Ev2 = (rev())#{source := <<"csn">>, source_id := <<"e-9">>},
  S2 = p56_dedupe:unir(S, Ev2),
  ?assertEqual(2, length(maps:get(fuentes, S2))).

%% ------------------------------------------------------------------
%% generador del escenario
%% ------------------------------------------------------------------

fuentes_evento_base_test() ->
  Ev = p56_fuentes:evento_base(7, 1700000000, 42),
  ?assert(maps:is_key(source_id, Ev)),
  ?_assert(maps:is_key(mag, Ev)).

fuentes_atrasado_test() ->
  Ev = p56_fuentes:atrasado(3, 1700000900),
  ?assertEqual(1700000000, maps:get(t, Ev)).

fuentes_revision_test() ->
  Ev = p56_fuentes:evento_base(7, 1700000000, 42),
  R = p56_fuentes:revision_de(Ev, 0.3, 1700000100),
  Dist = abs(maps:get(mag, R) - (maps:get(mag, Ev) + 0.3)),
  ?assert(Dist < 0.4),
  CambioTiempo = maps:get(t, R) =/= maps:get(t, Ev),
  ?assert(CambioTiempo).

%% ==================================================================
%% Enjambre: k eventos pequenos con coords cercanas a centro.
%% ==================================================================

fuentes_enjambre_test() ->
  Lote = p56_fuentes:enjambre({30.85, -114.60}, 40),
  ?assertEqual(40, length(Lote)),
  ListaPequena = lists:all(fun(E) -> maps:get(mag, E) < 4.0 end, Lote),
  ?assert(ListaPequena).

atrasado_llega_tardio_test() ->
  Ev = p56_fuentes:atrasado(3, 1700000900),
  ?assertEqual(1700000000, maps:get(t, Ev)).
