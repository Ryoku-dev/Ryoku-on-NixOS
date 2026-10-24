#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec4 focusBounds;
    float floorAlpha;
} u;

void main() {
    vec2 size = max(u.surfaceSize, vec2(1.0));
    vec2 point = qt_TexCoord0 * size;
    vec2 center = u.focusBounds.xy + u.focusBounds.zw * 0.5;
    float inner = max(1.0, min(u.focusBounds.z, u.focusBounds.w) * 0.5);
    vec2 farthest = max(center, size - center);
    float outer = inner + length(farthest);
    float t = clamp((distance(point, center) - inner)
        / max(1.0, outer - inner), 0.0, 1.0);
    float ramp = (exp(2.0 * t) - 1.0) / (exp(2.0) - 1.0);
    float alpha = mix(clamp(u.floorAlpha, 0.0, 1.0), 1.0, ramp)
        * u.qt_Opacity;
    fragColor = vec4(0.0, 0.0, 0.0, alpha);
}
