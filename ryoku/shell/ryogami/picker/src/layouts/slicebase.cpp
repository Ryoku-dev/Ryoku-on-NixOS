#include "slicebase.h"

#include <QColor>

#include <algorithm>
#include <cmath>

namespace {

void setVec4(float *dst, float a, float b, float c, float d)
{
    dst[0] = a;
    dst[1] = b;
    dst[2] = c;
    dst[3] = d;
}

} // namespace

void SliceParams::morphToward(const SliceParams &t, float amt)
{
    parallax = t.parallax;
    shadows = t.shadows;
    offsetX = geom::lerp(offsetX, t.offsetX, amt);
    offsetY = geom::lerp(offsetY, t.offsetY, amt);
    sliceW = geom::lerp(sliceW, t.sliceW, amt);
    expandedW = geom::lerp(expandedW, t.expandedW, amt);
    sliceH = geom::lerp(sliceH, t.sliceH, amt);
    spacing = geom::lerp(spacing, t.spacing, amt);
    skew = geom::lerp(skew, t.skew, amt);
    edgeTilt = geom::lerp(edgeTilt, t.edgeTilt, amt);
    visibleCount = t.visibleCount;
    wobble = t.wobble;
    wobbleStrength = geom::lerp(wobbleStrength, t.wobbleStrength, amt);
    shadowStrength = geom::lerp(shadowStrength, t.shadowStrength, amt);
    shadowDistance = geom::lerp(shadowDistance, t.shadowDistance, amt);
    for (int i = 0; i < 4; ++i)
        corners[size_t(i)] = geom::lerp(corners[size_t(i)], t.corners[size_t(i)], amt);
}

bool SliceParams::settledTo(const SliceParams &t) const
{
    return parallax == t.parallax && shadows == t.shadows && geom::feq(offsetX, t.offsetX)
        && geom::feq(offsetY, t.offsetY) && geom::feq(sliceW, t.sliceW)
        && geom::feq(expandedW, t.expandedW) && geom::feq(sliceH, t.sliceH)
        && geom::feq(spacing, t.spacing) && geom::feq(skew, t.skew)
        && geom::feq(edgeTilt, t.edgeTilt) && visibleCount == t.visibleCount && wobble == t.wobble
        && geom::feq(wobbleStrength, t.wobbleStrength)
        && geom::feq(shadowStrength, t.shadowStrength) && geom::feq(shadowDistance, t.shadowDistance)
        && geom::feq(corners[0], t.corners[0])
        && geom::feq(corners[1], t.corners[1]) && geom::feq(corners[2], t.corners[2])
        && geom::feq(corners[3], t.corners[3]);
}

void SliceBase::configure(const LayoutContext &ctx, bool animate)
{
    SliceParams next;
    readParams(ctx, next);
    m_target = next;
    if (!animate || !m_paramsInit) {
        m_live = m_target;
        m_anchor = true;
    }
    m_paramsInit = true;
}

bool SliceBase::morphParams(const LayoutContext &ctx, double dt)
{
    if (m_live.settledTo(m_target)) {
        m_live = m_target;
        return false;
    }
    const float amt = float(approachK(dt, ctx.motion->tau(MotionProfile::Standard)));
    m_live.morphToward(m_target, amt);
    return true;
}

void SliceBase::positionCamera(float target)
{
    if (m_anchor || !m_live.settledTo(m_target)) {
        m_camera.snap(target);
        m_anchor = false;
    } else {
        m_camera.target = target;
    }
}

void SliceBase::retargetSelection(int from, int to, double ms, double epsilon)
{
    const auto reSpring = [&](int row, double startFallback, double target) {
        const auto it = m_selection.find(row);
        const double x = it != m_selection.end() ? it->second.x : startFallback;
        Spring s = Spring::forDuration(x, ms);
        s.epsilon = epsilon;
        s.target = target;
        m_selection[row] = s;
    };
    reSpring(from, 1.0, 0.0);
    reSpring(to, 0.0, 1.0);
}

float SliceBase::selectionOf(int row, int current) const
{
    const auto it = m_selection.find(row);
    if (it != m_selection.end())
        return float(std::clamp(it->second.x, 0.0, 1.0));
    return row == current ? 1.0f : 0.0f;
}

bool SliceBase::tickSelection(double dt, double epsilon)
{
    bool moving = false;
    for (auto it = m_selection.begin(); it != m_selection.end();) {
        it->second.epsilon = epsilon;
        const bool m = it->second.tick(dt);
        moving |= m;
        if (!m && it->second.target <= 0.0)
            it = m_selection.erase(it);
        else
            ++it;
    }
    return moving;
}

int SliceBase::hitTest(QPointF point) const
{
    for (auto it = m_hits.rbegin(); it != m_hits.rend(); ++it) {
        if (geom::shearedContains(it->cx, it->cy, it->hw, it->hh, it->skew, it->edgeTilt,
                                  float(point.x()), float(point.y())))
            return it->row;
    }
    return -1;
}

QRectF SliceBase::cardRect(int row) const
{
    for (const HitRec &h : m_hits) {
        if (h.row == row)
            return QRectF(h.cx - h.hw, h.cy - h.hh, h.hw * 2.0, h.hh * 2.0);
    }
    return QRectF();
}

QPointF SliceBase::cardShear(int row) const
{
    for (const HitRec &h : m_hits) {
        if (h.row == row)
            return QPointF(h.skew, h.edgeTilt);
    }
    return QPointF();
}

QRectF SliceBase::stageRect(const LayoutContext &ctx) const
{
    const double vh = ctx.viewport.height();
    const double h = m_live.sliceH + 110.0;
    return QRectF(0, (vh - h) * 0.5, ctx.viewport.width(), h);
}

void SliceBase::emitCard(const LayoutContext &ctx, std::vector<CardVisual> &out, int row, float w,
                         float itemCx, float itemCy, float opacity, float halfView, float bend,
                         const SliceParams &sp, bool depthMode, bool depthSelectionFrame,
                         bool hasParallax, float parallax)
{
    const float vw = float(ctx.viewport.width());
    const float cx = geom::centerLayout(vw, 0.0f).centerX + sp.offsetX * vw * 0.5f;
    const bool isCurrent = row == ctx.current;
    const bool isHover = row == ctx.hovered;
    const std::array<float, 4> radii =
        geom::sliceClampedCorners(sp.corners, w, sp.sliceH, sp.skew, sp.edgeTilt);
    const float hw = w * 0.5f;
    const float hh = sp.sliceH * 0.5f;

    if (sp.shadows) {
        CardVisual sh;
        sh.row = row;
        sh.texture = CardVisual::TextureNone;
        const float shX = (isCurrent ? 4.0f : 2.0f) * sp.shadowDistance;
        const float shY = (isCurrent ? 10.0f : 5.0f) * sp.shadowDistance;
        const float shA = (isCurrent ? 0.5f : 0.3f) * sp.shadowStrength;
        setVec4(sh.inst.rect, itemCx + shX, itemCy + shY, hw, hh);
        for (int i = 0; i < 4; ++i)
            sh.inst.radii[i] = radii[size_t(i)];
        setVec4(sh.inst.fill, 0.0f, 0.0f, 0.0f, shA);
        setVec4(sh.inst.params, sp.skew, 0.0f, opacity, 0.0f);
        sh.inst.shape[0] = sp.edgeTilt;
        sh.inst.misc[3] = CardFlag::Shadow;
        out.push_back(sh);
    }

    CardVisual card;
    card.row = row;
    card.texture = CardVisual::TextureAuto;
    card.cover = true;
    card.cropAspect = 0.0f;
    setVec4(card.inst.rect, itemCx, itemCy, hw, hh);
    for (int i = 0; i < 4; ++i)
        card.inst.radii[i] = radii[size_t(i)];
    card.inst.params[0] = sp.skew;
    card.inst.params[2] = opacity;
    card.inst.shape[0] = sp.edgeTilt;

    const float sel = selectionOf(row, ctx.current);
    const QColor prim = ctx.palette.primary;
    const float pr = float(prim.redF());
    const float pg = float(prim.greenF());
    const float pb = float(prim.blueF());
    float baseBorder[4];
    float baseDim;
    if (isHover) {
        setVec4(baseBorder, pr, pg, pb, 0.4f);
        baseDim = 0.15f;
    } else {
        setVec4(baseBorder, 0.0f, 0.0f, 0.0f, 0.6f);
        baseDim = 0.4f;
    }
    const float borderSel = (depthMode && !depthSelectionFrame) ? 0.0f : sel;
    const float curBorder[4] = {pr, pg, pb, 1.0f};
    for (int i = 0; i < 4; ++i)
        card.inst.border[i] = baseBorder[i] + (curBorder[i] - baseBorder[i]) * borderSel;
    card.inst.params[1] = 1.0f + 2.0f * borderSel;

    if (depthMode && !depthSelectionFrame) {
        setVec4(card.inst.border, 0.0f, 0.0f, 0.0f, 0.0f);
        card.inst.params[1] = 0.0f;
        if (sp.skew == 0.0f && sp.edgeTilt == 0.0f && radii[0] == 0.0f && radii[1] == 0.0f
            && radii[2] == 0.0f && radii[3] == 0.0f)
            card.inst.misc[3] |= CardFlag::UnframedRect;
    }
    setVec4(card.inst.tint, 0.0f, 0.0f, 0.0f, baseDim * (1.0f - sel));

    if (sp.wobble) {
        const float pad = geom::wobblePad(sp.wobbleStrength);
        card.inst.rect[2] *= pad;
        card.inst.rect[3] *= pad;
        card.inst.flip[2] = pad;
        card.inst.misc[3] |= CardFlag::PageBend;
        card.inst.flip[3] = bend * sp.wobbleStrength;
        card.inst.flip[1] = std::clamp((itemCx - cx) / std::max(halfView, 1.0f), -1.0f, 1.0f) * 0.5f;
    }

    if (hasParallax) {
        card.cropZoom = 1.4f;
        card.cropShiftX = std::clamp(parallax, -1.0f, 1.0f);
    }

    out.push_back(card);
    m_hits.push_back({row, itemCx, itemCy, hw, hh, sp.skew, sp.edgeTilt});
}
