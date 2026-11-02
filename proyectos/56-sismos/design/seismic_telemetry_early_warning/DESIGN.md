---
name: Seismic Telemetry & Early Warning
colors:
  surface: '#0e1321'
  surface-dim: '#0e1321'
  surface-bright: '#343948'
  surface-container-lowest: '#090e1c'
  surface-container-low: '#161b2a'
  surface-container: '#1a1f2e'
  surface-container-high: '#252a39'
  surface-container-highest: '#303444'
  on-surface: '#dee2f6'
  on-surface-variant: '#bdc8d1'
  inverse-surface: '#dee2f6'
  inverse-on-surface: '#2b303f'
  outline: '#87929a'
  outline-variant: '#3e484f'
  surface-tint: '#7bd0ff'
  primary: '#8ed5ff'
  on-primary: '#00354a'
  primary-container: '#38bdf8'
  on-primary-container: '#004965'
  inverse-primary: '#00668a'
  secondary: '#bdc2ff'
  on-secondary: '#131e8c'
  secondary-container: '#2f3aa3'
  on-secondary-container: '#a8afff'
  tertiary: '#56e5a9'
  on-tertiary: '#003824'
  tertiary-container: '#30c88f'
  on-tertiary-container: '#004e34'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#c4e7ff'
  primary-fixed-dim: '#7bd0ff'
  on-primary-fixed: '#001e2c'
  on-primary-fixed-variant: '#004c69'
  secondary-fixed: '#e0e0ff'
  secondary-fixed-dim: '#bdc2ff'
  on-secondary-fixed: '#000767'
  on-secondary-fixed-variant: '#2f3aa3'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#0e1321'
  on-background: '#dee2f6'
  surface-variant: '#303444'
typography:
  headline-xl:
    fontFamily: Space Grotesk
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-xl-mobile:
    fontFamily: Space Grotesk
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  data-display:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  data-mono-lg:
    fontFamily: JetBrains Mono
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.02em
  data-mono-md:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-mono-sm:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 0.75rem
  gutter-tablet: 1rem
  margin: 1rem
  margin-tablet: 1.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style
This design system defines an authoritative, real-time scientific instrument interface tailored for geophysical monitoring, seismological telemetry, and emergency alert feeds. Designed specifically for critical, time-sensitive comprehension in high-stress situations, the visual language synthesizes modern data-dense aerospace telemetry with tactical field instrumentation.

The design movement relies on a technical, hyper-legible dark aesthetic: deep graphite and slate canvases paired with high-luminance spectral indicators, razor-sharp vector seismograms, and crisp tabular readouts. Interfaces prioritize immediate visual triage—allowing operators and civilians alike to parse magnitude, hypocentral depth, P/S wave arrival times, and epicentral coordinates in a single glance without perceptual fatigue.

## Colors
The system employs an OLED-optimized dark palette built to maximize the dynamic range of geospatial vector tiles, waveform traces, and focal mechanism diagrams. 

### Environmental Tones
- **Canvas Base (`#0A0F1D`)**: Absolute background ensuring low power consumption and high focal contrast.
- **Surface Elevation 1 (`#111827`)**: Container background for event cards, telemetry panels, and persistent navigation headers.
- **Surface Elevation 2 / Borders (`#1E293B`)**: Structural grid lines, card strokes, dividers, and inactive waveform baselines.
- **Surface Elevation 3 (`#334155`)**: Interactive hover states, elevated metric pills, and active filter containers.

### Instrumental Accents
- **Telemetry Cyan (`#38BDF8`)**: Primary interactive color for GPS coordinates, station telemetry, vector controls, and active network health.
- **Seismology Violet (`#818CF8`)**: Secondary indicator reserved for focal depth scales, tensor solutions, and spectral frequency overlays.

### Geophysical Alert Levels (Magnitude Thresholds)
- **Low Activity / Nominal (M &lt; 3.5)**: Emerald Green (`#10B981`). Designates microseisms, minor tremors, and healthy sensor ping states.
- **Elevated Activity (M 3.5 – 4.5)**: Amber Warning (`#F59E0B`). Signals felt events without immediate structural danger.
- **Moderate / Significant (M 4.5 – 5.5)**: Seismic Orange (`#F97316`). Signifies moderate ground acceleration, triggering user-level priority push notifications.
- **Critical / Severe (M &gt; 5.5)**: Crimson Red (`#EF4444`) with high-intensity strike tone (`#DC2626`). Reserved for destructive shaking alerts, tsunami evaluations, and sensor saturation warnings.

## Typography
Typography is separated strictly by operational utility:

1. **Space Grotesk** is applied for screen titles, section markers, and high-impact magnitude numbers. Its structural geometric cuts reflect engineering precision while providing commanding presence during emergency states.
2. **Inter** handles narrative descriptions, advisory texts, civil defense recommendations, and continuous reading material where uncompromised neutrality and rendering quality are paramount.
3. **JetBrains Mono** is mandatory for all quantitative data streams: hypocentral depth values (e.g., `10.4 km`), latitude/longitude coordinates (e.g., `34.0522° N, 118.2437° W`), UTC timestamps (`2023-11-04 14:02:11 UTC`), and spectral sensor IDs. It guarantees strict tabular alignment across rapidly updating data feeds without horizontal jitter.

## Layout & Spacing
The layout follows a continuous mobile-first fluid grid optimized for high-density information displays:
- **Mobile Grid**: 4 columns with `0.75rem` gutters and `1rem` safe margins. Critical data points are arranged in 2-column key-value telemetry pairs.
- **Tablet / Split Dashboard**: 8 columns with `1rem` gutters and `1.5rem` margins, enabling simultaneous side-by-side inspection of live cartographic maps alongside the real-time event log.

A strict 4px/8px micro-grid underpins all component paddings. Vertical rhythm remains tight (`space-xs` to `space-md` internally) to allow maximum visibility of recent seismic events on viewport load without excessive scrolling.

## Elevation & Depth
Elevation is expressed primarily through **tonal stratification** and **subtle luminescence** rather than physical drop shadows.

- **Base Ground**: `#0A0F1D` (Interactive map engine base and primary view canvas).
- **Sub-surface Tier (Level 1)**: `#111827` framed by a 1px border of `#1E293B`. Applied to seismic event feed cards and sensor lists.
- **Floating Overlays (Level 2)**: `#1E293B` with 85% opacity and a `backdrop-filter: blur(12px)`. Applied to bottom action sheets, persistent telemetry bars, and floating map toolbars.
- **Instrumental Glow**: Used sparingly for high-severity alerts. Seismic events with $M \ge 5.5$ employ a calibrated radial glow (`box-shadow: 0 0 24px -4px rgba(239, 68, 68, 0.35)`), guiding immediate visual focus in dark environments. Low-level ambient elements remain completely flat with hairline borders.

## Shapes
A controlled, technical corner radius (`roundedness: 1` = 0.25rem / 4px base; 0.5rem / 8px for containers) reinforces the feeling of physical scientific instruments, digital oscilloscopes, and rack-mounted monitors.

- **Cards and Panels**: `rounded-lg` (8px). Delivers a defined structure without appearing playful.
- **Interactive Badges & Pills**: `rounded-full` is exclusively reserved for magnitude indicator chips to create distinct geometric differentiation against the squared-off technical cards.
- **Waveform Viewports & Mini-maps**: `rounded-sm` (4px) with hard 1px framing lines.

## Components

### Magnitude Badges
- **Display**: High-contrast, circular or pill-shaped tokens containing the magnitude float (e.g., `4.8`, `6.2`).
- **Styling**: Colored dynamically by magnitude classification (`#10B981`, `#F59E0B`, `#F97316`, `#EF4444`). Contrast text is dark graphite (`#0A0F1D`) for low-to-moderate thresholds and pure white (`#FFFFFF`) on severe crimson alerts for absolute legibility. Font weight is bold tabular mono.

### Seismic Event Cards
- **Structure**: Surface level 1 (`#111827`) bounded by a 1px border (`#1E293B`).
- **Internal Layout**: 
  - Left column: Large magnitude badge paired with the event time delta (`"3m ago"`).
  - Center: Epicenter name (Space Grotesk 16px/600), followed by an inline key-value strip (`Depth: 12 km`, `Coord: 32.14°N 115.30°W`) rendered in `label-mono-sm`.
  - Right: Mini vector seismogram trace showing relative peak ground acceleration (PGA).

### Seismogram / Waveform Visualizers
- **Rendering**: SVG/Canvas vector traces. Nominal background trace set to slate (`#334155`). Active P-wave arrival indicated with primary cyan (`#38BDF8`); S-wave and coda phases tinted according to alert severity.
- **Axis Markings**: Hairline tick marks in `#1E293B` with timestamps in `JetBrains Mono` at 10px.

### Filter Chips
- **States**: Default chip has a `#111827` surface with `#1E293B` border and muted text (`#94A3B8`). Selected state features a filled background in `#1E293B` accented by an active border and indicator dot corresponding to the filtered magnitude range (e.g., `M 4.0+` with an amber dot).

### Telemetry Stat Modules
- **Appearance**: Bordered computational boxes showing hypocenter depth, distance to user location, and reporting station count.
- **Formatting**: Micro-labels displayed in uppercase tracking (`DEP`, `DIST`, `STA`), followed by bold monospaced values.

### Buttons & Critical Triggers
- **Primary / Actionable**: Solid `#38BDF8` background with `#0A0F1D` text for standard actions (e.g., `"Centrar Epicentro"`, `"Ver Estaciones"`).
- **Emergency / Report**: Crimson background (`#DC2626`) with white text, triggering local earthquake self-reports or SOS broadcasting.
- **Ghost / Utility**: Transparent background, 1px border (`#1E293B`), white text with cyan hover state.