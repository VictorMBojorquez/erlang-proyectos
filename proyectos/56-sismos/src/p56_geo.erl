-module(p56_geo).

%% Geometria de referencia para el dominio sismico.
%% Haversine con radio terrestre medio de 6371 km (cifra de referencia
%% anotada en el README; suficiente para el orden de magnitud que maneja
%% el problema: alertar por distancia epicentro-sitio).

-export([distancia_km/4]).

-spec distancia_km(number(), number(), number(), number()) -> float().
distancia_km(Lat1, Lon1, Lat2, Lon2) ->
  R = 6371.0,
  DLat = deg2rad(Lat2 - Lat1),
  DLon = deg2rad(Lon2 - Lon1),
  A = math:sin(DLat / 2) * math:sin(DLat / 2)
    + math:cos(deg2rad(Lat1)) * math:cos(deg2rad(Lat2))
    * math:sin(DLon / 2) * math:sin(DLon / 2),
  C = 2 * math:atan2(math:sqrt(A), math:sqrt(max(0.0, 1.0 - A))),
  R * C.

deg2rad(D) -> D * math:pi() / 180.0.
