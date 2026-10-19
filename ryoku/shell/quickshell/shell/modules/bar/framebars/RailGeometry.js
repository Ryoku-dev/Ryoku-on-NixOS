function edgeRect(edge, thickness, width, height) {
    if (edge === "top") return { x: 0, y: 0, width: width, height: thickness };
    if (edge === "bottom") return { x: 0, y: height - thickness, width: width, height: thickness };
    if (edge === "left") return { x: 0, y: 0, width: thickness, height: height };
    if (edge === "right") return { x: width - thickness, y: 0, width: thickness, height: height };
    return { x: 0, y: 0, width: 0, height: 0 };
}

function reserve(edge, frameLip, railThickness, enabled) {
    return enabled && (edge === "top" || edge === "bottom" || edge === "left" || edge === "right")
        ? frameLip + railThickness
        : 0;
}

function edgeNearest(x, y, width, height) {
    const d = { top: y, bottom: height - y, left: x, right: width - x };
    let best = "top";
    for (const e in d) if (d[e] < d[best]) best = e;
    return best;
}

// The rail edge a trigger sits on. A point inside a rail's depth belongs to that
// rail even near another edge. The horizontal rails span the full width and own
// the shared corners, so they are tested first.
function edgeForTrigger(x, y, width, height, clearances) {
    const c = clearances || {};
    const cl = c.left || 0, cr = c.right || 0, ct = c.top || 0, cb = c.bottom || 0;
    if (ct > 0 && y <= ct) return "top";
    if (cb > 0 && height - y <= cb) return "bottom";
    if (cl > 0 && x <= cl) return "left";
    if (cr > 0 && width - x <= cr) return "right";
    return edgeNearest(x, y, width, height);
}

// Where a card opened from a trigger sits: the edge it hangs from and its inset
// from the screen sides it is anchored to. It stays inside the rails and clears
// the trigger when there is room; the anchored side only moves when the card
// would otherwise leave the screen.
function cardPlacement(trigger, width, height, clearances, gap, cardWidth, cardHeight) {
    const c = clearances || {};
    const cl = c.left || 0, cr = c.right || 0, ct = c.top || 0, cb = c.bottom || 0;
    const clamp = (value, low, high) => Math.max(low, Math.min(Math.max(low, high), value));
    const fitLeft = value => clamp(value, cl + gap, width - cr - gap - cardWidth);
    const fitRight = value => clamp(value, cr + gap, width - cl - gap - cardWidth);
    const fitTop = value => clamp(value, ct + gap, height - cb - gap - cardHeight);
    const fitBottom = value => clamp(value, cb + gap, height - ct - gap - cardHeight);
    if (!trigger)
        return { edge: "top", corner: true, x: "left", left: cl + gap, y: "top", top: ct + gap };
    const cx = trigger.x + trigger.width / 2;
    const cy = trigger.y + trigger.height / 2;
    const edge = edgeForTrigger(cx, cy, width, height, c);
    if (edge === "top" || edge === "bottom") {
        const left = fitLeft(cx - cardWidth / 2);
        return edge === "top"
            ? { edge: edge, x: "left", left: left, y: "top", top: fitTop(trigger.y + trigger.height + gap) }
            : { edge: edge, x: "left", left: left, y: "bottom", bottom: fitBottom(height - trigger.y + gap) };
    }
    const below = height - cb - trigger.y;
    const above = trigger.y + trigger.height - ct;
    const along = below >= above
        ? { y: "top", top: fitTop(trigger.y) }
        : { y: "bottom", bottom: fitBottom(height - trigger.y - trigger.height) };
    const across = edge === "left"
        ? { x: "left", left: fitLeft(trigger.x + trigger.width + gap) }
        : { x: "right", right: fitRight(width - trigger.x + gap) };
    return Object.assign({ edge: edge }, across, along);
}

if (typeof module !== "undefined" && module.exports) module.exports = { edgeRect, reserve, edgeNearest, edgeForTrigger, cardPlacement };
