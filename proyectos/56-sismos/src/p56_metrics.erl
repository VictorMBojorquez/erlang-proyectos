-module(p56_metrics).

%% Metricas Prometheus (endpoint /metrics servido por p56_router).
%% Todos los nombres usan el prefijo p56_ para no chocar con otros colectores.

-export([iniciar/0,
         evento_recibido/1,
         evento_rechazado/1,
         revision/0,
         alerta/1,
         sismos_catalogo/1,
         latencia_alerta/1]).

%% ------------------------------------------------------------------
%% Declaracion (idempotente) de contadores y gauges
%% ------------------------------------------------------------------

iniciar() ->
  declare_counter(p56_eventos_recibidos_total,
    "Eventos sismicos recibidos por fuente", [source]),
  declare_counter(p56_eventos_rechazados_total,
    "Eventos rechazados en ingesta por validacion", [razon]),
  declare_counter(p56_revisiones_total,
    "Revisiones aplicadas a sismos ya conocidos", []),
  declare_counter(p56_alertas_total,
    "Alertas emitidas por nivel", [nivel]),
  declare_gauge(p56_sismos_catalogo, "Sismos en catalogo vivo", []),
  declare_gauge(p56_segundos_ingesta_a_alerta,
    "Latencia desde el tiempo del evento hasta la emision de alerta", []),
  ok.

%% declare/2 lanza una excepcion si el metric ya fue declarado con otra
%% forma (p.ej. reinicio de la app en pruebas); se trata como idempotente.
declare_counter(Name, Help, Labels) ->
  try prometheus_counter:declare([{name, Name},
                                  {help, Help},
                                  {labels, Labels}]) of
    _ -> ok
  catch
    _:_ -> ok
  end.

declare_gauge(Name, Help, Labels) ->
  try prometheus_gauge:declare([{name, Name},
                                 {help, Help},
                                 {labels, Labels}]) of
    _ -> ok
  catch
    _:_ -> ok
  end.

%% ------------------------------------------------------------------
%% helpers usados por el pipeline
%% ------------------------------------------------------------------

-spec evento_recibido(binary()) -> ok.
evento_recibido(Fuente) ->
  prometheus_counter:inc(p56_eventos_recibidos_total, [Fuente]),
  ok.

evento_rechazado(Razon) ->
  prometheus_counter:inc(p56_eventos_rechazados_total, [Razon]),
  ok.

-spec revision() -> ok.
revision() ->
  prometheus_counter:inc(p56_revisiones_total),
  ok.

-spec alerta(atom()) -> ok.
alerta(Nivel) ->
  prometheus_counter:inc(p56_alertas_total, [atom_to_binary(Nivel, utf8)]),
  ok.

-spec sismos_catalogo(non_neg_integer()) -> ok.
sismos_catalogo(N) ->
  prometheus_gauge:set(p56_sismos_catalogo, N),
  ok.

%% Latencia entre el tiempo del evento (epoch s) y ahora, expresada en
%% segundos con 2 decimales. Solo se marca en alertas nuevas/reaviso.
latencia_alerta(TEvento) ->
  Seg = erlang:max(0, os:system_time(second) - TEvento),
  prometheus_gauge:set(p56_segundos_ingesta_a_alerta, Seg),
  ok.
