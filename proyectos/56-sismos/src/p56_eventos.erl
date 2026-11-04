-module(p56_eventos).

%% Validacion y normalizacion del evento entrante (en bruto, tipicamente
%% desde una fuente GeoJSON-like o POST /api/eventos).
%%
%% Devuelve SIEMPRE un mapa canonico o un error explicativo; el resto del
%% pipeline asume campos listos: la ingesta no debe adivinar tipos.

-export([validar/1]).

%% ---------------------------------------------------------------
%% Mapa canonico:
%%   #{ source     => binary()   %% <<"usgs">> / <<"redlocal">> / ...
%%      source_id  => binary()   %% id del reporte en la fuente
%%      mag        => float()
%%      prof_km    => float()
%%      lat        => float()
%%      lon        => float()
%%      t          => integer()  %% epoch segundos
%%      lugar      => binary() }
%% ---------------------------------------------------------------

validar(Campos) when is_map(Campos) ->
  try map_valido(Campos) of
    Ev -> {ok, Ev}
  catch
    throw:{evento, Razon} -> {error, Razon}
  end;
validar(_) ->
  {error, <<"estructura no valida: se espera un objeto JSON">>}.

map_valido(C) ->
  Mag = obligatorio_mag(C),
  Lat = obligatorio_lat(C),
  Lon = obligatorio_lon(C),
  #{
    source   => ber(comes(C, source, <<"externa">>)),
    source_id => ber(comes(C, source_id, genera_id())),
    mag      => Mag,
    prof_km  => num(def(C, prof_km, 10.0)),
    lat      => Lat,
    lon      => Lon,
    t        => entero(def(C, t, os:system_time(second))),
    lugar    => ber(def(C, lugar, <<"sin descripcion">>))
  }.

obligatorio_mag(C) ->
  case comes(C, mag, nada) of
    nada  -> throw({evento, <<"falta magnitud">>});
    M     -> rango(num(M), -1.0, 9.5, <<"magnitud fuera de rango">>)
  end.

obligatorio_lat(C) ->
  case comes(C, lat, nada) of
    nada  -> throw({evento, <<"falta latitud">>});
    L     -> rango(num(L), -90.0, 90.0, <<"latitud fuera de rango">>)
  end.

obligatorio_lon(C) ->
  case comes(C, lon, nada) of
    nada  -> throw({evento, <<"falta longitud">>});
    L     -> rango(num(L), -180.0, 180.0, <<"longitud fuera de rango">>)
  end.

%% json:decode devuelve mapas con LLAVES BINARIAS; las fuentes internas
%% (p56_fuentes) usan atomoos. Se aceptan ambas formas.
comes(C, K, Def) ->
  lookup_bin(C, K, Def).

def(C, K, Def) ->
  lookup_bin(C, K, Def).

lookup_bin(C, K, Def) ->
  case maps:find(K, C) of
    {ok, V} -> V;
    error ->
      BK = atom_to_binary(K, utf8),
      case maps:find(BK, C) of
        {ok, V} -> V;
        error -> Def
      end
  end.

rango(X, Min, Max, _Msg) when is_number(X), X >= Min, X =< Max ->
  X;
rango(_, _, _, Msg) ->
  throw({evento, Msg}).

num(V) when is_number(V) ->
  V;
num(V) when is_list(V) ->
  case string:to_float(V) of
    {F, []} -> F;
    _ ->
      case string:to_integer(V) of
        {I, []} -> I;
        _ -> throw({evento, <<"valor numerico esperado">>})
      end
  end;
num(V) when is_binary(V) ->
  num(unicode:characters_to_list(V));
num(_) ->
  throw({evento, <<"valor numerico esperado">>}).

entero(T) when is_integer(T) -> T;
entero(T) when is_float(T) -> round(T);
entero(_) -> throw({evento, <<"tiempo (t) debe ser epoch entero">>}).

ber(V) when is_binary(V) -> V;
ber(V) when is_atom(V) -> atom_to_binary(V, utf8);
ber(V) when is_list(V) -> unicode:characters_to_binary(V);
ber(_) -> throw({evento, <<"campo de texto esperado">>}).

genera_id() ->
  B = erlang:unique_integer([positive, monotonic]),
  unicode:characters_to_binary("auto-" ++ integer_to_list(B)).
