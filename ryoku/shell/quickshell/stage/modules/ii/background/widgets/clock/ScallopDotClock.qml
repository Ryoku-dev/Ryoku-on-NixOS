pragma ComponentBehavior: Bound

import QtQuick
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets

// ScallopDotClock: 100% faithful replication of the 12-wave Scallop Dot Clock
//   Outer Minute Bubble: Fits cleanly inside the outer wave apex at 5-minute intervals without clipping
//   Inner Hour Bubble:   Navigates smoothly along the inner dot ring. Hides ONLY the inner dot physically
//                        underneath the hour bubble (distance check)

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

    onUseBlackBgChanged:      requestPaint()
    onShowHourHandChanged:     requestPaint()
    onShowMinuteBubbleChanged: requestPaint()
    onShowDotsChanged:         requestPaint()
    onBoldFontChanged:        requestPaint()
    onColTextChanged:         requestPaint()
    onColSubtextChanged:      requestPaint()
    onColAccentChanged:       requestPaint()
    onColPillFillChanged:     requestPaint()
    onColPillTextChanged:     requestPaint()

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
        var rOuterDot = W * 0.405; // Outer dot ring (inside Cookie12Sided peaks)
        var rInnerDot = W * 0.230; // Inner dot ring (around pivot)

        function ac(col, a) { return ColorUtils.applyAlpha(col, a); }

        // Active 5-minute block apex index (0..11)
        var activeMinutePeakIdx = Math.floor(min / 5) % 12;

        // Hour hand angle & position
        var hrAngle = -Math.PI / 2 + (hr12 + min / 60.0) * (2 * Math.PI / 12);
        var hbx = cx + Math.cos(hrAngle) * rInnerDot;
        var hby = cy + Math.sin(hrAngle) * rInnerDot;

        var hrBubbleR  = W * 0.062; // Hour bubble radius
        var minBubbleR = W * 0.068; // Minute bubble radius (compact & neat)

        // ── 1. DRAW TWO CONCENTRIC RINGS OF 12 DOTS ───────────────────────────
        if (showDots) {
            ctx.save();

            // A) OUTER DOT RING (12 Dots at peaks, except active minute peak)
            for (var o = 0; o < 12; o++) {
                if (showMinuteBubble && o === activeMinutePeakIdx)
                    continue; // Replaced by minute bubble!

                var oAngle = -Math.PI / 2 + (o * 2 * Math.PI / 12);
                var ox = cx + Math.cos(oAngle) * rOuterDot;
                var oy = cy + Math.sin(oAngle) * rOuterDot;

                ctx.beginPath();
                ctx.arc(ox, oy, W * 0.015, 0, 2 * Math.PI);
                ctx.fillStyle = ac(colSubtext, 0.75);
                ctx.fill();
            }

            // B) INNER DOT RING (12 Dots around pivot - hide ONLY if hour bubble overlaps!)
            for (var inD = 0; inD < 12; inD++) {
                var inAngle = -Math.PI / 2 + (inD * 2 * Math.PI / 12);
                var inX = cx + Math.cos(inAngle) * rInnerDot;
                var inY = cy + Math.sin(inAngle) * rInnerDot;

                // Check physical distance between hour bubble center (hbx, hby) and this dot (inX, inY)
                if (showHourHand) {
                    var dx = hbx - inX;
                    var dy = hby - inY;
                    var dist = Math.sqrt(dx * dx + dy * dy);
                    if (dist < hrBubbleR * 0.9) {
                        continue; // Hidden ONLY because the hour bubble is physically over this dot!
                    }
                }

                ctx.beginPath();
                ctx.arc(inX, inY, W * 0.015, 0, 2 * Math.PI);
                ctx.fillStyle = ac(colSubtext, 0.75);
                ctx.fill();
            }

            ctx.restore();
        }

        // ── 2. HOUR HAND LINE & HOUR BUBBLE ───────────────────────────────────
        if (showHourHand) {
            ctx.save();

            // Fine connecting line from center pivot to hour bubble
            ctx.lineWidth   = 2.2;
            ctx.strokeStyle = ac(colPillFill, 0.90);
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(hbx, hby);
            ctx.stroke();

            // Center pivot dot
            ctx.beginPath();
            ctx.arc(cx, cy, W * 0.015, 0, 2 * Math.PI);
            ctx.fillStyle = colPillFill;
            ctx.fill();

            // Hour Bubble Circle
            ctx.beginPath();
            ctx.arc(hbx, hby, hrBubbleR, 0, 2 * Math.PI);
            ctx.fillStyle = colPillFill;
            ctx.fill();

            // Hour Number text (e.g. "2")
            var displayHr = hr12 === 0 ? 12 : hr12;
            ctx.font = fontStyle + Math.round(W * 0.052) + "px sans-serif";
            ctx.fillStyle = colPillText;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("" + displayHr, hbx, hby);

            ctx.restore();
        }

        // ── 3. MINUTE BUBBLE (AT OUTER WAVE APEX) ─────────────────────────────
        if (showMinuteBubble) {
            var minApexAngle = -Math.PI / 2 + (activeMinutePeakIdx * 2 * Math.PI / 12);
            var mbx = cx + Math.cos(minApexAngle) * rOuterDot;
            var mby = cy + Math.sin(minApexAngle) * rOuterDot;

            ctx.save();

            // Minute Bubble Circle (Centered cleanly inside outer peak)
            ctx.beginPath();
            ctx.arc(mbx, mby, minBubbleR, 0, 2 * Math.PI);
            ctx.fillStyle = colPillFill;
            ctx.fill();

            // Minute Number text (e.g. "45")
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
