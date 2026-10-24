#version 440

// The scene textures share the target's framebuffer orientation, so uv needs no per-backend flip.

layout(location = 0) out vec2 v_uv;

void main()
{
    float x = float(gl_VertexIndex / 2) * 4.0 - 1.0;
    float y = float(gl_VertexIndex % 2) * 4.0 - 1.0;
    gl_Position = vec4(x, y, 0.0, 1.0);
    v_uv = vec2(x * 0.5 + 0.5, y * 0.5 + 0.5);
}
