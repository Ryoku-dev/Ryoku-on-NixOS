function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(value, maximum));
}

function advanceGrid(rawValue, anchor, gridValue, step, minimum, maximum) {
    const delta = rawValue - anchor;
    let steps = 0;

    if (delta >= step) {
        steps = Math.floor(delta / step);
    } else if (delta <= -step) {
        steps = Math.ceil(delta / step);
    }

    if (steps === 0) {
        return {
            "anchor": anchor,
            "value": gridValue
        };
    }

    return {
        "anchor": anchor + steps * step,
        "value": clamp(gridValue + steps * step, minimum, maximum)
    };
}

function shouldHoldSnap(rawValue, snapTarget, releaseThreshold) {
    return Math.abs(rawValue - snapTarget) <= releaseThreshold;
}

function nearestValidCandidate(candidates, minimum, maximum, enterThreshold) {
    let nearest = null;

    for (let i = 0; i < candidates.length; i++) {
        const candidate = candidates[i];
        if (!candidate || !Number.isFinite(candidate.target) || !Number.isFinite(candidate.distance))
            continue;
        if (candidate.target < minimum || candidate.target > maximum)
            continue;
        if (candidate.distance > enterThreshold)
            continue;
        if (nearest === null || candidate.distance < nearest.distance)
            nearest = candidate;
    }

    return nearest;
}

if (typeof module !== "undefined") {
    module.exports = {
        advanceGrid,
        clamp,
        nearestValidCandidate,
        shouldHoldSnap
    };
}
