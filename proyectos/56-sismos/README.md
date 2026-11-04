# #56 — Sismos

**Dominio:** Energía y medio ambiente

Ingesta de eventos sísmicos, deduplicación por ventana espacio-temporal, decisión
escalonada de alertas por severidad y visor en tiempo real.

## Contexto

Baja California está cruzada por el sistema de fallas San Andrés–Golfo de California
(fallas Agua Blanca, Rose Canyon, Cerro Prieto, San Miguel, entre otras). El 4 de abril
de 2010 el terremoto El Mayor–Cucapah (Mw 7.2) sacudió Mexicali y la región. Detectar y
reportar sismos con rapidez salva vidas y orienta la respuesta.

Puntos del mundo real que el problema exige capturar:

- Las ondas **P** viajan ~6 km/s y las **S** (las destructivas) ~3.5 km/s. A 100 km del
  epicentro las S llegan ~13 s después de las P (ventana de alerta temprana).
- USGS publica feeds de sismos en GeoJSON, actualizados cada minuto, con magnitud,
  profundidad, coordenadas y hora.
- La magnitud (escala logarítmica) mide la energía: cada punto entero = ~32 veces más
  energía. La intensidad (Mercalli) depende de la distancia y del suelo.
- La información se corrige: la magnitud reportada a los primeros minutos puede cambiar en
  0.3 o más; un mismo evento llega varias veces con revisiones y de varias redes.
- Lo que se avisa depende del lugar: un M4 a 20 km se siente; uno a 800 km no.

## Escenario simulado

- Flujo base de fuentes con eventos nuevos, duplicados (reenvíos de la red) y revisiones
  (correcciones de magnitud al alza o a la baja).
- Enjambres: decenas de eventos pequeños en pocas horas.
- Eventos atrasados (`t = now - 15 min`) y una fuente que se cae (`off`).

## Diseño OTP

Árbol de supervisión: `p56_sismos_app` → `p56_sismos_sup` (**one_for_one**, 6 workers).

| Proceso | Tipo | Responsabilidad |
|---|---|---|
| `p56_sismos_server` | gen_server | metadatos del nodo (uptime, contadores vía `p56_sismos_server:state/0`) |
| `p56_ingesta` | gen_server | valida eventos entrantes, mantiene buffer |
| `p56_dedupe` | gen_server | consolida sismos por ventana espacio-temporal |
| `p56_alertas` | gen_statem | calcula nivel, decide aviso/reaviso/silencio, bitácora, difusión WS |
| `p56_fuentes` | gen_server | simulador de fuentes (ticks, bursts, caídas) |
| `p56_api_http` | gen_server | arranca el listener cowboy |

Estrategia `one_for_one`: cada etapa es independiente para reiniciarse; las dependencias
entre etapas son de **mensajes** (cast/call por nombre local), no de referencias, así que
basta con que cada `gen_server` se arranque por nombre.

Flujo de eventos: `p56_fuentes` → cast a `p56_ingesta` → cast a `p56_dedupe` → cast a
`p56_alertas` → respuesta vía API/WebSocket.

## API y tiempo real

- `GET /api/sismos?min_mag=M`
- `GET /api/procesos` (incluye pid y reducciones por proceso)
- `GET /api/resumen` (KPIs: eventos, buffer, sismos, revisiones, alertas, avisos, por nivel, uptime, fuentes)
- `GET /api/alertas?limit=N`
- `GET /api/eventos_raw?limit=N`
- `GET /api/fuentes`
- `POST /api/eventos` (ingesta externa de un sismo)
- `POST /api/simular` (`{"modo": "enjambre" | "revision" | "atraso" | "caida"}`)
- `GET /metrics` (prometheus_text_format)
- `GET /` · `GET /proceso` · `GET /historial` (UI estática)
- `WebSocket /ws/alertas`: el despachador difunde `{evento_json, Bin}`; el cliente se
  suscribe desde `websocket_init/1` con `gen_statem:cast(p56_alertas, {suscribir, self()})`.

## Niveles y fórmulas

| Nivel | Condición | Color |
|---|---|---|
| `critica` | M ≥ 5.5 | rojo |
| `alta` | M ≥ 4.5 | naranja (degrada a `media` si el sitio queda a > 500 km) |
| `media` | M ≥ 3.5 | ámbar (solo si el sitio está a < 300 km; a mayor distancia baja a `info`) |
| `info` | M ≥ 2.5 | verde (solo si el sitio está a < 100 km) |
| `none` | resto | sin alerta |

- **PGA** (g): atenuación empírica de orden de magnitud `0.1 * 10^(0.5·M) / (R + 10)^1.6`.
  No es un modelo GMPE oficial; sirve para colorear la intensidad, no para ingeniería.
- **Mercalli**: creciente a partir del PGA.
- **Δt P→S** = `d/3.5 − d/6` (d = distancia al sitio de interés).

## UI

Tres pantallas servidas como estáticos planos desde `priv/static`
(`index.html`, `proceso.html`, `historial.html`, `css/app.css`, `js/{app,dashboard,proceso,historial}.js`):
HTML/CSS/JS sin frameworks (fetch + WebSocket nativo), responsive a móvil, paleta y tipografía
de `design/seismic_telemetry_early_warning/DESIGN.md`.

| Pantalla | Contenido |
|---|---|
| Dashboard | KPIs, alerta mayor, visor cartográfico, feed de ingesta, triage por nivel, traza P/S, fuentes, contadores del nodo |
| Detalle de proceso | Árbol de supervisión, trazas multicomponente (BHZ/BHN/BHE), solución preliminar, buffer crudo, simulador de escenarios |
| Historial | Bitácora cronológica, filtros (texto, magnitud, nivel, decisión), export CSV, detalle expandible |

## Entorno y arranque

La VM nueva se detectó como **Ubuntu 22.04.1 LTS aarch64** (desviación respecto del
Debian 13 objetivo en el enunciado). No hay build arm64 precompilado de OTP 27 en
`builds.hex.pm` para esa versión, por lo que se compiló **OTP 27.3.4.19 desde fuente** con:

```bash
./configure --without-javac --without-wx --without-odbc
make -j4
```

Instalado en `~/.local/otp/27.3.4.19`; `rebar3 3.28.0` en `~/.local/bin/rebar3`.

```bash
export PATH=/home/pi/.local/otp/27.3.4.19/bin:/home/pi/.local/bin:/bin:/usr/bin
cd ~/erlang-proyectos/proyectos/56-sismos
rebar3 compile
rebar3 eunit
rebar3 shell
# release
rebar3 release
./_build/default/rel/p56_sismos/bin/p56_sismos daemon
```

- Puerto del servicio: **8081** (`8080` ocupado por `hello_erlang` en el dispositivo).
- Arrancado en la VM nueva por SSH: `ssh -J ecfe7c33-02db-4b8d-acf4-26204f898356@proxy.app.avh.corellium.com pi@10.11.0.1`

## Pruebas

```bash
rebar3 compile   # OK
rebar3 eunit     # 20 tests, 0 failures
```

`test/p56_pruebaspuros.erl`: purezas (niveles, dedupe, alertas, fuentes, eventos, geo).
`test/p56_pruebassupervision.erl`: prueba de caos — mata `p56_dedupe` con `exit brutal`,
el supervisor lo reinicia y el proceso vuelve a responder.

## Supuestos propios

- Fuentes simuladas por `p56_fuentes` (ticks cada ~0.8 s); el broker SeedLink real no está.
- Sitio de interés: Campus ITT (Tijuana/Mexicali); el JSON de `/api/sismos` incluye
  `sitio` y `sitio_dist_km`.
- Sin sismógrafo real: las trazas (`traza_sismica`) son sintéticas.
- Lat/lon de epicentro con 2 decimales; magnitud con 1 decimal.
- PGA/Mercalli son estimaciones; no sustituyen un modelo GMPE.

## Entrega

- Release funcional en la VM nueva (`_build/default/rel/p56_sismos`).
- 0 crashes en `/tmp/p56dev.log` (después de los fixes) y 0 en el release.
- Capturas Stitch: `design/*/screen.png`.
- Capturas de la app real servida por cowboy: `capturas/pantalla-{dashboard,proceso,historial}.png`.

## Pendiente

- [x] Compilar OTP 27 desde fuente en la VM nueva
- [x] Proyecto copiado y corriendo (puerto 8081)
- [x] `rebar3 compile` y `rebar3 eunit` en verde
- [x] Todos los endpoints verificados con HTTP 200
- [x] WebSocket `/ws/alertas` con suscripción activa (fix: suscripción en `websocket_init/1`)
- [x] 3 pantallas UI servidas y verificadas headless
- [x] Release generado y arrancado
- [x] Prueba de caos
- [x] Mejoras de demo: botón "Detonar sismo crítico", chips de escenarios y
      formulario de sismo manual en `/` y `/proceso` (solo frontend + API existente)
- [x] Fix de plausibilidad física: magnitud del simulador acotada a
      [1.0, 8.2] con tope de revisiones por evento (`p56_fuentes`); rango de
      validación [−1.0, 9.5] en `p56_eventos`
- [x] Capturas finales de la app real en `capturas/`
