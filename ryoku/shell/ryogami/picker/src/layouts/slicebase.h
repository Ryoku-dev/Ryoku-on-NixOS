#pragma once

#include "../scene/layout.h"
#include "../scene/spring.h"
#include "geometry.h"

#include <array>
#include <unordered_map>
#include <vector>

// Depth feeds a per-card override of these onto the same primitive.
struct SliceParams {
    bool parallax = false;
    bool shadows = true;
    float offsetX = 0;
    float offsetY = 0;
    float sliceW = 289;
    float expandedW = 942;
    float sliceH = 389;
    float spacing = 15;
    float skew = 119;
    float edgeTilt = 0;
    int visibleCount = 7;
    std::array<float, 4> corners{{0, 0, 0, 0}};
    bool wobble = true;
    float wobbleStrength = 1.0f;
    float shadowStrength = 1.0f;
    float shadowDistance = 1.0f;

    float layoutWidth(float width) const { return geom::sliceMidlineWidth(width, skew); }
    float sliceStride() const { return layoutWidth(sliceW) + spacing; }

    void morphToward(const SliceParams &t, float amt);
    bool settledTo(const SliceParams &t) const;
};

class SliceBase : public Layout
{
public:
    void configure(const LayoutContext &ctx, bool animate) override;
    int hitTest(QPointF point) const override;
    QRectF cardRect(int row) const override;
    QPointF cardShear(int row) const override;
    QRectF stageRect(const LayoutContext &ctx) const override;
    bool flipsInPlace() const override { return true; }
    // Left/right step the row; up/down are inert in both slice modes.
    int step(const LayoutContext &ctx, int dx, int dy) const override
    {
        Q_UNUSED(dy)
        const int last = ctx.count > 0 ? ctx.count - 1 : 0;
        int row = ctx.current + (dx < 0 ? -1 : (dx > 0 ? 1 : 0));
        return row < 0 ? 0 : (row > last ? last : row);
    }
    // Wheel scrubs the index one card per notch (skwd slice_scroll); up = prev.
    int wheel(const LayoutContext &ctx, QPointF angle, QPointF pixels) override
    {
        Q_UNUSED(ctx)
        const float amount =
            pixels.y() != 0.0 ? float(pixels.y()) / 50.0f : float(angle.y()) / 120.0f;
        return -geom::sliceScrollSteps(m_scrollAccum, amount);
    }

protected:
    virtual void readParams(const LayoutContext &ctx, SliceParams &out) const = 0;

    bool morphParams(const LayoutContext &ctx, double dt);
    // Snaps while params are unsettled or a relayout anchored the camera, else glides.
    void positionCamera(float target);
    void retargetSelection(int from, int to, double ms, double epsilon);
    float selectionOf(int row, int current) const;
    bool tickSelection(double dt, double epsilon);

    // bend is the wobble camera-velocity bend; parallax is the crop shift.
    void emitCard(const LayoutContext &ctx, std::vector<CardVisual> &out, int row, float w,
                  float itemCx, float itemCy, float opacity, float halfView, float bend,
                  const SliceParams &sp, bool depthMode, bool depthSelectionFrame,
                  bool hasParallax, float parallax);

    struct HitRec {
        int row;
        float cx, cy, hw, hh, skew, edgeTilt;
    };

    SliceParams m_live{};
    SliceParams m_target{};
    bool m_paramsInit = false;
    Spring m_camera{};
    bool m_anchor = true;
    std::unordered_map<int, Spring> m_selection;
    std::vector<HitRec> m_hits;
    float m_scrollAccum = 0;
};
