pragma ComponentBehavior: Bound

import QtQuick
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets

// CirclePointerClock: Minimalist concentric dial with outer 5-minute step numbers,
// an intermediate circle featuring a smooth minute pointer tab, and a central 2-digit hour circle.

Canvas {
    id: root

    implicitWidth: 240
    implicitHeight: 240

    // ── Config toggles ────────────────────────────────────────────────────────
    property bool useBlackBg:            true
    property bool enableGlassReflection: false
    property bool showDots:              true
    property bool boldFont:              true

    // ── Colors (WidgetColorScheme) ────────────────────────────────────────────
    property color colText:        WidgetColorScheme.textColorOnBg
    property color colSubtext:     WidgetColorScheme.subtextColorOnBg
    property color colAccent:      WidgetColorScheme.accentColor
    property color colPillFill:    WidgetColorScheme.pillFillColor
    property color colPillText:    WidgetColorScheme.textColorOnPillFill
    property color colInnerShape:  WidgetColorScheme.innerShapeColor

    // ── Time ──────────────────────────────────────────────────────────────────
    property int currentMinute: DateTime.clock.minutes
    property int currentHour:   DateTime.clock.hours

    contextType: "2d"

    Connections {
        target: DateTime.clock
        function onMinutesChanged() { root.requestPaint(); }
    }

    onUseBlackBgChanged:            requestPaint()
    onShowDotsChanged:              requestPaint()
    onBoldFontChanged:              requestPaint()
    onColTextChanged:               requestPaint()
    onColSubtextChanged:            requestPaint()
    onColAccentChanged:             requestPaint()
    onColPillFillChanged:           requestPaint()
    onColPillTextChanged:           requestPaint()
    onColInnerShapeChanged:         requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var W  = width;
        var cx = W / 2;
        var cy = W / 2;
        var fontStyle = boldFont ? "bold " : "600 ";

        var hr12 = currentHour % 12;
        var min  = currentMinute;

        function ac(col, a) { return ColorUtils.applyAlpha(col, a); }

        // Radii
        var rOuter      = W * 0.405; // 5-minute numbers ring radius
        var rMid        = W * 0.310; // Intermediate circle radius
        var rPointer    = W * 0.348; // Compact minute pointer tip radius
        var rInner      = W * 0.180; // Innermost hour circle radius

        // ── 1. OUTER 5-MINUTE NUMBERS RING (00, 05, 10, ..., 55) ─────────────
        if (showDots) {
            ctx.save();
            ctx.font = fontStyle + Math.round(W * 0.048) + "px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            for (var o = 0; o < 12; o++) {
                var oAngle = -Math.PI / 2 + (o * 2 * Math.PI / 12);
                var ox = cx + Math.cos(oAngle) * rOuter;
                var oy = cy + Math.sin(oAngle) * rOuter;

                var val5 = o * 5;
                var str5 = val5 < 10 ? "0" + val5 : "" + val5;

                ctx.fillStyle = ac(colSubtext, 0.75);
                ctx.fillText(str5, ox, oy);
            }

            ctx.restore();
        }

        // ── 2. INTERMEDIATE CIRCLE WITH MINUTE POINTER TAB ───────────────────
        ctx.save();
        var minAngle = -Math.PI / 2 + (min / 60.0) * (2 * Math.PI);
        var deltaAngle = 0.22; // Compact angular spread of pointer tab base

        var aStart = minAngle - deltaAngle;
        var aEnd   = minAngle + deltaAngle;

        ctx.beginPath();

        // Main intermediate circle arc
        ctx.arc(cx, cy, rMid, aEnd, aStart, false);

        // Pointer tip coordinates
        var tipX = cx + Math.cos(minAngle) * rPointer;
        var tipY = cy + Math.sin(minAngle) * rPointer;

        var pEnd_x = cx + Math.cos(aEnd) * rMid;
        var pEnd_y = cy + Math.sin(aEnd) * rMid;

        // Smooth control points for compact pointer tab
        var midR = (rMid + rPointer) * 0.51;
        var cp1_x = cx + Math.cos(minAngle - deltaAngle * 0.45) * midR;
        var cp1_y = cy + Math.sin(minAngle - deltaAngle * 0.45) * midR;
        var cp2_x = cx + Math.cos(minAngle + deltaAngle * 0.45) * midR;
        var cp2_y = cy + Math.sin(minAngle + deltaAngle * 0.45) * midR;

        ctx.quadraticCurveTo(cp1_x, cp1_y, tipX, tipY);
        ctx.quadraticCurveTo(cp2_x, cp2_y, pEnd_x, pEnd_y);

        ctx.closePath();
        ctx.fillStyle = ac(colInnerShape, 0.90);
        ctx.fill();
        ctx.restore();

        // ── 3. INNERMOST HOUR CIRCLE & 2-DIGIT HOUR TEXT ──────────────────────
        ctx.save();

        ctx.beginPath();
        ctx.arc(cx, cy, rInner, 0, 2 * Math.PI);
        ctx.fillStyle = colPillFill;
        ctx.fill();

        var displayHr = hr12 === 0 ? 12 : hr12;
        var hrStr = displayHr < 10 ? "0" + displayHr : "" + displayHr;

        ctx.font = fontStyle + Math.round(W * 0.14) + "px sans-serif";
        // Text color matches intermediate circle background
        ctx.fillStyle = ac(colInnerShape, 0.95);
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        // Slight vertical offset (+ W * 0.008) for optical vertical centering
        ctx.fillText(hrStr, cx, cy + W * 0.008);

        ctx.restore();
    }
}
