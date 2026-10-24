#include "duellayout.h"

#include <QColor>

#include <algorithm>
#include <cmath>

namespace {

constexpr char kPrefix[] = "components.wallpaperSelector.";
// The chosen card is half again as wide as the base and a little taller than the row.
constexpr float kCenterWidth = 1.5f;
constexpr float kCenterExtraH = 30.0f;
// A neighbour starts at about half the base width and never narrows below 58 % of that.
constexpr float kSideWidth = 0.48f;
constexpr float kSideFloor = 0.58f;
constexpr float kHeightFalloff = 0.90f;
constexpr float kHeightFloor = 0.62f;
// The visible seam between two cards, and how far below the middle the row sits.
constexpr float kGap = 6.0f;
constexpr float kDrop = 25.0f;

QString skey(const char *name)
{
    return QString::fromLatin1(kPrefix) + QLatin1String(name);
}

void setVec4(float *dst, float a, float b, float c, float d)
{
    dst[0] = a;
    dst[1] = b;
    dst[2] = c;
    dst[3] = d;
}

} // namespace

void DuelLayout::readParams(const LayoutContext &ctx, SliceParams &out) const
{
    const ParamSource &p = *ctx.params;
    const bool small = p.smallScreen();
    out.sliceH = float(std::clamp(p.num(skey("duelHeight"), small ? 300.0 : 420.0), 120.0, 2400.0));
    const float c = float(std::clamp(p.num(skey("duelCorners"), 18.0), 0.0, 400.0));
    out.corners = {c, c, c, c};
    out.shadows = p.flag(skey("duelShadows"), false);
    out.shadowStrength = float(std::clamp(p.num(skey("shadowStrength"), 100.0) / 100.0, 0.0, 2.0));
    out.shadowDistance = float(std::clamp(p.num(skey("shadowDistance"), 100.0) / 100.0, 0.0, 2.0));
    out.offsetX = float(std::clamp(p.num(skey("duelStageX"), 0.0) / 100.0, -1.0, 1.0));
    out.offsetY = float(std::clamp(p.num(skey("duelStageY"), 0.0) / 100.0, -1.0, 1.0));
    out.skew = 0.0f;
    out.edgeTilt = 0.0f;
    out.wobble = false;
    out.parallax = false;
}

void DuelLayout::readDuelParams(const LayoutContext &ctx)
{
    const ParamSource &p = *ctx.params;
    const bool small = p.smallScreen();
    m_duel.width = float(std::clamp(p.num(skey("duelWidth"), small ? 280.0 : 400.0), 80.0, 2400.0));
    m_duel.skew = float(std::clamp(p.num(skey("duelSkew"), 35.0), -80.0, 80.0)) / 100.0f;
    m_duel.falloff = 1.0f - float(std::clamp(p.num(skey("duelFalloff"), 12.0), 0.0, 40.0)) / 100.0f;
    m_duel.navigationMs = float(std::clamp(p.num(skey("duelNavigationMs"), 400.0), 1.0, 10000.0));
}

double DuelLayout::navMs(const LayoutContext &ctx) const
{
    if (ctx.motion->reduced)
        return 1.0;
    return double(m_duel.navigationMs) * ctx.motion->scale;
}

DuelLayout::Size DuelLayout::sizeAt(float distance) const
{
    const float baseW = m_duel.width;
    const float baseH = m_live.sliceH;
    const float steps = std::max(distance, 1.0f) - 1.0f;
    const Size side{baseW * kSideWidth * std::max(kSideFloor, std::pow(m_duel.falloff, steps)),
                    baseH * std::max(kHeightFloor, std::pow(kHeightFalloff, steps))};
    if (distance >= 1.0f)
        return side;
    // Between the chosen card and its neighbour the size eases, so a step glides.
    const float t = geom::smoothstep(1.0f - distance);
    return {geom::lerp(side.w, baseW * kCenterWidth, t),
            geom::lerp(side.h, baseH + kCenterExtraH, t)};
}

float DuelLayout::fitFor(const LayoutContext &ctx) const
{
    const geom::CenterLayout cl = geom::centerLayout(float(ctx.viewport.width()), 0.0f);
    const float centerH = m_live.sliceH + kCenterExtraH;
    const float centerW = m_duel.width * kCenterWidth + std::abs(m_duel.skew) * centerH;
    return std::min({1.0f, cl.availW * 0.6f / std::max(centerW, 1.0f),
                     float(ctx.viewport.height()) * 0.72f / std::max(centerH, 1.0f)});
}

float DuelLayout::centerY(const LayoutContext &ctx, float fit) const
{
    const float vh = float(ctx.viewport.height());
    return vh * 0.5f + m_live.offsetY * vh * 0.5f + kDrop * fit;
}

QRectF DuelLayout::stageRect(const LayoutContext &ctx) const
{
    const float fit = fitFor(ctx);
    const float h = (m_live.sliceH + kCenterExtraH) * fit + 60.0f;
    return QRectF(0, centerY(ctx, fit) - h * 0.5f, ctx.viewport.width(), h);
}

void DuelLayout::configure(const LayoutContext &ctx, bool animate)
{
    readDuelParams(ctx);
    SliceBase::configure(ctx, animate);
}

void DuelLayout::reset(const LayoutContext &ctx)
{
    Q_UNUSED(ctx)
    m_selection.clear();
    m_scrollAccum = 0;
    m_camera.snap(0.0);
    m_anchor = true;
}

void DuelLayout::select(const LayoutContext &ctx, int from, int to)
{
    retargetSelection(from, to, navMs(ctx), 0.001);
}

bool DuelLayout::tick(const LayoutContext &ctx, double dt)
{
    bool moving = morphParams(ctx, dt);
    m_camera.setDuration(navMs(ctx), 1.0);
    m_camera.epsilon = 0.0005;
    moving |= m_camera.tick(dt);
    moving |= tickSelection(dt, 0.001);
    return moving;
}

void DuelLayout::build(const LayoutContext &ctx, std::vector<CardVisual> &out)
{
    m_hits.clear();
    const int count = ctx.count;
    if (count == 0)
        return;
    const int current = std::clamp(ctx.current, 0, count - 1);
    if (m_anchor) {
        m_camera.snap(current);
        m_anchor = false;
    } else {
        m_camera.target = current;
    }

    const float camera = std::clamp(float(m_camera.x), 0.0f, float(count - 1));
    const float vw = float(ctx.viewport.width());
    const float fit = fitFor(ctx);
    const float cx = geom::centerLayout(vw, 0.0f).centerX + m_live.offsetX * vw * 0.5f;
    const float cy = centerY(ctx, fit);
    const float gap = kGap * fit;
    const auto widthOf = [&](int row) { return sizeAt(std::abs(float(row) - camera)).w * fit; };

    // Lay the row out from the card under the camera, so sizes and positions move with it.
    const int anchor = std::clamp(int(std::floor(camera)), 0, count - 1);
    m_offsets.assign(size_t(count), 0.0f);
    const float reach = vw * 0.5f + m_duel.width * fit;
    int low = anchor;
    for (int i = anchor - 1; i >= 0; --i) {
        m_offsets[size_t(i)] = m_offsets[size_t(i + 1)] - (widthOf(i) + widthOf(i + 1)) * 0.5f - gap;
        low = i;
        if (m_offsets[size_t(i)] < -reach * 2.0f)
            break;
    }
    int high = anchor;
    for (int i = anchor + 1; i < count; ++i) {
        m_offsets[size_t(i)] = m_offsets[size_t(i - 1)] + (widthOf(i - 1) + widthOf(i)) * 0.5f + gap;
        high = i;
        if (m_offsets[size_t(i)] > reach * 2.0f)
            break;
    }
    const float frac = camera - float(anchor);
    const float view = anchor + 1 <= high
        ? geom::lerp(m_offsets[size_t(anchor)], m_offsets[size_t(anchor + 1)], frac)
        : m_offsets[size_t(anchor)];

    m_visible.clear();
    for (int i = low; i <= high; ++i) {
        const float x = cx + m_offsets[size_t(i)] - view;
        const Size s = sizeAt(std::abs(float(i) - camera));
        const float half = (s.w + std::abs(m_duel.skew) * s.h) * fit * 0.5f;
        if (x + half >= -vw * 0.1f && x - half <= vw * 1.1f)
            m_visible.push_back(i);
    }
    const int hover = ctx.hovered;
    std::sort(m_visible.begin(), m_visible.end(), [&](int a, int b) {
        const auto rank = [&](int i) {
            if (i == current)
                return 2.0f;
            if (i == hover)
                return 1.0f;
            return -std::abs(float(i) - camera);
        };
        return rank(a) < rank(b);
    });

    for (int i : m_visible)
        emitDuelCard(ctx, out, i, std::abs(float(i) - camera), fit,
                     cx + m_offsets[size_t(i)] - view, cy);
}

void DuelLayout::emitDuelCard(const LayoutContext &ctx, std::vector<CardVisual> &out, int row,
                              float distance, float fit, float cx, float cy)
{
    const Size s = sizeAt(distance);
    const float w = s.w * fit;
    const float h = s.h * fit;
    // Every card leans at the same angle, so the shear grows with its height.
    const float skew = m_duel.skew * h;
    const float hw = (w + std::abs(skew)) * 0.5f;
    const float hh = h * 0.5f;
    const float opacity = float(ctx.entrance);

    // Large radii relax toward the base as cards recede, so far cards keep a softer outline.
    const float base = m_live.corners[0] * fit;
    const float k = std::min(1.0f, (base / 48.0f) * (base / 48.0f));
    const float decay = std::max(0.45f, std::pow(0.85f, distance));
    const float r = base * (1.0f - k * (1.0f - decay));
    const std::array<float, 4> radii = geom::sliceClampedCorners({r, r, r, r}, hw * 2.0f, h, skew, 0.0f);

    if (m_live.shadows) {
        CardVisual sh;
        sh.row = row;
        sh.texture = CardVisual::TextureNone;
        const bool near = distance < 0.5f;
        setVec4(sh.inst.rect, cx + (near ? 4.0f : 2.0f) * m_live.shadowDistance,
                cy + (near ? 10.0f : 5.0f) * m_live.shadowDistance, hw, hh);
        for (int i = 0; i < 4; ++i)
            sh.inst.radii[i] = radii[size_t(i)];
        setVec4(sh.inst.fill, 0.0f, 0.0f, 0.0f, (near ? 0.5f : 0.3f) * m_live.shadowStrength);
        setVec4(sh.inst.params, skew, 0.0f, opacity, 0.0f);
        sh.inst.misc[3] = CardFlag::Shadow;
        out.push_back(sh);
    }

    CardVisual card;
    card.row = row;
    card.texture = CardVisual::TextureAuto;
    card.wantNear = distance < 2.5f;
    card.cover = true;
    setVec4(card.inst.rect, cx, cy, hw, hh);
    for (int i = 0; i < 4; ++i)
        card.inst.radii[i] = radii[size_t(i)];
    card.inst.params[0] = skew;
    card.inst.params[2] = opacity;

    // Serpantinum leaves its cards bare; the pointer still gets a faint frame to aim by.
    const float hoverAmt = row == ctx.hovered && row != ctx.current ? 1.0f : 0.0f;
    const QColor prim = ctx.palette.primary;
    setVec4(card.inst.border, float(prim.redF()), float(prim.greenF()), float(prim.blueF()), 0.45f * hoverAmt);
    card.inst.params[1] = 1.5f * hoverAmt;
    setVec4(card.inst.tint, 0.0f, 0.0f, 0.0f, 0.0f);

    out.push_back(card);
    m_hits.push_back({row, cx, cy, hw, hh, skew, 0.0f});
}
