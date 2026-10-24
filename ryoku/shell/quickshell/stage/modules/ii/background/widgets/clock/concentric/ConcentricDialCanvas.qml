pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.functions
import stage.services

Canvas {
    id: root

    property string dialStyle: "concentric" // "concentric" | "outer_only" | "inner_only" | "full_dense" | "minimal_arc" | "full_pixel3" | "none"
    property bool hideMinutePillArea: false
    property bool showMinuteDot: true
    property bool boldFont: false
    property real dialMarginOffset: 0.0

    property color textColor: WidgetColorScheme.textColorOnBg
    property color subtextColor: WidgetColorScheme.subtextColorOnBg
    property color accentColor: WidgetColorScheme.accentColor

    property int currentMinute: DateTime.clock.minutes
    property int currentSecond: DateTime.clock.seconds

    anchors.fill: parent
    contextType: "2d"

    Connections {
        target: DateTime.clock
        function onMinutesChanged() { root.requestPaint(); }
        function onSecondsChanged() {
            if (root.dialStyle === "minimal_arc" || root.dialStyle === "full_pixel3") {
                root.requestPaint();
            }
        }
    }

    Connections {
        target: Battery
        function onPercentageChanged() { if (root.dialStyle === "full_pixel3") root.requestPaint(); }
    }

    Connections {
        target: ResourceUsage
        function onMemoryUsedPercentageChanged() { if (root.dialStyle === "full_pixel3") root.requestPaint(); }
    }

    onDialStyleChanged:        requestPaint()
    onShowMinuteDotChanged:    requestPaint()
    onBoldFontChanged:         requestPaint()
    onDialMarginOffsetChanged: requestPaint()
    onTextColorChanged:        requestPaint()
    onSubtextColorChanged:     requestPaint()
    onAccentColorChanged:      requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        if (dialStyle === "none") return;

        var cx = width / 2;
        var cy = height / 2;
        var fontWeight = boldFont ? "bold " : "bold ";

        // ── STYLE 1: CONCENTRIC ──
        if (dialStyle === "concentric") {
            ctx.save();
            ctx.font = fontWeight + Math.round(width * 0.034) + "px sans-serif";
            ctx.fillStyle = subtextColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var r_outer = width * (0.44 + dialMarginOffset);
            var textR_outer = r_outer - 4;

            for (var i = 0; i < 30; i++) {
                var val = i * 2;
                var valStr = val < 10 ? "0" + val : "" + val;
                var angle = -Math.PI / 2 + (i * Math.PI / 15);

                ctx.fillText(valStr, cx + Math.cos(angle) * textR_outer, cy + Math.sin(angle) * textR_outer);

                var angle_mid = angle + (Math.PI / 30);
                ctx.beginPath();
                ctx.arc(cx + Math.cos(angle_mid) * textR_outer, cy + Math.sin(angle_mid) * textR_outer, 1.5, 0, 2 * Math.PI);
                ctx.fillStyle = ColorUtils.applyAlpha(subtextColor, 0.4);
                ctx.fill();
                ctx.fillStyle = subtextColor;
            }
            ctx.restore();

            ctx.save();
            ctx.font = fontWeight + Math.round(width * 0.052) + "px sans-serif";
            ctx.fillStyle = textColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var r_inner = width * (0.38 + dialMarginOffset);
            var innerNumbers = [
                { val: "05", angle: -Math.PI / 2 + (Math.PI / 6) },
                { val: "10", angle: -Math.PI / 2 + (Math.PI / 3) },
                { val: "15", angle: -Math.PI / 2 + (Math.PI / 2) },
                { val: "20", angle: -Math.PI / 2 + (2 * Math.PI / 3) },
                { val: "25", angle: -Math.PI / 2 + (5 * Math.PI / 6) },
                { val: "30", angle: -Math.PI / 2 + Math.PI },
                { val: "35", angle: -Math.PI / 2 + (7 * Math.PI / 6) },
                { val: "40", angle: -Math.PI / 2 + (4 * Math.PI / 3) },
                { val: "45", angle: -Math.PI / 2 + (3 * Math.PI / 2) },
                { val: "50", angle: -Math.PI / 2 + (5 * Math.PI / 3) },
                { val: "55", angle: -Math.PI / 2 + (11 * Math.PI / 6) },
                { val: "00", angle: -Math.PI / 2 }
            ];

            innerNumbers.forEach(function (item) {
                var tx = cx + Math.cos(item.angle) * r_inner;
                var ty = cy + Math.sin(item.angle) * r_inner;

                var rot = item.angle + Math.PI / 2;
                while (rot > Math.PI) rot -= 2 * Math.PI;
                while (rot < -Math.PI) rot += 2 * Math.PI;

                if (rot > Math.PI / 2 || rot < -Math.PI / 2) rot += Math.PI;

                ctx.save();
                ctx.translate(tx, ty);
                ctx.rotate(rot);
                ctx.fillText(item.val, 0, 0);
                ctx.restore();
            });
            ctx.restore();

            ctx.save();
            for (var j = 0; j < 12; j++) {
                var baseAngle = -Math.PI / 2 + (j * Math.PI / 6);
                for (var k = 1; k <= 4; k++) {
                    var tickAngle = baseAngle + (k * Math.PI / 30);
                    var isMiddle = (k === 2 || k === 3);
                    var tickHeight = isMiddle ? 6 : 3.5;
                    var tickWidth = isMiddle ? 2.0 : 1.2;

                    ctx.lineWidth = tickWidth;
                    ctx.strokeStyle = ColorUtils.applyAlpha(textColor, isMiddle ? 0.28 : 0.15);

                    var r_start = r_inner - (tickHeight / 2);
                    var r_end = r_inner + (tickHeight / 2);

                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(tickAngle) * r_start, cy + Math.sin(tickAngle) * r_start);
                    ctx.lineTo(cx + Math.cos(tickAngle) * r_end, cy + Math.sin(tickAngle) * r_end);
                    ctx.stroke();
                }
            }
            ctx.restore();
        }
        // ── STYLE 2: OUTER ONLY ──
        else if (dialStyle === "outer_only") {
            ctx.save();
            ctx.font = fontWeight + Math.round(width * 0.038) + "px sans-serif";
            ctx.fillStyle = textColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var r_out = width * (0.44 + dialMarginOffset);

            for (var i = 0; i < 12; i++) {
                var val = i * 5;
                var valStr = val < 10 ? "0" + val : "" + val;
                var angle = -Math.PI / 2 + (i * Math.PI / 6);

                ctx.fillText(valStr, cx + Math.cos(angle) * r_out, cy + Math.sin(angle) * r_out);
            }

            for (var m = 0; m < 60; m++) {
                if (m % 5 === 0) continue;
                var tickAngle = -Math.PI / 2 + (m * Math.PI / 30);
                var r_t = width * (0.44 + dialMarginOffset);
                ctx.beginPath();
                ctx.arc(cx + Math.cos(tickAngle) * r_t, cy + Math.sin(tickAngle) * r_t, 1.2, 0, 2 * Math.PI);
                ctx.fillStyle = ColorUtils.applyAlpha(subtextColor, 0.35);
                ctx.fill();
            }
            ctx.restore();
        }
        // ── STYLE 3: INNER ONLY ──
        else if (dialStyle === "inner_only") {
            ctx.save();
            ctx.font = fontWeight + Math.round(width * 0.05) + "px sans-serif";
            ctx.fillStyle = textColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var r_in = width * (0.38 + dialMarginOffset);
            for (var i = 0; i < 12; i++) {
                var val = i * 5;
                var valStr = val < 10 ? "0" + val : "" + val;
                var angle = -Math.PI / 2 + (i * Math.PI / 6);
                var tx = cx + Math.cos(angle) * r_in;
                var ty = cy + Math.sin(angle) * r_in;

                var rot = angle + Math.PI / 2;
                while (rot > Math.PI) rot -= 2 * Math.PI;
                while (rot < -Math.PI) rot += 2 * Math.PI;
                if (rot > Math.PI / 2 || rot < -Math.PI / 2) rot += Math.PI;

                ctx.save();
                ctx.translate(tx, ty);
                ctx.rotate(rot);
                ctx.fillText(valStr, 0, 0);
                ctx.restore();
            }
            ctx.restore();
        }
        // ── STYLE 4: FULL DENSE ──
        else if (dialStyle === "full_dense") {
            ctx.save();
            ctx.font = fontWeight + Math.round(width * 0.03) + "px sans-serif";
            ctx.fillStyle = subtextColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            var r_dense_outer = width * (0.44 + dialMarginOffset);
            var r_dense_inner = width * (0.35 + dialMarginOffset);

            for (var i = 0; i < 60; i += 2) {
                var valStr = i < 10 ? "0" + i : "" + i;
                var angle = -Math.PI / 2 + (i * Math.PI / 30);
                ctx.fillText(valStr, cx + Math.cos(angle) * r_dense_outer, cy + Math.sin(angle) * r_dense_outer);
            }

            ctx.font = fontWeight + Math.round(width * 0.045) + "px sans-serif";
            ctx.fillStyle = textColor;
            for (var j = 0; j < 12; j++) {
                var val = j * 5;
                var valStr = val < 10 ? "0" + val : "" + val;
                var angle = -Math.PI / 2 + (j * Math.PI / 6);
                ctx.fillText(valStr, cx + Math.cos(angle) * r_dense_inner, cy + Math.sin(angle) * r_dense_inner);
            }
            ctx.restore();
        }
        // ── STYLE 5: MINIMAL ARC ──
        else if (dialStyle === "minimal_arc") {
            ctx.save();
            var r_arc = width * (0.44 + dialMarginOffset);
            
            ctx.beginPath();
            ctx.arc(cx, cy, r_arc, 0, 2 * Math.PI);
            ctx.lineWidth = 2;
            ctx.strokeStyle = ColorUtils.applyAlpha(subtextColor, 0.15);
            ctx.stroke();

            var secAngle = -Math.PI / 2 + (currentSecond * 2 * Math.PI / 60);
            ctx.beginPath();
            ctx.arc(cx, cy, r_arc, -Math.PI / 2, secAngle);
            ctx.lineWidth = 3;
            ctx.strokeStyle = accentColor;
            ctx.stroke();

            ctx.font = fontWeight + Math.round(width * 0.04) + "px sans-serif";
            ctx.fillStyle = textColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            var mainHours = [
                { val: "12", a: -Math.PI / 2 },
                { val: "03", a: 0 },
                { val: "06", a: Math.PI / 2 },
                { val: "09", a: Math.PI }
            ];
            mainHours.forEach(function(h) {
                ctx.fillText(h.val, cx + Math.cos(h.a) * (r_arc - 14), cy + Math.sin(h.a) * (r_arc - 14));
            });
            ctx.restore();
        }
        // ── STYLE 6: FULL PIXEL 3 (Tighter Ring Spacing & Larger Clean Typography) ──
        else if (dialStyle === "full_pixel3") {
            ctx.save();

            // Tighter Radii for Compact Pixel Watch 3 Dial:
            // Outer Ring: 00..55 + 4 capsule ticks  (r = 0.46)
            // Middle Ring: 4 COMPLICATION ARCS     (r = 0.40 - CLOSE TO OUTER!)
            // Inner Ring: Rotating minute numbers (r = 0.34 - CLOSE TO MIDDLE!)
            var r_outer_num   = width * 0.46;
            var r_arc_track   = width * 0.40; 
            var r_inner_num   = width * 0.34; 

            function ac(c, a) { return ColorUtils.applyAlpha(c, a); }

            // 1. Outer Ring: 12 numbers (00..55) + 4 radial capsule ticks between each
            ctx.font = "bold " + Math.round(width * 0.040) + "px sans-serif";
            ctx.fillStyle = subtextColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            for (var m60 = 0; m60 < 60; m60++) {
                var a60 = -Math.PI / 2 + (m60 * 2 * Math.PI / 60);

                if (m60 % 5 === 0) {
                    var valStr = m60 < 10 ? "0" + m60 : "" + m60;
                    ctx.fillText(valStr, cx + Math.cos(a60) * r_outer_num, cy + Math.sin(a60) * r_outer_num);
                } else {
                    // Capsule tick
                    var tLen = width * 0.018;
                    var r1   = r_outer_num - tLen / 2;
                    var r2   = r_outer_num + tLen / 2;
                    ctx.lineWidth = 2.2;
                    ctx.strokeStyle = ac(subtextColor, 0.50);
                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(a60) * r1, cy + Math.sin(a60) * r1);
                    ctx.lineTo(cx + Math.cos(a60) * r2, cy + Math.sin(a60) * r2);
                    ctx.stroke();
                }
            }

            // 2. Middle Ring: 4 COMPLICATION ARCS WITH CLEAN TYPOGRAPHY
            function drawCurvedArcText(text, centerAngle, radius, fontPx, fillCol) {
                ctx.font = "bold " + fontPx + "px sans-serif";
                ctx.fillStyle = fillCol;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                var charWidths = [];
                var totalWidth = 0;
                for (var i = 0; i < text.length; i++) {
                    var w = ctx.measureText(text[i]).width;
                    charWidths.push(w);
                    totalWidth += w;
                }

                var totalArcAngle = totalWidth / radius;
                var startArcAngle = centerAngle - (totalArcAngle / 2);

                var currentArc = startArcAngle;
                for (var j = 0; j < text.length; j++) {
                    var charW = charWidths[j];
                    var halfCharAngle = (charW / 2) / radius;
                    var charAngle = currentArc + halfCharAngle;

                    var charX = cx + Math.cos(charAngle) * radius;
                    var charY = cy + Math.sin(charAngle) * radius;

                    var rot = charAngle + Math.PI / 2;
                    if (charAngle > Math.PI / 2 || charAngle < -Math.PI / 2) {
                        if (rot > Math.PI)  rot -= Math.PI * 2;
                        if (rot < -Math.PI) rot += Math.PI * 2;
                    }

                    ctx.save();
                    ctx.translate(charX, charY);
                    ctx.rotate(rot);
                    ctx.fillText(text[j], 0, 0);
                    ctx.restore();

                    currentArc += (charW / radius);
                }
            }

            function drawComplicationArc(startAngle, endAngle, labelText, valuePct) {
                ctx.save();

                // Track Arc Line
                ctx.beginPath();
                ctx.arc(cx, cy, r_arc_track, startAngle, endAngle);
                ctx.lineWidth = 2.8;
                ctx.lineCap = "round";
                ctx.strokeStyle = ac(subtextColor, 0.45);
                ctx.stroke();

                // Curved Text Label attached to the start of the arc
                var labelFontPx = Math.round(width * 0.034);
                ctx.font = "bold " + labelFontPx + "px sans-serif";
                var labelWidthPx = ctx.measureText(labelText).width;
                var labelArcLen = (labelWidthPx / r_arc_track) + 0.08;

                var labelCenterAngle = startAngle - labelArcLen / 2;
                drawCurvedArcText(labelText, labelCenterAngle, r_arc_track, labelFontPx, textColor);

                // Sliding Bullet Indicator
                var bulletAngle = startAngle + (endAngle - startAngle) * Math.max(0, Math.min(1, valuePct));
                var bx = cx + Math.cos(bulletAngle) * r_arc_track;
                var by = cy + Math.sin(bulletAngle) * r_arc_track;

                ctx.beginPath();
                ctx.arc(bx, by, 4.2, 0, 2 * Math.PI);
                ctx.fillStyle = accentColor;
                ctx.fill();

                ctx.restore();
            }

            // Quadrant 1 (Top-Left): Weather Temp
            var wTempStr = (Weather.data && Weather.data.temp) ? String(Weather.data.temp).replace("°C", "°") : "24°";
            var tempVal  = 0.65;
            drawComplicationArc(-Math.PI * 0.85, -Math.PI * 0.60, "≈ " + wTempStr, tempVal);

            // Quadrant 2 (Top-Right): Phone Battery (KDE Connect)
            var phoneBatt = (KdeConnectService && KdeConnectService.devices && KdeConnectService.devices[0])
                            ? KdeConnectService.devices[0].charge / 100.0 : 0.85;
            var phoneStr  = Math.round(phoneBatt * 100) + "%";
            drawComplicationArc(-Math.PI * 0.40, -Math.PI * 0.15, "PH " + phoneStr, phoneBatt);

            // Quadrant 3 (Bottom-Right): System PC/Laptop Battery
            var sysBatt = Battery.percentage ?? 0.75;
            var sysStr  = Math.round(sysBatt * 100) + "%";
            drawComplicationArc(Math.PI * 0.15, Math.PI * 0.40, "BAT " + sysStr, sysBatt);

            // Quadrant 4 (Bottom-Left): Memory RAM Usage
            var ramPct = ResourceUsage.memoryUsedPercentage ?? 0.45;
            var ramStr = Math.round(ramPct * 100) + "%";
            drawComplicationArc(Math.PI * 0.60, Math.PI * 0.85, "RAM " + ramStr, ramPct);

            // 3. Inner Ring: Rotates smoothly with minutes
            var currentMinRotAngle = (currentMinute + currentSecond / 60.0) * (2 * Math.PI / 60);

            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(-currentMinRotAngle);

            for (var mInner = 0; mInner < 60; mInner++) {
                var aInner = (mInner * 2 * Math.PI / 60);

                // If minute pill is visible at 3 o'clock (0 rad), hide text & ticks underneath
                if (hideMinutePillArea) {
                    var effA = aInner - currentMinRotAngle;
                    while (effA > Math.PI)  effA -= 2 * Math.PI;
                    while (effA < -Math.PI) effA += 2 * Math.PI;
                    if (Math.abs(effA) < 0.22) continue;
                }

                if (mInner % 5 === 0) {
                    var vStr = mInner < 10 ? "0" + mInner : "" + mInner;
                    var tx_in = Math.cos(aInner) * r_inner_num;
                    var ty_in = Math.sin(aInner) * r_inner_num;
                    var rot_in = aInner + Math.PI / 2;
                    if (aInner > Math.PI / 2 || aInner < -Math.PI / 2) {
                        if (rot_in > Math.PI)  rot_in -= Math.PI * 2;
                        if (rot_in < -Math.PI) rot_in += Math.PI * 2;
                    }

                    ctx.save();
                    ctx.translate(tx_in, ty_in);
                    ctx.rotate(rot_in);
                    ctx.font = "bold " + Math.round(width * 0.044) + "px sans-serif";
                    ctx.fillStyle = textColor;
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";
                    ctx.fillText(vStr, 0, 0);
                    ctx.restore();
                } else {
                    // Sub-ticks
                    var mtLen = width * 0.018;
                    var mr1   = r_inner_num - mtLen / 2;
                    var mr2   = r_inner_num + mtLen / 2;
                    ctx.lineWidth = 1.6;
                    ctx.strokeStyle = ac(subtextColor, 0.35);
                    ctx.beginPath();
                    ctx.moveTo(Math.cos(aInner) * mr1, Math.sin(aInner) * mr1);
                    ctx.lineTo(Math.cos(aInner) * mr2, Math.sin(aInner) * mr2);
                    ctx.stroke();
                }
            }
            ctx.restore();

            ctx.restore();
        }
        // ── STYLE 7: DOTS ──
        else if (dialStyle === "dots") {
            ctx.save();
            var r_dots = width * (0.44 + dialMarginOffset);
            for (var i = 0; i < 12; i++) {
                var angle = -Math.PI / 2 + (i * Math.PI / 6);
                ctx.beginPath();
                ctx.arc(cx + Math.cos(angle) * r_dots, cy + Math.sin(angle) * r_dots, 4, 0, 2 * Math.PI);
                ctx.fillStyle = textColor;
                ctx.fill();
            }
            ctx.restore();
        }
        // ── STYLE 8: FULL ──
        else if (dialStyle === "full") {
            ctx.save();
            var r_full_outer = width * (0.44 + dialMarginOffset);
            
            for (var i = 0; i < 12; i++) {
                var angle = -Math.PI / 2 + (i * Math.PI / 6);
                ctx.lineWidth = 3;
                ctx.strokeStyle = textColor;
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(angle) * (r_full_outer - 12), cy + Math.sin(angle) * (r_full_outer - 12));
                ctx.lineTo(cx + Math.cos(angle) * r_full_outer, cy + Math.sin(angle) * r_full_outer);
                ctx.stroke();
            }

            for (var m = 0; m < 60; m++) {
                if (m % 5 === 0) continue;
                var angle = -Math.PI / 2 + (m * Math.PI / 30);
                ctx.lineWidth = 1.5;
                ctx.strokeStyle = ColorUtils.applyAlpha(subtextColor, 0.4);
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(angle) * (r_full_outer - 6), cy + Math.sin(angle) * (r_full_outer - 6));
                ctx.lineTo(cx + Math.cos(angle) * r_full_outer, cy + Math.sin(angle) * r_full_outer);
                ctx.stroke();
            }
            ctx.restore();
        }
        // ── STYLE 9: SHAPES ──
        else if (dialStyle === "shapes") {
            ctx.save();
            var r_shapes = width * (0.44 + dialMarginOffset);
            for (var i = 0; i < 12; i++) {
                var angle = -Math.PI / 2 + (i * Math.PI / 6);
                var isCardinal = (i === 0 || i === 3 || i === 6 || i === 9);
                var shapeR = isCardinal ? 5 : 3;

                ctx.beginPath();
                ctx.arc(cx + Math.cos(angle) * r_shapes, cy + Math.sin(angle) * r_shapes, shapeR, 0, 2 * Math.PI);
                ctx.fillStyle = isCardinal ? accentColor : textColor;
                ctx.fill();
            }
            ctx.restore();
        }

        // ── MINUTE INDICATOR DOT ON RING ──
        if (showMinuteDot && dialStyle !== "none" && dialStyle !== "minimal_arc" && dialStyle !== "full_pixel3") {
            ctx.save();
            var minAngle = -Math.PI / 2 + (currentMinute * Math.PI / 30);
            var dotR = width * (0.44 + dialMarginOffset) - 4;
            ctx.beginPath();
            ctx.arc(cx + Math.cos(minAngle) * dotR, cy + Math.sin(minAngle) * dotR, 3.5, 0, 2 * Math.PI);
            ctx.fillStyle = accentColor;
            ctx.fill();
            ctx.restore();
        }
    }
}
