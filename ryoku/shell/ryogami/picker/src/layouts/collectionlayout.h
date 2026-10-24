#pragma once

#include "handrig.h"
#include "layout.h"
#include "spring.h"

#include <QRectF>
#include <QVector3D>

#include <array>
#include <map>
#include <vector>

class CollectionLayout : public Layout
{
public:
    CollectionLayout();

    QString key() const override { return QStringLiteral("collection"); }
    void configure(const LayoutContext &ctx, bool animate) override;
    void reset(const LayoutContext &ctx) override;
    void select(const LayoutContext &ctx, int from, int to) override;
    bool tick(const LayoutContext &ctx, double dt) override;
    void build(const LayoutContext &ctx, std::vector<CardVisual> &out) override;

    int hitTest(QPointF point) const override;
    QRectF cardRect(int row) const override;
    int step(const LayoutContext &ctx, int dx, int dy) const override;
    int page(const LayoutContext &ctx, int dir) const override;
    int wheel(const LayoutContext &ctx, QPointF angle, QPointF pixels) override;
    bool pointer(const LayoutContext &ctx, QPointF pos, bool inside) override;
    Click click(const LayoutContext &ctx, int row) override;
    double cameraMs(const LayoutContext &ctx) const override;

private:
    struct Params {
        float size = 42;     // % of viewport height
        float spacing = 17;  // shelf depth spread (% of size)
        float count = 7;
        float tilt = 52;     // resting lay-back angle (deg)
        float corners = 2;   // corner radius px
        float speed = 100;   // scales camera + open spring
        bool shadows = true;
        float shadowStrength = 1.0f;
        float shadowDistance = 1.0f;
    };
    struct Hit {
        int row;
        std::array<QVector3D, 4> pts;
    };

    void readParams(const ParamSource *src, Params &out) const;
    double openMs(const LayoutContext &ctx) const;
    bool openFor(int idx) const { return m_card == idx && m_open.target > 0.5; }
    void raiseSelf(int idx);

    Params m_params;
    Spring m_camera;   // index-space push
    Spring m_open;     // 0 = shelf, 1 = raised
    int m_card = -1;
    int m_current = 0;
    int m_count = 0;
    bool m_anchor = true;
    int m_raiseIntent = -1;
    float m_wheelAccum = 0;

    std::vector<Hit> m_hits;
    std::map<int, QRectF> m_rects;
};
