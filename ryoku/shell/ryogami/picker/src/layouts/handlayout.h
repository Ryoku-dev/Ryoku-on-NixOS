#pragma once

#include "handrig.h"
#include "layout.h"
#include "spring.h"

#include <QRectF>

#include <array>
#include <map>
#include <optional>
#include <vector>

class HandLayout : public Layout
{
public:
    HandLayout();

    QString key() const override { return QStringLiteral("hand"); }
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
    bool drag(const LayoutContext &ctx, QPointF delta, bool released) override;
    Click click(const LayoutContext &ctx, int row) override;
    bool action(const LayoutContext &ctx, const QString &name) override;
    bool flipsInPlace() const override { return true; }
    double cameraMs(const LayoutContext &ctx) const override;

private:
    // Live and target geometry, morphed so a settings change animates.
    struct Params {
        float offsetX = 0, offsetY = 0;
        float cardW = 168, cardH = 432;
        float spread = 126;
        int ribbons = 6;
        float fanAngle = 12, fanRoll = 8.5f, arch = 20;
        float radius = 0, skew = 0, blur = 1;
        int count = 5;
        handrig::Axis axis = handrig::Axis::Rows;
        handrig::Cut cut = handrig::Cut::Straight;
        handrig::Variance variance = handrig::Variance::None;
        handrig::DealMode dealMode = handrig::DealMode::Cycle;
        std::array<bool, handrig::MOVE_COUNT> moves{{true, true, true, true, true}};
        float speed = 1, tilt = 1, perspective = 1700;
        bool ghosts = true, bob = false, backdrop = true, revealFill = true;

        float speedScale() const { return 1.0f / std::max(speed, 0.35f); }
        handrig::Fan fan(float k) const { return {spread * k, fanAngle, fanRoll, arch * k}; }
    };

    struct Stage {
        float k = 1, hw = 0, hh = 0, radius = 0, skew = 0;
        handrig::Camera cam;
        QVector2D rig;
        QVector2D parallax;
        float vw = 0, vh = 0;
    };

    enum class DealPhase { Out, In };
    struct CardAnim {
        int store = 0;
        int slot = 0;
        float n = 0;
        handrig::PoseTween pose;
        std::vector<handrig::PoseTween> ribbons;
        std::array<handrig::PoseTween, 2> ghosts;
    };
    struct Deal {
        DealPhase phase = DealPhase::Out;
        float t = 0;
        handrig::Move mv = handrig::Move::Corkscrew;
        std::vector<CardAnim> cards;
        float end = 0;
    };

    enum class SlatLayout { Fan, Row, Column };
    enum class FaceKind { Card, Back, Slice };
    struct Face {
        FaceKind kind = FaceKind::Card;
        int store = 0;
        bool column = false;
        bool operator==(const Face &o) const { return kind == o.kind && store == o.store && column == o.column; }
    };
    enum class RevealPhase { Turning, Held };
    struct Reveal {
        bool open = true;
        RevealPhase phase = RevealPhase::Held;
        SlatLayout from = SlatLayout::Fan;
        SlatLayout to = SlatLayout::Fan;
        float turn = 0;
        uint32_t turnsDone = 0;
        std::array<Face, 2> faces{{Face{}, Face{}}};
        int len = 0;
    };

    struct Draw {
        float depth = 0;
        CardVisual vis;
        int hitRow = -1;
        float hcx = 0, hcy = 0, hhw = 0, hhh = 0;
    };
    struct HitRect {
        int row;
        float cx, cy, hw, hh;
    };
    struct SlatResult {
        CardVisual vis;
        float depth = 0;
        int hitIndex = -1;
        FaceKind faceKind = FaceKind::Card;
        std::array<float, 4> aabb{{0, 0, 0, 0}};
    };

    void readParams(const ParamSource *src, Params &out) const;
    void morph(const LayoutContext &ctx, double dt);
    Stage stageFor(const LayoutContext &ctx) const;
    QMatrix4x4 cardMatrix(const Stage &stage, const handrig::Pose &pose, int slot, float rigMix) const;
    float selT(int idx) const;
    float liftT(int idx) const;
    float pushSum() const;
    handrig::Pose restPose(const Stage &stage, int slot, int len, float push) const;

    CardVisual quadVisual(const Stage &stage, int row, const handrig::Quad &quad, const std::array<float, 4> &locals,
                          bool columns, QVector2D shift, float hw, float hh, bool wantNear) const;
    void addPlain(const LayoutContext &ctx, const Stage &stage, std::vector<Draw> &draws, int store, float n,
                  const QMatrix4x4 &m, float opacity, int idx, float selt, float lift);
    void addGhost(const Stage &stage, std::vector<Draw> &draws, int store, const QMatrix4x4 &m, int level, float entrance);
    bool addRibbons(const LayoutContext &ctx, const Stage &stage, std::vector<Draw> &draws, int store, int slot, float n,
                    const QMatrix4x4 &mCard, const std::vector<handrig::Pose> &poses, float opacity, bool showBack, float seam);
    std::optional<SlatResult> slatInstance(const LayoutContext &ctx, const Stage &stage, const handrig::Pose &rest,
                                           int slot, int len, float n, const Reveal &rev, float t) const;
    void addSlat(const LayoutContext &ctx, const Stage &stage, std::vector<Draw> &draws, const handrig::Pose &rest,
                 int idx, int slot, int len, float n, float opacity);
    void addFlipped(const LayoutContext &ctx, const Stage &stage, std::vector<Draw> &draws,
                    std::vector<HitRect> &lateHits, int store, int idx, int slot, float n,
                    const handrig::Pose &rest, float opacity);
    void addBackdrop(const LayoutContext &ctx, std::vector<CardVisual> &out, int store, float entrance);

    void beginDeal(const LayoutContext &ctx, int newOffset);
    void swapDeal(const LayoutContext &ctx);
    void landDeal(const LayoutContext &ctx);
    void revealToggle(const LayoutContext &ctx);
    void revealClock(const LayoutContext &ctx, float step);
    void syncFlip(const LayoutContext &ctx);

    Params m_params;
    Params m_target;
    bool m_haveParams = false;

    Spring m_rigX;
    Spring m_rigY;
    std::map<int, Spring> m_lift;
    std::map<int, Spring> m_selection;
    int m_current = 0;
    int m_count = 0;

    int m_offset = 0;
    std::vector<int> m_shown;
    std::optional<Deal> m_deal;
    std::optional<Reveal> m_reveal;
    handrig::Move m_cycle = handrig::Move::Corkscrew;
    uint32_t m_deals = 0;
    float m_lseed = 0;
    float m_bobT = 0;

    bool m_flipActive = false;
    bool m_flipClosing = false;
    float m_flipSeed = 0;
    float m_flipPrev = 0;

    float m_wheelAccum = 0;

    std::vector<HitRect> m_hits;
    std::map<int, QRectF> m_rects;
};
