/* ==========================================================================
   Dashboard en tiempo real (/)
   Consume /api/resumen, /api/sismos, /api/alertas y el WebSocket
   /ws/alertas. Todo el estado vive en memoria y se repinta por partes.
   ========================================================================== */
(function () {
  "use strict";

  const A = window.App;

  const SITIOS = [
    { nombre: "Tijuana", lat: 32.5144, lon: -117.0382 },
    { nombre: "Mexicali", lat: 32.6669, lon: -115.4673 },
    { nombre: "Ensenada", lat: 31.8667, lon: -116.6000 },
    { nombre: "Campus ITT", lat: 32.5168, lon: -115.4368 }
  ];

  /* Proyeccion simple del visor (no es cartografia oficial). */
  const MAPA = { w: 640, h: 420, lonMin: -118.6, lonMax: -111.9, latMin: 27.0, latMax: 33.0 };

  const estado = {
    resumen: null,
    sismos: [],
    alertas: [],
    filtroMin: 0,
    ultimaAlertaVista: null
  };

  const $ = function (id) { return document.getElementById(id); };

  function x(lon) { return ((lon - MAPA.lonMin) / (MAPA.lonMax - MAPA.lonMin)) * MAPA.w; }
  function y(lat) { return ((MAPA.latMax - lat) / (MAPA.latMax - MAPA.latMin)) * MAPA.h; }

  /* ------------------------------------------------------------------ KPIs */

  function pintarResumen(r) {
    if (!r) return;
    estado.resumen = r;

    $("kpi-eventos").textContent = A.entero(r.eventos);
    $("kpi-eventos-sub").textContent = "buffer vivo " + A.entero(r.buffer);
    $("kpi-sismos").textContent = A.entero(r.sismos);
    $("kpi-sismos-sub").textContent = A.entero(r.revisiones) + " revisiones";
    $("kpi-alertas").textContent = A.entero(r.alertas);
    $("kpi-alertas-sub").textContent = A.entero(r.avisos) + " con aviso";
    $("kpi-max").textContent = A.mag(r.max_mag);
    $("kpi-rechazados").textContent = A.entero(r.rechazados);
    $("kpi-uptime").textContent = "uptime " + A.duracion(r.uptime_s);

    $("side-eventos").textContent = A.entero(r.eventos);
    $("side-alertas").textContent = A.entero(r.alertas);
    $("side-max").textContent = A.mag(r.max_mag);

    $("n-buffer").textContent = A.entero(r.buffer);
    $("n-ticks").textContent = A.entero(r.ticks);
    $("n-uptime").textContent = A.duracion(r.uptime_s);
    $("n-rechazos").textContent = A.entero(r.rechazados);
    $("n-revisiones").textContent = A.entero(r.revisiones);
    $("n-avisos").textContent = A.entero(r.avisos);
    $("n-procesos").textContent = r.nodo ? A.entero(r.nodo.procesos) : "—";
    $("n-memoria").textContent = r.nodo ? A.entero(r.nodo.memoria_mb) + " MB" : "—";

    pintarTriage(r.por_nivel || {});
    pintarFuentes(r);
  }

  function pintarTriage(porNivel) {
    const orden = ["critica", "alta", "media", "info", "none"];
    const total = orden.reduce(function (acc, n) { return acc + (porNivel[n] || 0); }, 0);
    const max = Math.max.apply(null, orden.map(function (n) { return porNivel[n] || 0; }).concat([1]));

    $("triage").innerHTML = orden.map(function (n) {
      const v = porNivel[n] || 0;
      const color = A.colorNivel(n);
      return '<div class="triage-row">' +
        '<span class="lbl">' + A.esc(A.nivelTexto(n)) + "</span>" +
        A.barra(v, max, color) +
        '<span class="num mono" style="color:' + (v ? color : "#64748b") + '">' + A.entero(v) + "</span>" +
        "</div>";
    }).join("") +
      '<div class="tiny mono faint" style="margin-top:2px">' + A.entero(total) +
      " entradas · " + A.entero(estado.resumen ? estado.resumen.avisos : 0) + " con aviso</div>";
  }

  function pintarFuentes(r) {
    const fuentes = r.fuentes || {};
    const nombres = Object.keys(fuentes);
    $("fuentes-nota").textContent = A.entero(r.ticks) + " ticks";

    if (!nombres.length) {
      $("fuentes").innerHTML = '<div class="empty">sin fuentes reportando</div>';
      return;
    }

    $("fuentes").innerHTML = nombres.map(function (nombre) {
      const on = fuentes[nombre] === "on";
      return '<div class="src-row">' +
        '<span class="dot" style="color:' + (on ? "#10b981" : "#ef4444") + '"></span>' +
        "<span>" + A.esc(nombre) + "</span>" +
        '<span class="tag ' + (on ? "none" : "critica") + '">' + (on ? "en línea" : "caída") + "</span>" +
        "</div>";
    }).join("") +
      '<div class="tiny mono faint" style="margin-top:8px">simulador SeedLink · ' +
      A.esc(Object.keys(fuentes).filter(function (k) { return fuentes[k] === "on"; }).length) +
      " de " + nombres.length + " activas</div>";
  }

  /* ------------------------------------------------------------- alerta */

  function pintarAlerta() {
    const caja = $("alerta");
    const conAviso = estado.alertas.filter(function (e) { return e.aviso; });

    if (!conAviso.length) {
      const ultimo = estado.sismos[0];
      caja.className = "alert-card calm";
      caja.innerHTML =
        '<div class="alert-top">' +
        '<div class="alert-flag">' +
        '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 13 4 4L19 7"></path></svg>' +
        "sin alertas activas</div>" +
        '<div class="alert-meta mono">umbral M ≥ 4.5 · monitoreo continuo</div>' +
        "</div>" +
        '<div class="alert-main">' +
        '<div class="alert-mag"><small>Mw</small>' + (ultimo ? A.mag(ultimo.mag) : "—") + "</div>" +
        "<div><div class=\"alert-place\">" + (ultimo ? A.esc(ultimo.lugar) : "esperando telemetría") + "</div>" +
        '<div class="alert-meta">' + (ultimo
          ? A.km(ultimo.prof_km) + " de profundidad · " + A.hace(ultimo.t)
          : "el simulador publica eventos cada pocos segundos") + "</div></div>" +
        "</div>" +
        '<div class="alert-grid">' +
        '<div class="tel"><div class="k">Eventos</div><div class="v">' + A.entero(estado.resumen ? estado.resumen.eventos : 0) + "</div></div>" +
        '<div class="tel"><div class="k">Sismos</div><div class="v">' + A.entero(estado.sismos.length) + "</div></div>" +
        '<div class="tel"><div class="k">Revisión</div><div class="v">' + A.entero(estado.resumen ? estado.resumen.revisiones : 0) + "</div></div>" +
        '<div class="tel"><div class="k">Fuentes</div><div class="v">' + (estado.resumen ? A.entero(Object.keys(estado.resumen.fuentes || {}).length) : 0) + "</div></div>" +
        "</div>";
      return;
    }

    const e = conAviso[0];
    const clase = A.nivelClase(e.nivel);
    caja.className = "alert-card " + clase;
    caja.innerHTML =
      '<div class="alert-top">' +
      '<div class="alert-flag">' +
      '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3 2 21h20L12 3Z"></path><path d="M12 9v5M12 17.5v.5"></path></svg>' +
      "alerta sísmica · " + A.esc(A.nivelTexto(e.nivel)) + "</div>" +
      '<div class="alert-meta mono">' + A.esc(e.id) + " · " + A.hace(e.t) + "</div>" +
      "</div>" +
      '<div class="alert-main">' +
      '<div class="alert-mag"><small>Mw</small>' + A.mag(e.mag) + "</div>" +
      "<div><div class=\"alert-place\">" + A.esc(e.lugar) + "</div>" +
      '<div class="alert-meta">' + A.esc(e.razon) + " · " + A.entero(e.revisiones) + " revisiones</div></div>" +
      "</div>" +
      '<div class="alert-grid">' +
      '<div class="tel"><div class="k">Profundidad</div><div class="v">' + A.km(e.prof_km) + "</div></div>" +
      '<div class="tel"><div class="k">Distancia</div><div class="v">' + A.km(e.sitio_dist_km) + "</div></div>" +
      '<div class="tel"><div class="k">Sitio</div><div class="v" style="font-size:12px" title="' + A.esc(e.sitio) + '">' + A.esc(e.sitio || "—") + "</div></div>" +
      '<div class="tel"><div class="k">Hora UTC</div><div class="v" style="font-size:12px">' + A.horaUTC(e.t_evento || e.t) + "</div></div>" +
      "</div>";
  }

  /* --------------------------------------------------------------- mapa */

  function pintarMapa() {
    const sitios = SITIOS.map(function (s) {
      const px = x(s.lon), py = y(s.lat);
      return '<g>' +
        '<path d="M' + px + " " + (py - 6) + "v12M" + (px - 6) + " " + py + "h12" +
        '" stroke="#64748b" stroke-width="1.2"></path>' +
        '<circle cx="' + px + '" cy="' + py + '" r="2.2" fill="#94a3b8"></circle>' +
        '<text x="' + (px + 9) + '" y="' + (py + 3.5) + '" fill="#94a3b8" font-family="JetBrains Mono, monospace" font-size="9">' +
        A.esc(s.nombre) + "</text>" +
        "</g>";
    }).join("");
    $("mapa-sitios").innerHTML = sitios;

    const epis = estado.sismos.map(function (s) {
      const px = x(s.lon), py = y(s.lat);
      const r = 3 + Math.min(9, Math.max(0, (s.mag || 0) - 1.5) * 1.6);
      const color = A.colorNivel(s.nivel);
      const clase = A.nivelClase(s.nivel);
      const halo = clase === "critica" || clase === "alta"
        ? '<circle cx="' + px + '" cy="' + py + '" r="' + (r * 3.2) + '" fill="url(#brillo-epi)"></circle>'
        : "";
      return '<g><title>' + A.esc(s.lugar) + " · M " + A.mag(s.mag) + " · " + A.km(s.prof_km) + "</title>" +
        halo +
        '<circle cx="' + px + '" cy="' + py + '" r="' + r.toFixed(1) + '" fill="' + color +
        '" fill-opacity=".28" stroke="' + color + '" stroke-width="1.4"></circle>' +
        '<circle cx="' + px + '" cy="' + py + '" r="1.4" fill="' + color + '"></circle>' +
        "</g>";
    }).join("");
    $("mapa-epicentros").innerHTML = epis;

    const max = estado.sismos.reduce(function (m, s) { return Math.max(m, s.mag || 0); }, 0);
    $("mapa-nota").textContent = estado.sismos.length + " epicentros · máx M " + A.mag(max);
  }

  /* --------------------------------------------------------------- feed */

  function itemFeed(e) {
    const clase = A.nivelClase(e.nivel);
    return '<button class="feed-item" type="button" data-id="' + A.esc(e.id) + '">' +
      '<span class="badge-mag sm ' + clase + '">' + A.mag(e.mag) + "</span>" +
      "<span>" +
      '<span class="feed-title">' + A.esc(e.lugar) + "</span>" +
      '<span class="feed-sub">' + A.km(e.prof_km) + " · " + A.esc(e.sitio || "—") +
      " · " + A.hace(e.t_evento || e.t) + "</span>" +
      "</span>" +
      '<span class="tag ' + (e.aviso ? clase : "muted") + '">' +
      (e.aviso ? A.nivelTexto(e.nivel) : "catálogo") + "</span>" +
      "</button>";
  }

  function pintarFeed() {
    const lista = estado.alertas
      .filter(function (e) { return Number(e.mag) >= estado.filtroMin; })
      .slice(0, 40);

    $("feed-nota").textContent = lista.length + " de " + estado.alertas.length + " entradas";

    if (!lista.length) {
      $("feed").innerHTML = '<div class="empty">sin eventos para este filtro</div>';
      return;
    }
    $("feed").innerHTML = lista.map(itemFeed).join("");
  }

  /* --------------------------------------------------------------- traza */

  function pintarTraza() {
    const ultimo = estado.sismos[0];
    const semilla = ultimo ? Math.round((ultimo.mag || 3) * 100) + (ultimo.id || "").length : 7;
    const amp = ultimo ? Math.min(1, 0.45 + (ultimo.mag || 0) / 9) : 0.55;

    $("traza-ejes").innerHTML = A.ejesTraza(640, 132);
    $("traza-linea").setAttribute("points", A.traza({ ancho: 640, alto: 132, semilla: semilla, amplitud: amp }));
    $("traza-linea").setAttribute("stroke", ultimo ? A.colorNivel(ultimo.nivel) : "#38bdf8");

    const px = 640 * 0.18, sx = 640 * 0.34;
    ["p", "s"].forEach(function (k, i) {
      const pos = i === 0 ? px : sx;
      $("traza-" + k).setAttribute("x1", pos);
      $("traza-" + k).setAttribute("x2", pos);
      $("traza-" + k + "-txt").setAttribute("x", pos + 4);
    });

    const dist = ultimo ? (ultimo.sitio_dist_km || 0) : 0;
    const dt = dist > 0 ? dist / 3.5 - dist / 6 : 0;
    $("traza-dt").textContent = dist > 0 ? dt.toFixed(1) + " s" : "—";
    $("traza-amp").textContent = ultimo && ultimo.pga_g != null
      ? Number(ultimo.pga_g).toFixed(3) + " g"
      : "—";
    $("traza-nota").textContent = ultimo ? "evento " + ultimo.id : "simulada · sin sismógrafo";
  }

  /* --------------------------------------------------------------- carga */

  async function cargarResumen() {
    try { pintarResumen(await A.api("/api/resumen")); } catch (e) { /* siguiente ciclo */ }
  }

  async function cargarSismos() {
    try {
      const r = await A.api("/api/sismos");
      estado.sismos = (r.sismos || []).sort(function (a, b) { return b.t - a.t; });
      pintarMapa();
      pintarTraza();
    } catch (e) { /* siguiente ciclo */ }
  }

  async function cargarAlertas() {
    try {
      const r = await A.api("/api/alertas?limit=200");
      estado.alertas = r.alertas || [];
      pintarFeed();
      pintarAlerta();
    } catch (e) { /* siguiente ciclo */ }
  }

  function alRecibir(dato) {
    if (dato.tipo === "alerta") {
      estado.alertas.unshift(dato);
      estado.alertas = estado.alertas.slice(0, 300);
      pintarFeed();
      pintarAlerta();
      if (dato.aviso) {
        A.toast("Alerta " + A.nivelTexto(dato.nivel) + " · M " + A.mag(dato.mag),
          dato.lugar + " · " + A.hace(dato.t));
      }
      cargarResumen();
      cargarSismos();
    } else if (dato.tipo === "sismo") {
      const i = estado.sismos.findIndex(function (s) { return s.id === dato.id; });
      const previo = i >= 0 ? estado.sismos[i] : {};
      const nuevo = Object.assign({}, previo, dato, {
        pga_g: previo.pga_g,
        mercalli: previo.mercalli
      });
      if (i >= 0) estado.sismos[i] = nuevo;
      else estado.sismos.unshift(nuevo);
      pintarMapa();
      pintarTraza();
    }
  }

  /* --------------------------------------------------------------- init */

  function init() {
    A.reloj($("reloj"), $("fecha"));

    $("feed-filtros").addEventListener("click", function (ev) {
      const boton = ev.target.closest(".chip");
      if (!boton) return;
      estado.filtroMin = Number(boton.dataset.min) || 0;
      Array.prototype.forEach.call(this.querySelectorAll(".chip"), function (c) {
        c.setAttribute("aria-pressed", c === boton ? "true" : "false");
      });
      pintarFeed();
    });

    $("mapa-refrescar").addEventListener("click", function () {
      cargarSismos();
      cargarAlertas();
      cargarResumen();
    });

    $("feed").addEventListener("click", function (ev) {
      const item = ev.target.closest(".feed-item");
      if (!item) return;
      location.href = "/historial?q=" + encodeURIComponent(item.dataset.id);
    });

    cargarResumen();
    cargarSismos();
    cargarAlertas();

    setInterval(cargarResumen, 4000);
    setInterval(cargarSismos, 6000);
    setInterval(cargarAlertas, 8000);

    A.wsAlertas(alRecibir, function (texto, clase) {
      A.estadoLive($("estado-live"), texto, clase);
      $("side-enlace").textContent = texto === "en vivo" ? "WS ACTIVO" : texto.toUpperCase();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
