#pragma once

#include "slicebase.h"

#include <QString>

#include <vector>

// One row of slanted cards like a duelist's field: the chosen card stands tall and wide in the
// middle and its neighbours narrow and shorten with their distance from it. The design follows
// the wallpaper picker in Serpantinum by ilyamiro (https://github.com/ilyamiro/serpantinum).
class DuelLayout : public SliceBase
{
public:
    QString key() const override { return QStringLiteral("duel"); }
    void configure(const LayoutContext &ctx, bool animate) override;
    void reset(const LayoutContext &ctx) override;
    void select(const LayoutContext &ctx, int from, int to) override;
    bool tick(const LayoutContext &ctx, double dt) override;
    void build(const LayoutContext &ctx, std::vector<CardVisual> &out) override;
    double cameraMs(const LayoutContext &ctx) const override { return navMs(ctx); }
    QRectF stageRect(const LayoutContext &ctx) const override;

private:
    struct Size {
        float w;
        float h;
    };

    void readParams(const LayoutContext &ctx, SliceParams &out) const override;
    void readDuelParams(const LayoutContext &ctx);
    double navMs(const LayoutContext &ctx) const;
    // Flat card width and height at a fractional distance from the camera, before the fit scale.
    Size sizeAt(float distance) const;
    // Shrinks every card together so the chosen one fits the viewport.
    float fitFor(const LayoutContext &ctx) const;
    float centerY(const LayoutContext &ctx, float fit) const;
    void emitDuelCard(const LayoutContext &ctx, std::vector<CardVisual> &out, int row,
                      float distance, float fit, float cx, float cy);

    struct DuelParams {
        float width = 400;        // side-card base width; the chosen card is 1.5x
        float skew = 0.35f;       // horizontal shear per pixel of height
        float falloff = 0.88f;    // side-card width kept per step away
        float navigationMs = 400;
    };
    DuelParams m_duel;
    std::vector<int> m_visible;
    std::vector<float> m_offsets;
};
