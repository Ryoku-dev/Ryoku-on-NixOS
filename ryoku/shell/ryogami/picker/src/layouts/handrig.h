#pragma once

#include <QMatrix4x4>
#include <QPointF>
#include <QQuaternion>
#include <QVector2D>
#include <QVector3D>

#include <array>
#include <cstdint>
#include <vector>

namespace handrig {

// Design frame and rig tuning.
constexpr float DESIGN_W = 1440.0f;
constexpr float DESIGN_H = 900.0f;
constexpr float ANCHOR_Y = 0.48f;
constexpr float PERSPECTIVE_DROP = 0.018f;
constexpr float PAD = 2.0f;
constexpr float RIBBON_OVERLAP = 0.6f;
constexpr float RIBBON_MIN = 2.0f;
constexpr float CROP_ZOOM = 1.10f;
constexpr float OUT_MS = 620.0f;
constexpr float IN_MS = 900.0f;
constexpr float CARD_STAGGER_MS = 40.0f;
constexpr float RIBBON_CARD_STAGGER_MS = 26.0f;
constexpr float RIBBON_STAGGER_MS = 34.0f;
constexpr float SWAP_GAP_MS = 80.0f;
constexpr float FLIP_LIFT_MS = 500.0f;
constexpr float FLIP_CLOSE_LIFT_MS = 520.0f;
constexpr float TWIST_MS = 900.0f;
constexpr float BOB_PERIOD_S = 5.4f;
constexpr float BOB_DELAY_S = 0.42f;
constexpr float TILT_X_DEG = 4.5f;
constexpr float TILT_Y_DEG = 6.0f;
constexpr float FLIP_LAND_AT = 0.72f;
constexpr float REVEAL_TURN_MS = 440.0f;
constexpr float REVEAL_STAGGER_MS = 55.0f;
constexpr float REVEAL_GAP = 8.0f;
constexpr float THUMB_ASPECT = 16.0f / 9.0f;
constexpr float ROW_FIT = 0.92f;
constexpr float COLUMN_FIT = 0.78f;
constexpr float TALL_ASPECT = 9.0f / 16.0f;

// (alpha, blur, duration-mult) per ghost trail level (hand.rs:19).
constexpr std::array<std::array<float, 3>, 2> GHOST_LEVELS = {{{0.46f, 0.65f, 1.22f}, {0.26f, 1.5f, 1.5f}}};
// Per-ribbon (duration_ms, stagger_ms) for the flip open / close stages (hand.rs:22-23).
constexpr std::array<std::array<float, 2>, 2> FLIP_OPEN = {{{470.0f, 44.0f}, {640.0f, 46.0f}}};
constexpr std::array<std::array<float, 2>, 2> FLIP_CLOSE = {{{490.0f, 46.0f}, {680.0f, 48.0f}}};
// (lag_s, alpha, blur) per reveal ghost trail (hand.rs:33).
constexpr std::array<std::array<float, 3>, 2> REVEAL_GHOST_LAG = {{{0.05f, 0.42f, 0.7f}, {0.1f, 0.24f, 1.3f}}};
// smoothstep window the flip metadata content relaxes over (hand.rs:29).
constexpr float RELAX_LO = 0.3f;
constexpr float RELAX_HI = 0.68f;

constexpr float FLIP_KICK = 260.0f;
constexpr float REVEAL_KICK = 300.0f;
constexpr float SLAT_KICK = 90.0f;
constexpr float DEAL_KICK_Y = 620.0f;
constexpr float DEAL_KICK_X = 280.0f;
constexpr float DRAG_GAIN_X = 0.34f;
constexpr float DRAG_GAIN_Y = 0.42f;

inline const QVector3D AXIS_X{1.0f, 0.0f, 0.0f};
inline const QVector3D AXIS_Y{0.0f, 1.0f, 0.0f};
inline const QVector3D AXIS_Z{0.0f, 0.0f, 1.0f};

enum class Axis { Rows, Columns };
enum class Cut { Straight, Slant, Steep };
enum class Variance { None, Soft, Wild };
enum class DealMode { Cycle, Random };
// Deal move styles, in enabled[] index order.
enum class Move { Corkscrew, Cascade, Shuffle, Ribbon, Spiral };

constexpr int MOVE_COUNT = 5;
inline int moveIndex(Move m) { return int(m); }
constexpr float cutFactor(Cut c) { return c == Cut::Slant ? 1.2f : c == Cut::Steep ? 2.4f : 0.0f; }
constexpr float varianceFactor(Variance v) { return v == Variance::Soft ? 0.5f : v == Variance::Wild ? 1.05f : 0.0f; }

Axis axisFromKey(const QString &key);
Cut cutFromKey(const QString &key);
Variance varianceFromKey(const QString &key);
DealMode dealModeFromKey(const QString &key);
Move pickMove(DealMode mode, const std::array<bool, MOVE_COUNT> &enabled, Move last, float seed);

inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }
inline bool feq(float a, float b) { return std::abs(a - b) < 0.05f; }
inline float smoothstep01(float t)
{
    t = t < 0.0f ? 0.0f : t > 1.0f ? 1.0f : t;
    return t * t * (3.0f - 2.0f * t);
}
float rnd(float a, float b, float c, float d);

struct Bezier {
    float x1, y1, x2, y2;
    float at(float x) const;
};

constexpr Bezier EASE_DEAL_OUT{0.62f, 0.0f, 0.86f, 0.24f};
constexpr Bezier EASE_DEAL_IN{0.16f, 1.06f, 0.28f, 1.0f};
constexpr Bezier EASE_RIBBON_OUT{0.42f, 0.0f, 0.7f, 0.2f};
constexpr Bezier EASE_RIBBON_IN{0.2f, 0.92f, 0.26f, 1.0f};
constexpr Bezier EASE_FLIP_LIFT{0.38f, 0.02f, 0.28f, 1.0f};
constexpr Bezier EASE_FLIP_LAND{0.2f, 1.12f, 0.3f, 1.0f};
constexpr Bezier EASE_FLIP_CLOSE{0.2f, 1.14f, 0.3f, 1.0f};
constexpr Bezier EASE_TWIST{0.34f, 1.36f, 0.32f, 1.0f};
constexpr Bezier EASE_REVEAL_TRAVEL{0.3f, 0.0f, 0.25f, 1.08f};
constexpr Bezier EASE_REVEAL_TURN{0.36f, 0.0f, 0.2f, 1.24f};

struct Rot {
    QVector3D axis = AXIS_Z;
    float deg = 0.0f;
};

struct Pose {
    QVector3D t{0, 0, 0};
    std::array<Rot, 3> rots{{{AXIS_Z, 0.0f}, {AXIS_Z, 0.0f}, {AXIS_Z, 0.0f}}};
    int n = 0;
    float s = 1.0f;

    static Pose make(const QVector3D &t, std::initializer_list<Rot> rots, float s);
    static Pose rest() { return Pose{}; }
    QMatrix4x4 matrix() const;
    static Pose mix(const Pose &a, const Pose &b, float u);
};

struct PoseTween {
    Pose from;
    Pose to;
    float delay = 0.0f;   // seconds
    float dur = 0.001f;   // seconds
    Bezier ease = EASE_DEAL_OUT;

    static PoseTween make(const Pose &from, const Pose &to, float delayMs, float durMs, Bezier ease);
    Pose at(float t) const;
    float end() const { return delay + dur; }
    void retarget(float now, const Pose &to, float delayMs, float durMs, Bezier ease);
};

struct Fan {
    float spread, angle, roll, arch;
};

Pose fanPose(float n, const Fan &fan, float k, float push, float lift, float zback, float s);
Pose selPose(float k);
Pose movePose(Move mv, float n, float s, float k);
Pose rowPose(float n, float slatW, float gap);
Pose columnPose(float n, float slatH, float gap);
Pose ribbonDealPose(int r, float s, float k, Axis axis);
Pose ribbonFlipPose(uint8_t stage, int r, int nr, float dir, float k, Axis axis);
Pose twistPose(uint8_t stage, float k);
Pose flipRibbonPose(float tauMs, bool closing, int r, int nr, float dir, float k, Axis axis);
Pose flipTwistPose(float tauMs, bool closing, float k);
std::pair<Pose, float> slatTurnPose(float t, float dir, float k);
Pose bob(float timeS, int slot, float k);

float flipOpenMs(int nr);
float flipCloseMs(int nr);
float ribbonDir(float seed, int card, int r, bool deal);

std::pair<float, float> revealFrame(float vw, float vh, bool tall);
std::pair<float, float> slatHalfExtent(int len, std::pair<float, float> frame, float gap, bool tall);
std::pair<float, float> keepExtent(int len, std::pair<float, float> card, std::pair<float, float> frame, float gap, bool tall);
float revealTurn(float clockS, int order, float speedScale);
int revealOrder(int slot, int len, uint32_t turnsDone);
float revealDirFor(int slot, uint32_t turnsDone);
float revealTurnEnd(int len, float speedScale);
int revealFace(uint32_t turnsDone, float t);
float relax(float progress);

std::array<float, 4> sliceCrop(int slot, int len, float rowW, float rowH, float gap);
std::array<float, 4> columnCrop(int slot, int len, float stackW, float stackH, float gap);

struct RibbonCut {
    float a0, a1, b0, b1, mid;
};
std::vector<RibbonCut> ribbonCuts(int nr, float total, Cut cut, Variance variance, float lseed, int card, float pad);
RibbonCut mirroredCut(const RibbonCut &cut);
std::array<QVector3D, 4> ribbonCorners(const RibbonCut &cut, Axis axis, float hw, float hh, float pad);
std::array<float, 4> ribbonLocals(const RibbonCut &cut, Axis axis);
QMatrix4x4 ribbonOrigin(const RibbonCut &cut, Axis axis);
QMatrix4x4 ribbonBack(const RibbonCut &cut, Axis axis);

std::array<QVector3D, 4> cardCorners(float hw, float hh, float padX, float padY);
std::array<float, 4> cardLocals(float hh, float pad);

// An origin-and-shift projective divide, not a matrix; project returns (x, y, w).
struct Camera {
    float d = 1.0f;
    QVector2D origin{0, 0};
    QVector2D shift{0, 0};
    QVector3D project(const QVector3D &p) const;
};

// Corners TL, TR, BR, BL plus a sort depth.
struct Quad {
    std::array<QVector3D, 4> pts{};
    float depth = 0.0f;

    Quad mirrored() const;
    bool facing() const;
    std::array<float, 4> bounds() const;  // centre x, centre y, half w, half h
    bool visible(float vw, float vh) const;
};

Quad projectQuad(const Camera &cam, const QMatrix4x4 &m, const std::array<QVector3D, 4> &corners);
std::array<float, 4> unionBounds(const std::vector<Quad> &quads);

QMatrix4x4 rotationMatrix(const QVector3D &axis, float deg);
std::pair<float, float> parallaxShift(float rigX, float rigY, float k);
std::pair<float, float> tiltTarget(float x, float y, float vw, float vh, float tilt);
float fanSlot(int slot, int len, int excluded);  // excluded < 0 means none
float stageScale(float vw, float vh);
int handWindow(int current, int count, int size);
int handLen(int offset, int count, int size);

bool pointInQuad(const std::array<QVector3D, 4> &pts, QPointF p);

}  // namespace handrig
