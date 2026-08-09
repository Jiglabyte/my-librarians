// PerfectScreen — rig construction.
//
// The rig lives inside a precomp ("PS Screen - <layer>"). A hidden null,
// PS_Controls, carries one Expression Control per parameter. Every wired
// effect property reads its value from that null via an expression, so:
//   - the panel only ever reads/writes PS_Controls
//   - every parameter is keyframeable in AE like any other property
//   - settings persist in the project file with no sidecar state
//
// Layer stack inside the precomp (top -> bottom):
//   PS_Controls   null, all Expression Controls
//   PS_Grain      adjustment: Add Grain
//   PS_Vignette   black solid, Multiply, radial Gradient Ramp
//   PS_Dust       black solid, Screen, thresholded Fractal Noise
//   PS_Optics     adjustment: Exposure, Tint, Optics Compensation, Camera Lens Blur
//   PS_Grid       black solid: 2x Venetian Blinds (pixel grid + scanlines)
//   PS_PixelFX    adjustment: Mosaic + Glow  <- master pixel toggle gates this
//   PS_SRC_R      duplicate, red channel only, Add mode, shifted +x
//   PS_SRC_B      duplicate, blue channel only, Add mode, shifted -x
//   PS_SRC        original layer, green channel only

var PSRig = (function () {

    var CTRL = "PS_Controls";
    var PRECOMP_PREFIX = "PS Screen - ";

    // name, type ("slider"|"checkbox"), default
    var CONTROLS = [
        ["PS Exposure",             "slider",   0],
        ["PS Auto Exposure",        "checkbox", 0],
        ["PS Tint Type",            "slider",   0],   // 0 neutral, 1 warm, 2 cool, 3 green
        ["PS Tint Amount",          "slider",   0],
        ["PS Distortion",           "slider",   5],   // -50 pincushion .. +50 barrel
        ["PS DOF",                  "slider",  15],
        ["PS Chromatic Aberration", "slider",   2],
        ["PS Vignette",             "slider",  35],
        ["PS Vignette Feather",     "slider", 100],
        ["PS Dust Amount",          "slider",  12],
        ["PS Dust Size",            "slider",   3],
        ["PS Dust Opacity",         "slider",  70],
        ["PS Grain",                "slider",  20],
        ["PS Grain Size",           "slider",   1],
        ["PS Pixels On",            "checkbox", 1],   // master LCD toggle
        ["PS Pixel Size",           "slider",   4],
        ["PS Grid Intensity",       "slider",  35],
        ["PS Pixel Glow",           "slider",  30],
        ["PS Scanlines On",         "checkbox", 0],
        ["PS RGB Shift",            "slider",   2]
    ];

    // expression snippet: read a control value
    function C(name) {
        return 'thisComp.layer("' + CTRL + '").effect("' + name + '")(1)';
    }

    // ------------------------------------------------------------------
    // Rig resolution: given the active comp / selection, find the rig comp.
    // Returns { pre: CompItem, ctrl: Layer, pinLayer: Layer|null } or null.
    function resolve() {
        var comp = PSU.activeComp();
        if (!comp) return null;

        // Case 1: we are inside the rig precomp.
        var ctrl = PSU.findLayer(comp, CTRL);
        if (ctrl) return { pre: comp, ctrl: ctrl, pinLayer: findPinLayer(comp) };

        // Case 2: a rigged precomp layer is selected in the parent comp.
        var sel = PSU.firstSelectedAVLayer(comp);
        if (sel && sel.source instanceof CompItem) {
            var inner = PSU.findLayer(sel.source, CTRL);
            if (inner) return { pre: sel.source, ctrl: inner, pinLayer: sel };
        }

        // Case 3: any rigged precomp layer in the active comp.
        for (var i = 1; i <= comp.numLayers; i++) {
            var ly = comp.layer(i);
            if (ly instanceof AVLayer && ly.source instanceof CompItem &&
                PSU.findLayer(ly.source, CTRL)) {
                return { pre: ly.source, ctrl: PSU.findLayer(ly.source, CTRL), pinLayer: ly };
            }
        }
        return null;
    }

    // Find the layer in some comp that uses `pre` as its source (for corner pin).
    function findPinLayer(pre) {
        for (var i = 1; i <= app.project.numItems; i++) {
            var it = app.project.item(i);
            if (!(it instanceof CompItem) || it === pre) continue;
            for (var j = 1; j <= it.numLayers; j++) {
                var ly = it.layer(j);
                if (ly instanceof AVLayer && ly.source === pre) return ly;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    function addControls(pre) {
        var ctrl = pre.layers.addNull(pre.duration);
        ctrl.name = CTRL;
        ctrl.enabled = false;
        ctrl.label = 14; // cyan
        for (var i = 0; i < CONTROLS.length; i++) {
            var def = CONTROLS[i];
            var fx = PSU.applyEffect(ctrl,
                [def[1] === "checkbox" ? "ADBE Checkbox Control" : "ADBE Slider Control"],
                def[1] === "checkbox" ? "Checkbox Control" : "Slider Control");
            fx.name = def[0];
            PSU.setVal(fx.property(1), def[2]);
        }
        return ctrl;
    }

    // ------------------------------------------------------------------
    function buildChannelSplit(pre, src) {
        src.name = "PS_SRC";

        var dupB = src.duplicate(); // lands just above src
        dupB.name = "PS_SRC_B";
        var dupR = dupB.duplicate();
        dupR.name = "PS_SRC_R";

        // Shift Channels enum order: Alpha, Red, Green, Blue, Luminance,
        // Hue, Lightness, Saturation, Full On, Full Off
        var OFF = 10;
        function shift(layer, r, g, b) {
            var fx = PSU.applyEffect(layer, ["ADBE Shift Channels"], "Shift Channels");
            PSU.setVal(PSU.prop(fx, ["Take Red From"]),   r);
            PSU.setVal(PSU.prop(fx, ["Take Green From"]), g);
            PSU.setVal(PSU.prop(fx, ["Take Blue From"]),  b);
        }
        shift(src,  OFF, 3, OFF);   // green only
        shift(dupR, 2, OFF, OFF);   // red only
        shift(dupB, OFF, OFF, 4);   // blue only
        dupR.blendingMode = BlendingMode.ADD;
        dupB.blendingMode = BlendingMode.ADD;

        // Lens CA is always active; pixel-level RGB shift joins in only
        // while the master pixel toggle is on.
        var offset =
            'var C = thisComp.layer("' + CTRL + '");\n' +
            'var amt = C.effect("PS Chromatic Aberration")(1) + ' +
            '(C.effect("PS Pixels On")(1) > 0 ? C.effect("PS RGB Shift")(1) : 0);\n';
        PSU.setExpr(dupR.property("ADBE Transform Group").property("ADBE Position"),
            offset + 'value + [amt / 2, 0];');
        PSU.setExpr(dupB.property("ADBE Transform Group").property("ADBE Position"),
            offset + 'value + [-amt / 2, 0];');
    }

    // ------------------------------------------------------------------
    function buildPixelFX(pre) {
        var fx = pre.layers.addSolid([0, 0, 0], "PS_PixelFX", pre.width, pre.height,
                                     pre.pixelAspect, pre.duration);
        fx.adjustmentLayer = true;

        // Master toggle: adjustment layer at 0% opacity applies nothing.
        PSU.setExpr(fx.property("ADBE Transform Group").property("ADBE Opacity"),
            C("PS Pixels On") + ' > 0 ? 100 : 0;');

        var mosaic = PSU.applyEffect(fx, ["ADBE Mosaic"], "Mosaic");
        PSU.setExpr(PSU.prop(mosaic, ["Horizontal Blocks"]),
            'var sz = Math.max(1, ' + C("PS Pixel Size") + ');\n' +
            'Math.max(2, Math.round(thisComp.width / sz));');
        PSU.setExpr(PSU.prop(mosaic, ["Vertical Blocks"]),
            'var sz = Math.max(1, ' + C("PS Pixel Size") + ');\n' +
            'Math.max(2, Math.round(thisComp.height / sz));');
        PSU.setVal(PSU.prop(mosaic, ["Sharp Colors"]), 1);

        var glow = PSU.applyEffect(fx, ["ADBE Glo2"], "Glow");
        PSU.setVal(PSU.prop(glow, ["Glow Threshold"]), 60);
        PSU.setExpr(PSU.prop(glow, ["Glow Radius"]),    C("PS Pixel Glow") + ' * 0.4;');
        PSU.setExpr(PSU.prop(glow, ["Glow Intensity"]), C("PS Pixel Glow") + ' * 0.015;');
        return fx;
    }

    function buildGrid(pre) {
        var grid = pre.layers.addSolid([0, 0, 0], "PS_Grid", pre.width, pre.height,
                                       pre.pixelAspect, pre.duration);
        // Whole layer gated by master toggle * grid intensity.
        PSU.setExpr(grid.property("ADBE Transform Group").property("ADBE Opacity"),
            '(' + C("PS Pixels On") + ' > 0 ? 1 : 0) * ' + C("PS Grid Intensity") + ';');

        // Vertical pixel-column lines: always on while the layer shows.
        var v = PSU.applyEffect(grid, ["ADBE Venetian Blinds"], "Venetian Blinds");
        PSU.setVal(PSU.prop(v, ["Transition Completion"]), 88);
        PSU.setVal(PSU.prop(v, ["Direction"]), 90);
        PSU.setExpr(PSU.prop(v, ["Width"]),
            'Math.max(2, ' + C("PS Pixel Size") + ');');

        // Horizontal scanlines: gated by their own checkbox.
        // Completion 100 = fully transparent = off; ~82 = visible lines.
        var h = PSU.applyEffect(grid, ["ADBE Venetian Blinds"], "Venetian Blinds");
        PSU.setExpr(PSU.prop(h, ["Transition Completion"]),
            C("PS Scanlines On") + ' > 0 ? 82 : 100;');
        PSU.setVal(PSU.prop(h, ["Direction"]), 0);
        PSU.setExpr(PSU.prop(h, ["Width"]),
            'Math.max(2, ' + C("PS Pixel Size") + ');');
        return grid;
    }

    function buildOptics(pre) {
        var op = pre.layers.addSolid([0, 0, 0], "PS_Optics", pre.width, pre.height,
                                     pre.pixelAspect, pre.duration);
        op.adjustmentLayer = true;

        // Exposure (with optional auto mode sampling the source layer).
        var expo = PSU.applyEffect(op, ["ADBE Exposure2"], "Exposure");
        var expoProp = PSU.prop(expo, ["Master Exposure", "Exposure"]);
        PSU.setExpr(expoProp,
            'var C = thisComp.layer("' + CTRL + '");\n' +
            'var manual = C.effect("PS Exposure")(1);\n' +
            'if (C.effect("PS Auto Exposure")(1) > 0) {\n' +
            '  var L = thisComp.layer("PS_SRC");\n' +
            '  var pts = [[0.3,0.3],[0.7,0.3],[0.5,0.5],[0.3,0.7],[0.7,0.7]];\n' +
            '  var sum = 0;\n' +
            '  for (var i = 0; i < pts.length; i++) {\n' +
            '    sum += L.sampleImage([L.width*pts[i][0], L.height*pts[i][1]],\n' +
            '                         [L.width*0.08, L.height*0.08], true, time)[1];\n' +
            '  }\n' +
            // PS_SRC is green-only after the channel split; green dominates
            // luminance, so it is a usable brightness proxy.
            '  manual + clamp(linear(sum/pts.length, 0.05, 0.9, 2.2, -2.2), -3, 3);\n' +
            '} else manual;');

        // Tint: white point picks the cast, amount blends it in.
        var tint = PSU.applyEffect(op, ["ADBE Tint"], "Tint");
        PSU.setExpr(PSU.prop(tint, ["Map White To"]),
            'var t = Math.round(' + C("PS Tint Type") + ');\n' +
            't == 1 ? [1, 0.93, 0.82, 1] :\n' +   // warm
            't == 2 ? [0.82, 0.90, 1, 1] :\n' +   // cool
            't == 3 ? [0.85, 1, 0.87, 1] : [1, 1, 1, 1];');  // green / neutral
        PSU.setExpr(PSU.prop(tint, ["Amount to Tint"]), C("PS Tint Amount") + ';');

        // Barrel / pincushion distortion.
        var oc = PSU.applyEffect(op, ["ADBE Optics Compensation"], "Optics Compensation");
        PSU.setExpr(PSU.prop(oc, ["Field Of View", "Field of View"]),
            'Math.abs(' + C("PS Distortion") + ') * 1.8;');
        PSU.setExpr(PSU.prop(oc, ["Reverse Lens Distortion"]),
            C("PS Distortion") + ' < 0 ? 1 : 0;');

        // Depth of field.
        var dof = PSU.applyEffect(op, ["ADBE Camera Lens Blur"], "Camera Lens Blur");
        PSU.setExpr(PSU.prop(dof, ["Blur Radius"]), C("PS DOF") + ' * 0.4;');
        return op;
    }

    function buildDust(pre) {
        var dust = pre.layers.addSolid([0, 0, 0], "PS_Dust", pre.width, pre.height,
                                       pre.pixelAspect, pre.duration);
        dust.blendingMode = BlendingMode.SCREEN;
        PSU.setExpr(dust.property("ADBE Transform Group").property("ADBE Opacity"),
            '(' + C("PS Dust Amount") + ' > 0.5 ? 1 : 0) * ' + C("PS Dust Opacity") + ';');

        var fn = PSU.applyEffect(dust, ["ADBE Fractal Noise"], "Fractal Noise");
        // Crushed noise -> sparse bright specks. Amount raises brightness
        // (more specks survive); size scales the noise.
        PSU.setVal(PSU.propDeep(fn, "Contrast"), 700);
        PSU.setExpr(PSU.propDeep(fn, "Brightness"),
            '-168 + ' + C("PS Dust Amount") + ' * 0.85;');
        PSU.setExpr(PSU.propDeep(fn, "Scale"),
            'Math.max(3, ' + C("PS Dust Size") + ' * 3);');
        PSU.setExpr(PSU.propDeep(fn, "Evolution"), 'time * 15;');
        return dust;
    }

    function buildVignette(pre) {
        var vig = pre.layers.addSolid([0, 0, 0], "PS_Vignette", pre.width, pre.height,
                                      pre.pixelAspect, pre.duration);
        vig.blendingMode = BlendingMode.MULTIPLY;
        PSU.setExpr(vig.property("ADBE Transform Group").property("ADBE Opacity"),
            C("PS Vignette") + ';');

        // Radial ramp, white centre (multiply no-op) to black edges.
        var ramp = PSU.applyEffect(vig, ["ADBE Ramp"], "Gradient Ramp");
        PSU.setVal(PSU.prop(ramp, ["Ramp Shape"]), 2); // radial
        PSU.setVal(PSU.prop(ramp, ["Start of Ramp"]), [pre.width / 2, pre.height / 2]);
        PSU.setVal(PSU.prop(ramp, ["Start Color"]), [1, 1, 1, 1]);
        PSU.setVal(PSU.prop(ramp, ["End Color"]), [0, 0, 0, 1]);
        PSU.setExpr(PSU.prop(ramp, ["End of Ramp"]),
            'var f = ' + C("PS Vignette Feather") + ';\n' +
            '[thisComp.width / 2 + thisComp.width * 0.45 + f * 2, thisComp.height / 2];');
        return vig;
    }

    function buildGrain(pre) {
        var gr = pre.layers.addSolid([0, 0, 0], "PS_Grain", pre.width, pre.height,
                                     pre.pixelAspect, pre.duration);
        gr.adjustmentLayer = true;
        var fx = PSU.applyEffect(gr, ["ADBE AddGrain", "ADBE Add Grain"], "Add Grain");
        // Viewing Mode enum: Preview / Blending Matte / Final Output — use final.
        PSU.setVal(PSU.prop(fx, ["Viewing Mode"]), 3);
        PSU.setExpr(PSU.propDeep(fx, "Intensity"), C("PS Grain") + ' * 0.02;');
        PSU.setExpr(PSU.propDeep(fx, "Size"),
            'Math.max(0.2, ' + C("PS Grain Size") + ');');
        return gr;
    }

    // ------------------------------------------------------------------
    // Main entry: rig the selected layer.
    function apply() {
        var comp = PSU.activeComp();
        if (!comp) throw new Error("Open a composition and select the screen-content layer.");
        var layer = PSU.firstSelectedAVLayer(comp);
        if (!layer) throw new Error("Select the footage layer to use as screen content.");

        if (layer.source instanceof CompItem && PSU.findLayer(layer.source, CTRL)) {
            return { alreadyRigged: true };
        }

        app.beginUndoGroup("PerfectScreen: Apply");
        try {
            var pre = comp.layers.precompose([layer.index],
                PRECOMP_PREFIX + layer.name, true);
            var pinLayer = null;
            for (var i = 1; i <= comp.numLayers; i++) {
                if (comp.layer(i).source === pre) { pinLayer = comp.layer(i); break; }
            }

            // Bottom-up: each addSolid/addNull lands on top of the stack.
            buildChannelSplit(pre, pre.layer(1));
            buildPixelFX(pre);
            buildGrid(pre);
            buildOptics(pre);
            buildDust(pre);
            buildVignette(pre);
            buildGrain(pre);
            addControls(pre);

            // Corner pin on the precomp layer in the parent comp. Defaults
            // are the layer corners (identity) — drag them in the viewer or
            // use Set From Mask.
            PSU.applyEffect(pinLayer, ["ADBE Corner Pin"], "Corner Pin");

            return { alreadyRigged: false, precomp: pre.name };
        } finally {
            app.endUndoGroup();
        }
    }

    return {
        CTRL: CTRL,
        CONTROLS: CONTROLS,
        resolve: resolve,
        apply: apply
    };
})();
