#pragma once

#include <cstdint>

// Matches card.vert's per-instance input: fifteen 16-byte slots, slot 8 unsigned.
struct CardInstance {
    float rect[4] = {0, 0, 0, 0};      // centre x, centre y, half width, half height
    float radii[4] = {0, 0, 0, 0};     // top-left, top-right, bottom-right, bottom-left
    float fill[4] = {0, 0, 0, 0};      // base colour (and shadow colour), straight alpha
    float tint[4] = {0, 0, 0, 0};      // rgb, a = mix amount
    float border[4] = {0, 0, 0, 0};    // stroke colour, a = stroke opacity
    float params[4] = {0, 0, 1, 1};    // skew, border width, opacity, fade (texture over fill)
    float uv[4] = {0, 0, 1, 1};        // tier sub-rect: origin.xy, size.zw
    float crop[4] = {0, 0, 1, 1};      // crop inside the image: origin.xy, size.zw
    uint32_t misc[4] = {0, 0, 0, 0};   // source, layer, clip flag, flags
    float flip[4] = {0, 0, 0, 0};      // progress, seed / aberration, effect id, blur / bend
    float shape[4] = {0, 0, 0, 0};     // edge tilt, ribbon extra half width, backface pivot, unused
    float quadA[4] = {0, 0, 0, 0};     // projected corners 0 and 1
    float quadB[4] = {0, 0, 0, 0};     // projected corners 2 and 3
    float quadW[4] = {1, 1, 1, 1};     // projected per-corner w
    float quadL[4] = {0, 0, 0, 0};     // projected along coordinates / ribbon cut edges
};

static_assert(sizeof(CardInstance) == 240, "CardInstance must match the shader input layout");

namespace CardTex {
enum : uint32_t { None = 0, Near = 1, Far = 2, Preview = 3 };
}

namespace CardFlag {
enum : uint32_t {
    CustomShape = 1u,
    Shimmer = 2u,
    PageBend = 32u,
    Shadow = 64u,
    Projected = 128u,
    RibbonColumns = 4096u,
    Ghost = 8192u,
    Backdrop = 16384u,
    Backface = 32768u,
    Muted = 65536u,
    UnframedRect = 131072u,
};

// Shape ids for CustomShape: 1-4 triangles, 5-6 diamond, anything else a
// flat-top hexagon.
constexpr uint32_t shape(uint32_t id) { return CustomShape | ((id & 15u) << 8); }
}
