#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float strokeWidth;
    float blur;
    float strength;
    vec4 color;
    float phase;
    float activeFade;
    int mode;
};

const float PI = 3.14159265358979323846;
const float TAU = 6.28318530717958647692;

float roundedRectSdf(vec2 point, vec2 center, vec2 halfSize, float cornerRadius) {
    vec2 offset = abs(point - center) - halfSize + vec2(cornerRadius);
    return length(max(offset, vec2(0.0))) + min(max(offset.x, offset.y), 0.0) - cornerRadius;
}

void main() {
    vec2 pixel = qt_TexCoord0 * size;
    vec2 center = size * 0.5;
    float halfStroke = max(strokeWidth * 0.5, 0.001);
    vec2 halfSize = max(center - vec2(halfStroke), vec2(0.0));
    float cornerRadius = clamp(radius - halfStroke, 0.0, min(halfSize.x, halfSize.y));
    float sdf = roundedRectSdf(pixel, center, halfSize, cornerRadius);
    float feather = max(blur, fwidth(sdf));
    float band = 1.0 - smoothstep(halfStroke, halfStroke + feather, abs(sdf));

    float window = 1.0;
    if (mode == 0) {
        float beamCenter = mix(-0.05, 1.05, phase);
        float distance = (qt_TexCoord0.x - beamCenter) / 0.115;
        float gaussian = exp(-0.5 * distance * distance);
        float bottomEdge = smoothstep(0.56, 0.94, qt_TexCoord0.y);
        float cycleFade = smoothstep(0.0, 0.10, phase) * (1.0 - smoothstep(0.82, 1.0, phase));
        window = gaussian * bottomEdge * cycleFade;
    } else if (mode == 1) {
        float borderAngle = atan(pixel.y - center.y, pixel.x - center.x);
        float headAngle = phase * TAU - PI;
        float trailingAngle = mod(headAngle - borderAngle + TAU, TAU);
        window = 1.0 - smoothstep(0.0, PI * 0.5, trailingAngle);
    } else {
        window = 0.35 + 0.65 * (0.5 + 0.5 * sin(TAU * phase));
    }

    float alpha = band * window * strength * activeFade * color.a;
    fragColor = vec4(color.rgb * alpha, alpha) * qt_Opacity;
}
