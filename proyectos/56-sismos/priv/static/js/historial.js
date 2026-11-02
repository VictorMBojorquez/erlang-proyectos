/* ==========================================================================
   Historial y bitácora (/historial)
   Fuente: /api/alertas (bitácora del despachador, más reciente primero).
   Filtros en cliente + exportación CSV + actualización por WebSocket.
   ========================================================================== */
(function () {
  "use strict";

  const A = window.App;
  const $ = function (id) { return document.getElementById(id); };

  const estado = {
    alertas: [],
    resumen: null,
    filtros: { texto: "", mag: 0, nivel: "", aviso: "" },
    abiertas: {}
  };

  /* --------------------------------------------------------------- filtros */

  function aplicar(lista) {
    const f = estado.filtros;
    const texto = f.texto.trim().toLowerCase();

    return lista.filter(function (e) {
      if (Number(e.mag) < f.mag) return false;
      if (f.nivel && A.nivelClase(e.nivel) !== f.nivel) return false;
      if (f.aviso === "1" && !e.aviso) return false;
      if (f.aviso === "0" && e.aviso) return false;
      if (texto) {
        const pajar = [e.id, e.lugar, e.sitio, e.razon].join(" ").toLowerCase();
        if (pajar.indexOf(texto) < 0) return false;
      }
      return true;
    });
  }

  /* ----------------------------------------------------------------- KPIs */

  function pintarKPIs() {
    const lista = estado.alertas;
    const total = lista.length;
    const avisos = lista.filter(function (e) { return e.aviso; }).length;
    const revisiones = lista.filter(function (e) {
      return String(e.razon || "").indexOf("reavisa") >= 0;
    }).length;
    const maximo = lista.reduce(function (m, e) { return Number(e.mag) > Number(m.mag || 0) ? e : m; }, {});

    $("k-total").textContent = A.entero(total);
    $("k-total-sub").textContent = total ? "más reciente " + A.hace(lista[0].t) : "sin entradas";
    $("k-max").textContent = maximo.mag != null ? A.mag(maximo.mag) : "—";
    $("k-max-sub").textContent = maximo.lugar ? maximo.lugar + " · " + A.nivelTexto(maximo.nivel) : "—";
    $("k-avisos").textContent = A.entero(avisos);
    $("k-avisos-sub").textContent = total ? Math.round((avisos / total) * 100) + "% de la bitácora" : "—";
    $("k-revisiones").textContent = A.entero(revisiones);

    const r = estado.resumen;
    if (r) {
      const fuentes = r.fuentes || {};
      const nombres = Object.keys(fuentes);
      const activas = nombres.filter(function (k) { return fuentes[k] === "on"; }).length;
      $("k-fuentes").textContent = activas + "/" + nombres.length;
      $("k-fuentes-sub").textContent = "ticks " + A.entero(r.ticks);
      $("side-total").textContent = A.entero(total);
      $("side-avisos").textContent = A.entero(avisos);
      $("side-max").textContent = A.mag(r.max_mag);
    }
  }

  /* ---------------------------------------------------------------- tabla */

  function fila(e, idx) {
    const clase = A.nivelClase(e.nivel);
    const clave = String(idx);
    const abierta = !!estado.abiertas[clave];

    let html = '<tr class="row-alert ' + clase + '">' +
      '<td class="mono nowrap">' + A.horaUTC(e.t_evento || e.t) +
      '<div class="cell-sub">' + A.fechaUTC(e.t_evento || e.t) + "</div></td>" +
      '<td><span class="badge-mag sm ' + clase + '">' + A.mag(e.mag) + "</span></td>" +
      '<td><div class="cell-main">' + A.esc(e.lugar) + "</div>" +
      '<div class="cell-sub">' + A.esc(e.id) + " · " + A.esc(e.sitio || "—") + "</div></td>" +
      '<td class="mono hide-sm">' + A.km(e.prof_km) + "</td>" +
      '<td class="mono hide-sm">' + A.km(e.sitio_dist_km) + "</td>" +
      '<td><span class="tag ' + clase + '">' + A.esc(A.nivelTexto(e.nivel)) + "</span></td>" +
      "<td>" + (e.aviso
        ? '<span class="tag ' + clase + '">aviso emitido</span>'
        : '<span class="tag muted">solo catálogo</span>') + "</td>" +
      '<td><button class="icon-btn" type="button" data-clave="' + clave + '" aria-expanded="' + abierta + '" title="Ver detalle">' +
      '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" style="transform:rotate(' + (abierta ? 90 : 0) + 'deg)"><path d="m9 6 6 6-6 6"></path></svg>' +
      "</button></td></tr>";

    if (abierta) {
      html += '<tr class="row-detail"><td colspan="8">' +
        "<div><strong>razón:</strong> " + A.esc(e.razon) + "</div>" +
        "<div><strong>registro:</strong> " + A.stampUTC(e.t) + " UTC · evento " + A.stampUTC(e.t_evento) + " UTC</div>" +
        "<div><strong>sitio:</strong> " + A.esc(e.sitio || "—") + " (" + A.km(e.sitio_dist_km) + ") · " +
        "<strong>revisiones:</strong> " + A.entero(e.revisiones) + " · " +
        "<strong>aviso:</strong> " + (e.aviso ? "sí" : "no") + "</div>" +
        "</td></tr>";
    }
    return html;
  }

  function pintarTabla() {
    const filtradas = aplicar(estado.alertas);
    const tbody = $("filas");

    $("tabla-nota").textContent = filtradas.length + " de " + estado.alertas.length + " entradas";
    $("pie-tabla").textContent = "mostrando " + filtradas.length + " de " + estado.alertas.length + " entradas";

    if (!filtradas.length) {
      tbody.innerHTML = '<tr><td colspan="8" class="empty">sin entradas para estos filtros</td></tr>';
      return;
    }
    tbody.innerHTML = filtradas.slice(0, 300).map(function (e) {
      return fila(e, estado.alertas.indexOf(e));
    }).join("");
  }

  /* ------------------------------------------------------------------ CSV */

  function csv() {
    const filas = aplicar(estado.alertas);
    const cab = ["id", "hora_utc", "mag", "lugar", "sitio", "dist_km", "prof_km", "nivel", "aviso", "revisiones", "razon"];
    const esc = function (v) {
      const s = String(v == null ? "" : v);
      return '"' + s.replace(/"/g, '""') + '"';
    };
    const lineas = [cab.join(",")].concat(filas.map(function (e) {
      return [
        e.id,
        A.stampUTC(e.t_evento || e.t),
        e.mag,
        e.lugar,
        e.sitio,
        e.sitio_dist_km,
        e.prof_km,
        A.nivelTexto(e.nivel),
        e.aviso ? "si" : "no",
        e.revisiones,
        e.razon
      ].map(esc).join(",");
    }));

    const blob = new Blob(["\uFEFF" + lineas.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "bitacora-sismos-" + new Date().toISOString().slice(0, 10) + ".csv";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
    A.toast("CSV generado", filas.length + " entradas exportadas", "info");
  }

  /* ---------------------------------------------------------------- carga */

  async function cargar(silencioso) {
    try {
      const [alertas, resumen] = await Promise.all([
        A.api("/api/alertas?limit=300"),
        A.api("/api/resumen")
      ]);
      estado.alertas = alertas.alertas || [];
      estado.resumen = resumen;
      pintarKPIs();
      pintarTabla();
      if (!silencioso) A.toast("Bitácora sincronizada", estado.alertas.length + " entradas", "info");
    } catch (e) {
      if (!silencioso) A.toast("No se pudo sincronizar", String(e.message || e));
    }
  }

  /* ----------------------------------------------------------------- init */

  function init() {
    A.reloj($("reloj"), $("fecha"));

    const buscar = $("f-buscar");
    const params = new URLSearchParams(location.search);
    if (params.get("q")) {
      buscar.value = params.get("q");
      estado.filtros.texto = params.get("q");
    }

    buscar.addEventListener("input", function () {
      estado.filtros.texto = this.value;
      pintarTabla();
    });
    $("f-mag").addEventListener("change", function () {
      estado.filtros.mag = Number(this.value) || 0;
      pintarTabla();
    });
    $("f-nivel").addEventListener("change", function () {
      estado.filtros.nivel = this.value;
      pintarTabla();
    });
    $("f-aviso").addEventListener("change", function () {
      estado.filtros.aviso = this.value;
      pintarTabla();
    });

    $("b-limpiar").addEventListener("click", function () {
      estado.filtros = { texto: "", mag: 0, nivel: "", aviso: "" };
      buscar.value = "";
      $("f-mag").value = "0";
      $("f-nivel").value = "";
      $("f-aviso").value = "";
      pintarTabla();
    });

    $("b-sync").addEventListener("click", function () { cargar(false); });
    $("b-csv").addEventListener("click", csv);

    $("filas").addEventListener("click", function (ev) {
      const boton = ev.target.closest("[data-clave]");
      if (!boton) return;
      const clave = boton.dataset.clave;
      estado.abiertas[clave] = !estado.abiertas[clave];
      pintarTabla();
    });

    cargar(true);
    setInterval(function () { cargar(true); }, 10000);

    A.wsAlertas(function (dato) {
      if (dato.tipo !== "alerta") return;
      estado.alertas.unshift(dato);
      estado.alertas = estado.alertas.slice(0, 300);
      pintarKPIs();
      pintarTabla();
      if (dato.aviso) {
        A.toast("Alerta " + A.nivelTexto(dato.nivel) + " · M " + A.mag(dato.mag), dato.lugar);
      }
    }, function (texto, clase) {
      A.estadoLive($("estado-live"), texto, clase);
      $("side-enlace").textContent = texto === "en vivo" ? "WS ACTIVO" : texto.toUpperCase();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
