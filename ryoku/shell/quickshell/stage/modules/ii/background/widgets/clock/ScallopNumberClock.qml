pragma ComponentBehavior: Bound

import QtQuick
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets

// ScallopNumberClock: Organic Material You scallop clock face with 5-minute outer numbers,
// 1-12 inner hour numbers, smooth hour circle indicator, active minute bubble, and center date badge.

Canvas {
    id: root

    implicitWidth: 240
    implicitHeight: 240

    // ── Config toggles ────────────────────────────────────────────────────────
    property bool useBlackBg:            true
    property bool enableGlassReflection: false
    property bool showHourHand:          true
    property bool showMinuteBubble:      true
    property bool showDots:              true
    property bool boldFont:              true

    // ── Colors (WidgetColorScheme) ────────────────────────────────────────────
    property color colText:        WidgetColorScheme.textColorOnBg
    property color colSubtext:     WidgetColorScheme.subtextColorOnBg
    property color colAccent:      WidgetColorScheme.accentColor
    property color colPillFill:    WidgetColorScheme.pillFillColor
    property color colPillText:    WidgetColorScheme.textColorOnPillFill

    // ── Time ──────────────────────────────────────────────────────────────────
    property int currentMinute: DateTime.clock.minutes
    property int currentHour:   DateTime.clock.hours

    contextType: "2d"

    Connections {
        target: DateTime.clock
        function onMinutesChanged() { root.requestPaint(); }
    }

    onUseBlackBgChanged:            requestPaint()
    onShowHourHandChanged:          requestPaint()
    onShowMinuteBubbleChanged:      requestPaint()
    onShowDotsChanged:              requestPaint()
    onBoldFontChanged:              requestPaint()
    onColTextChanged:               requestPaint()
    onColSubtextChanged:            requestPaint()
    onColAccentChanged:             requestPaint()
    onColPillFillChanged:           requestPaint()
    onColPillTextChanged:           requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var W  = width;
        var cx = W / 2;
        var cy = W / 2;
        var fontStyle = boldFont ? "bold " : "600 ";

        var hr12 = currentHour % 12;
        var min  = currentMinute;

        // Radii matched to MaterialShape Cookie12Sided bounds
        var rOuterDot = W * 0.405; // Outer 5-minute numbers ring (inside Cookie12Sided peaks)
        var rInnerDot = W * 0.230; // Inner 1-12 hour numbers ring

        function ac(col, a) { return ColorUtils.applyAlpha(col, a); }

        // Active 5-minute block apex index (0..11)
        var activeMinutePeakIdx = Math.floor(min / 5) % 12;

        // Hour indicator angle & position along inner ring
        var hrAngle = -Math.PI / 2 + (hr12 + min / 60.0) * (2 * Math.PI / 12);
        var hbx = cx + Math.cos(hrAngle) * rInnerDot;
        var hby = cy + Math.sin(hrAngle) * rInnerDot;

        var hrBubbleR  = W * 0.072; // Hour circle radius
        var minBubbleR = W * 0.068; // Minute bubble radius

        // ── 1. OUTER 5-MINUTE NUMBERS RING (00, 05, 10, ..., 55) ─────────────
        if (showDots) {
            ctx.save();
            ctx.font = fontStyle + Math.round(W * 0.048) + "px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            for (var o = 0; o < 12; o++) {
                if (showMinuteBubble && o === activeMinutePeakIdx)
                    continue; // Replaced by active minute bubble!

                var oAngle = -Math.PI / 2 + (o * 2 * Math.PI / 12);
                var ox = cx + Math.cos(oAngle) * rOuterDot;
                var oy = cy + Math.sin(oAngle) * rOuterDot;

                var val5 = o * 5;
                var str5 = val5 < 10 ? "0" + val5 : "" + val5;

                ctx.fillStyle = ac(colSubtext, 0.75);
                ctx.fillText(str5, ox, oy);
            }

            ctx.restore();
        }

        // ── 2. INNER 1-12 HOUR NUMBERS RING ──────────────────────────────────
        if (showDots) {
            ctx.save();
            ctx.font = fontStyle + Math.round(W * 0.052) + "px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            for (var inD = 0; inD < 12; inD++) {
                var inAngle = -Math.PI / 2 + (inD * 2 * Math.PI / 12);
                var inX = cx + Math.cos(inAngle) * rInnerDot;
                var inY = cy + Math.sin(inAngle) * rInnerDot;

                var displayVal = inD === 0 ? 12 : inD;

                // Hide background number ONLY if hour bubble physically overlaps it!
                if (showHourHand) {
                    var dx = hbx - inX;
                    var dy = hby - inY;
                    var dist = Math.sqrt(dx * dx + dy * dy);
                    if (dist < hrBubbleR * 0.95) {
                        continue;
                    }
                }

                ctx.fillStyle = ac(colSubtext, 0.75);
                ctx.fillText("" + displayVal, inX, inY);
            }

            ctx.restore();
        }

        // ── 3. HOUR CIRCLE INDICATOR (IN INNER RING, NO CONNECTING LINE) ─────
        if (showHourHand) {
            ctx.save();

            // Hour Bubble Circle
            ctx.beginPath();
            ctx.arc(hbx, hby, hrBubbleR, 0, 2 * Math.PI);
            ctx.fillStyle = colPillFill;
            ctx.fill();

            // Hour Number text (e.g. "2")
            var displayHr = hr12 === 0 ? 12 : hr12;
            ctx.font = fontStyle + Math.round(W * 0.054) + "px sans-serif";
            ctx.fillStyle = colPillText;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("" + displayHr, hbx, hby);

            ctx.restore();
        }

        // ── 4. MINUTE BUBBLE (AT OUTER WAVE APEX) ─────────────────────────────
        if (showMinuteBubble) {
            var minApexAngle = -Math.PI / 2 + (activeMinutePeakIdx * 2 * Math.PI / 12);
            var mbx = cx + Math.cos(minApexAngle) * rOuterDot;
            var mby = cy + Math.sin(minApexAngle) * rOuterDot;

            ctx.save();

            // Minute Bubble Circle
            ctx.beginPath();
            ctx.arc(mbx, mby, minBubbleR, 0, 2 * Math.PI);
            ctx.fillStyle = colPillFill;
            ctx.fill();

            // Minute Number text (e.g. "15")
            var minStr = min < 10 ? "0" + min : "" + min;
            ctx.font = fontStyle + Math.round(W * 0.048) + "px sans-serif";
            ctx.fillStyle = colPillText;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(minStr, mbx, mby);

            ctx.restore();
        }
    }
}
