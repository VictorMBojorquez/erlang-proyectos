/* ==========================================================================
   Detalle de proceso (/proceso)
   Lee /api/procesos, /api/sismos, /api/eventos_raw y /api/resumen.
   Los botones de escenario disparan POST /api/simular (casos difíciles).
   ========================================================================== */
(function () {
  "use strict";

  const A = window.App;
  const $ = function (id) { return document.getElementById(id); };

  const DESCRIPCION = {
    p56_ingesta: "valida eventos y alimenta el buffer",
    p56_dedupe: "consolida sismos por ventana espaciotemporal",
    p56_alertas: "decide aviso, reaviso o silencio",
    p56_fuentes: "simulador de fuentes sísmicas",
    p56_sismos_server: "servidor base del nodo"
  };

  const estado = { procesos: [], sismos: [], resumen: null };

  /* --------------------------------------------------------------- procesos */

  function detallesTexto(d) {
    if (!d) return "—";
    const partes = Object.keys(d).map(function (k) {
      let v = d[k];
      if (v && typeof v === "object") {
        v = Object.keys(v).map(function (kk) { return kk + "=" + v[kk]; }).join(" ");
      }
      return k + "=" + v;
    });
    return partes.length ? partes.join(" · ") : "sin detalles";
  }

  function pintarProcesos() {
    const caja = $("procesos");
    if (!estado.procesos.length) {
      caja.innerHTML = '<div class="empty">sin procesos reportando</div>';
      return;
    }

    caja.innerHTML = estado.procesos.map(function (p) {
      const vivo = !!p.alive;
      const mem = p.memoria_bytes || 0;
      const pct = Math.max(2, Math.min(100, (mem / (64 * 1024)) * 100));
      return '<article class="proc-card' + (vivo ? "" : " off") + '">' +
        '<div class="proc-name"><span>' + A.esc(p.nombre) + "</span>" +
        '<span class="tag ' + (vivo ? "none" : "critica") + '">' + (vivo ? "activo" : "caído") + "</span></div>" +
        '<div class="proc-pid">' + A.esc(p.pid || "sin pid") + " · " + A.bytes(mem) + "</div>" +
        A.barra(mem, 64 * 1024, vivo ? "#38bdf8" : "#ef4444") +
        '<div class="proc-metrics">' +
        '<div class="tel"><div class="k">Cola</div><div class="v">' + A.entero(p.cola) + "</div></div>" +
        '<div class="tel"><div class="k">Reducciones</div><div class="v">' + A.entero(p.reducciones) + "</div></div>" +
        "</div>" +
        '<div class="tiny mono faint" title="' + A.esc(detallesTexto(p.detalles)) + '">' +
        A.esc(DESCRIPCION[p.nombre] || "") + "</div>" +
        '<div class="tiny mono faint" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' +
        A.esc(detallesTexto(p.detalles)) + "</div>" +
        "</article>";
    }).join("");
  }

  /* ------------------------------------------------------------- solucion */

  function pintarSolucion() {
    const s = estado.sismos[0];
    const caja = $("solucion");
    if (!s) {
      caja.innerHTML = '<div class="empty">esperando un evento consolidado…</div>';
      return;
    }

    const clase = A.nivelClase(s.nivel);
    $("sol-nota").textContent = s.id + " · " + A.hace(s.t);

    caja.innerHTML =
      '<div style="display:flex;align-items:center;gap:14px;flex-wrap:wrap">' +
      '<div class="badge-mag ' + clase + '" style="width:58px;height:58px;font-size:20px">' + A.mag(s.mag) + "</div>" +
      "<div style=\"min-width:0\">" +
      '<div class="alert-place">' + A.esc(s.lugar) + "</div>" +
      '<div class="alert-meta">' + A.coord(s.lat, s.lon) + " · " + A.km(s.prof_km) + " de profundidad</div>" +
      "</div>" +
      '<div style="margin-left:auto;display:flex;gap:6px;flex-wrap:wrap">' +
      '<span class="tag ' + clase + '">' + A.esc(A.nivelTexto(s.nivel)) + "</span>" +
      '<span class="tag muted">' + A.entero(s.revisiones) + " rev.</span>" +
      "</div></div>" +
      '<div class="telemetry" style="margin-top:14px">' +
      '<div class="tel"><div class="k">Mag. máx</div><div class="v">' + A.mag(s.mag_max) + "</div></div>" +
      '<div class="tel"><div class="k">PGA</div><div class="v">' + (s.pga_g != null ? Number(s.pga_g).toFixed(3) + " g" : "—") + "</div></div>" +
      '<div class="tel"><div class="k">Mercalli</div><div class="v">' + (s.mercalli != null ? " " + s.mercalli : "—") + "</div></div>" +
      '<div class="tel"><div class="k">Sitio</div><div class="v" style="font-size:12px">' + A.esc(s.sitio || "—") + "</div></div>" +
      '<div class="tel"><div class="k">Distancia</div><div class="v" style="font-size:12px">' + A.km(s.sitio_dist_km) + "</div></div>" +
      '<div class="tel"><div class="k">Fuentes</div><div class="v" style="font-size:12px">' +
      A.esc((s.fuentes || []).join(", ") || "—") + "</div></div>" +
      "</div>";
  }

  /* ---------------------------------------------------------------- trazas */

  function pintarTrazas() {
    const s = estado.sismos[0];
    const base = s ? Math.round((s.mag || 3) * 100) + (s.id || "").length : 11;
    const amp = s ? Math.min(1, 0.4 + (s.mag || 0) / 9) : 0.5;

    [["bhz", base, "#38bdf8"], ["bhn", base + 37, "#818cf8"], ["bhe", base + 71, "#10b981"]]
      .forEach(function (cfg) {
        $("eje-" + cfg[0]).innerHTML = A.ejesTraza(640, 92);
        const linea = $("w-" + cfg[0]);
        linea.setAttribute("points", A.traza({ ancho: 640, alto: 92, semilla: cfg[1], amplitud: amp }));
        linea.setAttribute("stroke", s ? (cfg[0] === "bhz" ? A.colorNivel(s.nivel) : cfg[2]) : cfg[2]);
      });

    const dist = s ? (s.sitio_dist_km || 0) : 0;
    const tp = dist > 0 ? dist / 6 : 0;
    const ts = dist > 0 ? dist / 3.5 : 0;
    $("t-p").textContent = dist > 0 ? "+" + tp.toFixed(1) + " s" : "—";
    $("t-s").textContent = dist > 0 ? "+" + ts.toFixed(1) + " s" : "—";
    $("traza-nota").textContent = s ? "evento " + s.id : "simulada · sin sismógrafo";
  }

  /* ------------------------------------------------------------------ raw */

  function pintarRaw(eventos) {
    const tbody = $("raw");
    $("raw-nota").textContent = eventos.length + " en buffer · orden de llegada";

    if (!eventos.length) {
      tbody.innerHTML = '<tr><td colspan="6" class="empty">sin eventos</td></tr>';
      return;
    }

    tbody.innerHTML = eventos.slice(0, 14).map(function (item) {
      const e = item.ev || {};
      return "<tr>" +
        '<td class="mono">' + A.horaUTC(e.t) + "</td>" +
        "<td><span class=\"tag muted\">" + A.esc(e.source) + "</span></td>" +
        '<td class="mono" style="color:' + A.colorMag(e.mag) + '">' +
        A.mag(e.mag) + "</td>" +
        '<td class="cell-main">' + A.esc(e.lugar) + "</td>" +
        '<td class="mono">' + A.km(e.prof_km) + "</td>" +
        '<td class="mono faint">' + A.coord(e.lat, e.lon) + "</td>" +
        "</tr>";
    }).join("");
  }

  /* --------------------------------------------------------------- fuentes */

  function pintarFuentes(r) {
    const fuentes = (r && r.fuentes) || {};
    const nombres = Object.keys(fuentes);
    $("fuentes-nota").textContent = A.entero(r ? r.ticks : 0) + " ticks";

    if (!nombres.length) {
      $("fuentes").innerHTML = '<div class="empty">sin fuentes</div>';
      return;
    }
    $("fuentes").innerHTML = nombres.map(function (n) {
      const on = fuentes[n] === "on";
      return '<div class="src-row">' +
        '<span class="dot" style="color:' + (on ? "#10b981" : "#ef4444") + '"></span>' +
        "<span>" + A.esc(n) + "</span>" +
        '<span class="tag ' + (on ? "none" : "critica") + '">' + (on ? "publicando" : "sin datos") + "</span>" +
        "</div>";
    }).join("");
  }

  function pintarPipeline(r) {
    if (!r) return;
    $("p-eventos").textContent = A.entero(r.eventos);
    $("p-revisiones").textContent = A.entero(r.revisiones);
    $("p-rechazos").textContent = A.entero(r.rechazados);
    $("p-ticks").textContent = A.entero(r.ticks);
    $("p-buffer").textContent = A.entero(r.buffer);
    $("p-avisos").textContent = A.entero(r.avisos);

    $("side-eventos").textContent = A.entero(r.eventos);
    $("side-sismos").textContent = A.entero(r.sismos);
    $("side-uptime").textContent = A.duracion(r.uptime_s);
  }

  /* ---------------------------------------------------------------- carga */

  async function cargarProcesos() {
    try {
      const r = await A.api("/api/procesos");
      estado.procesos = r.procesos || [];
      pintarProcesos();
    } catch (e) { /* siguiente ciclo */ }
  }

  async function cargarSismos() {
    try {
      const r = await A.api("/api/sismos");
      estado.sismos = (r.sismos || []).sort(function (a, b) { return b.t - a.t; });
      pintarSolucion();
      pintarTrazas();
    } catch (e) { /* siguiente ciclo */ }
  }

  async function cargarRaw() {
    try {
      const r = await A.api("/api/eventos_raw?limit=40");
      pintarRaw(r.eventos || []);
    } catch (e) { /* siguiente ciclo */ }
  }

  async function cargarResumen() {
    try {
      const r = await A.api("/api/resumen");
      estado.resumen = r;
      pintarPipeline(r);
      pintarFuentes(r);
    } catch (e) { /* siguiente ciclo */ }
  }

  /* ------------------------------------------------------------ escenarios */

  async function disparar(modo, boton) {
    boton.disabled = true;
    try {
      const resp = await fetch("/api/simular", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ modo: modo })
      });
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      A.toast("Escenario lanzado: " + modo, "los eventos entran al pipeline en los próximos segundos", "info");
      setTimeout(function () { cargarSismos(); cargarRaw(); cargarResumen(); }, 1200);
    } catch (e) {
      A.toast("No se pudo lanzar " + modo, String(e.message || e));
    } finally {
      setTimeout(function () { boton.disabled = false; }, 1500);
    }
  }

  /* ----------------------------------------------------------------- init */

  function init() {
    A.reloj($("reloj"), $("fecha"));

    $("escenarios").addEventListener("click", function (ev) {
      const boton = ev.target.closest(".chip");
      if (!boton) return;
      disparar(boton.dataset.modo, boton);
    });

    cargarProcesos();
    cargarSismos();
    cargarRaw();
    cargarResumen();

    setInterval(cargarProcesos, 3000);
    setInterval(cargarSismos, 4000);
    setInterval(cargarRaw, 4000);
    setInterval(cargarResumen, 5000);

    A.wsAlertas(function (dato) {
      if (dato.tipo === "alerta" && dato.aviso) {
        A.toast("Alerta " + A.nivelTexto(dato.nivel) + " · M " + A.mag(dato.mag), dato.lugar);
        cargarSismos();
        cargarResumen();
      } else if (dato.tipo === "sismo") {
        cargarSismos();
      }
    }, function (texto, clase) {
      A.estadoLive($("estado-live"), texto, clase);
      $("side-enlace").textContent = texto === "en vivo" ? "WS ACTIVO" : texto.toUpperCase();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
