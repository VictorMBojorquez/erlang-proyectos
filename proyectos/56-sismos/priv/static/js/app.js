/* ==========================================================================
   SISMOS — utilidades comunes para las tres pantallas.
   Sin dependencias: fetch, WebSocket nativo y plantillas de texto.
   ========================================================================== */
(function () {
  "use strict";

  const NIVELES = ["none", "info", "media", "alta", "critica"];
  const ETIQUETA_NIVEL = {
    none: "sin alerta",
    info: "informativa",
    media: "media",
    alta: "alta",
    critica: "crítica"
  };

  const App = {};

  /* ---------------------------------------------------------------- formato */

  App.esc = function (valor) {
    return String(valor == null ? "" : valor).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  };

  App.num = function (valor, dec) {
    if (valor == null || valor === "" || isNaN(Number(valor))) return "—";
    return Number(valor).toLocaleString("es-MX", {
      minimumFractionDigits: dec || 0,
      maximumFractionDigits: dec == null ? 1 : dec
    });
  };

  App.entero = function (valor) {
    if (valor == null || isNaN(Number(valor))) return "0";
    return Math.round(Number(valor)).toLocaleString("es-MX");
  };

  App.mag = function (valor) {
    return valor == null || isNaN(Number(valor)) ? "—" : Number(valor).toFixed(1);
  };

  App.km = function (valor) {
    if (valor == null || isNaN(Number(valor))) return "—";
    const n = Number(valor);
    return (n >= 100 ? Math.round(n) : n.toFixed(1)) + " km";
  };

  App.bytes = function (n) {
    if (n == null) return "—";
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    return (n / (1024 * 1024)).toFixed(1) + " MB";
  };

  App.duracion = function (seg) {
    if (seg == null) return "—";
    const s = Math.max(0, Math.floor(seg));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m";
    if (m > 0) return m + "m " + String(s % 60).padStart(2, "0") + "s";
    return s + "s";
  };

  App.fechaUTC = function (epoch) {
    if (!epoch) return "—";
    const d = new Date(Number(epoch) * 1000);
    return d.toISOString().slice(0, 10);
  };

  App.horaUTC = function (epoch) {
    if (!epoch) return "—";
    return new Date(Number(epoch) * 1000).toISOString().slice(11, 19);
  };

  App.stampUTC = function (epoch) {
    if (!epoch) return "—";
    const iso = new Date(Number(epoch) * 1000).toISOString();
    return iso.slice(0, 10) + " " + iso.slice(11, 19);
  };

  App.hace = function (epoch) {
    if (!epoch) return "—";
    const dif = Math.max(0, Math.floor(Date.now() / 1000 - Number(epoch)));
    if (dif < 10) return "ahora";
    if (dif < 60) return "hace " + dif + " s";
    if (dif < 3600) return "hace " + Math.floor(dif / 60) + " min";
    if (dif < 86400) return "hace " + Math.floor(dif / 3600) + " h";
    return "hace " + Math.floor(dif / 86400) + " d";
  };

  App.coord = function (lat, lon) {
    if (lat == null || lon == null) return "—";
    const la = Number(lat), lo = Number(lon);
    return Math.abs(la).toFixed(2) + "° " + (la >= 0 ? "N" : "S") + "  " +
           Math.abs(lo).toFixed(2) + "° " + (lo >= 0 ? "E" : "O");
  };

  /* ---------------------------------------------------------------- niveles */

  App.niveles = NIVELES;

  App.nivelClase = function (nivel) {
    const n = String(nivel || "none").toLowerCase();
    return NIVELES.indexOf(n) >= 0 ? n : "none";
  };

  App.nivelTexto = function (nivel) {
    return ETIQUETA_NIVEL[App.nivelClase(nivel)] || "sin alerta";
  };

  App.colorNivel = function (nivel) {
    return {
      none: "#10b981",
      info: "#10b981",
      media: "#f59e0b",
      alta: "#f97316",
      critica: "#ef4444"
    }[App.nivelClase(nivel)];
  };

  /* Color por magnitud, independiente del nivel calculado: se usa en
     tablas donde solo hay mag (buffer crudo, por ejemplo). */
  App.colorMag = function (mag) {
    const m = Number(mag) || 0;
    if (m >= 5.5) return "#ef4444";
    if (m >= 4.5) return "#f97316";
    if (m >= 3.5) return "#f59e0b";
    if (m >= 2.5) return "#10b981";
    return "#64748b";
  };

  /* ---------------------------------------------------------------- red */

  App.api = async function (ruta) {
    const resp = await fetch(ruta, { cache: "no-store", headers: { accept: "application/json" } });
    if (!resp.ok) throw new Error("HTTP " + resp.status + " en " + ruta);
    return resp.json();
  };

  /* Reloj UTC compartido por la cabecera. */
  App.reloj = function (horaEl, fechaEl) {
    const pinta = function () {
      const d = new Date();
      if (horaEl) horaEl.textContent = d.toISOString().slice(11, 19) + " UTC";
      if (fechaEl) fechaEl.textContent = d.toISOString().slice(0, 10);
    };
    pinta();
    return setInterval(pinta, 1000);
  };

  /* ---------------------------------------------------------------- WebSocket */

  /* Se reconecta con backoff y avisa del estado a la UI. */
  App.wsAlertas = function (alRecibir, alEstado) {
    let ws = null;
    let intentos = 0;
    let cerrado = false;

    const estado = function (texto, clase) {
      if (alEstado) alEstado(texto, clase);
    };

    const conectar = function () {
      if (cerrado) return;
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      try {
        ws = new WebSocket(proto + "//" + location.host + "/ws/alertas");
      } catch (e) {
        estado("sin enlace", "off");
        return;
      }

      ws.onopen = function () {
        intentos = 0;
        estado("en vivo", "");
      };

      ws.onmessage = function (ev) {
        let dato;
        try { dato = JSON.parse(ev.data); } catch (e) { return; }
        alRecibir(dato);
      };

      ws.onclose = function () {
        if (cerrado) return;
        estado("reconectando", "warn");
        intentos += 1;
        setTimeout(conectar, Math.min(1000 * intentos, 8000));
      };

      ws.onerror = function () {
        estado("sin enlace", "off");
        try { ws.close(); } catch (e) { /* ya cerrado */ }
      };
    };

    conectar();

    return {
      cerrar: function () {
        cerrado = true;
        if (ws) ws.close();
      }
    };
  };

  /* ---------------------------------------------------------------- UI */

  App.estadoLive = function (el, texto, clase) {
    if (!el) return;
    el.className = "live-pill" + (clase ? " " + clase : "");
    el.innerHTML = '<span class="dot"></span>' + App.esc(texto);
  };

  App.toast = function (titulo, detalle, tipo) {
    let pila = document.querySelector(".toasts");
    if (!pila) {
      pila = document.createElement("div");
      pila.className = "toasts";
      document.body.appendChild(pila);
    }
    const el = document.createElement("div");
    el.className = "toast" + (tipo === "info" ? " info" : "");
    el.innerHTML =
      '<div class="tt">' + App.esc(titulo) + "</div>" +
      '<div class="ts">' + App.esc(detalle) + "</div>";
    pila.appendChild(el);
    setTimeout(function () { el.remove(); }, 6500);
  };

  /* Barra de progreso simple para conteos. */
  App.barra = function (valor, maximo, color) {
    const pct = maximo > 0 ? Math.min(100, Math.round((valor / maximo) * 100)) : 0;
    return '<div class="bar"><i style="width:' + pct + "%;background:" + (color || "#38bdf8") + '"></i></div>';
  };

  /* Traza sismica sintetica: no hay sismografo real conectado, la forma
     de onda se deriva del ultimo evento para dar contexto visual. */
  App.traza = function (opciones) {
    const o = opciones || {};
    const ancho = o.ancho || 640;
    const alto = o.alto || 120;
    const semilla = o.semilla || 7;
    const amplitud = o.amplitud == null ? 0.7 : o.amplitud;
    const puntos = [];
    let s = semilla % 2147483647;
    if (s <= 0) s += 2147483646;
    const rnd = function () { s = (s * 16807) % 2147483647; return s / 2147483647; };

    const n = 220;
    for (let i = 0; i <= n; i++) {
      const x = (i / n) * ancho;
      const t = i / n;
      /* ruido de fondo + arribo P (impulso) + paquete S (decaimiento) */
      let v = (rnd() - 0.5) * 0.06;
      v += Math.sin(t * 90 + semilla) * 0.015;
      if (t > 0.18 && t < 0.26) v += Math.exp(-(t - 0.2) * 34) * Math.sin(t * 260) * 0.5 * amplitud;
      if (t > 0.32) {
        const d = t - 0.32;
        v += Math.exp(-d * 4.2) * (rnd() - 0.5) * 1.5 * amplitud;
        v += Math.exp(-d * 3.0) * Math.sin(d * 120) * 0.45 * amplitud;
      }
      const y = alto / 2 - v * (alto * 0.42);
      puntos.push(x.toFixed(1) + "," + y.toFixed(1));
    }
    return puntos.join(" ");
  };

  /* Linea de tiempo compartida por las trazas. */
  App.ejesTraza = function (ancho, alto) {
    let marcas = "";
    for (let i = 0; i <= 6; i++) {
      const x = (i / 6) * ancho;
      marcas += '<line x1="' + x + '" y1="0" x2="' + x + '" y2="' + alto +
        '" stroke="#1e293b" stroke-width="1" stroke-dasharray="2 6" />';
    }
    marcas += '<line x1="0" y1="' + (alto / 2) + '" x2="' + ancho + '" y2="' + (alto / 2) +
      '" stroke="#334155" stroke-width="1" />';
    return marcas;
  };

  /* ---------------------------------------------------------------- demo */

  /* POST JSON generico para las acciones del demo (api/eventos y
     api/simular); devuelve el cuerpo o lanza Error con el detalle. */
  App.postJson = function (ruta, cuerpo) {
    return fetch(ruta, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(cuerpo)
    }).then(function (resp) {
      if (!resp.ok) throw new Error("HTTP " + resp.status + " en " + ruta);
      return resp.json();
    });
  };

  /* Inyecta un evento directamente en la API; el nivel y el aviso se
     calculan en el backend (p56_niveles) con la misma logica del flujo
     simulado, asi que el resultado es identico a un evento real. */
  App.inyectarEvento = async function (cuerpo) {
    const t = Math.floor(Date.now() / 1000);
    return App.postJson("/api/eventos", Object.assign({
      source: "demo",
      source_id: "demo-" + t,
      t: t
    }, cuerpo));
  };

  /* Detona un M6.5 a ~25 km de Mexicali / Campus ITT: nivel critico
     garantizado (M >= 5.5), aparece toast + flash en el dashboard. */
  App.demoDetonar = async function (boton) {
    if (boton) boton.disabled = true;
    try {
      await App.inyectarEvento({
        mag: 6.5, lat: 32.52, lon: -115.44, lugar: "Mexicali (demo)"
      });
      App.toast("Sismo crítico inyectado", "M 6.5 en Mexicali · mantente atento al toast de alerta crítica", "info");
    } catch (e) {
      App.toast("No se pudo detonar", String(e.message || e));
    }finally {
      if (boton) setTimeout(function () { boton.disabled = false; }, 1200);
    }
  };

  /* Lanza uno de los escenarios del simulador (POST /api/simular). */
  App.demoEscenario = async function (modo, boton) {
    if (boton) boton.disabled = true;
    try {
      await App.postJson("/api/simular", { modo: modo });
      App.toast("Escenario lanzado: " + modo,
        "los eventos entran al pipeline en los próximos segundos", "info");
    } catch (e) {
      App.toast("No se pudo lanzar " + modo, String(e.message || e));
    } finally {
      if (boton) setTimeout(function () { boton.disabled = false; }, 1200);
    }
  };

  /* Formulario de sismo manual: lee los #m-... dentro del form. */
  App.demoManual = async function (form) {
    const get = function (id) { return form.querySelector("#" + id); };
    const mag = parseFloat(get("m-mag").value);
    const lat = parseFloat(get("m-lat").value);
    const lon = parseFloat(get("m-lon").value);
    const lugar = (get("m-lugar").value || "").trim() || "Lugar sin nombre";

    if (isNaN(mag) || mag < 1 || mag > 9.5) {
      App.toast("Magnitud inválida", "debe estar entre 1.0 y 9.5");
      return;
    }
    if (isNaN(lat) || isNaN(lon)) {
      App.toast("Coordenadas inválidas", "lat y lon deben ser números");
      return;
    }

    const boton = form.querySelector("button[type=submit]");
    if (boton) boton.disabled = true;
    try {
      await App.inyectarEvento({ mag: mag, lat: lat, lon: lon, lugar: lugar });
      App.toast("Evento inyectado", "M " + mag.toFixed(1) + " en " + lugar + " · visible en segundos", "info");
      form.reset();
      form.classList.remove("open");
    } catch (e) {
      App.toast("No se pudo inyectar", String(e.message || e));
    } finally {
      if (boton) setTimeout(function () { boton.disabled = false; }, 1200);
    }
  };

  /* Conecta los controles del demo a los ids estandar del HTML.
     Todos los ids son opcionales: solo se conectan si existen. */
  App.demoBind = function (opciones) {
    const o = opciones || {};
    const porId = function (id) { return document.getElementById(id); };

    const detonar = porId(o.idDetonar || "btn-critico");
    if (detonar) detonar.addEventListener("click", function () {
      App.demoDetonar(detonar);
    });

    const escenarios = porId(o.idEscenarios || "demo-escenarios");
    if (escenarios) escenarios.addEventListener("click", function (ev) {
      const chip = ev.target.closest(".chip");
      if (!chip) return;
      App.demoEscenario(chip.getAttribute("data-modo") || chip.dataset.modo, chip);
    });

    const abrir = porId(o.idAbrir || "btn-manual");
    const form = porId(o.idForma || "form-manual");
    if (abrir && form) {
      abrir.addEventListener("click", function () { form.classList.toggle("open"); });
      form.addEventListener("submit", function (ev) {
        ev.preventDefault();
        App.demoManual(form);
      });
    }
  };

  window.App = App;
})();
