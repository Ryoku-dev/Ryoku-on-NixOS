#version 440

layout(location = 0) in vec4 qt_VertexPosition;
layout(location = 1) in vec2 qt_VertexTexCoord;

layout(location = 0) out vec2 qt_TexCoord0;

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

void main() {
    gl_Position = qt_Matrix * qt_VertexPosition;
    qt_TexCoord0 = qt_VertexTexCoord;
}
