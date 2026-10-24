#version 440

// The serpantinum liquid wave (battery pills, usage cards, desktop tiles) as a
// fragment shader instead of a threaded Canvas. The Canvas ran a JS bezier fill
// and an FBO raster on the CPU every tick of the shared WaveTick (~1% of a core
// per 10 Hz tick on a charging battery tile, the largest idle cost on the
// desktop layer, and it was paid under every bar style because the tiles are
// style-independent). The wave is one cubic whose control points sit at exact
// thirds of the fill axis, so x is linear in t and the surface is closed-form:
// here the GPU evaluates it per pixel from the same phase the Canvas read.
// Output is premultiplied, matching the shell's other shader passes.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float sizeX;       // item width in px
    float sizeY;       // item height in px
    float fill;        // 0..1 fill level along the wave axis
    float amp;         // crest height in px (already gated by the caller)
    float phase;       // radians, from WaveTick
    float radius;      // corner radius of the clipped plate in px
    float horizontal;  // 1: wave on the right edge (tiles), 0: top edge (pills)
    float alpha;       // fill opacity (pills 0.95, cards 0.94, tiles 1)
    vec4  colorTop;    // gradient start (always vertical, as the Canvas drew it)
    vec4  colorBottom; // gradient end
} u;

void main() {
    vec2 p = qt_TexCoord0 * vec2(u.sizeX, u.sizeY);

    // Rounded-plate clip, the same SDF the Canvas path's arcTo clip enforced.
    vec2 half_ = vec2(u.sizeX, u.sizeY) * 0.5;
    float r = min(u.radius, min(half_.x, half_.y));
    vec2 q = abs(p - half_) - (half_ - vec2(r));
    float box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float inside = smoothstep(0.5, -0.5, box);
    if (inside <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // The surface: base line plus the cubic swell. For a vertical fill the
    // wave runs left to right along x; for a horizontal tile along y.
    bool horiz = u.horizontal > 0.5;
    float along  = horiz ? p.y : p.x;
    float across = horiz ? p.x : p.y;
    float span   = horiz ? u.sizeY : u.sizeX;
    float t = clamp(along / max(1.0, span), 0.0, 1.0);
    float base = horiz ? u.sizeX * u.fill : u.sizeY * (1.0 - u.fill);
    float c = cos(u.phase);
    float s = sin(u.phase);
    float surf = base + u.amp * (3.0 * (1.0 - t) * (1.0 - t) * t * (-c)
                               + 3.0 * (1.0 - t) * t * t * s);

    // Inside the liquid: below the surface for pills, left of it for tiles.
    float d = horiz ? (surf - across) : (across - surf);
    inside *= smoothstep(-0.5, 0.5, d);
    if (inside <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 col = mix(u.colorTop, u.colorBottom, clamp(p.y / max(1.0, u.sizeY), 0.0, 1.0));
    float a = inside * u.alpha * u.qt_Opacity;
    fragColor = vec4(col.rgb * a, a);
}
