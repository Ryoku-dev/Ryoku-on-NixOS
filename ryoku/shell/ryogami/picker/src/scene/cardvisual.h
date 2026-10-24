#pragma once

#include "../render/cardinstance.h"

#include <cstdint>

// Layouts fill geometry and style; CardField resolves the texture fields.
struct CardVisual {
    enum Texture : uint8_t {
        TextureNone,      // solid fill only (shadows, placeholders, chrome)
        TextureAuto,      // near tier when resident and wanted, else far
        TextureNear,      // near tier only (falls back to fill)
        TexturePreview,   // the live video preview texture
    };

    int row = -1;                   // card row, -1 for decorations
    CardInstance inst;
    Texture texture = TextureAuto;
    bool wantNear = false;          // ask the decoder for the sharp image
    bool cover = true;              // derive crop from the image aspect
    float cropZoom = 1.0f;          // > 1 zooms into the cover crop
    float cropShiftX = 0.0f;        // parallax, in crop widths
    float cropShiftY = 0.0f;        // parallax, in crop heights
    // 0 uses the rect half extents; projected quads pass the card's own aspect.
    float cropAspect = 0.0f;
};
