#pragma once

#include "../scene/cardvisual.h"
#include "../scene/layout.h"
#include "../scene/spring.h"

#include <QRectF>

#include <cstdint>
#include <utility>
#include <vector>

class HexLayout final : public Layout
{
public:
    HexLayout();

    QString key() const override;
    void configure(const LayoutContext &ctx, bool animate) override;
    void reset(const LayoutContext &ctx) override;
    void select(const LayoutContext &ctx, int from, int to) override;
    bool tick(const LayoutContext &ctx, double dt) override;
    void build(const LayoutContext &ctx, std::vector<CardVisual> &out) override;

    int hitTest(QPointF point) const override;
    QRectF cardRect(int row) const override;
    QRectF stageRect(const LayoutContext &ctx) const override;
    int step(const LayoutContext &ctx, int dx, int dy) const override;
    int wheel(const LayoutContext &ctx, QPointF angle, QPointF pixels) override;

public:
    enum Curve { Flat, Arc, Wave, S, Cylinder };
    enum Shape { Hexagon, Triangle, Diamond, Rhombus };

private:

    struct Stage {
        float offsetX = 0, offsetY = 0, scale = 1, rotation = 0;
        float perspective = 0, shearX = 0, shearY = 0, depthAngle = 0;
        void transform(float x, float y, float ox, float oy, float vw, float vh,
                       float &outX, float &outY, float &outScale) const;
        void morphToward(const Stage &t, float amt);
        bool settledTo(const Stage &t) const;
    };

    // Topology fields hard-copy on a settings change; continuous fields lerp toward target.
    struct Params {
        bool parallax = false;
        float r = 140;
        int rows = 3, cols = 7, scrollStep = 1;
        Curve curve = Arc;
        Shape shape = Hexagon;
        float curveStrength = 1.2f, curveFrequency = 1.0f;
        float gapX = 6, gapY = 6, aspect = 1.0f, stagger = 0.5f;
        float lens = 0, lensRadius = 620, orbit = 0, orbitRadius = 620;
        float twist = 0, scatter = 0;
        Stage stage;

        float hexH() const;
        float itemHalfW() const;
        float itemHalfH() const;
        float stepX() const;
        float stepY() const;
        float contentH() const;
        float visibleBand() const;
        float columnX(int col) const;
        float rowY(int row) const;
        float staggerOffset(int col) const;
        void deform(int index, float x, float y, float ox, float oy, float &outX,
                    float &outY) const;
        void morphToward(const Params &t, float amt);
        bool settledTo(const Params &t) const;
    };

    struct Center {
        int row;
        float cx, cy, hw, hh;
        int triDir;
    };
    struct Deferred {
        float key;
        bool hasShadow;
        CardVisual shadow;
        CardVisual body;
        Center center;
    };

    Params readParams(const LayoutContext &ctx) const;
    Stage readStage(const LayoutContext &ctx) const;
    float hexCamera(float selCenter, float cx, float fadeZone, float vw) const;
    float hexScale(int col, float colCenter, float fadeZone, float vw, double colMs);
    void hexOffsets(int col, float colCenter, float cx, float &curve, float &odd) const;
    void hexCard(const LayoutContext &ctx, std::vector<CardVisual> &out, int idx, float colCenter,
                 float itemCy, float scale, float entrance, float centerX);
    void setSelection(int row, double target, double ms, double defaultStart);

    Params m_live;
    Params m_target;
    bool m_haveParams = false;
    bool m_snapCamera = true;
    Spring m_camera;
    std::vector<Spring> m_colScale;
    std::vector<uint8_t> m_colSeen;
    std::vector<std::pair<int, Spring>> m_selFades;
    std::vector<Center> m_centers;
    std::vector<Deferred> m_deferred;
    int m_colLo = 0;
    int m_colHi = -1;
    float m_lastCenterX = 0;
};
