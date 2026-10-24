#include "cavaspectrum.hpp"

#include <QBrush>
#include <QPainter>
#include <QPen>
#include <QVariantMap>

#include <algorithm>
#include <cmath>

namespace {

qreal boundedUnit(qreal value) {
    return std::clamp(value, qreal(0.0), qreal(1.0));
}

qreal pointValue(qreal value) {
    return std::isnan(value) ? 0.0 : value;
}

} // namespace

CavaSpectrumPainter::CavaSpectrumPainter(QQuickItem* parent)
    : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setFillColor(Qt::transparent);
    makePalette();
    rebuildClipSegments();
    rebuildGeometryCaches(width(), height());
}

void CavaSpectrumPainter::notifyAndUpdate(ChangeSignal signal) {
    (this->*signal)();
    update();
}

void CavaSpectrumPainter::setPoints(const QList<qreal>& points) {
    if (m_points == points)
        return;
    m_points = points;
    notifyAndUpdate(&CavaSpectrumPainter::pointsChanged);
}

void CavaSpectrumPainter::setVisualizerType(const QString& type) {
    if (m_visualizerType == type)
        return;
    m_visualizerType = type;
    notifyAndUpdate(&CavaSpectrumPainter::visualizerTypeChanged);
}

void CavaSpectrumPainter::setNormalizationCeiling(qreal ceiling) {
    if (m_normalizationCeiling == ceiling)
        return;
    m_normalizationCeiling = ceiling;
    notifyAndUpdate(&CavaSpectrumPainter::normalizationCeilingChanged);
}

void CavaSpectrumPainter::setFillRatio(qreal ratio) {
    if (m_fillRatio == ratio)
        return;
    m_fillRatio = ratio;
    notifyAndUpdate(&CavaSpectrumPainter::fillRatioChanged);
}

void CavaSpectrumPainter::setSpectrumOpacity(qreal opacity) {
    if (m_spectrumOpacity == opacity)
        return;
    m_spectrumOpacity = opacity;
    emit spectrumOpacityChanged();
}

void CavaSpectrumPainter::setSpectrumColor(const QColor& color) {
    if (m_spectrumColor == color)
        return;
    m_spectrumColor = color;
    makePalette();
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::spectrumColorChanged);
}

void CavaSpectrumPainter::setSpectrumColors(const QVariantList& colors) {
    if (m_spectrumColors == colors)
        return;
    m_spectrumColors = colors;
    makePalette();
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::spectrumColorsChanged);
}

void CavaSpectrumPainter::setSampleStartRatio(qreal ratio) {
    if (m_sampleStartRatio == ratio)
        return;
    m_sampleStartRatio = ratio;
    notifyAndUpdate(&CavaSpectrumPainter::sampleStartRatioChanged);
}

void CavaSpectrumPainter::setSampleEndRatio(qreal ratio) {
    if (m_sampleEndRatio == ratio)
        return;
    m_sampleEndRatio = ratio;
    notifyAndUpdate(&CavaSpectrumPainter::sampleEndRatioChanged);
}

void CavaSpectrumPainter::setReverseFrequency(bool reverse) {
    if (m_reverseFrequency == reverse)
        return;
    m_reverseFrequency = reverse;
    notifyAndUpdate(&CavaSpectrumPainter::reverseFrequencyChanged);
}

void CavaSpectrumPainter::setPixelsPerBar(qreal pixels) {
    if (m_pixelsPerBar == pixels)
        return;
    m_pixelsPerBar = pixels;
    notifyAndUpdate(&CavaSpectrumPainter::pixelsPerBarChanged);
}

void CavaSpectrumPainter::setBarSpacing(qreal spacing) {
    if (m_barSpacing == spacing)
        return;
    m_barSpacing = spacing;
    notifyAndUpdate(&CavaSpectrumPainter::barSpacingChanged);
}

void CavaSpectrumPainter::setBarRadius(qreal radius) {
    if (m_barRadius == radius)
        return;
    m_barRadius = radius;
    notifyAndUpdate(&CavaSpectrumPainter::barRadiusChanged);
}

void CavaSpectrumPainter::setBarMinHeight(qreal height) {
    if (m_barMinHeight == height)
        return;
    m_barMinHeight = height;
    notifyAndUpdate(&CavaSpectrumPainter::barMinHeightChanged);
}

void CavaSpectrumPainter::setBarsOrigin(const QString& origin) {
    if (m_barsOrigin == origin)
        return;
    m_barsOrigin = origin;
    notifyAndUpdate(&CavaSpectrumPainter::barsOriginChanged);
}

void CavaSpectrumPainter::setSmoothing(int smoothing) {
    if (m_smoothing == smoothing)
        return;
    m_smoothing = smoothing;
    notifyAndUpdate(&CavaSpectrumPainter::smoothingChanged);
}

void CavaSpectrumPainter::setWaveMode(const QString& mode) {
    if (m_waveMode == mode)
        return;
    m_waveMode = mode;
    notifyAndUpdate(&CavaSpectrumPainter::waveModeChanged);
}

void CavaSpectrumPainter::setLineWidth(qreal width) {
    if (m_lineWidth == width)
        return;
    m_lineWidth = width;
    notifyAndUpdate(&CavaSpectrumPainter::lineWidthChanged);
}

void CavaSpectrumPainter::setEdgeInset(qreal inset) {
    if (m_edgeInset == inset)
        return;
    m_edgeInset = inset;
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::edgeInsetChanged);
}

void CavaSpectrumPainter::setLeftRadius(qreal radius) {
    if (m_leftRadius == radius)
        return;
    m_leftRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::leftRadiusChanged);
}

void CavaSpectrumPainter::setRightRadius(qreal radius) {
    if (m_rightRadius == radius)
        return;
    m_rightRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::rightRadiusChanged);
}

void CavaSpectrumPainter::setTopLeftRadius(qreal radius) {
    if (m_topLeftRadius == radius)
        return;
    m_topLeftRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::topLeftRadiusChanged);
}

void CavaSpectrumPainter::setTopRightRadius(qreal radius) {
    if (m_topRightRadius == radius)
        return;
    m_topRightRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::topRightRadiusChanged);
}

void CavaSpectrumPainter::setBottomLeftRadius(qreal radius) {
    if (m_bottomLeftRadius == radius)
        return;
    m_bottomLeftRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::bottomLeftRadiusChanged);
}

void CavaSpectrumPainter::setBottomRightRadius(qreal radius) {
    if (m_bottomRightRadius == radius)
        return;
    m_bottomRightRadius = radius;
    rebuildGeometryCaches(m_cachedWidth, m_cachedHeight);
    notifyAndUpdate(&CavaSpectrumPainter::bottomRightRadiusChanged);
}

void CavaSpectrumPainter::setEdgeSoftness(qreal softness) {
    if (m_edgeSoftness == softness)
        return;
    m_edgeSoftness = softness;
    makeEdgeTapers();
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::edgeSoftnessChanged);
}

void CavaSpectrumPainter::setFrequencyProfile(const QString& profile) {
    if (m_frequencyProfile == profile)
        return;
    m_frequencyProfile = profile;
    notifyAndUpdate(&CavaSpectrumPainter::frequencyProfileChanged);
}

void CavaSpectrumPainter::setAccentStrength(qreal strength) {
    if (m_accentStrength == strength)
        return;
    m_accentStrength = strength;
    notifyAndUpdate(&CavaSpectrumPainter::accentStrengthChanged);
}

void CavaSpectrumPainter::setMirroredStereo(bool mirrored) {
    if (m_mirroredStereo == mirrored)
        return;
    m_mirroredStereo = mirrored;
    notifyAndUpdate(&CavaSpectrumPainter::mirroredStereoChanged);
}

void CavaSpectrumPainter::setStartOpacity(qreal opacity) {
    if (m_startOpacity == opacity)
        return;
    m_startOpacity = opacity;
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::startOpacityChanged);
}

void CavaSpectrumPainter::setEndOpacity(qreal opacity) {
    if (m_endOpacity == opacity)
        return;
    m_endOpacity = opacity;
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::endOpacityChanged);
}

void CavaSpectrumPainter::setStartTaper(qreal taper) {
    if (m_startTaper == taper)
        return;
    m_startTaper = taper;
    makeEdgeTapers();
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::startTaperChanged);
}

void CavaSpectrumPainter::setEndTaper(qreal taper) {
    if (m_endTaper == taper)
        return;
    m_endTaper = taper;
    makeEdgeTapers();
    rebuildGradient();
    notifyAndUpdate(&CavaSpectrumPainter::endTaperChanged);
}

void CavaSpectrumPainter::setClipSegments(const QVariantList& segments) {
    if (m_clipSegments == segments)
        return;
    m_clipSegments = segments;
    rebuildClipSegments();
    clipSurface();
    notifyAndUpdate(&CavaSpectrumPainter::clipSegmentsChanged);
}

void CavaSpectrumPainter::makePalette() {
    m_palette.clear();
    m_palette.reserve(m_spectrumColors.size());
    for (const QVariant& value : m_spectrumColors) {
        const QColor color = value.value<QColor>();
        if (color.isValid())
            m_palette.append(color);
    }
    if (m_palette.isEmpty())
        m_palette.append(m_spectrumColor);
}

QColor CavaSpectrumPainter::colorAt(qreal position) const {
    if (m_palette.size() == 1)
        return m_palette.front();

    const qreal x = boundedUnit(position) * (m_palette.size() - 1);
    const int lower = static_cast<int>(std::floor(x));
    const int upper = std::min(static_cast<int>(m_palette.size()) - 1, lower + 1);
    const qreal amount = x - lower;
    const QColor& a = m_palette[lower];
    const QColor& b = m_palette[upper];
    return QColor::fromRgbF(
        a.redF() + (b.redF() - a.redF()) * amount,
        a.greenF() + (b.greenF() - a.greenF()) * amount,
        a.blueF() + (b.blueF() - a.blueF()) * amount,
        1.0);
}

QLinearGradient CavaSpectrumPainter::horizontalGradient(qreal x0, qreal x1, qreal alphaScale) const {
    QLinearGradient gradient(x0, 0.0, x1, 0.0);
    constexpr int StopCount = 16;
    for (int i = 0; i <= StopCount; ++i) {
        const qreal ratio = static_cast<qreal>(i) / StopCount;
        const qreal x = x0 + (x1 - x0) * ratio;
        const qreal opacity = m_startOpacity + (m_endOpacity - m_startOpacity) * ratio;
        QColor color = colorAt(ratio);
        color.setAlphaF(boundedUnit(opacity * alphaScale * std::sqrt(edgeMorphFactor(x, x0, x1))));
        gradient.setColorAt(ratio, color);
    }
    return gradient;
}

void CavaSpectrumPainter::selectedPoints() {
    m_selected.clear();
    const int count = m_points.size();
    if (count == 0)
        return;

    const qreal startRatio = boundedUnit(m_sampleStartRatio);
    const qreal endRatio = std::max(startRatio, boundedUnit(m_sampleEndRatio));
    const int start = std::min(count - 1, static_cast<int>(std::floor(startRatio * count)));
    const int end = std::max(start + 1,
        std::min(count, static_cast<int>(std::ceil(endRatio * count))));
    m_selected.reserve(end - start);
    for (int i = start; i < end; ++i)
        m_selected.append(pointValue(m_points[i]));
}

qreal CavaSpectrumPainter::profileWeight(qreal position) const {
    const qreal x = boundedUnit(position);
    if (m_frequencyProfile == QStringLiteral("bass"))
        return 0.44 + 1.86 * std::exp(-4.2 * x);
    if (m_frequencyProfile == QStringLiteral("warm"))
        return 1.82 - 1.08 * x;
    if (m_frequencyProfile == QStringLiteral("vocal")) {
        const qreal distance = (x - 0.46) / 0.17;
        return 0.48 + 1.72 * std::exp(-distance * distance);
    }
    if (m_frequencyProfile == QStringLiteral("treble"))
        return 0.44 + 1.86 * std::pow(x, 1.75);
    if (m_frequencyProfile == QStringLiteral("smile"))
        return 0.52 + 1.56 * std::pow(std::abs(x - 0.5) * 2.0, 1.45);
    return 1.0;
}

void CavaSpectrumPainter::applyFrequencyProfile() {
    const qreal strength = boundedUnit(m_accentStrength);
    if (m_selected.isEmpty() || strength <= 0.0 || m_frequencyProfile == QStringLiteral("flat"))
        return;

    const qreal start = boundedUnit(m_sampleStartRatio);
    const qreal end = std::max(start, boundedUnit(m_sampleEndRatio));
    const int count = m_selected.size();
    for (int i = 0; i < count; ++i) {
        const qreal domainPosition = start + (end - start)
            * (count > 1 ? static_cast<qreal>(i) / (count - 1) : 0.5);
        const qreal frequencyPosition = m_mirroredStereo
            ? std::abs(domainPosition * 2.0 - 1.0) : domainPosition;
        const qreal weight = profileWeight(frequencyPosition);
        m_selected[i] *= 1.0 + (weight - 1.0) * strength;
    }
}

QList<qreal>& CavaSpectrumPainter::frequencySmooth() {
    const int radius = std::max(0, m_smoothing);
    if (radius == 0 || m_selected.size() < 3)
        return m_selected;

    const int count = m_selected.size();
    m_smoothed.resize(count);
    int start = 0;
    int end = std::min(count - 1, radius);
    qreal sum = 0.0;
    for (int i = start; i <= end; ++i)
        sum += m_selected[i];
    for (int i = 0; i < count; ++i) {
        const int nextStart = std::max(0, i - radius);
        const int nextEnd = std::min(count - 1, i + radius);
        while (start < nextStart)
            sum -= m_selected[start++];
        while (end < nextEnd)
            sum += m_selected[++end];
        m_smoothed[i] = sum / std::max(1, end - start + 1);
    }
    return m_smoothed;
}

void CavaSpectrumPainter::barLevels(const QList<qreal>& source, int count) {
    m_levels.resize(count);
    const qreal ceiling = std::max(qreal(1.0), m_normalizationCeiling);
    const int sourceCount = static_cast<int>(source.size());
    for (int i = 0; i < count; ++i) {
        const int from = static_cast<int>(std::floor(static_cast<qreal>(i) * sourceCount / count));
        const int to = std::min(sourceCount, std::max(from + 1,
            static_cast<int>(std::ceil(static_cast<qreal>(i + 1) * sourceCount / count))));
        qreal sum = 0.0;
        qreal peak = 0.0;
        int samples = 0;
        for (int j = from; j < to; ++j) {
            const qreal value = pointValue(source[j]);
            sum += value;
            peak = std::max(peak, value);
            ++samples;
        }
        const qreal average = samples > 0 ? sum / samples : 0.0;
        m_levels[i] = boundedUnit((average * 0.72 + peak * 0.28) / ceiling);
    }
}

void CavaSpectrumPainter::waveLevels(const QList<qreal>& source, int count) {
    m_levels.resize(count);
    const qreal ceiling = std::max(qreal(1.0), m_normalizationCeiling);
    if (source.size() == 1) {
        std::fill(m_levels.begin(), m_levels.end(), boundedUnit(source.front() / ceiling));
        return;
    }
    for (int i = 0; i < count; ++i) {
        const qreal position = static_cast<qreal>(i) * (source.size() - 1) / std::max(1, count - 1);
        const int low = static_cast<int>(std::floor(position));
        const int high = std::min(static_cast<int>(source.size()) - 1, low + 1);
        const qreal fraction = position - low;
        const qreal value = source[low] * (1.0 - fraction) + source[high] * fraction;
        m_levels[i] = boundedUnit(value / ceiling);
    }
}

void CavaSpectrumPainter::makeCornerRadii(qreal width, qreal height) {
    const qreal maximum = std::max(qreal(0.0), std::min(width / 2.0, height / 2.0));
    m_cornerRadii = {
        std::clamp(m_topLeftRadius >= 0.0 ? m_topLeftRadius : m_leftRadius, qreal(0.0), maximum),
        std::clamp(m_topRightRadius >= 0.0 ? m_topRightRadius : m_rightRadius, qreal(0.0), maximum),
        std::clamp(m_bottomRightRadius >= 0.0 ? m_bottomRightRadius : m_rightRadius, qreal(0.0), maximum),
        std::clamp(m_bottomLeftRadius >= 0.0 ? m_bottomLeftRadius : m_leftRadius, qreal(0.0), maximum),
    };
}

qreal CavaSpectrumPainter::smoothstep(qreal value) {
    const qreal x = boundedUnit(value);
    return x * x * (3.0 - 2.0 * x);
}

void CavaSpectrumPainter::makeEdgeTapers() {
    const qreal scale = 0.75 + boundedUnit(m_edgeSoftness) * 1.25;
    const qreal autoStart = std::max(m_cornerRadii[0], m_cornerRadii[3]) * scale;
    const qreal autoEnd = std::max(m_cornerRadii[1], m_cornerRadii[2]) * scale;
    m_edgeTapers = {
        m_startTaper >= 0.0 ? m_startTaper : autoStart,
        m_endTaper >= 0.0 ? m_endTaper : autoEnd,
    };
}

qreal CavaSpectrumPainter::edgeMorphFactor(qreal x, qreal x0, qreal x1) const {
    qreal factor = 1.0;
    if (m_edgeTapers[0] > 0.0)
        factor *= smoothstep((x - x0) / m_edgeTapers[0]);
    if (m_edgeTapers[1] > 0.0)
        factor *= smoothstep((x1 - x) / m_edgeTapers[1]);
    return boundedUnit(factor);
}

qreal CavaSpectrumPainter::cornerInset(qreal x, qreal radius, bool fromLeft) const {
    if (!(radius > 0.0))
        return 0.0;
    qreal distance = 0.0;
    if (fromLeft) {
        if (x >= radius)
            return 0.0;
        distance = radius - std::max(qreal(0.0), x);
    } else {
        if (x <= m_cachedWidth - radius)
            return 0.0;
        distance = std::max(qreal(0.0), x - (m_cachedWidth - radius));
    }
    return radius - std::sqrt(std::max(qreal(0.0), radius * radius - distance * distance));
}

std::array<qreal, 2> CavaSpectrumPainter::surfaceBounds(qreal x) const {
    const qreal top = std::max(cornerInset(x, m_cornerRadii[0], true),
                               cornerInset(x, m_cornerRadii[1], false));
    const qreal bottomInset = std::max(cornerInset(x, m_cornerRadii[3], true),
                                       cornerInset(x, m_cornerRadii[2], false));
    return {top, std::max(top, m_cachedHeight - bottomInset)};
}

std::array<qreal, 2> CavaSpectrumPainter::peakBounds(const std::array<qreal, 2>& surface) const {
    const qreal top = surface[0];
    const qreal bottom = surface[1];
    const qreal available = std::max(qreal(0.0), bottom - top);
    const qreal curveInset = std::max(top, m_cachedHeight - bottom);
    const qreal pressure = boundedUnit(curveInset / std::max(qreal(1.0), m_cachedHeight / 2.0));
    const qreal curveHeadroom = available * boundedUnit(m_edgeSoftness) * pressure * 0.24;
    const qreal strokeHeadroom = m_visualizerType == QStringLiteral("wave")
        ? std::max(qreal(0.0), m_lineWidth / 2.0 + 0.5) : 0.0;
    const qreal center = (top + bottom) / 2.0;
    return {
        std::min(center, top + curveHeadroom + strokeHeadroom),
        std::max(center, bottom - curveHeadroom - strokeHeadroom),
    };
}

void CavaSpectrumPainter::appendRoundedClip(QPainterPath& path, qreal x, qreal y,
                                             qreal width, qreal height,
                                             const std::array<qreal, 4>& radii) {
    const qreal maximum = std::max(qreal(0.0), std::min(width / 2.0, height / 2.0));
    const qreal tl = std::clamp(radii[0], qreal(0.0), maximum);
    const qreal tr = std::clamp(radii[1], qreal(0.0), maximum);
    const qreal br = std::clamp(radii[2], qreal(0.0), maximum);
    const qreal bl = std::clamp(radii[3], qreal(0.0), maximum);
    path.moveTo(x + tl, y);
    path.lineTo(x + width - tr, y);
    if (tr > 0.0)
        path.quadTo(x + width, y, x + width, y + tr);
    else
        path.lineTo(x + width, y);
    path.lineTo(x + width, y + height - br);
    if (br > 0.0)
        path.quadTo(x + width, y + height, x + width - br, y + height);
    else
        path.lineTo(x + width, y + height);
    path.lineTo(x + bl, y + height);
    if (bl > 0.0)
        path.quadTo(x, y + height, x, y + height - bl);
    else
        path.lineTo(x, y + height);
    path.lineTo(x, y + tl);
    if (tl > 0.0)
        path.quadTo(x, y, x + tl, y);
    else
        path.lineTo(x, y);
    path.closeSubpath();
}

void CavaSpectrumPainter::clipSurface() {
    m_clipPath.clear();
    m_clipPath.setFillRule(Qt::WindingFill);
    if (!m_clipSegments.isEmpty()) {
        for (const ClipSegment& segment : m_parsedClipSegments) {
            appendRoundedClip(m_clipPath, segment.rect.x(), segment.rect.y(),
                              segment.rect.width(), segment.rect.height(), segment.radii);
        }
    } else {
        appendRoundedClip(m_clipPath, 0.0, 0.0, m_cachedWidth, m_cachedHeight, m_cornerRadii);
    }
}

qreal CavaSpectrumPainter::alphaAt(qreal x) const {
    const qreal ratio = m_cachedWidth > 0.0 ? boundedUnit(x / m_cachedWidth) : 0.0;
    return boundedUnit(m_startOpacity + (m_endOpacity - m_startOpacity) * ratio);
}

void CavaSpectrumPainter::roundedRect(QPainterPath& path, qreal x, qreal y,
                                       qreal width, qreal height, qreal radius) {
    path.clear();
    if (!(width > 0.0) || !(height > 0.0))
        return;
    const qreal r = std::max(qreal(0.0), std::min({radius, width / 2.0, height / 2.0}));
    path.moveTo(x + r, y);
    path.lineTo(x + width - r, y);
    path.quadTo(x + width, y, x + width, y + r);
    path.lineTo(x + width, y + height - r);
    path.quadTo(x + width, y + height, x + width - r, y + height);
    path.lineTo(x + r, y + height);
    path.quadTo(x, y + height, x, y + height - r);
    path.lineTo(x, y + r);
    path.quadTo(x, y, x + r, y);
    path.closeSubpath();
}

void CavaSpectrumPainter::paintBars(QPainter* painter, const QList<qreal>& source,
                                     qreal x0, qreal x1) {
    const qreal span = std::max(qreal(1.0), x1 - x0);
    const qreal pitch = std::max(qreal(3.0), m_pixelsPerBar);
    const int count = std::max(4, static_cast<int>(std::floor((span + m_barSpacing) / pitch)));
    barLevels(source, count);
    const qreal slot = span / count;
    const qreal barWidth = std::max(qreal(1.0), slot - std::max(qreal(0.0), m_barSpacing));

    for (int i = 0; i < count; ++i) {
        const qreal x = x0 + i * slot + (slot - barWidth) / 2.0;
        const qreal centerX = x + barWidth / 2.0;
        const qreal edgeFactor = edgeMorphFactor(centerX, x0, x1);
        if (edgeFactor < 0.01)
            continue;
        const auto surface = surfaceBounds(centerX);
        const auto peaks = peakBounds(surface);
        const qreal top = surface[0];
        const qreal bottom = surface[1];
        const qreal rawValue = pointValue(m_levels[i]);
        const qreal value = rawValue * edgeFactor;
        const qreal center = (top + bottom) / 2.0;
        const qreal fill = std::max(qreal(0.1), std::min(qreal(1.0), m_fillRatio));
        painter->setOpacity(0.5 + rawValue * 0.5);

        if (m_barsOrigin == QStringLiteral("top")) {
            const qreal available = std::max(qreal(0.0), peaks[1] - top);
            if (!(available > 0.0))
                continue;
            const qreal height = std::min(available,
                std::max(m_barMinHeight * edgeFactor, value * available * fill));
            roundedRect(m_shapePath, x, top, barWidth, height, m_barRadius);
        } else if (m_barsOrigin == QStringLiteral("center")) {
            const qreal available = std::max(qreal(0.0), center - peaks[0]);
            if (!(available > 0.0))
                continue;
            const qreal height = std::min(available,
                std::max(m_barMinHeight * edgeFactor, value * available * fill));
            roundedRect(m_shapePath, x, center - height, barWidth, height, m_barRadius);
        } else if (m_barsOrigin == QStringLiteral("mirror")) {
            const qreal available = std::max(qreal(0.0),
                std::min(center - peaks[0], peaks[1] - center));
            if (!(available > 0.0))
                continue;
            const qreal halfHeight = std::min(available,
                std::max(m_barMinHeight * edgeFactor, value * available * fill));
            roundedRect(m_shapePath, x, center - halfHeight - 0.5,
                        barWidth, halfHeight, m_barRadius);
            painter->fillPath(m_shapePath, m_gradientBrush);
            roundedRect(m_shapePath, x, center + 0.5,
                        barWidth, halfHeight, m_barRadius);
        } else {
            const qreal available = std::max(qreal(0.0), bottom - peaks[0]);
            if (!(available > 0.0))
                continue;
            const qreal height = std::min(available,
                std::max(m_barMinHeight * edgeFactor, value * available * fill));
            roundedRect(m_shapePath, x, bottom - height, barWidth, height, m_barRadius);
        }
        painter->fillPath(m_shapePath, m_gradientBrush);
    }
    painter->setOpacity(1.0);
}

void CavaSpectrumPainter::traceSmooth(QPainterPath& path, const QVector<QPointF>& coordinates) {
    if (coordinates.isEmpty())
        return;
    path.moveTo(coordinates.front());
    for (int i = 1; i < coordinates.size() - 1; ++i) {
        const QPointF& current = coordinates[i];
        const QPointF& next = coordinates[i + 1];
        path.quadTo(current, (current + next) / 2.0);
    }
    if (coordinates.size() > 1) {
        const QPointF& last = coordinates.back();
        path.quadTo(last, last);
    }
}

void CavaSpectrumPainter::paintWave(QPainter* painter, const QList<qreal>& source,
                                     qreal x0, qreal x1) {
    const qreal span = std::max(qreal(1.0), x1 - x0);
    const int count = std::max(2, std::min(static_cast<int>(source.size()),
        static_cast<int>(std::round(span / std::max(qreal(4.0), m_pixelsPerBar)))));
    waveLevels(source, count);
    m_primary.clear();
    m_secondary.clear();
    m_baseline.clear();
    m_primary.reserve(count);
    m_secondary.reserve(count);
    m_baseline.reserve(count);

    for (int i = 0; i < count; ++i) {
        const qreal x = x0 + static_cast<qreal>(i) * span / std::max(1, count - 1);
        const qreal edgeFactor = edgeMorphFactor(x, x0, x1);
        const auto surface = surfaceBounds(x);
        const auto peaks = peakBounds(surface);
        const qreal top = surface[0];
        const qreal bottom = surface[1];
        const qreal center = (top + bottom) / 2.0;
        const qreal value = pointValue(m_levels[i]) * edgeFactor;
        const qreal fill = std::max(qreal(0.1), std::min(qreal(1.0), m_fillRatio));

        if (m_waveMode == QStringLiteral("ribbon") || m_barsOrigin == QStringLiteral("mirror")) {
            const qreal maximum = std::max(qreal(0.0),
                std::min(center - peaks[0], peaks[1] - center));
            const qreal half = value * maximum * fill;
            m_primary.append({x, center - half});
            m_secondary.append({x, center + half});
            m_baseline.append({x, center});
        } else if (m_barsOrigin == QStringLiteral("top")) {
            const qreal maximum = std::max(qreal(0.0), peaks[1] - top);
            m_primary.append({x, top + value * maximum * fill});
            m_baseline.append({x, top});
        } else if (m_barsOrigin == QStringLiteral("center")) {
            const qreal maximum = std::max(qreal(0.0), center - peaks[0]);
            m_primary.append({x, center - value * maximum * fill});
            m_baseline.append({x, center});
        } else {
            const qreal maximum = std::max(qreal(0.0), bottom - peaks[0]);
            m_primary.append({x, bottom - value * maximum * fill});
            m_baseline.append({x, bottom});
        }
    }

    if (m_waveMode == QStringLiteral("line")) {
        m_wavePath.clear();
        traceSmooth(m_wavePath, m_primary);
        QPen pen(m_gradientBrush, std::max(qreal(1.0), m_lineWidth),
                 Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        painter->drawPath(m_wavePath);
        return;
    }

    m_wavePath.clear();
    traceSmooth(m_wavePath, m_primary);
    const QVector<QPointF>& returnPoints = m_secondary.isEmpty() ? m_baseline : m_secondary;
    for (auto it = returnPoints.crbegin(); it != returnPoints.crend(); ++it)
        m_wavePath.lineTo(*it);
    m_wavePath.closeSubpath();
    painter->fillPath(m_wavePath, m_gradientBrush);

    m_wavePath.clear();
    traceSmooth(m_wavePath, m_primary);
    painter->setOpacity(0.9);
    QPen pen(m_gradientBrush, std::max(qreal(1.0), m_lineWidth * 0.65),
             Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    painter->drawPath(m_wavePath);
    painter->setOpacity(1.0);
}

void CavaSpectrumPainter::rebuildGradient() {
    const qreal inset = std::max(qreal(0.0),
        std::min(m_cachedWidth / 2.0 - 1.0, m_edgeInset));
    m_gradientX0 = inset;
    m_gradientX1 = std::max(m_gradientX0 + 1.0, m_cachedWidth - inset);
    m_gradientBrush = QBrush(horizontalGradient(m_gradientX0, m_gradientX1, 1.0));
}

void CavaSpectrumPainter::rebuildClipSegments() {
    m_parsedClipSegments.clear();
    m_parsedClipSegments.reserve(m_clipSegments.size());
    for (const QVariant& value : m_clipSegments) {
        const QVariantMap map = value.toMap();
        const qreal width = map.value(QStringLiteral("width")).toDouble();
        const qreal height = map.value(QStringLiteral("height")).toDouble();
        if (!(width > 0.0) || !(height > 0.0))
            continue;
        ClipSegment segment;
        segment.rect = QRectF(map.value(QStringLiteral("x")).toDouble(),
                              map.value(QStringLiteral("y")).toDouble(), width, height);
        const QVariantList radii = map.value(QStringLiteral("radii")).toList();
        const int radiusCount = std::min(4, static_cast<int>(radii.size()));
        for (int i = 0; i < radiusCount; ++i)
            segment.radii[i] = radii[i].toDouble();
        m_parsedClipSegments.append(segment);
    }
}

void CavaSpectrumPainter::rebuildGeometryCaches(qreal width, qreal height) {
    m_cachedWidth = width;
    m_cachedHeight = height;
    makeCornerRadii(width, height);
    makeEdgeTapers();
    clipSurface();
    rebuildGradient();
}

void CavaSpectrumPainter::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        rebuildGeometryCaches(newGeometry.width(), newGeometry.height());
}

void CavaSpectrumPainter::paint(QPainter* painter) {
    if (!isVisible() || !(m_cachedWidth > 0.0) || !(m_cachedHeight > 0.0))
        return;

    painter->save();
    painter->setCompositionMode(QPainter::CompositionMode_Source);
    painter->fillRect(QRectF(0.0, 0.0, m_cachedWidth, m_cachedHeight), Qt::transparent);
    painter->setCompositionMode(QPainter::CompositionMode_SourceOver);
    painter->setRenderHint(QPainter::Antialiasing, true);

    selectedPoints();
    applyFrequencyProfile();
    QList<qreal>& source = frequencySmooth();
    if (m_reverseFrequency)
        std::reverse(source.begin(), source.end());
    if (source.isEmpty()) {
        painter->restore();
        return;
    }

    painter->setClipPath(m_clipPath, Qt::IntersectClip);
    if (m_visualizerType == QStringLiteral("wave"))
        paintWave(painter, source, m_gradientX0, m_gradientX1);
    else
        paintBars(painter, source, m_gradientX0, m_gradientX1);
    painter->restore();
}
