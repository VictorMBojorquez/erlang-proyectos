-module(p56_router).
%% Rutas cowboy + helpers compartidos por los handlers de p56_api.

-export([rutas/0, init/2]).
-export([json_resp/2, error_resp/3, leer_json/1, int_qs/3, nivel_texto/1,
         float_qs/2]).

rutas() ->
  cowboy_router:compile([
    {'_', [
      {"/",          cowboy_static, {priv_file, p56_sismos, "static/index.html"}},
      {"/proceso",   cowboy_static, {priv_file, p56_sismos, "static/proceso.html"}},
      {"/historial", cowboy_static, {priv_file, p56_sismos, "static/historial.html"}},
      {"/css/[...]", cowboy_static, {priv_dir,  p56_sismos, "static/css"}},
      {"/js/[...]",  cowboy_static, {priv_dir,  p56_sismos, "static/js"}},
      {"/metrics",          ?MODULE,  metrics},
      {"/api/sismos",      ?MODULE,  sismos},
      {"/api/procesos",    ?MODULE,  procesos},
      {"/api/resumen",     ?MODULE,  resumen},
      {"/api/fuentes",     ?MODULE,  fuentes},
      {"/api/simular",     ?MODULE,  api_simular},
      {"/api/eventos",     ?MODULE,  api_eventos},
      {"/api/alertas",     ?MODULE,  alertas},
      {"/api/eventos_raw", ?MODULE,  eventos_raw},
      {"/ws/alertas",      p56_ws,   []},
      {"/[...]",     cowboy_static, {priv_dir,  p56_sismos, "static"}}
    ]}
  ]).

%% Handler dinamico: cowboy pasa las opciones de la ruta como segundo
%% argumento; todo el despacho vive en p56_api:handle/2.
%% OJO: en cowboy 2.12 `cowboy_req:reply/4` devuelve el Req actualizado
%% (un mapa), no {ok, Req}. cowboy_handler:execute/2 exige
%% {ok, Req, State}, asi que aqui se normalizan ambos formatos; si no,
%% la respuesta sale bien pero queda un try_clause en el log.
init(Req, Opt) ->
  case p56_api:handle(Req, Opt) of
    Req2 when is_map(Req2) -> {ok, Req2, undefined};
    {ok, Req2} -> {ok, Req2, undefined};
    {ok, Req2, State} -> {ok, Req2, State};
    _ -> {ok, Req, undefined}
  end.

%% ------------------------------------------------------------------
%% Helpers HTTP
%% ------------------------------------------------------------------

json_resp(Bin, Req) ->
  cowboy_req:reply(
    200,
    #{<<"content-type">> => <<"application/json; charset=utf-8">>},
    Bin, Req).

error_resp(Codigo, Mensaje, Req) ->
  cowboy_req:reply(
    Codigo,
    #{<<"content-type">> => <<"application/json; charset=utf-8">>},
    json:encode(#{ok => false, error => Mensaje}),
    Req).

leer_json(Req) ->
  case cowboy_req:read_body(Req) of
    {ok, <<>>, _} ->
      {error, <<"cuerpo vacio">>};
    {ok, Cuerpo, _} ->
      case catch json:decode(Cuerpo) of
        C when is_map(C) -> {ok, C};
        _ -> {error, <<"se espera un objeto JSON">>}
      end;
    _ ->
      {error, <<"error al leer el cuerpo">>}
  end.

%% Integer opcional de query string: ?limit=N
int_qs(Req, Clave, Def) ->
  case lists:keyfind(Clave, 1, cowboy_req:parse_qs(Req)) of
    {_, B} ->
      case catch binary_to_integer(B) of
        I when is_integer(I) -> I;
        _ -> Def
      end;
    false -> Def
  end.

nivel_texto(none)    -> <<"none">>;
nivel_texto(info)    -> <<"info">>;
nivel_texto(media)   -> <<"media">>;
nivel_texto(alta)    -> <<"alta">>;
nivel_texto(critica) -> <<"critica">>.

%% filtrar magnitud minima del query ?min_mag=
float_qs(Req, Clave) ->
  case lists:keyfind(Clave, 1, cowboy_req:parse_qs(Req)) of
    {_, B} ->
      case catch binary_to_float(B) of
        F when is_float(F) -> F;
        _ ->
          case catch binary_to_integer(B) of
            I when is_integer(I) -> I * 1.0;
            _ -> none
          end
      end;
    false -> none
  end.
