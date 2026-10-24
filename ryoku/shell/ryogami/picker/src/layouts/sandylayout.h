#pragma once

#include "../render/sandypass.h"
#include "../scene/layout.h"
#include "../scene/spring.h"

#include <QRectF>

#include <vector>

class SandyLayout final : public Layout
{
public:
    SandyLayout();

    QString key() const override { return QStringLiteral("sandy"); }

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
    bool pointer(const LayoutContext &ctx, QPointF pos, bool inside) override;

    bool flipsInPlace() const override { return true; }
    const SandyPass *sandyPass() const override { return m_hasPass ? &m_pass : nullptr; }

private:
    struct Tween {
        double x = 1;
        double target = 1;
        double rate = 1;
        void setDurationMs(double ms) { rate = 1000.0 / std::max(ms, 1.0); }
        void retarget(double t) { target = t; }
        void snap(double v) { x = target = v; }
        bool settled() const { return x == target; }
        bool tick(double dt)
        {
            const double step = rate * std::min(dt, 0.05);
            if (x < target)
                x = std::min(x + step, target);
            else if (x > target)
                x = std::max(x - step, target);
            if (std::abs(x - target) < 1e-4)
                x = target;
            return !settled();
        }
    };

    // Live chases target every tick so a settings change morphs smoothly.
    struct Params {
        double offsetX = 0, offsetY = 0;
        double centerH = 440, sliceW = 96, sliceH = 180, spacing = 26, skew = 12;
        double durationMs = 1250, blendMs = 700;
        double strands = 22, twist = 1, orbit = 1, turbulence = 1, waist = 1;
        double front = 0.65, fan = 0.6, arc = 1;
        double edgeSpeed = 14;
        double ringSize = 1, ringSpin = 1, ringWave = 1, ringSoft = 1, ringBlend = 1, ringHold = 0.2;
        double grain = 3;
        double corners[4] = {0, 0, 0, 0};
        double swapStyle = 1;
        bool swapLoop = false;
        bool videoOutLive = true;

        double stride() const { return (sliceW - std::abs(skew)) + spacing; }
        double stripH() const { return sliceH + 52.0; }  // STRIP_MARGIN * 2
        double centerHw() const { return centerH * 8.0 / 9.0; }
        double centerHh() const { return centerH * 0.5; }
        void morphToward(const Params &t, double amount);
        bool settledTo(const Params &t) const;
    };

    struct Placed {
        int row = -1;
        double cx = 0, cy = 0, hw = 0, hh = 0, skew = 0;
    };

    Params readParams(const LayoutContext &ctx) const;
    void settleNow(const LayoutContext &ctx);
    void swapPick(int from, int to);
    void ringPick(int from, int to);
    void stormPick(const LayoutContext &ctx, int from, int to, double newDir);
    void ringFade(int to);
    void ringChainTick();
    bool ringEngaged() const { return m_swirl.target > 0.5 || m_swirl.x > 0.02; }
    bool heroAnimating() const;
    static Spring overrideSpring(double value, double ms, double target);
    QString keyOf(const LayoutContext &ctx, int row) const;
    void buildPass(const LayoutContext &ctx, int current, double prog, double cx, double cy,
                   double chw, double chh);

    Params m_live;
    Params m_target;
    bool m_configured = false;

    Spring m_camera;
    Tween m_prog;
    Spring m_bmix;
    Spring m_swirl;
    Spring m_pop;
    Spring m_heroFade;
    double m_swirlHold = 0;
    double m_dir = 1;
    double m_carry = 0;
    double m_bcut = 1;
    int m_from = -1;
    int m_bfrom = -1;
    int m_bfrom2 = -1;
    int m_bto = -1;
    int m_stormTo = -1;
    int m_ringTo = -1;
    int m_current = 0;
    bool m_camFree = false;
    double m_edgePan = 0;
    double m_motion = 0;
    double m_lodMax = 1;
    double m_resScale = 1;
    double m_wheelAcc = 0;

    std::vector<Placed> m_placed;
    QRectF m_heroRect;
    int m_heroRow = -1;

    SandyPass m_pass;
    bool m_hasPass = false;
};
