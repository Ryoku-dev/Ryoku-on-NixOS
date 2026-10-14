#version 440

// skwd transition: edge-transition. Ports skwd-daemon's EDGE_TRANSITION_FRAG
// (crates/paper/src/transition_paper.rs); math verbatim, only Qt plumbing changed.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float seed;
    vec2 res;
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;

const float edge_thickness = 0.001;
const float edge_brightness = 8.0;

vec4 getFromEdgeColor(vec2 uv) {
    vec2 e = vec2(edge_thickness);
    vec3 c0 = texture(oldTex, uv + e * vec2(-1.0, -1.0)).rgb;
    vec3 c1 = texture(oldTex, uv + e * vec2(-1.0,  0.0)).rgb;
    vec3 c2 = texture(oldTex, uv + e * vec2(-1.0,  1.0)).rgb;
    vec3 c3 = texture(oldTex, uv + e * vec2( 0.0, -1.0)).rgb;
    vec3 c4 = texture(oldTex, uv).rgb;
    vec3 c5 = texture(oldTex, uv + e * vec2( 0.0,  1.0)).rgb;
    vec3 c6 = texture(oldTex, uv + e * vec2( 1.0, -1.0)).rgb;
    vec3 c7 = texture(oldTex, uv + e * vec2( 1.0,  0.0)).rgb;
    vec3 c8 = texture(oldTex, uv + e * vec2( 1.0,  1.0)).rgb;
    vec3 dx = 2.0 * abs(c7 - c1) + abs(c2 - c6) + abs(c8 - c0);
    vec3 dy = 2.0 * abs(c3 - c5) + abs(c6 - c8) + abs(c0 - c2);
    float delta = length(0.25 * (dx + dy) * 0.5);
    return vec4(clamp(edge_brightness * delta, 0.0, 1.0) * c4, 1.0);
}

vec4 getToEdgeColor(vec2 uv) {
    vec2 e = vec2(edge_thickness);
    vec3 c0 = texture(newTex, uv + e * vec2(-1.0, -1.0)).rgb;
    vec3 c1 = texture(newTex, uv + e * vec2(-1.0,  0.0)).rgb;
    vec3 c2 = texture(newTex, uv + e * vec2(-1.0,  1.0)).rgb;
    vec3 c3 = texture(newTex, uv + e * vec2( 0.0, -1.0)).rgb;
    vec3 c4 = texture(newTex, uv).rgb;
    vec3 c5 = texture(newTex, uv + e * vec2( 0.0,  1.0)).rgb;
    vec3 c6 = texture(newTex, uv + e * vec2( 1.0, -1.0)).rgb;
    vec3 c7 = texture(newTex, uv + e * vec2( 1.0,  0.0)).rgb;
    vec3 c8 = texture(newTex, uv + e * vec2( 1.0,  1.0)).rgb;
    vec3 dx = 2.0 * abs(c7 - c1) + abs(c2 - c6) + abs(c8 - c0);
    vec3 dy = 2.0 * abs(c3 - c5) + abs(c6 - c8) + abs(c0 - c2);
    float delta = length(0.25 * (dx + dy) * 0.5);
    return vec4(clamp(edge_brightness * delta, 0.0, 1.0) * c4, 1.0);
}

vec4 transition (vec2 uv) {
  vec4 start = mix(texture(oldTex, uv), getFromEdgeColor(uv), clamp(2.0 * progress, 0.0, 1.0));
  vec4 end = mix(getToEdgeColor(uv), texture(newTex, uv), clamp(2.0 * (progress - 0.5), 0.0, 1.0));
  return mix(
    start,
    end,
    progress
  );
}
void main() {
    vec2 v_uv = qt_TexCoord0;
    fragColor = transition(v_uv) * qt_Opacity;
}
