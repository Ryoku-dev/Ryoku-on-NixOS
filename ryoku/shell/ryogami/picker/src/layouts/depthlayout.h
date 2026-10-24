#pragma once

#include "slicebase.h"

#include <QString>

#include <vector>

class DepthLayout : public SliceBase
{
public:
    QString key() const override { return QStringLiteral("depth"); }
    void configure(const LayoutContext &ctx, bool animate) override;
    void reset(const LayoutContext &ctx) override;
    void select(const LayoutContext &ctx, int from, int to) override;
    bool tick(const LayoutContext &ctx, double dt) override;
    void build(const LayoutContext &ctx, std::vector<CardVisual> &out) override;
    double cameraMs(const LayoutContext &ctx) const override { return navMs(ctx); }

private:
    void readParams(const LayoutContext &ctx, SliceParams &out) const override;
    void readDepthParams(const LayoutContext &ctx);
    double navMs(const LayoutContext &ctx) const;

    struct DepthParams {
        float width = 280;
        float spacing = 280;
        float falloff = 0.05f;
        float navigationMs = 1000;
        bool selectionFrame = false;
    };
    DepthParams m_depth;
    std::vector<int> m_visible;
};
