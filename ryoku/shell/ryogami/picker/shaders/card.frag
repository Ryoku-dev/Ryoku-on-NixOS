#version 440

// Output is premultiplied alpha.

layout(location = 0) in vec2 v_local;
layout(location = 1) in vec2 v_half;
layout(location = 2) in vec4 v_radii;
layout(location = 3) in vec4 v_fill;
layout(location = 4) in vec4 v_tint;
layout(location = 5) in vec4 v_border;
layout(location = 6) in vec4 v_params;
layout(location = 7) in vec4 v_uv;
layout(location = 8) in vec4 v_crop;
layout(location = 9) flat in uvec4 v_misc;
layout(location = 10) in vec2 v_world;
layout(location = 11) in vec4 v_flip;
layout(location = 12) in vec4 v_shape;
layout(location = 13) flat in vec4 v_quadL;

layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 mvp;
    vec4 clip;
    float time;
    float vis;
    float opacity;
    float pad;
};

layout(binding = 1) uniform sampler2DArray nearTex;
layout(binding = 2) uniform sampler2DArray farTex;
layout(binding = 3) uniform sampler2D previewTex;

const uint CUSTOM_SHAPE = 1u;
const uint SHIMMER = 2u;
const uint PAGE_BEND = 32u;
const uint SHADOW = 64u;
const uint PROJECTED = 128u;
const uint RIBBON_COLUMNS = 4096u;
const uint GHOST = 8192u;
const uint BACKDROP = 16384u;
const uint BACKFACE = 32768u;
const uint MUTED = 65536u;
const uint UNFRAMED_RECT = 131072u;

vec3 sampleCard(vec2 norm)
{
    vec2 n = clamp(norm, vec2(0.0), vec2(1.0));
    vec2 cropped = v_crop.xy + n * v_crop.zw;
    vec2 uv = v_uv.xy + cropped * v_uv.zw;
    if (v_misc.x == 1u)
        return textureLod(nearTex, vec3(uv, float(v_misc.y)), 0.0).rgb;
    if (v_misc.x == 3u)
        return textureLod(previewTex, uv, 0.0).rgb;
    return textureLod(farTex, vec3(uv, float(v_misc.y)), 0.0).rgb;
}

vec3 nearLod(vec2 norm, float lod)
{
    vec2 n = clamp(norm, vec2(0.0), vec2(1.0));
    vec2 cropped = v_crop.xy + n * v_crop.zw;
    vec2 uv = v_uv.xy + cropped * v_uv.zw;
    return textureLod(nearTex, vec3(uv, float(v_misc.y)), lod).rgb;
}

float ribbonCut()
{
    vec2 he = max(v_half, vec2(1.0));
    if ((v_misc.w & RIBBON_COLUMNS) != 0u) {
        float f = clamp(v_local.y / he.y * 0.5 + 0.5, -0.5, 1.5);
        float left = mix(v_quadL.x, v_quadL.w, f);
        float right = mix(v_quadL.y, v_quadL.z, f);
        return max(left - v_local.x, v_local.x - right);
    }
    float f = clamp(v_local.x / he.x * 0.5 + 0.5, -0.5, 1.5);
    float top = mix(v_quadL.x, v_quadL.y, f);
    float bottom = mix(v_quadL.w, v_quadL.z, f);
    return max(top - v_local.y, v_local.y - bottom);
}

vec3 backdropBlur(vec2 norm, float radius)
{
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 16; i++) {
        float fi = float(i) + 0.5;
        float ang = fi * 2.39996323;
        float r = sqrt(fi / 16.0) * radius;
        acc += nearLod(norm + vec2(cos(ang), sin(ang)) * r, 4.0);
    }
    return acc / 16.0;
}

vec3 ghostBlur(vec2 norm, float radius)
{
    float aspect = max(v_half.x, 1.0) / max(v_half.y, 1.0);
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 12; i++) {
        float fi = float(i) + 0.5;
        float ang = fi * 2.39996323;
        float r = sqrt(fi / 12.0) * radius;
        vec2 p = norm + vec2(cos(ang), sin(ang) * aspect) * r;
        if (v_misc.x == 1u)
            acc += nearLod(p, 1.0);
        else
            acc += sampleCard(p);
    }
    return acc / 12.0;
}

vec3 backdropGrade(vec3 rgbIn)
{
    vec3 rgb = (rgbIn - vec3(0.5)) * 1.25 + vec3(0.5);
    rgb = max(rgb, vec3(0.0)) * 0.38;
    vec2 norm = v_local / (2.0 * max(v_half, vec2(1.0))) + vec2(0.5);
    float p = length((norm - vec2(0.5, 0.44)) / vec2(0.7, 0.6));
    float veil = 0.72 * clamp(p / 0.7, 0.0, 1.0);
    veil = veil + 0.24 * clamp((p - 0.7) / 0.3, 0.0, 1.0);
    rgb = mix(rgb, vec3(4.0, 4.0, 6.0) / 255.0, clamp(veil, 0.0, 0.96));
    float line = step(fract(v_world.y / 3.0), 0.34) - 0.34;
    return rgb + vec3(line * 0.008);
}

float sdShearedRoundedBox(vec2 p, vec2 bIn, vec4 radii, float skew, float edgeTilt)
{
    float sx = skew * 0.5;
    float ty = edgeTilt * 0.5;
    vec2 b = max(bIn - abs(vec2(sx, ty)), vec2(1.0));
    float det = b.x * b.y - sx * ty;
    float safeDet = abs(det) < 1.0 ? (det >= 0.0 ? 1.0 : -1.0) : det;
    vec2 q = vec2((b.y * p.x + sx * p.y) / safeDet * b.x,
                  (ty * p.x + b.x * p.y) / safeDet * b.y);
    bool top = q.y < 0.0;
    bool left = q.x < 0.0;
    float r = top ? (left ? radii.x : radii.y) : (left ? radii.w : radii.z);
    vec2 d = abs(q) - b + vec2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0))) - r;
}

float sdHexagonFlat(vec2 p, float circumradius)
{
    float a = circumradius * 0.866025;
    vec2 q = abs(p);
    return max(dot(q, vec2(0.866025, 0.5)), q.y) - a;
}

float sdTriangle(vec2 p, vec2 halfExt, uint direction)
{
    vec2 q = p / max(halfExt, vec2(1.0));
    if (direction == 1u)
        q.y = -q.y;
    else if (direction == 2u)
        q = vec2(q.y, q.x);
    else if (direction == 3u)
        q = vec2(q.y, -q.x);
    float side = (2.0 * abs(q.x) - q.y - 1.0) / 2.2360679775;
    return max(side, q.y - 1.0) * min(halfExt.x, halfExt.y);
}

float sdDiamond(vec2 p, vec2 halfExt)
{
    vec2 he = max(halfExt, vec2(1.0));
    float normalLen = length(vec2(he.y, he.x));
    float edge = he.x * he.y;
    float topRight = dot(p, vec2(he.y, he.x)) - edge;
    float bottomRight = dot(p, vec2(he.y, -he.x)) - edge;
    float topLeft = dot(p, vec2(-he.y, he.x)) - edge;
    float bottomLeft = dot(p, vec2(-he.y, -he.x)) - edge;
    return max(max(topRight, bottomRight), max(topLeft, bottomLeft)) / normalLen;
}

float hash21(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise2(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float cnoise(vec2 p)
{
    return vnoise2(p) * 0.65 + vnoise2(p * 2.13 + vec2(11.5, 3.7)) * 0.35;
}

float luma(vec3 c)
{
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 cardDof(vec2 norm, float blur, float ca)
{
    vec2 dirn = v_local / max(v_half, vec2(1.0));
    vec2 caOff = dirn * ca * 0.016;
    if (v_misc.x == 1u) {
        float lod = blur * 3.4;
        if (ca > 0.01) {
            float r = nearLod(norm + caOff, lod).r;
            float g = nearLod(norm, lod).g;
            float b = nearLod(norm - caOff, lod).b;
            return vec3(r, g, b);
        }
        return nearLod(norm, lod);
    }
    vec2 offs[5] = vec2[5](vec2(0.0, 0.0), vec2(0.85, 0.3), vec2(-0.3, 0.85),
                           vec2(-0.85, -0.3), vec2(0.3, -0.85));
    float rad = blur * 0.05;
    vec3 acc = vec3(0.0);
    for (int t = 0; t < 5; t++)
        acc += sampleCard(norm + offs[t] * rad);
    vec3 rgb = acc / 5.0;
    if (ca > 0.01) {
        float r = sampleCard(norm + caOff).r;
        float b = sampleCard(norm - caOff).b;
        rgb = vec3(mix(rgb.r, r, 0.7), rgb.g, mix(rgb.b, b, 0.7));
    }
    return rgb;
}

vec3 flipColor(float p)
{
    int eff = int(v_flip.z + 0.5);
    vec2 norm = clamp(v_local / (2.0 * v_half) + vec2(0.5), vec2(0.0), vec2(1.0));
    vec2 seed = vec2(v_flip.y * 1.7, v_flip.y * 0.9 + 4.0);
    vec3 sharp = sampleCard(norm);
    vec3 bacc = sampleCard(norm + vec2(0.012, 0.0)) + sampleCard(norm + vec2(-0.012, 0.0))
              + sampleCard(norm + vec2(0.0, 0.012)) + sampleCard(norm + vec2(0.0, -0.012));
    vec3 back = (bacc / 4.0) * 0.2;
    vec3 col = sharp;

    if (eff == 0) {
        float lum = luma(sharp);
        float n = cnoise(norm * 7.0 + seed) * 0.12;
        float field = (1.0 - lum) * 0.8 + n;
        float burn = p * 1.25 - 0.12;
        float e = field - burn;
        float intact = smoothstep(0.0, 0.05, e);
        float g1 = e / 0.045;
        float glow = exp(-g1 * g1);
        float g2 = e / 0.015;
        float core = exp(-g2 * g2);
        vec3 c = mix(back, sharp, intact);
        c = mix(c, c * vec3(0.25, 0.18, 0.15), smoothstep(0.05, -0.02, e) * intact);
        c = c + vec3(1.0, 0.5, 0.12) * glow * 1.3 + vec3(1.0, 0.9, 0.5) * core * 0.8;
        float spk = hash21(floor((norm - vec2(0.0, p * 0.1)) * 200.0) + seed);
        c = c + vec3(1.0, 0.7, 0.3) * step(0.992, spk) * glow * 1.5;
        col = c;
    } else if (eff == 1) {
        float o = 0.004;
        float lx1 = luma(sampleCard(norm + vec2(o, 0.0)));
        float lx0 = luma(sampleCard(norm - vec2(o, 0.0)));
        float ly1 = luma(sampleCard(norm + vec2(0.0, o)));
        float ly0 = luma(sampleCard(norm - vec2(0.0, o)));
        vec2 grad = vec2(lx1 - lx0, ly1 - ly0);
        float edge = clamp(length(grad) * 7.0, 0.0, 1.0);
        float field = (1.0 - edge) * 0.7 + cnoise(norm * 9.0 + seed) * 0.3;
        float front = p * 1.2 - 0.1;
        float m = smoothstep(front, front + 0.08, field);
        vec3 src = sampleCard(norm + normalize(grad + vec2(1e-4, 0.0)) * (1.0 - m) * 0.06);
        col = mix(back, src, m) + vec3(0.5, 0.75, 1.0) * edge * (1.0 - m) * m * 3.5;
    } else if (eff == 2) {
        float lum = luma(sharp);
        float field = mix((norm.x + norm.y) * 0.5, 1.0 - lum, 0.75);
        float front = p * 1.2 - 0.1;
        float m = smoothstep(front - 0.04, front + 0.04, field);
        float g = (field - front) / 0.04;
        float glow = exp(-g * g);
        col = mix(back, sharp, m) + vec3(0.7, 0.85, 1.0) * glow * 0.5;
    } else if (eff == 4) {
        float depth = luma(sharp);
        float push = p * 0.18;
        vec2 disp = (norm - vec2(0.5)) * (depth * push * 1.5 + push * 0.2);
        vec3 s = sampleCard(norm + disp);
        float shade = mix(0.6, 1.1, depth);
        float dim = mix(1.0, 0.42, smoothstep(0.3, 1.0, p));
        col = s * shade * dim;
    } else if (eff == 5) {
        float r = 0.012 + p * 0.07;
        vec3 acc = vec3(0.0);
        float wsum = 0.0;
        for (int i = 0; i < 40; i++) {
            float fi = float(i) + 0.5;
            float ang = fi * 2.39996323;
            float rad = sqrt(fi / 40.0) * r;
            vec3 s = sampleCard(norm + vec2(cos(ang), sin(ang)) * rad);
            float w = pow(luma(s) + 0.02, 4.0);
            acc += s * w;
            wsum += w;
        }
        vec3 bok = acc / max(wsum, 0.0001);
        vec3 mixed = mix(sharp, bok, smoothstep(0.0, 0.45, p));
        vec3 glow = mixed * (1.0 + smoothstep(0.55, 1.0, luma(bok)) * 0.9);
        col = glow * mix(1.0, 0.55, smoothstep(0.3, 1.0, p));
    } else if (eff == 6) {
        vec2 dir = normalize(vec2(0.55, -0.83));
        float len = p * 0.55;
        vec3 acc = vec3(0.0);
        float w = 0.0;
        for (int i = 0; i < 16; i++) {
            float f = float(i) / 16.0;
            vec3 s = sampleCard(norm - dir * len * f);
            float l = luma(s);
            float wt = l * l * (1.0 - f) + 0.001;
            acc += s * wt;
            w += wt;
        }
        vec3 streak = acc / w;
        vec3 base = sharp + streak * smoothstep(0.0, 0.55, p) * 1.3;
        col = base * mix(1.0, 0.5, smoothstep(0.3, 1.0, p));
    } else if (eff == 7) {
        float n = mix(70.0, 22.0, p);
        vec2 cell = floor(norm * n);
        vec2 tile = (cell + vec2(0.5)) / n;
        float tl = luma(sampleCard(tile));
        vec2 local = fract(norm * n) - vec2(0.5);
        float bevel = clamp(1.0 - (abs(local.x) + abs(local.y)) * 0.8, 0.45, 1.25);
        vec3 s = sampleCard(tile) * bevel * (0.7 + tl * 0.7);
        col = s * mix(1.0, 0.5, smoothstep(0.3, 1.0, p));
    } else if (eff == 8) {
        float amt = p * 0.6;
        vec3 acc = vec3(0.0);
        float w = 0.0;
        for (int i = 0; i < 16; i++) {
            float f = float(i) / 16.0;
            vec3 s = sampleCard(vec2(norm.x, clamp(norm.y - amt * f, 0.0, 1.0)));
            float wt = smoothstep(0.45, 1.0, luma(s)) + 0.03;
            acc += s * wt;
            w += wt;
        }
        vec3 sorted = acc / w;
        vec3 base = mix(sharp, sorted, smoothstep(0.0, 0.45, p));
        col = base * mix(1.0, 0.5, smoothstep(0.3, 1.0, p));
    } else if (eff == 9) {
        float r = p * 0.05;
        vec3 acc = vec3(0.0);
        for (int i = 0; i < 24; i++) {
            float fi = float(i) + 0.5;
            float ang = fi * 2.39996323;
            float rad = sqrt(fi / 24.0) * r;
            acc += sampleCard(norm + vec2(cos(ang), sin(ang)) * rad);
        }
        col = (acc / 24.0) * mix(1.0, 0.5, smoothstep(0.3, 1.0, p));
    } else if (eff == 10) {
        float l = luma(sharp);
        float d = abs(fract(l * 15.0) - 0.5) * 2.0;
        float contour = 1.0 - smoothstep(0.0, 0.14, d);
        vec3 glowcol = mix(sharp * 0.22, vec3(0.45, 0.85, 1.0), contour);
        vec3 topo = mix(sharp, glowcol, smoothstep(0.1, 0.55, p));
        col = topo * mix(1.0, 0.5, smoothstep(0.3, 1.0, p));
    } else if (eff == 11) {
        float lum = luma(sharp);
        float field = 1.0 - lum;
        float front = p * 1.2 - 0.1;
        float m = smoothstep(front - 0.04, front + 0.04, field);
        float g = (field - front) / 0.04;
        float glow = exp(-g * g);
        col = mix(back, sharp, m) + vec3(0.7, 0.85, 1.0) * glow * 0.5;
    } else {
        float lum = luma(sharp);
        float order = (1.0 - lum) * 0.85 + cnoise(norm * 8.0 + seed) * 0.15;
        float burn = p * 1.2 - 0.1;
        float age = clamp((burn - order) * 2.2, 0.0, 1.0);
        if (age <= 0.0) {
            col = sharp;
        } else {
            vec2 drift = vec2((cnoise(norm * 5.0 + seed) - 0.5) * 0.6, -0.5) * age * 0.13;
            vec3 src = sampleCard(norm - drift);
            float grain = hash21(floor((norm - drift) * 150.0) + seed);
            float a = step(age, grain) * (1.0 - age);
            float e = (age - 0.1) / 0.12;
            float glow = exp(-e * e);
            col = mix(back, src + vec3(0.8, 0.4, 0.15) * glow, a);
            col = col + vec3(1.0, 0.85, 0.6) * step(0.99, grain) * glow * 0.7;
        }
    }
    return col;
}

void main()
{
    float skew = v_params.x;
    float borderW = v_params.y;
    float cardOpacity = v_params.z;
    float fade = v_params.w;
    float vf = clamp(vis, 0.0, 1.0) * opacity;

    if ((v_misc.w & SHADOW) != 0u) {
        float blur = max(borderW, 1.0);
        vec2 he = max(v_half - vec2(blur * 0.8), vec2(1.0));
        float ds = sdShearedRoundedBox(v_local, he, v_radii, skew, v_shape.x);
        float sa = v_fill.a * pow(clamp(1.0 - (ds + blur * 0.2) / blur, 0.0, 1.0), 1.7) * cardOpacity;
        fragColor = vec4(v_fill.rgb * sa * vf, sa * vf);
        return;
    }

    vec2 cardP = v_local;
    if ((v_misc.w & BACKFACE) != 0u) {
        if ((v_misc.w & RIBBON_COLUMNS) != 0u)
            cardP.x = 2.0 * v_shape.z - cardP.x;
        else
            cardP.y = 2.0 * v_shape.z - cardP.y;
    }

    float d;
    if ((v_misc.w & CUSTOM_SHAPE) != 0u) {
        uint shape = (v_misc.w >> 8u) & 15u;
        if (shape >= 1u && shape <= 4u)
            d = sdTriangle(v_local, v_half, shape - 1u);
        else if (shape == 5u || shape == 6u)
            d = sdDiamond(v_local, v_half);
        else
            d = sdHexagonFlat(v_local, v_half.x);
    } else {
        d = sdShearedRoundedBox(cardP, v_half, v_radii, skew, v_shape.x);
    }
    if ((v_misc.w & PROJECTED) != 0u)
        d = max(d, ribbonCut());
    float grad = max(length(vec2(dFdx(d), dFdy(d))), 0.0001);
    float shapeA = (v_misc.w & UNFRAMED_RECT) != 0u ? step(d, 0.0) : clamp(0.5 - d / grad, 0.0, 1.0);

    if ((v_misc.w & PAGE_BEND) != 0u && v_misc.x > 0u) {
        float bend = clamp(v_flip.w, -2.7, 2.7);
        float par = v_flip.y;
        float padding = max(v_flip.z, 1.0);
        float hw = v_half.x / padding;
        float hh = v_half.y / padding;
        vec2 loc = v_local;
        float yn = clamp(loc.y / max(hh, 1.0), -1.35, 1.35);
        loc.x -= bend * hw * 0.5 * yn * yn;
        loc.y *= 1.0 + abs(bend) * 0.12 * (1.0 - clamp(abs(loc.x / max(hw, 1.0)), 0.0, 1.0));
        float d2 = sdShearedRoundedBox(loc, vec2(hw, hh), v_radii, skew, v_shape.x);
        float grad2 = max(length(vec2(dFdx(d2), dFdy(d2))), 0.0001);
        float sa = clamp(0.5 - d2 / grad2, 0.0, 1.0);
        vec2 norm = clamp(loc / (2.0 * vec2(hw, hh)) + vec2(0.5), vec2(0.0), vec2(1.0));
        norm.x = clamp(norm.x + par * 0.05, 0.0, 1.0);
        float ca = abs(bend) * 0.02;
        vec3 cr = sampleCard(vec2(clamp(norm.x + ca, 0.0, 1.0), norm.y));
        vec3 cg = sampleCard(norm);
        vec3 cb = sampleCard(vec2(clamp(norm.x - ca, 0.0, 1.0), norm.y));
        vec3 col = vec3(cr.r, cg.g, cb.b);
        col = mix(col, v_tint.rgb, v_tint.a);
        vec3 base2 = mix(v_fill.rgb, col, fade);
        float strokeD2 = abs(d2 + borderW * 0.5) - borderW * 0.5;
        float sa2 = clamp(0.5 - strokeD2 / grad2, 0.0, 1.0) * v_border.a * step(0.001, borderW);
        vec3 rgbo = base2 * sa;
        rgbo = rgbo * (1.0 - sa2) + v_border.rgb * sa2;
        float ao = max(sa, sa2);
        fragColor = vec4(rgbo * cardOpacity * vf, ao * cardOpacity * vf);
        return;
    }

    vec4 base = v_fill;
    if (v_misc.x > 0u) {
        vec2 norm = clamp(cardP / (2.0 * v_half) + vec2(0.5), vec2(0.0), vec2(1.0));
        float blur = v_flip.w;
        float ca = v_flip.x < 0.001 ? v_flip.y : 0.0;
        vec3 rgb;
        if ((v_misc.w & GHOST) != 0u) {
            rgb = ghostBlur(norm, 0.06 * v_flip.w);
        } else if ((v_misc.w & BACKDROP) != 0u && v_misc.x == 1u) {
            rgb = backdropGrade(backdropBlur(norm, 0.05 * v_flip.w));
        } else if (blur > 0.01 || ca > 0.01) {
            rgb = cardDof(norm, blur, ca);
        } else {
            vec2 cropped = v_crop.xy + norm * v_crop.zw;
            vec2 uv = v_uv.xy + cropped * v_uv.zw;
            if (v_misc.x == 1u)
                rgb = texture(nearTex, vec3(uv, float(v_misc.y))).rgb;
            else if (v_misc.x == 3u)
                rgb = texture(previewTex, uv).rgb;
            else
                rgb = texture(farTex, vec3(uv, float(v_misc.y))).rgb;
        }
        if ((v_misc.w & GHOST) != 0u)
            rgb = vec3(luma(rgb) * 1.7);
        if ((v_misc.w & (BACKFACE | MUTED)) != 0u)
            rgb = vec3(clamp((luma(rgb) - 0.5) * 1.15 + 0.5, 0.0, 1.0) * 0.5);
        base = mix(v_fill, vec4(rgb, 1.0), fade);
    }
    if ((v_misc.w & SHIMMER) != 0u) {
        float sweep = fract(time / 1.2);
        float nx = clamp(v_local.x / (2.0 * max(v_half.x, 1.0)) + 0.5, 0.0, 1.0);
        float band = 1.0 - abs(nx - sweep * 1.5 + 0.25) / 0.25;
        base = vec4(base.rgb + vec3(0.35) * clamp(band, 0.0, 1.0) * 0.35, base.a);
    }
    float flipP = v_flip.x;
    if (flipP > 0.001 && v_misc.x > 0u)
        base = vec4(flipColor(clamp(flipP, 0.0, 1.0)), base.a);
    base = vec4(mix(base.rgb, v_tint.rgb, v_tint.a), base.a);

    float fillA = shapeA * base.a;
    float strokeD = abs(d + borderW * 0.5) - borderW * 0.5;
    float strokeA = clamp(0.5 - strokeD / grad, 0.0, 1.0) * v_border.a * step(0.001, borderW);
    vec3 rgb = base.rgb * fillA;
    rgb = rgb * (1.0 - strokeA) + v_border.rgb * strokeA;
    float a = max(fillA, strokeA) * cardOpacity;
    if (v_misc.z == 1u) {
        float inside = step(clip.x, v_world.x) * step(clip.y, v_world.y)
                     * step(v_world.x, clip.z) * step(v_world.y, clip.w);
        a *= inside;
        rgb *= inside;
    }
    fragColor = vec4(rgb * cardOpacity * vf, a * vf);
}
