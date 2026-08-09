// PerfectScreen — CEP host entry point.
// The panel calls PS.dispatch('<json>') and gets a JSON string back.

#include "core/utils.jsx"
#include "core/rig.jsx"

var PS = (function () {

    var PIN_PROPS = {
        ul: "Upper Left",
        ur: "Upper Right",
        ll: "Lower Left",
        lr: "Lower Right"
    };

    function pinEffect(pinLayer) {
        if (!pinLayer) return null;
        var fxGroup = pinLayer.property("ADBE Effect Parade");
        for (var i = 1; i <= fxGroup.numProperties; i++) {
            if (fxGroup.property(i).matchName === "ADBE Corner Pin") {
                return fxGroup.property(i);
            }
        }
        return null;
    }

    // ---- actions -------------------------------------------------------

    function doApply() {
        return PSRig.apply();
    }

    function doGetState() {
        var rig = PSRig.resolve();
        if (!rig) return { rigged: false };

        var values = {};
        for (var i = 0; i < PSRig.CONTROLS.length; i++) {
            var name = PSRig.CONTROLS[i][0];
            var fx = rig.ctrl.effect(name);
            if (fx) values[name] = fx.property(1).value;
        }

        var pin = null;
        var fx2 = pinEffect(rig.pinLayer);
        if (fx2) {
            pin = {};
            for (var k in PIN_PROPS) {
                if (PIN_PROPS.hasOwnProperty(k)) {
                    var p = PSU.prop(fx2, [PIN_PROPS[k]]);
                    if (p) pin[k] = p.value;
                }
            }
        }
        return { rigged: true, precomp: rig.pre.name, values: values, pin: pin };
    }

    function doSetControl(payload) {
        var rig = PSRig.resolve();
        if (!rig) throw new Error("No PerfectScreen rig found. Select the rigged layer (or click Apply first).");
        var fx = rig.ctrl.effect(payload.name);
        if (!fx) throw new Error("Unknown control: " + payload.name);
        app.beginUndoGroup("PerfectScreen: " + payload.name);
        try {
            fx.property(1).setValue(Number(payload.value));
        } finally {
            app.endUndoGroup();
        }
        return { set: payload.name };
    }

    function doApplyPreset(payload) {
        var rig = PSRig.resolve();
        if (!rig) throw new Error("No PerfectScreen rig found. Click Apply on a layer first.");
        app.beginUndoGroup("PerfectScreen: Preset");
        try {
            for (var name in payload.values) {
                if (!payload.values.hasOwnProperty(name)) continue;
                var fx = rig.ctrl.effect(name);
                if (fx) fx.property(1).setValue(Number(payload.values[name]));
            }
        } finally {
            app.endUndoGroup();
        }
        return { preset: true };
    }

    function doSetPin(payload) {
        var rig = PSRig.resolve();
        var fx = rig ? pinEffect(rig.pinLayer) : null;
        if (!fx) throw new Error("No Corner Pin found — is the rig applied?");
        app.beginUndoGroup("PerfectScreen: Corner Pin");
        try {
            for (var k in PIN_PROPS) {
                if (PIN_PROPS.hasOwnProperty(k) && payload[k]) {
                    PSU.setVal(PSU.prop(fx, [PIN_PROPS[k]]), payload[k]);
                }
            }
        } finally {
            app.endUndoGroup();
        }
        return { pin: true };
    }

    function doResetPin() {
        var rig = PSRig.resolve();
        if (!rig || !rig.pinLayer) throw new Error("No rigged layer found.");
        var w = rig.pre.width, h = rig.pre.height;
        return doSetPin({ ul: [0, 0], ur: [w, 0], ll: [0, h], lr: [w, h] });
    }

    // Copy a 4-point mask on the rigged precomp layer into the corner pin.
    // Draw the mask clockwise from the top-left corner of the screen.
    function doPinFromMask() {
        var rig = PSRig.resolve();
        if (!rig || !rig.pinLayer) throw new Error("No rigged layer found.");
        var masks = rig.pinLayer.property("ADBE Mask Parade");
        if (!masks || masks.numProperties < 1) {
            throw new Error("Draw a 4-point mask on the rigged layer first (clockwise from top-left).");
        }
        var shape = masks.property(1).property("ADBE Mask Shape").value;
        if (shape.vertices.length !== 4) {
            throw new Error("The mask must have exactly 4 points (it has " +
                            shape.vertices.length + ").");
        }
        var v = shape.vertices;
        var out = doSetPin({ ul: v[0], ur: v[1], lr: v[2], ll: v[3] });
        // The mask has done its job; disable it so it doesn't crop the layer.
        masks.property(1).maskMode = MaskMode.NONE;
        return out;
    }

    // ---- dispatch --------------------------------------------------------

    function dispatch(jsonStr) {
        var out;
        try {
            var msg = PSU.parse(jsonStr);
            var payload = msg.payload || {};
            var result;
            switch (msg.action) {
                case "apply":       result = doApply(); break;
                case "getState":    result = doGetState(); break;
                case "setControl":  result = doSetControl(payload); break;
                case "applyPreset": result = doApplyPreset(payload); break;
                case "setPin":      result = doSetPin(payload); break;
                case "resetPin":    result = doResetPin(); break;
                case "pinFromMask": result = doPinFromMask(); break;
                default: throw new Error("Unknown action: " + msg.action);
            }
            out = { ok: true, result: result };
        } catch (e) {
            out = { ok: false, error: String(e.message || e) };
        }
        return PSU.stringify(out);
    }

    return { dispatch: dispatch };
})();
