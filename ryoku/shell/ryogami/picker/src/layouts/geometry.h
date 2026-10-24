#pragma once

#include "../render/cardinstance.h"

#include <QMatrix4x4>
#include <QPointF>
#include <QRectF>
#include <QVector3D>

#include <array>
#include <cstdint>

namespace geom {

// Filter-bar footprint the layouts leave clear at the top of the scene.
constexpr float kTopBar = 50.0f;
// Per-card sweep spread of the filter-swap roll.
constexpr float kFilterFlipSweep = 0.6f;
// Atlas source aspect the far thumbnails are decoded at.
constexpr float kThumbW = 640.0f;
constexpr float kThumbH = 360.0f;
constexpr float kPad = 2.0f;

inline float lerp(float a, float b, float t) { return a + (b - a) * t; }

// Two scalars count as settled within 0.05.
inline bool feq(float a, float b) { return std::abs(a - b) < 0.05f; }

inline float smoothstep(float t)
{
    t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
    return t * t * (3.0f - 2.0f * t);
}
inline float window(float p, float start, float end)
{
    const float span = end - start;
    return smoothstep(span != 0.0f ? (p - start) / span : (p >= end ? 1.0f : 0.0f));
}
inline float easeOutCubic(float t)
{
    t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
    const float m = 1.0f - t;
    return 1.0f - m * m * m;
}

// Deterministic per-index hash in [-1, 1] for the scatter and variance modifiers.
float signedHash(unsigned index, uint32_t salt);

// Cubic Bézier with fixed end points: Newton-solve x, then sample y.
struct Bezier {
    float x1 = 0, y1 = 0, x2 = 1, y2 = 1;
    float at(float x) const;
};

struct CenterLayout {
    float centerX = 0;
    float availW = 1;
};
inline float clampInset(float viewportW, float rawInset)
{
    const float capped = viewportW * 0.6f;
    float v = rawInset < 0.0f ? 0.0f : rawInset;
    return v > capped ? capped : v;
}
inline CenterLayout centerLayout(float viewportW, float rawInset, bool rtl = false)
{
    const float inset = clampInset(viewportW, rawInset);
    const float lead = rtl ? 0.0f : inset;
    const float usable = viewportW - inset;
    return {lead + usable * 0.5f, usable < 1.0f ? 1.0f : usable};
}

inline float sliceMidlineWidth(float width, float skew)
{
    const float w = width - std::abs(skew);
    return w < 1.0f ? 1.0f : w;
}
inline float wobblePad(float strength) { return 1.05f + 0.30f * (strength < 1.0f ? 1.0f : strength); }
inline float wobbleBend(float vel, float scale)
{
    const float denom = scale * 2.2f < 1.0f ? 1.0f : scale * 2.2f;
    float b = vel / denom;
    return b < -1.35f ? -1.35f : (b > 1.35f ? 1.35f : b);
}

std::array<float, 4> cornerClamp(std::array<float, 4> corners, float flatW, float slantLen);
std::array<float, 4> sliceClampedCorners(std::array<float, 4> corners, float w, float h,
                                         float skew, float edgeTilt);

bool shearedContains(float cx, float cy, float hw, float hh, float skew, float edgeTilt,
                     float px, float py);

bool pointInQuad(const std::array<QPointF, 4> &quad, float px, float py);

float sliceOpacity(float itemCenterX, float viewCenterX, float halfView,
                   float expandedLayoutW, float sliceStride, float edgeDist, float halfWidth);

// Whole notches round; sub-notch deltas accumulate.
int sliceScrollSteps(float &accumulator, float amount);

// rollIn reveals right-to-left from a sliver; rollOut hides left-to-right.
void rollInCut(CardInstance &body, float fraction);
void rollOutCut(CardInstance &body, float fraction);

// project returns screen x, y and the perspective divisor w in z.
struct Camera {
    float d = 1.0f;
    QPointF origin;
    QPointF shift;
    QVector3D project(const QVector3D &p) const;
};

std::array<QVector3D, 4> cardCorners(float hw, float hh, float padX, float padY);
std::array<float, 4> cardLocals(float hh, float pad);

struct Rot {
    QVector3D axis;
    float deg = 0;
};

// Resolved as translate · rotations · scale.
struct Pose {
    QVector3D t;
    std::array<Rot, 3> rots{};
    int n = 0;
    float s = 1.0f;

    static Pose make(const QVector3D &t, std::initializer_list<Rot> rots, float s);
    QMatrix4x4 matrix() const;
    // Angle lerp when rotation orders agree, else a quaternion slerp.
    static Pose mix(const Pose &a, const Pose &b, float u);
};

struct ProjectedQuad {
    std::array<QPointF, 4> screen{};
    std::array<float, 4> w{{1, 1, 1, 1}};
    float depth = 0;

    bool facing() const;
    QRectF bounds() const;
    bool visible(float viewportW, float viewportH) const;
};

ProjectedQuad projectQuad(const Camera &cam, const QMatrix4x4 &m,
                          const std::array<QVector3D, 4> &corners);

} // namespace geom
