#version 440

// Six vertices per instance, no index buffer.

layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_radii;
layout(location = 2) in vec4 a_fill;
layout(location = 3) in vec4 a_tint;
layout(location = 4) in vec4 a_border;
layout(location = 5) in vec4 a_params;
layout(location = 6) in vec4 a_uv;
layout(location = 7) in vec4 a_crop;
layout(location = 8) in uvec4 a_misc;
layout(location = 9) in vec4 a_flip;
layout(location = 10) in vec4 a_shape;
layout(location = 11) in vec4 a_quadA;
layout(location = 12) in vec4 a_quadB;
layout(location = 13) in vec4 a_quadW;
layout(location = 14) in vec4 a_quadL;

layout(std140, binding = 0) uniform buf {
    mat4 mvp;
    vec4 clip;
    float time;
    float vis;
    float opacity;
    float pad;
};

layout(location = 0) out vec2 v_local;
layout(location = 1) out vec2 v_half;
layout(location = 2) out vec4 v_radii;
layout(location = 3) out vec4 v_fill;
layout(location = 4) out vec4 v_tint;
layout(location = 5) out vec4 v_border;
layout(location = 6) out vec4 v_params;
layout(location = 7) out vec4 v_uv;
layout(location = 8) out vec4 v_crop;
layout(location = 9) flat out uvec4 v_misc;
layout(location = 10) out vec2 v_world;
layout(location = 11) out vec4 v_flip;
layout(location = 12) out vec4 v_shape;
layout(location = 13) flat out vec4 v_quadL;

const uint PROJECTED = 128u;
const uint RIBBON_COLUMNS = 4096u;

void main()
{
    vec2 corners[6] = vec2[6](
        vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0),
        vec2(1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
    int vi = gl_VertexIndex % 6;
    vec2 c = corners[vi];
    vec2 halfBB = a_rect.zw + vec2(2.0);
    vec2 local = c * halfBB;
    vec2 world = a_rect.xy + local;
    float w = 1.0;
    if ((a_misc.w & PROJECTED) != 0u) {
        int order[6] = int[6](0, 1, 3, 1, 2, 3);
        int ci = order[vi];
        vec2 screen[4] = vec2[4](a_quadA.xy, a_quadA.zw, a_quadB.xy, a_quadB.zw);
        float depth[4] = float[4](a_quadW.x, a_quadW.y, a_quadW.z, a_quadW.w);
        float along[4] = float[4](a_quadL.x, a_quadL.y, a_quadL.z, a_quadL.w);
        world = screen[ci];
        w = depth[ci];
        if ((a_misc.w & RIBBON_COLUMNS) != 0u)
            local = vec2(along[ci], c.y * halfBB.y);
        else
            local = vec2(c.x * (halfBB.x + a_shape.y), along[ci]);
    }

    gl_Position = (mvp * vec4(world, 0.0, 1.0)) * w;
    v_local = local;
    v_half = a_rect.zw;
    v_radii = a_radii;
    v_fill = a_fill;
    v_tint = a_tint;
    v_border = a_border;
    v_params = a_params;
    v_uv = a_uv;
    v_crop = a_crop;
    v_misc = a_misc;
    v_world = world;
    v_flip = a_flip;
    v_shape = a_shape;
    v_quadL = a_quadL;
}
