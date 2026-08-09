// PerfectScreen — core ExtendScript utilities
// ExtendScript is ES3: no JSON object, no Array.forEach, etc.

var PSU = (function () {

    // ---- minimal JSON (ExtendScript has none) -------------------------

    function jsonStringify(v) {
        var t = typeof v;
        if (v === null || v === undefined) return "null";
        if (t === "number") return isFinite(v) ? String(v) : "null";
        if (t === "boolean") return v ? "true" : "false";
        if (t === "string") {
            return '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
                          .replace(/\n/g, "\\n").replace(/\r/g, "\\r")
                          .replace(/\t/g, "\\t") + '"';
        }
        if (v instanceof Array) {
            var parts = [];
            for (var i = 0; i < v.length; i++) parts.push(jsonStringify(v[i]));
            return "[" + parts.join(",") + "]";
        }
        if (t === "object") {
            var kv = [];
            for (var k in v) {
                if (v.hasOwnProperty(k)) kv.push(jsonStringify(k) + ":" + jsonStringify(v[k]));
            }
            return "{" + kv.join(",") + "}";
        }
        return "null";
    }

    function jsonParse(s) {
        // Panel is the only caller; input is trusted. Basic sanity check,
        // then eval — the standard ExtendScript approach.
        if (/^[\],:{}\s]*$/.test(
            s.replace(/\\["\\\/bfnrtu]/g, "@")
             .replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, "]")
             .replace(/(?:^|:|,)(?:\s*\[)+/g, ""))) {
            return eval("(" + s + ")");
        }
        throw new Error("Bad JSON payload");
    }

    // ---- comp / layer helpers -----------------------------------------

    function activeComp() {
        var c = app.project.activeItem;
        return (c && c instanceof CompItem) ? c : null;
    }

    function findLayer(comp, name) {
        for (var i = 1; i <= comp.numLayers; i++) {
            if (comp.layer(i).name === name) return comp.layer(i);
        }
        return null;
    }

    function firstSelectedAVLayer(comp) {
        var sel = comp.selectedLayers;
        for (var i = 0; i < sel.length; i++) {
            if (sel[i] instanceof AVLayer) return sel[i];
        }
        return null;
    }

    // ---- effect helpers -------------------------------------------------

    // Apply an effect trying a list of match names, then a display name.
    function applyEffect(layer, matchNames, displayName) {
        var fxGroup = layer.property("ADBE Effect Parade");
        for (var i = 0; i < matchNames.length; i++) {
            try {
                if (fxGroup.canAddProperty(matchNames[i])) {
                    return fxGroup.addProperty(matchNames[i]);
                }
            } catch (e) {}
        }
        if (displayName) {
            try {
                if (fxGroup.canAddProperty(displayName)) {
                    return fxGroup.addProperty(displayName);
                }
            } catch (e2) {}
        }
        throw new Error("Cannot apply effect: " + (displayName || matchNames.join(", ")) +
                        " (is this AE version missing it?)");
    }

    // Find a direct child property by any of several names (exact, then
    // case-insensitive, then substring).
    function prop(group, names) {
        if (!(names instanceof Array)) names = [names];
        var i, j, p;
        for (i = 0; i < names.length; i++) {
            try {
                p = group.property(names[i]);
                if (p) return p;
            } catch (e) {}
        }
        for (j = 1; j <= group.numProperties; j++) {
            p = group.property(j);
            for (i = 0; i < names.length; i++) {
                if (p.name.toLowerCase() === String(names[i]).toLowerCase()) return p;
            }
        }
        for (j = 1; j <= group.numProperties; j++) {
            p = group.property(j);
            for (i = 0; i < names.length; i++) {
                if (p.name.toLowerCase().indexOf(String(names[i]).toLowerCase()) !== -1) return p;
            }
        }
        return null;
    }

    // Recursive search for a property by display name (for effects with
    // nested groups like Add Grain / Fractal Noise).
    function propDeep(group, name) {
        for (var i = 1; i <= group.numProperties; i++) {
            var p = group.property(i);
            if (p.name.toLowerCase() === name.toLowerCase()) return p;
            if (p.propertyType !== PropertyType.PROPERTY) {
                var r = propDeep(p, name);
                if (r) return r;
            }
        }
        return null;
    }

    function setVal(p, v) {
        if (p) { try { p.setValue(v); } catch (e) {} }
        return p;
    }

    function setExpr(p, expr) {
        if (p) { try { p.expression = expr; } catch (e) {} }
        return p;
    }

    return {
        stringify: jsonStringify,
        parse: jsonParse,
        activeComp: activeComp,
        findLayer: findLayer,
        firstSelectedAVLayer: firstSelectedAVLayer,
        applyEffect: applyEffect,
        prop: prop,
        propDeep: propDeep,
        setVal: setVal,
        setExpr: setExpr
    };
})();
