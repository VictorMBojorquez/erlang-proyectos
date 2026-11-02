-module(p56_niveles).

%% Clasificacion de severidad: conversion de (magnitud, distancia a
%% sitio de interes) en un nivel de alerta y en estimaciones de PGA /
%% intensidad (Mercalli) que la UI pinta con los colores del DESIGN.md.
%%
%% Umbrales (cifras del problema, orden de magnitud):
%%   M >= 5.5  -> critica  (rojo)
%%   M >= 4.5  -> alta     (naranja), degradada a media si el sitio queda
%%                            a mas de 500 km
%%   M >= 3.5  -> media    (ambar) si el sitio esta a menos de 300 km;
%%                            a mayor distancia baja a info
%%   M >= 2.5  -> info     (verde) solo si el sitio esta a menos de 100 km
%%   el resto  -> none     (el sismo existe en el catalogo, pero no avisa)
%%
%% El ultimo sitio (minima distancia) es el que decide: el JSON de
%% /api/sismos incluye sitio y distancia para el panel lateral.

-export([sitios/0,
         sitio_cercano/2,
         min_dist_km/2,
         calcular/2,
         calcular/1,
         poder/1,
         decidir/2,
         pga_g/2,
         mercalli/1]).

%% ------------------------------------------------------------------
%% Sitios de interes (Baja California, contexto del problema)
%% ------------------------------------------------------------------

sitios() ->
  case application:get_env(p56_sismos, sitios) of
    {ok, S} when is_list(S), S =/= [] -> S;
    _ ->
      [{<<"Tijuana">>, 32.5144, -117.0382},
       {<<"Mexicali">>, 32.6669, -115.4673},
       {<<"Ensenada">>, 31.8667, -116.6000},
       {<<"Campus ITT">>, 32.5168, -115.4368}]
  end.

%% Escala de severidad comparable con poder/1
-define(ORDEN, [none, info, media, alta, critica]).

%% ------------------------------------------------------------------
%% Calculo de nivel
%% ------------------------------------------------------------------

%% Version pura probada en eunit: nivel por magnitud y distancia al
%% sitio mas cercano (km).
-spec calcular(number(), number()) -> none | info | media | alta | critica.
calcular(Mag, _DistKm) when Mag >= 5.5 ->
  critica;
calcular(Mag, DistKm) when Mag >= 4.5 ->
  caso_dist(DistKm, alta, media, 500);
calcular(Mag, DistKm) when Mag >= 3.5 ->
  caso_dist(DistKm, media, info, 300);
calcular(Mag, DistKm) when Mag >= 2.5 ->
  caso_dist(DistKm, info, none, 100);
calcular(_, _) -> none.

caso_dist(Dist, Cerca, Lejos, Umbral) ->
  case Dist =< Umbral of
    true -> Cerca;
    false -> Lejos
  end.

%% Sismo consolidado desde dedupe:
%% #{mag => float(), sitio_dist_km => float(), ...}
-spec calcular(map()) -> none | info | media | alta | critica.
calcular(#{mag := Mag, sitio_dist_km := Dist}) ->
  calcular(Mag, Dist);
calcular(#{mag := Mag, lat := Lat, lon := Lon}) ->
  calcular(Mag, min_dist_km(Lat, Lon));

calcular(_) -> none.

min_dist_km(Lat, Lon) ->
  {_Nombre, D} = sitio_cercano(Lat, Lon),
  D.

%% Sitio de interes mas cercano: {Nombre, DistanciaKm}.
sitio_cercano(Lat, Lon) ->
  lists:foldl(
    fun({Nombre, SLat, SLon}, Mejor) ->
      D = p56_geo:distancia_km(Lat, Lon, SLat, SLon),
      case Mejor of
        undefined -> {Nombre, D};
        {_N, D0} when D < D0 -> {Nombre, D};
        _ -> Mejor
      end
    end, undefined, sitios()).

%% ------------------------------------------------------------------
%% Comparacion de niveles (usada por p56_alertas para decidir
%% nueva / reaviso / silencio)
%% ------------------------------------------------------------------

poder(none) -> 0;
poder(info) -> 1;
poder(media) -> 2;
poder(alta) -> 3;
poder(critica) -> 4.

%% Nuevo aviso, reaviso por correccion al alza, o silencio.
decidir(undefined, _) -> nueva;
decidir(Prev, Nivel) ->
  case poder(Nivel) > poder(Prev) of
    true -> reaviso;
    false -> silencio
  end.

%% ------------------------------------------------------------------
%% Estimaciones fisicas (cifras de referencia del problema)
%% ------------------------------------------------------------------

%% PGA en g: atenuacion empirica de orden de magnitud (NO es un modelo
%% GMPE oficial). Cae con la distancia como (R+10)^-1.6 y crece con la
%% magnitud; sirve para colorear la seccion de intensidad, no para
%% ingenieria. Con M6 a 40 km da ~0.19 g; con M4.2 a 237 km, ~0.002 g.
pga_g(Mag, DistKm) ->
  P = 0.1 * math:pow(10, 0.5 * Mag) / math:pow(max(1.0, DistKm) + 10.0, 1.6),
  min(2.0, max(0.001, P)).

%% Mercalli aproximado a partir de PGA (g), tabla de referencia usada
%% por la UI (bandas del visor cartografico del dashboard).
-spec mercalli(number()) -> non_neg_integer().
mercalli(Pga) ->
  Bandas = [0.002, 0.014, 0.039, 0.092, 0.18, 0.34, 0.65, 1.24],
  mercalli(Pga, Bandas, 1).

mercalli(_, [], N) -> N;
mercalli(Pga, [B | _], N) when Pga < B -> N;
mercalli(Pga, [_ | Resto], N) -> mercalli(Pga, Resto, N + 1).
