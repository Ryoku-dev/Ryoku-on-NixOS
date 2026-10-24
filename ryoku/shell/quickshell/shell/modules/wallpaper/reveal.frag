#version 440

// Wallpaper reveal shader for the in-shell backdrop. Reveals newTex over oldTex
// through an animated per-pixel mask whose geometry is `kind`, whose feathered
// boundary width is `edgeSoftness`, and whose progress is already eased by the
// preset's cubic-bezier on the QML side. This restores the wallpaper-daemon
// transition set (fade / wipe / wave / center / grow / any / outer) on the GPU:
// the new image reveals over the old via the mask, fade is a plain eased
// crossfade, and both textures are the current + incoming buffers so an
// interrupted reveal commits and the next one grows from that composite.
//
// Kinds 7..15 are the expressive set ported from the upstream ii transitions.
// They cannot be written as a scalar reveal mask because they warp the sample
// coordinates themselves (mosaics, ripples, flying shards, screen melt), so they
// take their own branch that composites the two textures directly and leaves the
// 0..6 mask path untouched.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;     // eased 0..1 sweep of the reveal front
    float angle;        // wipe / wave / stripes sweep direction, degrees
    float waveAmp;      // wave boundary amplitude (fraction of the sweep extent)
    float originX;      // radial origin, surface coords 0..1
    float originY;
    float edgeSoftness; // feathered boundary half-width (fraction)
    float seed;         // fresh 0..1 per switch: seeds the noise kinds so the
                        // dissolve / shatter / glitch / melt look different each
                        // time rather than replaying one fixed pattern
    int kind;           // 0 fade,1 wipe,2 wave,3 center,4 grow,5 any,6 outer,
                        // 7 pixelate,8 dissolve,9 ripple,10 shatter,11 glitch,
                        // 12 crt,13 stripes,14 melt,15 peel
    vec2 res;           // surface size in px, for aspect-correct circles
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;

const float TAU = 6.28318530718;
const float PI = 3.14159265359;

// Hash / noise helpers shared by the expressive kinds. rand is the canonical
// sin-dot hash; vnoise smooths four hashed lattice corners into value noise;
// hash2 returns a 2-vector for per-cell random direction and delay. They are the
// upstream primitives, kept file-scope so no kind re-rolls its own.
float rand(vec2 c) {
    return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    float a = rand(i), b = rand(i + vec2(1.0, 0.0));
    float c = rand(i + vec2(0.0, 1.0)), d = rand(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

vec2 hash2(vec2 q) {
    q = vec2(dot(q, vec2(127.1, 311.7)), dot(q, vec2(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

// The expressive kinds (7..15): each warps how the two frames are sampled, so it
// returns a finished colour rather than a mask. `p` is the eased progress.
vec4 revealExpressive(vec2 uv) {
    float p = progress;

    if (kind == 7) {
        // pixelate: the block grid swells to its coarsest at mid-switch then
        // collapses back, and the crossfade lands at that peak, so the swap
        // happens while the image is chunkiest and the seam is invisible.
        float amp = 1.0 - abs(2.0 * p - 1.0);
        vec2 suv = uv;
        if (amp > 0.001) {
            float block = 0.05 * amp;
            suv = floor(uv / block) * block + block * 0.5;
        }
        float a = smoothstep(0.4, 0.6, p);
        return mix(texture(oldTex, suv), texture(newTex, suv), a);
    }

    if (kind == 8) {
        // dissolve: two octaves of value noise give a threshold the reveal eats
        // through, coarse blotches broken by fine grain; the seed offset means
        // each switch dissolves along a different contour. A bright band rides the
        // moving edge so it reads as burning through rather than merely clipping.
        vec2 nuv = uv + seed;
        float n = vnoise(nuv * 6.0) * 0.7 + vnoise(nuv * 15.0) * 0.3;
        float reveal = step(n, p);
        float glow = 1.0 - smoothstep(0.0, 0.05, abs(n - p));
        vec4 colour = mix(texture(oldTex, uv), texture(newTex, uv), reveal);
        colour.rgb += vec3(1.0, 0.82, 0.45) * glow * 1.3; // warm burning edge
        return colour;
    }

    if (kind == 9) {
        // ripple: a single wave front expands from the reveal origin, bending the
        // sample point just ahead of itself so the new image wells up under a ring
        // of water; step() commits everything the front has already crossed. The
        // front runs to the farthest corner so the whole screen commits before the
        // animation ends, rather than snapping the last ring in at the finish.
        float asp = res.x / max(res.y, 1.0);
        vec2 origin = vec2(originX * asp, originY);
        vec2 pu = vec2(uv.x * asp, uv.y);
        float d = distance(pu, origin);
        float m = max(max(distance(origin, vec2(0.0, 0.0)), distance(origin, vec2(asp, 0.0))),
                      max(distance(origin, vec2(0.0, 1.0)), distance(origin, vec2(asp, 1.0))));
        float front = p * m;
        float wave = sin((d - front) * 35.0) * exp(-abs(d - front) * 10.0);
        vec2 dir = normalize(pu - origin + 1e-4);
        vec2 suv = uv + dir * wave * 0.04;
        float reveal = step(d, front);
        vec4 colour = mix(texture(oldTex, suv), texture(newTex, suv), reveal);
        colour.rgb += max(wave, 0.0) * 0.25; // crest highlight
        return colour;
    }

    if (kind == 10) {
        // shatter: the old frame is diced into a 10x10 grid and each shard waits
        // out its own hashed delay before spinning, shrinking and flying along a
        // random vector, so the wall breaks apart raggedly instead of all at once.
        // Seeding the cell hash gives a different break pattern per switch.
        const float cells = 10.0;
        vec2 g = uv * cells;
        vec2 id = floor(g), cuv = fract(g);
        vec2 r = hash2(id + seed);
        float delay = r.x * 0.6;
        float lp = clamp((p - delay) / (1.0 - delay), 0.0, 1.0); // this shard's progress
        float rot = lp * (r.y - 0.5) * 3.0;
        vec2 c = cuv - 0.5;
        c = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * c * (1.0 - lp * 0.35);
        c += normalize(r - 0.5) * lp * 0.6;
        vec2 suv = (id + c + 0.5) / cells;
        float oldA = 1.0 - smoothstep(0.0, 1.0, lp);
        return mix(texture(newTex, uv), texture(oldTex, suv), oldA);
    }

    if (kind == 11) {
        // glitch: horizontal tears grow and fade around the midpoint (sin(p*PI)),
        // so the disruption peaks exactly when the frame is changing. Each scanline
        // block jumps by its own random amount and the channels split, so the swap
        // arrives as a burst of signal loss that resolves into the new frame.
        float amp = sin(p * PI) * 0.08;
        float band = floor(uv.y * 24.0) / 24.0;
        float dx = (rand(vec2(band, seed)) - 0.5) * amp;
        vec2 g = vec2(uv.x + dx, uv.y);
        float shift = amp * 0.5; // RGB split widens with the tear
        float r = mix(texture(oldTex, g + vec2(shift, 0.0)).r, texture(newTex, g + vec2(shift, 0.0)).r, p);
        float gc = mix(texture(oldTex, g).g, texture(newTex, g).g, p);
        float b = mix(texture(oldTex, g - vec2(shift, 0.0)).b, texture(newTex, g - vec2(shift, 0.0)).b, p);
        float n = rand(uv * (seed + 1.0)) * amp * 2.0; // grain, loudest at the peak
        return vec4(r + n, gc + n, b + n, 1.0);
    }

    if (kind == 12) {
        // crt: a tube being switched off then on. In the first half the old frame
        // is crushed vertically into a bright horizontal line; in the second the
        // new frame reopens back out of it. The glow spikes at the pinch, where a
        // real tube dumps its charge, and everything outside the band goes black.
        float dy = abs(uv.y - 0.5);
        vec3 colour;
        if (p < 0.5) {
            float h = clamp(p * 2.0, 0.0, 1.0);
            float band = mix(0.5, 0.004, h);
            if (dy < band) {
                vec2 s = vec2(uv.x, 0.5 + (uv.y - 0.5) / max(band / 0.5, 0.001));
                colour = texture(oldTex, s).rgb + vec3(0.8, 0.9, 1.0) * smoothstep(band, band * 0.7, dy) * h;
            } else {
                colour = vec3(0.0);
            }
        } else {
            float h = clamp(p * 2.0 - 1.0, 0.0, 1.0);
            float band = mix(0.004, 0.5, h);
            if (dy < band) {
                vec2 s = vec2(uv.x, 0.5 + (uv.y - 0.5) / max(band / 0.5, 0.001));
                colour = texture(newTex, s).rgb + vec3(0.8, 0.9, 1.0) * smoothstep(band, band * 0.7, dy) * (1.0 - h);
            } else {
                colour = vec3(0.0);
            }
        }
        return vec4(colour, 1.0);
    }

    if (kind == 13) {
        // stripes: angled bands sweep in from alternating ends -- odd stripes close
        // from one side, even ones from the other -- each starting a touch later the
        // further along it sits, so the new frame arrives as an interleaving comb.
        // Uses the preset `angle`; the perpendicular extent is derived from it so
        // the sweep clears the whole tilted square. A shadow tracks each moving edge.
        const float stripes = 12.0;
        float a = radians(angle);
        float along = uv.x * cos(a) + uv.y * sin(a);
        float perp = -uv.x * sin(a) + uv.y * cos(a);
        int idx = int(floor(along * stripes));
        bool odd = mod(float(idx), 2.0) != 0.0;
        float delay = clamp(along, 0.0, 1.0) * 0.1; // staggered start per stripe
        float sp = clamp((p - delay) / (1.0 - 0.1), 0.0, 1.0);
        float lo = min(min(0.0, -sin(a)), min(cos(a), cos(a) - sin(a)));
        float hi = max(max(0.0, -sin(a)), max(cos(a), cos(a) - sin(a)));
        float soft = 0.02;
        float edge = odd ? (hi + soft) - sp * (hi - lo + soft * 2.0)
                         : (lo - soft) + sp * (hi - lo + soft * 2.0);
        float mask = odd ? smoothstep(edge - soft, edge + soft, perp)
                         : 1.0 - smoothstep(edge - soft, edge + soft, perp);
        vec4 colour = mix(texture(oldTex, uv), texture(newTex, uv), mask);
        colour.rgb *= 1.0 - 0.2 * (1.0 - abs(sp - 0.5) * 2.0) * (1.0 - smoothstep(0.0, soft * 2.5, abs(perp - edge)));
        return colour;
    }

    if (kind == 14) {
        // melt: Doom's screen melt, from correlated column noise instead of the
        // original 256-entry table. Neighbouring columns share a fall height so the
        // old frame sags in ragged sheets, and the fall gathers speed in the back
        // half as gravity takes over. The old frame is sampled ABOVE the fragment,
        // which slides it down the screen, and the band it has vacated at the top
        // shows the new frame -- the direction the original melts in.
        float col = vnoise(vec2(uv.x * 24.0, seed)) * 0.6 + vnoise(vec2(uv.x * 96.0, seed)) * 0.15;
        float accel = 1.0 + smoothstep(0.5, 1.0, p) * 0.5;
        float push = clamp(col * 0.5 + (p * 2.0 - 1.0) * accel * 2.0, 0.0, 2.0);
        vec2 s = vec2(uv.x, uv.y - push);
        return s.y >= 0.0 ? texture(oldTex, s) : texture(newTex, uv);
    }

    if (kind == 15) {
        // peel: a diagonal front runs corner to corner; ahead of it the new frame
        // is already down, behind it the old sheet slides off toward the origin
        // corner, so it reads as one page being pulled away to show the next.
        float front = (uv.x + uv.y) * 0.5;
        return front < p ? texture(newTex, uv)
                         : texture(oldTex, uv - vec2(p * 0.2));
    }

    return texture(newTex, uv);
}

void main() {
    vec2 uv = qt_TexCoord0;

    // The expressive kinds distort the sample coordinates themselves, which no
    // scalar reveal mask can express, so they composite directly and return before
    // the 0..6 mask path below ever runs.
    if (kind >= 7) {
        fragColor = revealExpressive(uv) * qt_Opacity;
        return;
    }

    vec4 oldC = texture(oldTex, uv);
    vec4 newC = texture(newTex, uv);

    float a;
    if (kind == 0) {
        // fade: plain eased crossfade, no spatial mask.
        a = progress;
    } else {
        float pos; // 0 = revealed first, 1 = revealed last
        if (kind == 1 || kind == 2) {
            // wipe / wave: project uv onto the sweep direction and normalise to the
            // unit square's projected extent, so the front sweeps fully edge to edge
            // at any angle.
            float rad = radians(angle);
            vec2 dir = vec2(cos(rad), sin(rad));
            float lo = min(0.0, dir.x) + min(0.0, dir.y);
            float hi = max(0.0, dir.x) + max(0.0, dir.y);
            pos = (dot(uv, dir) - lo) / max(hi - lo, 1e-4);
            if (kind == 2) {
                // wave: ripple the boundary with a sine along the perpendicular axis.
                vec2 perp = vec2(-dir.y, dir.x);
                pos += waveAmp * sin(dot(uv, perp) * TAU * 2.5);
            }
        } else {
            // radial kinds: distance from the origin in aspect-corrected space so the
            // reveal front is a true circle, normalised by the farthest corner.
            float asp = res.x / max(res.y, 1.0);
            vec2 o = vec2(originX * asp, originY);
            vec2 p = vec2(uv.x * asp, uv.y);
            float d = distance(p, o);
            float m = max(max(distance(o, vec2(0.0, 0.0)), distance(o, vec2(asp, 0.0))),
                          max(distance(o, vec2(0.0, 1.0)), distance(o, vec2(asp, 1.0))));
            float radial = d / max(m, 1e-4);
            // center / grow / any bloom outward; outer seals inward from the edges.
            pos = (kind == 6) ? (1.0 - radial) : radial;
        }
        // sweep a feathered front; widen the range by the feather (and any wave
        // amplitude) so progress 0 reveals nothing and progress 1 reveals all.
        float soft = max(edgeSoftness, 0.002);
        float margin = soft + waveAmp;
        float f = progress * (1.0 + 2.0 * margin) - margin;
        a = smoothstep(pos - soft, pos + soft, f);
    }

    fragColor = mix(oldC, newC, clamp(a, 0.0, 1.0)) * qt_Opacity;
}
