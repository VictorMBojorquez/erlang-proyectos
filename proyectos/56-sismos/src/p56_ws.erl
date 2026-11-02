-module(p56_ws).
%% WebSocket /ws/alertas: recibe la difusion de eventos del despachador
%% p56_alertas ({evento_json, Bin}) y la escribe al cliente en texto.
%% El resto de los datos del REST va por fetch normal (no por aqui).

-behaviour(cowboy_websocket).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2,
         terminate/3]).

%% init/2 solo autoriza el upgrade. OJO: en cowboy 2.x con HTTP/1.1 este
%% callback corre en el proceso de la peticion, que termina en cuanto se
%% completa el handshake; el socket lo atiende despues el proceso de
%% conexion. Por eso aqui NO se suscribe nadie: suscribir con self() en
%% este punto registraba un pid que ya iba a morir, p56_alertas recibia
%% el DOWN y borraba al suscriptor (sintoma: handshake OK, 0 mensajes).
init(Req, Estado) ->
  {cowboy_websocket, Req, Estado}.

%% websocket_init/1 si corre en el proceso que vive mientras dura el
%% socket, asi que es el pid correcto para la difusion. El monitor que
%% p56_alertas deja sobre el evita suscriptores fantasma si el cliente
%% se cae sin cerrar limpio.
websocket_init(Estado) ->
  gen_statem:cast(p56_alertas, {suscribir, self()}),
  {ok, Estado}.

%% El cliente no manda datos: pings y texto se ignoran,
%% el pong lo responde cowboy automaticamente.
websocket_handle(_Frame, Estado) ->
  {ok, Estado}.

%% Difusion: mensajes directos a este proceso (uno por evento JSON).
websocket_info({evento_json, Bin}, Estado) ->
  {reply, {text, Bin}, Estado};
websocket_info(_Otro, Estado) ->
  {ok, Estado}.

terminate(_Razon, _Req, _Estado) ->
  gen_statem:cast(p56_alertas, {desuscribir, self()}),
  ok.
