// The band maths of the `aura` look: fold a spectrum's bands into the twelve
// sectors the edge-field shader reads, weight them by a frequency profile,
// derive their energy, and ease a value toward its target. Ported from the iNiR
// shell's organic edge visualiser (GPL-3.0), reduced to the pure parts so the
// desktop renderer (AuraMotion) and the Hub preview (VizPreview) derive
// identical sectors instead of each re-deriving them. Framework-free and
// module-exported like the sibling lib files, so it is node-tested.

// One of six fixed weightings of the frequency axis (0..1, bass to treble):
// how much a band at that position counts toward the field. "flat" leaves
// everything as it sounds; the rest tilt the look toward one part of the mix.
function profileWeight(name, x) {
    var p = Math.max(0, Math.min(1, x));
    if (name === "bass")
        return 0.44 + 1.86 * Math.exp(-4.2 * p);
    if (name === "warm")
        return 1.82 - 1.08 * p;
    if (name === "vocal") {
        var d = (p - 0.46) / 0.17;
        return 0.48 + 1.72 * Math.exp(-d * d);
    }
    if (name === "treble")
        return 0.44 + 1.86 * Math.pow(p, 1.75);
    if (name === "smile")
        return 0.52 + 1.56 * Math.pow(Math.abs(p - 0.5) * 2, 1.45);
    return 1;
}

// Mix a share (`strength`, 0..1) of the profile's tilt into the levels, so
// zero strength is the untouched spectrum and full strength is the pure tilt.
function applyProfile(levels, name, strength) {
    if (!levels || !levels.length || name === "flat" || !(strength > 0))
        return levels;
    var out = new Array(levels.length);
    for (var i = 0; i < levels.length; i++) {
        var w = profileWeight(name, levels.length > 1 ? i / (levels.length - 1) : 0.5);
        out[i] = levels[i] * (1 + (w - 1) * Math.max(0, Math.min(1, strength)));
    }
    return out;
}

// Fold `levels` into twelve equal slices of the spectrum. Each sector takes the
// mean and the peak of its slice and mixes them toward the peak, then lifts the
// result with a gentle power so quiet music still moves the field.
function sectors(levels) {
    var n = 12;
    var out = new Array(n);
    var m = levels ? levels.length : 0;
    if (m === 0) {
        for (var z = 0; z < n; z++)
            out[z] = 0;
        return out;
    }
    for (var i = 0; i < n; i++) {
        var from = Math.floor(m * i / n);
        var to = Math.max(from + 1, Math.ceil(m * (i + 1) / n));
        var total = 0, peak = 0;
        for (var j = from; j < to; j++) {
            var level = Math.max(0, Math.min(1, levels[j] || 0));
            total += level;
            if (level > peak)
                peak = level;
        }
        var avg = total / (to - from);
        out[i] = Math.pow(Math.min(1, avg * 0.66 + peak * 0.54), 0.68);
    }
    return out;
}

// The contrast pass over the raw sectors: spread each sector against the
// frame's own minimum and maximum, then mix a share of that contrast back in,
// weighted by how loud the frame is. Without it a quiet track moves every
// sector equally and the field reads as one blob. Energy weights the low
// sectors: the shader reads them as the field's driver.
function frame(raw) {
    var n = raw.length;
    var min = 1, max = 0, sum = 0;
    for (var i = 0; i < n; i++) {
        if (raw[i] < min) min = raw[i];
        if (raw[i] > max) max = raw[i];
        sum += raw[i] * (1.35 - (i / (n - 1 || 1)) * 0.55);
    }
    var energy = Math.min(1, sum / 9.6);
    var spread = Math.max(0.10, max - min);
    var activity = Math.min(1, Math.pow(max, 0.72) * 1.16);
    var levels = new Array(n);
    for (var j = 0; j < n; j++) {
        var contrast = Math.max(0, Math.min(1, (raw[j] - min) / spread));
        levels[j] = Math.min(1, raw[j] * 0.34 + contrast * activity * 0.76);
    }
    return { levels: levels, energy: energy, max: max };
}

// One-pole follow with separate attack and release rates, the frame-rate
// independent step iNiR's organic motion uses: transients snap up, everything
// else sinks away gently.
function follow(cur, target, dt, attack, release) {
    var rate = target > cur ? attack : release;
    return cur + (target - cur) * (1 - Math.exp(-dt * rate));
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { profileWeight, applyProfile, sectors, frame, follow };
