// PerfectScreen — panel logic.
// Talks to jsx/host.jsx through the CEP bridge (__adobe_cep__.evalScript).

(function () {
  "use strict";

  // ---- CEP bridge ----------------------------------------------------

  function evalScript(script, cb) {
    if (window.__adobe_cep__ && window.__adobe_cep__.evalScript) {
      window.__adobe_cep__.evalScript(script, cb || function () {});
    } else if (cb) {
      cb('{"ok":false,"error":"Not running inside After Effects."}');
    }
  }

  function send(action, payload, cb) {
    var msg = JSON.stringify({ action: action, payload: payload || {} });
    evalScript("PS.dispatch(" + JSON.stringify(msg) + ")", function (raw) {
      var res;
      try {
        res = JSON.parse(raw);
      } catch (e) {
        res = { ok: false, error: "Bad response from host: " + raw };
      }
      if (cb) cb(res);
    });
  }

  // ---- status line -----------------------------------------------------

  var statusEl = document.getElementById("status");
  function status(msg, cls) {
    statusEl.textContent = msg;
    statusEl.className = "status" + (cls ? " " + cls : "");
  }

  // ---- controls --------------------------------------------------------

  var inputs = Array.prototype.slice.call(document.querySelectorAll("[data-ctl]"));
  var debounceTimers = {};

  function displayValue(el) {
    var span = document.getElementById("v-" + el.id.slice(2));
    if (span) span.textContent = el.value;
  }

  function readControl(el) {
    return el.type === "checkbox" ? (el.checked ? 1 : 0) : Number(el.value);
  }

  function pushControl(el) {
    var name = el.getAttribute("data-ctl");
    clearTimeout(debounceTimers[name]);
    debounceTimers[name] = setTimeout(function () {
      send("setControl", { name: name, value: readControl(el) }, function (res) {
        if (!res.ok) status(res.error, "error");
        else status("Updated " + name.replace(/^PS /, ""), "ok");
      });
    }, 80);
  }

  inputs.forEach(function (el) {
    displayValue(el);
    el.addEventListener("input", function () {
      displayValue(el);
      if (el.id === "c-pixelson") updatePixelSectionState();
      pushControl(el);
    });
    el.addEventListener("change", function () {
      displayValue(el);
      if (el.id === "c-pixelson") updatePixelSectionState();
      pushControl(el);
    });
  });

  function updatePixelSectionState() {
    var on = document.getElementById("c-pixelson").checked;
    document.getElementById("pixel-controls").className = on ? "" : "disabled";
  }

  // ---- populate from AE ------------------------------------------------

  function refresh() {
    send("getState", {}, function (res) {
      if (!res.ok) { status(res.error, "error"); return; }
      if (!res.result.rigged) {
        status("No rig on the selected layer. Select footage and click Apply.");
        return;
      }
      var values = res.result.values || {};
      inputs.forEach(function (el) {
        var name = el.getAttribute("data-ctl");
        if (!(name in values)) return;
        if (el.type === "checkbox") el.checked = values[name] > 0;
        else el.value = values[name];
        displayValue(el);
      });
      updatePixelSectionState();
      status("Connected: " + res.result.precomp, "ok");
    });
  }

  // ---- buttons -----------------------------------------------------------

  document.getElementById("btn-apply").addEventListener("click", function () {
    status("Rigging layer…");
    send("apply", {}, function (res) {
      if (!res.ok) { status(res.error, "error"); return; }
      if (res.result.alreadyRigged) {
        status("Layer is already rigged — controls reconnected.", "ok");
      } else {
        status("Rig built: " + res.result.precomp, "ok");
      }
      refresh();
    });
  });

  document.getElementById("btn-refresh").addEventListener("click", refresh);

  document.getElementById("btn-pin-mask").addEventListener("click", function () {
    send("pinFromMask", {}, function (res) {
      status(res.ok ? "Corner pin set from mask." : res.error, res.ok ? "ok" : "error");
    });
  });

  document.getElementById("btn-pin-reset").addEventListener("click", function () {
    send("resetPin", {}, function (res) {
      status(res.ok ? "Corner pin reset." : res.error, res.ok ? "ok" : "error");
    });
  });

  // ---- presets ------------------------------------------------------------

  var presetSelect = document.getElementById("preset-select");
  Object.keys(PS_PRESETS).forEach(function (name) {
    var opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    presetSelect.appendChild(opt);
  });

  document.getElementById("btn-preset").addEventListener("click", function () {
    var name = presetSelect.value;
    send("applyPreset", { values: PS_PRESETS[name] }, function (res) {
      if (!res.ok) { status(res.error, "error"); return; }
      status("Preset applied: " + name, "ok");
      refresh();
    });
  });

  // ---- init -----------------------------------------------------------------

  updatePixelSectionState();
  refresh();
})();
