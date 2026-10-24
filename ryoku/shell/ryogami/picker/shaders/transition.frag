#version 440

// Inputs are premultiplied, so the blends and the final opacity stay premultiplied.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    vec2 resolution;
    vec2 origin;
    float progress;
    uint kind;
    float opacity;
    float pad;
    vec4 accent;
};

layout(binding = 1) uniform sampler2D texA;
layout(binding = 2) uniform sampler2D texB;

float hash2(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 s = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

void main()
{
    float p = clamp(progress, 0.0, 1.0);
    float t = p * p * (3.0 - 2.0 * p);
    vec2 uv = v_uv;
    vec4 col;

    if (kind == 1u) {
        float aspect = resolution.x / max(resolution.y, 1.0);
        vec2 pos = vec2(uv.x * aspect, uv.y);
        vec2 org = vec2(origin.x * aspect, origin.y);
        float d = distance(pos, org);
        float wave = sin(d * 44.0 - p * 18.0);
        float amp = 0.022 * (1.0 - p) * smoothstep(0.0, 0.2, p);
        vec2 dir = normalize(pos - org + vec2(0.0001, 0.0));
        vec2 off = vec2(dir.x / aspect, dir.y) * wave * amp;
        vec2 uv0 = clamp(uv + off, vec2(0.0), vec2(1.0));
        vec2 uv1 = clamp(uv + off * 1.6, vec2(0.0), vec2(1.0));
        vec2 uv2 = clamp(uv + off * 0.4, vec2(0.0), vec2(1.0));
        vec4 a = vec4(texture(texA, uv1).r, texture(texA, uv0).g, texture(texA, uv2).b, texture(texA, uv0).a);
        vec4 b = vec4(texture(texB, uv1).r, texture(texB, uv0).g, texture(texB, uv2).b, texture(texB, uv0).a);
        col = mix(a, b, t);
        float wf = p * 1.3;
        float ring = exp(-abs(d - wf) * 26.0) * (1.0 - p) * 1.5;
        col = vec4(col.rgb + accent.rgb * ring, max(col.a, ring * 0.5));
    } else if (kind == 2u) {
        float n = vnoise(uv * 14.0) * 0.7 + vnoise(uv * 47.0) * 0.3;
        float edge = 0.06;
        float cut = p * (1.0 + edge * 2.0) - edge;
        float m = smoothstep(cut - edge, cut + edge, n);
        vec4 a = texture(texA, uv);
        vec4 b = texture(texB, uv);
        float burn = smoothstep(cut - edge, cut, n) * smoothstep(cut + edge, cut, n);
        col = mix(b, a, m);
        col = vec4(col.rgb + accent.rgb * burn * 1.6 * col.a, col.a);
    } else if (kind == 3u) {
        float row = floor(uv.y * 36.0);
        float jitter = (hash2(vec2(row, floor(p * 14.0))) - 0.5) * 2.0;
        float strength = sin(p * 3.14159);
        float shift = jitter * 0.08 * strength;
        vec2 uv_s = vec2(clamp(uv.x + shift, 0.0, 1.0), uv.y);
        float split = 0.012 * strength;
        float src_mix = step(hash2(vec2(row, 7.0)), p);
        if (src_mix > 0.5) {
            col = vec4(texture(texB, vec2(clamp(uv_s.x + split, 0.0, 1.0), uv_s.y)).r,
                       texture(texB, uv_s).g,
                       texture(texB, vec2(clamp(uv_s.x - split, 0.0, 1.0), uv_s.y)).b,
                       texture(texB, uv_s).a);
        } else {
            col = vec4(texture(texA, vec2(clamp(uv_s.x + split, 0.0, 1.0), uv_s.y)).r,
                       texture(texA, uv_s).g,
                       texture(texA, vec2(clamp(uv_s.x - split, 0.0, 1.0), uv_s.y)).b,
                       texture(texA, uv_s).a);
        }
    } else {
        vec4 a = texture(texA, uv);
        vec4 b = texture(texB, uv);
        col = mix(a, b, t);
    }

    fragColor = col * opacity;
}
