#include "handrig.h"

#include <QVector4D>

#include <algorithm>
#include <cmath>

namespace handrig {

namespace {

constexpr float kTau = 6.283185307179586f;

float clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }

// Euclidean modulo for a positive modulus.
float remEuclid(float value, float modulus)
{
    float r = std::fmod(value, modulus);
    return r < 0.0f ? r + modulus : r;
}

QVector3D alongCross(Axis axis, float along, float cross, float z)
{
    return axis == Axis::Rows ? QVector3D(cross, along, z) : QVector3D(along, cross, z);
}

Rot hinge(Axis axis, float deg) { return axis == Axis::Rows ? Rot{AXIS_X, deg} : Rot{AXIS_Y, deg}; }
Rot swing(Axis axis, float deg) { return axis == Axis::Rows ? Rot{AXIS_Y, deg} : Rot{AXIS_X, deg}; }

bool axisEq(const QVector3D &a, const QVector3D &b)
{
    return std::abs(a.x() - b.x()) < 1e-4f && std::abs(a.y() - b.y()) < 1e-4f && std::abs(a.z() - b.z()) < 1e-4f;
}

QQuaternion poseQuat(const Pose &pose)
{
    QQuaternion q;  // identity
    for (int i = 0; i < pose.n; ++i) {
        QVector3D axis = pose.rots[i].axis;
        if (axis.lengthSquared() > 1e-12f)
            q = q * QQuaternion::fromAxisAndAngle(axis.normalized(), pose.rots[i].deg);
    }
    return q;
}

std::array<float, 4> cover(float tileAspect, float boxAspect)
{
    if (boxAspect >= tileAspect) {
        const float h = tileAspect / boxAspect;
        return {0.0f, (1.0f - h) * 0.5f, 1.0f, h};
    }
    const float w = boxAspect / tileAspect;
    return {(1.0f - w) * 0.5f, 0.0f, w, 1.0f};
}

}  // namespace

Axis axisFromKey(const QString &key) { return key == QLatin1String("columns") ? Axis::Columns : Axis::Rows; }

Cut cutFromKey(const QString &key)
{
    if (key == QLatin1String("slant"))
        return Cut::Slant;
    if (key == QLatin1String("steep"))
        return Cut::Steep;
    return Cut::Straight;
}

Variance varianceFromKey(const QString &key)
{
    if (key == QLatin1String("soft"))
        return Variance::Soft;
    if (key == QLatin1String("wild"))
        return Variance::Wild;
    return Variance::None;
}

DealMode dealModeFromKey(const QString &key)
{
    return key == QLatin1String("random") ? DealMode::Random : DealMode::Cycle;
}

Move pickMove(DealMode mode, const std::array<bool, MOVE_COUNT> &enabled, Move last, float seed)
{
    std::vector<Move> pool;
    for (int i = 0; i < MOVE_COUNT; ++i)
        if (enabled[size_t(i)])
            pool.push_back(Move(i));
    if (pool.empty())
        for (int i = 0; i < MOVE_COUNT; ++i)
            pool.push_back(Move(i));
    if (mode == DealMode::Cycle) {
        size_t at = 0;
        for (size_t i = 0; i < pool.size(); ++i)
            if (pool[i] == last) {
                at = (i + 1) % pool.size();
                break;
            }
        return pool[at];
    }
    std::vector<Move> choices;
    if (pool.size() > 1) {
        for (Move mv : pool)
            if (mv != last)
                choices.push_back(mv);
    } else {
        choices = pool;
    }
    const size_t at = size_t(clampf(seed, 0.0f, 0.99999f) * float(choices.size()));
    return choices[std::min(at, choices.size() - 1)];
}

float rnd(float a, float b, float c, float d)
{
    const float x = std::sin(a * 127.1f + b * 311.7f + c * 74.7f + d * 269.5f + 17.3f) * 43758.547f;
    return x - std::floor(x);
}

float Bezier::at(float x) const
{
    if (x <= 0.0f)
        return 0.0f;
    if (x >= 1.0f)
        return 1.0f;
    const auto sample = [](float p1, float p2, float t) {
        const float mt = 1.0f - t;
        return 3.0f * mt * mt * t * p1 + 3.0f * mt * t * t * p2 + t * t * t;
    };
    float t = x;
    for (int i = 0; i < 8; ++i) {
        const float fx = sample(x1, x2, t) - x;
        const float mt = 1.0f - t;
        const float dx = 3.0f * mt * mt * x1 + 6.0f * mt * t * (x2 - x1) + 3.0f * t * t * (1.0f - x2);
        if (std::abs(dx) < 1e-6f)
            break;
        t = clampf(t - fx / dx, 0.0f, 1.0f);
    }
    return sample(y1, y2, t);
}

Pose Pose::make(const QVector3D &t, std::initializer_list<Rot> rots, float s)
{
    Pose pose;
    pose.t = t;
    pose.s = s;
    int i = 0;
    for (const Rot &r : rots) {
        if (i >= 3)
            break;
        pose.rots[size_t(i)] = r;
        ++i;
    }
    pose.n = std::min<int>(int(rots.size()), 3);
    return pose;
}

QMatrix4x4 rotationMatrix(const QVector3D &axis, float deg)
{
    if (axis.lengthSquared() < 1e-12f || std::abs(deg) < 1e-6f)
        return QMatrix4x4();
    QMatrix4x4 m;
    m.rotate(deg, axis.normalized());
    return m;
}

QMatrix4x4 Pose::matrix() const
{
    QMatrix4x4 m;
    m.translate(t);
    for (int i = 0; i < n; ++i)
        m *= rotationMatrix(rots[size_t(i)].axis, rots[size_t(i)].deg);
    if (std::abs(s - 1.0f) > 1e-6f)
        m.scale(s);
    return m;
}

Pose Pose::mix(const Pose &a, const Pose &b, float u)
{
    const QVector3D t{lerpf(a.t.x(), b.t.x(), u), lerpf(a.t.y(), b.t.y(), u), lerpf(a.t.z(), b.t.z(), u)};
    const float s = lerpf(a.s, b.s, u);

    const int shared = std::min(a.n, b.n);
    bool match = true;
    for (int i = 0; i < shared; ++i)
        if (!axisEq(a.rots[size_t(i)].axis, b.rots[size_t(i)].axis)) {
            match = false;
            break;
        }
    if (match) {
        Pose out;
        out.t = t;
        out.s = s;
        out.n = std::max(a.n, b.n);
        for (int i = 0; i < out.n; ++i) {
            const QVector3D axis = i < b.n ? b.rots[size_t(i)].axis : a.rots[size_t(i)].axis;
            const float da = i < a.n ? a.rots[size_t(i)].deg : 0.0f;
            const float db = i < b.n ? b.rots[size_t(i)].deg : 0.0f;
            out.rots[size_t(i)] = Rot{axis, lerpf(da, db, u)};
        }
        return out;
    }

    const QQuaternion q = QQuaternion::slerp(poseQuat(a), poseQuat(b), u);
    QVector3D axis;
    float angle = 0.0f;
    q.getAxisAndAngle(&axis, &angle);
    if (std::abs(angle) < 1e-3f)
        return Pose::make(t, {Rot{AXIS_Z, 0.0f}}, s);
    return Pose::make(t, {Rot{axis, angle}}, s);
}

PoseTween PoseTween::make(const Pose &from, const Pose &to, float delayMs, float durMs, Bezier ease)
{
    PoseTween tw;
    tw.from = from;
    tw.to = to;
    tw.delay = delayMs / 1000.0f;
    tw.dur = std::max(durMs / 1000.0f, 0.001f);
    tw.ease = ease;
    return tw;
}

Pose PoseTween::at(float t) const
{
    const float u = ease.at(clampf((t - delay) / dur, 0.0f, 1.0f));
    return Pose::mix(from, to, u);
}

void PoseTween::retarget(float now, const Pose &to_, float delayMs, float durMs, Bezier ease_)
{
    *this = make(at(now), to_, delayMs, durMs, ease_);
}

Pose fanPose(float n, const Fan &fan, float k, float push, float lift, float zback, float s)
{
    return Pose::make(QVector3D(n * fan.spread * push, std::pow(std::abs(n), 1.7f) * fan.arch + lift,
                                -std::abs(n) * 55.0f * k + zback),
                      {Rot{AXIS_Y, n * -fan.angle}, Rot{AXIS_Z, n * fan.roll}}, s);
}

Pose selPose(float k)
{
    return Pose::make(QVector3D(0.0f, -40.0f * k, 170.0f * k), {Rot{AXIS_Y, 0.0f}, Rot{AXIS_Z, 0.0f}}, 1.02f);
}

Pose movePose(Move mv, float n, float s, float k)
{
    switch (mv) {
    case Move::Corkscrew:
        return Pose::make(QVector3D(n * 95.0f * k, s * -780.0f * k, s * 560.0f * k),
                          {Rot{AXIS_Y, s * (940.0f + n * 90.0f)}, Rot{AXIS_Z, s * (210.0f + n * 55.0f)}}, 0.08f);
    case Move::Shuffle:
        return Pose::make(QVector3D((s * 1010.0f + n * 130.0f) * k, s * n * 70.0f * k, n * 110.0f * k),
                          {Rot{AXIS_Z, s * (72.0f + n * 26.0f)}, Rot{AXIS_Y, s * 200.0f}}, 0.7f);
    case Move::Cascade:
        return Pose::make(QVector3D(n * 150.0f * k, s * 720.0f * k, s * 260.0f * k),
                          {Rot{AXIS_X, s * -64.0f}, Rot{AXIS_Z, n * 8.5f}}, 0.44f);
    case Move::Ribbon:
        return Pose::make(QVector3D(n * 138.0f * k, s * -34.0f * k, s * 40.0f * k), {Rot{AXIS_Z, n * 8.5f}}, 1.04f);
    case Move::Spiral: {
        const float a2 = 1.15f * n + 0.5f;
        return Pose::make(QVector3D(std::cos(a2) * 520.0f * s * k, std::sin(a2) * 430.0f * s * k, -560.0f * k),
                          {Rot{QVector3D(0.4f, 1.0f, 0.3f), s * (520.0f + n * 120.0f)}}, 0.24f);
    }
    }
    return Pose::rest();
}

Pose rowPose(float n, float slatW, float gap)
{
    return Pose::make(QVector3D(n * (slatW + gap), 0.0f, 0.0f), {Rot{AXIS_Y, 0.0f}, Rot{AXIS_Z, 0.0f}}, 1.0f);
}

Pose columnPose(float n, float slatH, float gap)
{
    return Pose::make(QVector3D(0.0f, n * (slatH + gap), 0.0f), {Rot{AXIS_Y, 0.0f}, Rot{AXIS_Z, -90.0f}}, 1.0f);
}

Pose ribbonDealPose(int r, float s, float k, Axis axis)
{
    const float d = (r % 2 == 1) ? s : -s;
    const float rf = float(r);
    return Pose::make(alongCross(axis, 0.0f, d * (420.0f + rf * 64.0f) * k, (90.0f + rf * 26.0f) * k),
                      {hinge(axis, d * (72.0f + rf * 8.0f)), Rot{AXIS_Z, d * 9.0f}}, 0.92f);
}

Pose ribbonFlipPose(uint8_t stage, int r, int nr, float dir, float k, Axis axis)
{
    const float mid = (float(nr) - 1.0f) / 2.0f;
    const float rf = float(r);
    const float tail = float(nr - 1 - r);
    switch (stage) {
    case 1:
        return Pose::make(alongCross(axis, dir * (84.0f + rf * 7.0f) * k, (rf - mid) * 34.0f * k,
                                     (120.0f + rf * 22.0f) * k),
                          {hinge(axis, dir * 104.0f), swing(axis, dir * 44.0f), Rot{AXIS_Z, dir * 17.0f}}, 1.0f);
    case 2:
        return Pose::make(QVector3D(0, 0, 0), {hinge(axis, dir * 180.0f)}, 1.0f);
    case 3:
        return Pose::make(alongCross(axis, -dir * (92.0f + tail * 7.0f) * k, (mid - rf) * 34.0f * k,
                                     (150.0f + tail * 20.0f) * k),
                          {hinge(axis, dir * 258.0f), swing(axis, -dir * 54.0f), Rot{AXIS_Z, -dir * 21.0f}}, 1.0f);
    case 4:
        return Pose::make(QVector3D(0, 0, 0), {hinge(axis, dir * 360.0f)}, 1.0f);
    default:
        return Pose::rest();
    }
}

Pose twistPose(uint8_t stage, float k)
{
    float ry = 0.0f, tz = 0.0f, s = 1.0f;
    switch (stage) {
    case 1:
        ry = -26.0f;
        tz = 70.0f;
        s = 1.05f;
        break;
    case 2:
        ry = -13.0f;
        tz = 120.0f;
        s = 1.06f;
        break;
    case 3:
        ry = 27.0f;
        tz = 84.0f;
        s = 1.05f;
        break;
    default:
        break;
    }
    return Pose::make(QVector3D(0.0f, 0.0f, tz * k), {Rot{AXIS_Y, ry}}, s);
}

Pose flipRibbonPose(float tauMs, bool closing, int r, int nr, float dir, float k, Axis axis)
{
    const float rf = float(r);
    const float tail = float(nr - 1 - r);
    if (closing) {
        const Pose s3 = ribbonFlipPose(3, r, nr, dir, k, axis);
        const Pose s4 = ribbonFlipPose(4, r, nr, dir, k, axis);
        const Pose landed = ribbonFlipPose(2, r, nr, dir, k, axis);
        const PoseTween lift = PoseTween::make(landed, s3, tail * FLIP_CLOSE[0][1], FLIP_CLOSE[0][0], EASE_FLIP_LIFT);
        if (tauMs < FLIP_CLOSE_LIFT_MS)
            return lift.at(tauMs / 1000.0f);
        const PoseTween land = PoseTween::make(lift.at(FLIP_CLOSE_LIFT_MS / 1000.0f), s4, rf * FLIP_CLOSE[1][1],
                                               FLIP_CLOSE[1][0], EASE_FLIP_CLOSE);
        return land.at((tauMs - FLIP_CLOSE_LIFT_MS) / 1000.0f);
    }
    const Pose s1 = ribbonFlipPose(1, r, nr, dir, k, axis);
    const Pose s2 = ribbonFlipPose(2, r, nr, dir, k, axis);
    const PoseTween lift = PoseTween::make(Pose::rest(), s1, rf * FLIP_OPEN[0][1], FLIP_OPEN[0][0], EASE_FLIP_LIFT);
    if (tauMs < FLIP_LIFT_MS)
        return lift.at(tauMs / 1000.0f);
    const PoseTween land = PoseTween::make(lift.at(FLIP_LIFT_MS / 1000.0f), s2, tail * FLIP_OPEN[1][1],
                                           FLIP_OPEN[1][0], EASE_FLIP_LAND);
    return land.at((tauMs - FLIP_LIFT_MS) / 1000.0f);
}

Pose flipTwistPose(float tauMs, bool closing, float k)
{
    const float liftMs = closing ? FLIP_CLOSE_LIFT_MS : FLIP_LIFT_MS;
    const Pose first = closing ? twistPose(3, k) : twistPose(1, k);
    const Pose second = closing ? twistPose(4, k) : twistPose(2, k);
    const Pose start = closing ? twistPose(2, k) : Pose::rest();
    const PoseTween lift = PoseTween::make(start, first, 0.0f, TWIST_MS, EASE_TWIST);
    if (tauMs < liftMs)
        return lift.at(tauMs / 1000.0f);
    const PoseTween land = PoseTween::make(lift.at(liftMs / 1000.0f), second, 0.0f, TWIST_MS, EASE_TWIST);
    return land.at((tauMs - liftMs) / 1000.0f);
}

std::pair<Pose, float> slatTurnPose(float t, float dir, float k)
{
    t = clampf(t, 0.0f, 1.0f);
    const float e = EASE_REVEAL_TURN.at(t);
    const float s = std::sin(t * float(M_PI));
    const Pose pose = Pose::make(QVector3D(0.0f, -46.0f * k * s, 150.0f * k * s),
                                 {Rot{AXIS_Y, dir * 180.0f * e}, Rot{AXIS_X, dir * -14.0f * s},
                                  Rot{AXIS_Z, dir * 9.0f * s}},
                                 1.0f + 0.07f * s);
    return {pose, e};
}

Pose bob(float timeS, int slot, float k)
{
    const float phase = remEuclid((timeS - float(slot) * BOB_DELAY_S) / BOB_PERIOD_S, 1.0f);
    const float s = 0.5f - 0.5f * std::cos(phase * kTau);
    return Pose::make(QVector3D(0.0f, lerpf(-6.0f, 7.0f, s) * k, 0.0f), {Rot{AXIS_Z, lerpf(-0.7f, 0.9f, s)}}, 1.0f);
}

float flipOpenMs(int nr) { return FLIP_LIFT_MS + FLIP_OPEN[1][0] + float(std::max(nr - 1, 0)) * FLIP_OPEN[1][1]; }
float flipCloseMs(int nr) { return FLIP_CLOSE_LIFT_MS + FLIP_CLOSE[1][0] + float(std::max(nr - 1, 0)) * FLIP_CLOSE[1][1]; }

float ribbonDir(float seed, int card, int r, bool deal)
{
    return rnd(seed * 613.0f, float(card), float(r), deal ? 1.0f : 7.0f) > 0.5f ? 1.0f : -1.0f;
}

std::pair<float, float> revealFrame(float vw, float vh, bool tall)
{
    const float aspect = tall ? TALL_ASPECT : THUMB_ASPECT;
    const float w = std::min(vw * ROW_FIT, vh * COLUMN_FIT * aspect);
    return {w, w / aspect};
}

std::pair<float, float> slatHalfExtent(int len, std::pair<float, float> frame, float gap, bool tall)
{
    const float n = float(std::max(len, 1));
    if (tall) {
        const float slatH = (frame.second - (n - 1.0f) * gap) / n;
        return {slatH * 0.5f, frame.first * 0.5f};
    }
    const float slatW = (frame.first - (n - 1.0f) * gap) / n;
    return {slatW * 0.5f, frame.second * 0.5f};
}

std::pair<float, float> keepExtent(int len, std::pair<float, float> card, std::pair<float, float> frame, float gap, bool tall)
{
    const float n = float(std::max(len, 1));
    const float hw = card.first;
    const float hh = card.second;
    const float along = std::max(n * hw * 2.0f, 1.0f);
    const float limitAlong = tall ? frame.second : frame.first;
    const float limitCross = tall ? frame.first : frame.second;
    float fit = std::min((limitAlong - (n - 1.0f) * gap) / along, limitCross / std::max(hh * 2.0f, 1.0f));
    fit = std::min(fit, 1.0f);
    return {hw * fit, hh * fit};
}

float revealTurn(float clockS, int order, float speedScale)
{
    const float delay = float(order) * REVEAL_STAGGER_MS * speedScale / 1000.0f;
    const float dur = REVEAL_TURN_MS * speedScale / 1000.0f;
    return clampf((clockS - delay) / dur, 0.0f, 1.0f);
}

int revealOrder(int slot, int len, uint32_t turnsDone)
{
    return (turnsDone % 2 == 0) ? slot : std::max(len - 1 - slot, 0);
}

float revealDirFor(int slot, uint32_t turnsDone)
{
    return ((uint32_t(slot) + turnsDone) % 2 == 0) ? 1.0f : -1.0f;
}

float revealTurnEnd(int len, float speedScale)
{
    return (float(std::max(len - 1, 0)) * REVEAL_STAGGER_MS + REVEAL_TURN_MS) * speedScale / 1000.0f;
}

int revealFace(uint32_t turnsDone, float t)
{
    const float angle = 180.0f * (float(turnsDone) + clampf(t, 0.0f, 1.0f));
    return int(uint32_t(std::floor((angle + 90.0f) / 180.0f)) % 2);
}

float relax(float progress)
{
    const float t = clampf((progress - RELAX_LO) / (RELAX_HI - RELAX_LO), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

std::array<float, 4> sliceCrop(int slot, int len, float rowW, float rowH, float gap)
{
    len = std::max(len, 1);
    rowW = std::max(rowW, 1.0f);
    const auto c = cover(THUMB_ASPECT, rowW / std::max(rowH, 1.0f));
    const float band = (rowW - (float(len) - 1.0f) * gap) / float(len);
    const float start = float(std::min(slot, len - 1)) * (band + gap) / rowW;
    return {c[0] + c[2] * start, c[1], c[2] * band / rowW, c[3]};
}

std::array<float, 4> columnCrop(int slot, int len, float stackW, float stackH, float gap)
{
    len = std::max(len, 1);
    stackH = std::max(stackH, 1.0f);
    const auto c = cover(TALL_ASPECT, std::max(stackW, 1.0f) / stackH);
    const float band = (stackH - (float(len) - 1.0f) * gap) / float(len);
    const float v = c[1] + c[3] * float(std::min(slot, len - 1)) * (band + gap) / stackH;
    const float bv = c[3] * band / stackH;
    return {1.0f - v - bv, c[0], bv, c[2]};
}

std::vector<RibbonCut> ribbonCuts(int nr, float total, Cut cut, Variance variance, float lseed, int card, float pad)
{
    nr = std::clamp(nr, 1, 14);
    const float band = total / float(nr);
    const float skew0 = cutFactor(cut) * band;
    const float vary = varianceFactor(variance);

    std::vector<float> bounds;
    bounds.reserve(size_t(nr) + 1);
    bounds.push_back(0.0f);
    if (vary > 0.0f) {
        std::vector<float> weights(static_cast<size_t>(nr), 0.0f);
        float sum = 0.0f;
        for (int kk = 0; kk < nr; ++kk) {
            weights[size_t(kk)] = 1.0f + vary * (rnd(lseed * 997.0f, float(card), float(kk), 11.0f) - 0.5f) * 1.5f;
            sum += weights[size_t(kk)];
        }
        float acc = 0.0f;
        for (int kk = 0; kk < nr; ++kk) {
            acc += weights[size_t(kk)] / sum * total;
            bounds.push_back(kk == nr - 1 ? total : acc);
        }
    } else {
        for (int kk = 1; kk <= nr; ++kk)
            bounds.push_back(float(kk) * band);
    }

    std::vector<float> skews(size_t(nr) + 1);
    for (int kk = 0; kk <= nr; ++kk) {
        const float jitter =
            vary > 0.0f ? 1.0f + vary * (rnd(lseed * 331.0f, float(card), float(kk), 13.0f) - 0.5f) * 1.6f : 1.0f;
        skews[size_t(kk)] = skew0 * jitter;
    }
    for (int kk = 1; kk < std::max(nr - 1, 0); ++kk) {
        const float room = 2.0f * std::max(bounds[size_t(kk) + 1] - bounds[size_t(kk)] - RIBBON_MIN, 0.0f);
        skews[size_t(kk) + 1] = clampf(skews[size_t(kk) + 1], skews[size_t(kk)] - room, skews[size_t(kk)] + room);
    }

    const float half = total * 0.5f;
    const float far = half + pad + total;
    std::vector<RibbonCut> out;
    out.reserve(size_t(nr));
    for (int kk = 0; kk < nr; ++kk) {
        const float a = bounds[size_t(kk)] - half;
        const float b = bounds[size_t(kk) + 1] - half;
        const float ska = skews[size_t(kk)];
        const float skb = skews[size_t(kk) + 1];
        const bool first = kk == 0;
        const bool last = kk == nr - 1;
        out.push_back(RibbonCut{
            first ? -far : a - ska * 0.5f - RIBBON_OVERLAP,
            first ? -far : a + ska * 0.5f - RIBBON_OVERLAP,
            last ? far : b - skb * 0.5f + RIBBON_OVERLAP,
            last ? far : b + skb * 0.5f + RIBBON_OVERLAP,
            (a + b) * 0.5f,
        });
    }
    return out;
}

RibbonCut mirroredCut(const RibbonCut &cut)
{
    const float m = 2.0f * cut.mid;
    return RibbonCut{m - cut.b0, m - cut.b1, m - cut.a0, m - cut.a1, cut.mid};
}

std::array<QVector3D, 4> ribbonCorners(const RibbonCut &cut, Axis axis, float hw, float hh, float pad)
{
    if (axis == Axis::Rows)
        return {QVector3D(-hw - pad, cut.a0, 0.0f), QVector3D(hw + pad, cut.a1, 0.0f), QVector3D(hw + pad, cut.b1, 0.0f),
                QVector3D(-hw - pad, cut.b0, 0.0f)};
    return {QVector3D(cut.a0, -hh - pad, 0.0f), QVector3D(cut.b0, -hh - pad, 0.0f), QVector3D(cut.b1, hh + pad, 0.0f),
            QVector3D(cut.a1, hh + pad, 0.0f)};
}

std::array<float, 4> ribbonLocals(const RibbonCut &cut, Axis axis)
{
    if (axis == Axis::Rows)
        return {cut.a0, cut.a1, cut.b1, cut.b0};
    return {cut.a0, cut.b0, cut.b1, cut.a1};
}

QMatrix4x4 ribbonOrigin(const RibbonCut &cut, Axis axis)
{
    QMatrix4x4 m;
    if (axis == Axis::Rows)
        m.translate(0.0f, cut.mid, 0.0f);
    else
        m.translate(cut.mid, 0.0f, 0.0f);
    return m;
}

QMatrix4x4 ribbonBack(const RibbonCut &cut, Axis axis)
{
    QMatrix4x4 m;
    if (axis == Axis::Rows)
        m.translate(0.0f, -cut.mid, 0.0f);
    else
        m.translate(-cut.mid, 0.0f, 0.0f);
    return m;
}

std::array<QVector3D, 4> cardCorners(float hw, float hh, float padX, float padY)
{
    return {QVector3D(-hw - padX, -hh - padY, 0.0f), QVector3D(hw + padX, -hh - padY, 0.0f),
            QVector3D(hw + padX, hh + padY, 0.0f), QVector3D(-hw - padX, hh + padY, 0.0f)};
}

std::array<float, 4> cardLocals(float hh, float pad) { return {-hh - pad, -hh - pad, hh + pad, hh + pad}; }

QVector3D Camera::project(const QVector3D &p) const
{
    const float w = std::max((d - p.z()) / std::max(d, 1.0f), 0.05f);
    return QVector3D(origin.x() + shift.x() + (p.x() - shift.x()) / w,
                     origin.y() + shift.y() + (p.y() - shift.y()) / w, w);
}

Quad Quad::mirrored() const
{
    return Quad{{pts[1], pts[0], pts[3], pts[2]}, depth};
}

bool Quad::facing() const
{
    const float ax = pts[1].x() - pts[0].x();
    const float ay = pts[1].y() - pts[0].y();
    const float bx = pts[3].x() - pts[0].x();
    const float by = pts[3].y() - pts[0].y();
    return ax * by - ay * bx > 0.0f;
}

std::array<float, 4> Quad::bounds() const
{
    float minx = pts[0].x(), miny = pts[0].y(), maxx = pts[0].x(), maxy = pts[0].y();
    for (const QVector3D &p : pts) {
        minx = std::min(minx, p.x());
        miny = std::min(miny, p.y());
        maxx = std::max(maxx, p.x());
        maxy = std::max(maxy, p.y());
    }
    return {(minx + maxx) * 0.5f, (miny + maxy) * 0.5f, (maxx - minx) * 0.5f, (maxy - miny) * 0.5f};
}

bool Quad::visible(float vw, float vh) const
{
    const auto b = bounds();
    return b[0] + b[2] >= -8.0f && b[0] - b[2] <= vw + 8.0f && b[1] + b[3] >= -8.0f && b[1] - b[3] <= vh + 8.0f;
}

Quad projectQuad(const Camera &cam, const QMatrix4x4 &m, const std::array<QVector3D, 4> &corners)
{
    Quad quad;
    for (int i = 0; i < 4; ++i) {
        const QVector4D w4 = m * QVector4D(corners[size_t(i)], 1.0f);
        const QVector3D world(w4.x(), w4.y(), w4.z());
        quad.depth += world.z() * 0.25f;
        quad.pts[size_t(i)] = cam.project(world);
    }
    return quad;
}

std::array<float, 4> unionBounds(const std::vector<Quad> &quads)
{
    if (quads.empty())
        return {0.0f, 0.0f, 0.0f, 0.0f};
    float minx = quads[0].pts[0].x(), miny = quads[0].pts[0].y();
    float maxx = minx, maxy = miny;
    for (const Quad &quad : quads)
        for (const QVector3D &p : quad.pts) {
            minx = std::min(minx, p.x());
            miny = std::min(miny, p.y());
            maxx = std::max(maxx, p.x());
            maxy = std::max(maxy, p.y());
        }
    return {(minx + maxx) * 0.5f, (miny + maxy) * 0.5f, (maxx - minx) * 0.5f, (maxy - miny) * 0.5f};
}

std::pair<float, float> parallaxShift(float rigX, float rigY, float k)
{
    return {clampf(rigY / 4.0f, -1.0f, 1.0f) * 40.0f * k, clampf(-rigX / 3.0f, -1.0f, 1.0f) * 30.0f * k};
}

std::pair<float, float> tiltTarget(float x, float y, float vw, float vh, float tilt)
{
    return {-((y / std::max(vh, 1.0f)) - 0.5f) * TILT_X_DEG * tilt,
            ((x / std::max(vw, 1.0f)) - 0.5f) * TILT_Y_DEG * tilt};
}

float fanSlot(int slot, int len, int excluded)
{
    if (excluded >= 0 && excluded != slot && len > 1) {
        const int j = slot > excluded ? slot - 1 : slot;
        return float(j) - (float(len) - 2.0f) * 0.5f;
    }
    return float(slot) - (float(std::max(len, 1)) - 1.0f) * 0.5f;
}

float stageScale(float vw, float vh)
{
    return std::max(std::min(vh / DESIGN_H, vw / DESIGN_W), 0.2f);
}

int handWindow(int current, int count, int size)
{
    size = std::max(size, 1);
    if (count <= size)
        return 0;
    return std::min((current / size) * size, count - size);
}

int handLen(int offset, int count, int size)
{
    return std::min(std::max(count - offset, 0), std::max(size, 1));
}

bool pointInQuad(const std::array<QVector3D, 4> &pts, QPointF p)
{
    bool hasPos = false, hasNeg = false;
    for (int i = 0; i < 4; ++i) {
        const QVector3D &a = pts[size_t(i)];
        const QVector3D &b = pts[size_t((i + 1) % 4)];
        const float cross =
            (b.x() - a.x()) * (float(p.y()) - a.y()) - (b.y() - a.y()) * (float(p.x()) - a.x());
        if (cross > 1e-4f)
            hasPos = true;
        else if (cross < -1e-4f)
            hasNeg = true;
    }
    return !(hasPos && hasNeg);
}

}  // namespace handrig
