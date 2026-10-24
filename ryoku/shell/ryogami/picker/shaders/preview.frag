#version 440

// kind: 0 crossfade, 1 wipe, 2 ripple, 3 dissolve. Uniforms follow the ShaderEffect layout.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    int kind;
};

layout(binding = 1) uniform sampler2D texA;
layout(binding = 2) uniform sampler2D texB;

float hash2(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main()
{
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    float t = p * p * (3.0 - 2.0 * p);
    vec4 a = texture(texA, uv);
    vec4 b = texture(texB, uv);
    vec4 col;

    if (kind == 1) {
        float edge = p * 1.12 - 0.06;
        float m = 1.0 - smoothstep(edge - 0.06, edge + 0.06, uv.x);
        col = mix(a, b, m);
    } else if (kind == 2) {
        float d = distance(uv, vec2(0.5));
        float wave = sin(d * 40.0 - p * 18.0);
        float amp = 0.03 * (1.0 - p) * smoothstep(0.0, 0.2, p);
        vec2 dir = normalize(uv - vec2(0.5) + vec2(0.0001));
        vec2 off = dir * wave * amp;
        vec4 aw = texture(texA, clamp(uv + off, vec2(0.0), vec2(1.0)));
        vec4 bw = texture(texB, clamp(uv + off, vec2(0.0), vec2(1.0)));
        col = mix(aw, bw, t);
    } else if (kind == 3) {
        float n = hash2(floor(uv * vec2(120.0)));
        float edge = 0.08;
        float cut = p * (1.0 + edge * 2.0) - edge;
        float m = smoothstep(cut - edge, cut + edge, n);
        col = mix(b, a, m);
    } else {
        col = mix(a, b, t);
    }

    fragColor = col * qt_Opacity;
}
