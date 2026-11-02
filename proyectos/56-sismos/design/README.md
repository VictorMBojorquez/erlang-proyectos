# Diseño Stitch — #56 Sismos

Fuente de verdad visual: `DESIGN.md` (paleta oscura orientada a instrumento
sismológico, Space Grotesk / Inter / JetBrains Mono, badges de magnitud por
umbral).

## Pantallas

| Carpeta | Pantalla | USD/Image |
|---|---|---|
| `dashboard_centro_de_control_s_smico/` | Dashboard: telemetría de red, alerta mayor, visor cartográfico, feed de ingesta en vivo | `code.html`, `screen.png` |
| `detalle_de_proceso_ingesta_s_smica/` | Detalle de proceso: pipeline de picking P/S, solución preliminar (M, prof, coords), red concurrente | `code.html`, `screen.png` |
| `historial_y_bit_cora_de_alertas/` | Historial/bitácora: registro cronológico, filtros, validación y export | `code.html`, `screen.png` |

Notas de implementación:

- Se sirve tal cual desde cowboy (`cowboy_static`, sin frameworks JS pesados).
- Los datos reales llegan vía `/api/...` y WebSocket; el HTML de Stitch se usa
  como base visual y se sustituyen los datos de ejemplo por el estado del nodo.
