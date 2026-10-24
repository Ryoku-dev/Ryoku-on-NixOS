#include "systemgraph.hpp"

#include <QEvent>
#include <QQuickWindow>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QSGVertexColorMaterial>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <limits>
#include <utility>

namespace {

using Vertex = QSGGeometry::ColoredPoint2D;
constexpr int MaxSubdivisions = 4;
// A curve segment is subdivided to roughly this many pixels; dense sampling
// already lands a sample under every pixel, so the buffers follow the width.
constexpr float SubdivisionPixels = 3.0f;
constexpr int MaxIntervals = SystemMonitor::HistoryCapacity - 1;
constexpr int FillVerticesPerStep = 6;
constexpr int LineVerticesPerStep = 18;
constexpr int PointSegments = 12;
constexpr int PointVertices = PointSegments * 3;
constexpr int GridLines = 7;
constexpr int GridVertices = GridLines * 6;
// The newest sample eases in over exactly one sample period, so the curve's
// right end is always in motion and never steps when the next sample lands.
constexpr qint64 ValueBlendMilliseconds = SystemMonitor::SamplePeriodMs;
constexpr float RateScaleFloor = 1024.0f * 1024.0f;
// The rate axis follows the window maximum with this time constant so a burst
// entering or leaving the window rescales the sparkline smoothly.
constexpr float RateScaleSeconds = 0.45f;

qint64 monotonicMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

class ColorNode final : public QSGGeometryNode {
public:
    explicit ColorNode(int vertexCapacity) {
        buffer = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), vertexCapacity);
        buffer->setDrawingMode(QSGGeometry::DrawTriangles);
        buffer->setVertexDataPattern(QSGGeometry::DynamicPattern);
        auto* vertexMaterial = new QSGVertexColorMaterial;
        vertexMaterial->setFlag(QSGMaterial::Blending);
        setGeometry(buffer);
        setMaterial(vertexMaterial);
        setFlag(QSGNode::OwnsGeometry);
        setFlag(QSGNode::OwnsMaterial);
        clear();
    }

    void clear() {
        Vertex* vertices = buffer->vertexDataAsColoredPoint2D();
        for (int i = 0; i < buffer->vertexCount(); ++i)
            vertices[i].set(0.0f, 0.0f, 0, 0, 0, 0);
        usedVertices = 0;
        markDirty(QSGNode::DirtyGeometry);
    }

    void ensureCapacity(int vertexCount) {
        if (buffer->vertexCount() >= vertexCount)
            return;
        buffer->allocate(vertexCount);
        clear();
    }

    QSGGeometry* buffer = nullptr;
    int usedVertices = 0;
};

struct GraphNode final : QSGNode {
    GraphNode() {
        grid = new ColorNode(GridVertices);
        appendChildNode(grid);
        fillGroup = new QSGNode;
        lineGroup = new QSGNode;
        pointGroup = new QSGNode;
        appendChildNode(fillGroup);
        appendChildNode(lineGroup);
        appendChildNode(pointGroup);
    }

    void ensureTraceCount(int count) {
        while (fills.size() < count) {
            auto* fill = new ColorNode(FillVerticesPerStep);
            auto* line = new ColorNode(LineVerticesPerStep);
            auto* point = new ColorNode(PointVertices);
            fillGroup->appendChildNode(fill);
            lineGroup->appendChildNode(line);
            pointGroup->appendChildNode(point);
            fills.append(fill);
            lines.append(line);
            points.append(point);
        }
        while (fills.size() > count) {
            ColorNode* fill = fills.takeLast();
            ColorNode* line = lines.takeLast();
            ColorNode* point = points.takeLast();
            fillGroup->removeChildNode(fill);
            lineGroup->removeChildNode(line);
            pointGroup->removeChildNode(point);
            delete fill;
            delete line;
            delete point;
        }
    }

    ColorNode* grid = nullptr;
    QSGNode* fillGroup = nullptr;
    QSGNode* lineGroup = nullptr;
    QSGNode* pointGroup = nullptr;
    QVector<ColorNode*> fills;
    QVector<ColorNode*> lines;
    QVector<ColorNode*> points;
    float gridWidth = -1.0f;
    float gridHeight = -1.0f;
    QColor gridColor;
    bool gridVisible = false;
};

struct Point {
    float x = 0.0f;
    float y = 0.0f;
};

struct Rgba {
    unsigned char r = 0;
    unsigned char g = 0;
    unsigned char b = 0;
    unsigned char a = 0;
};

Rgba premultiplied(const QColor& color, float opacity) {
    const float alpha = std::clamp(color.alphaF() * opacity, 0.0f, 1.0f);
    return {
        static_cast<unsigned char>(std::lround(color.redF() * alpha * 255.0f)),
        static_cast<unsigned char>(std::lround(color.greenF() * alpha * 255.0f)),
        static_cast<unsigned char>(std::lround(color.blueF() * alpha * 255.0f)),
        static_cast<unsigned char>(std::lround(alpha * 255.0f)),
    };
}

void setVertex(Vertex& vertex, const Point& point, const Rgba& color) {
    vertex.set(point.x, point.y, color.r, color.g, color.b, color.a);
}

void appendQuad(Vertex* vertices, int& offset, const Point& a, const Point& b, const Point& c, const Point& d,
                const Rgba& ca, const Rgba& cb, const Rgba& cc, const Rgba& cd) {
    setVertex(vertices[offset++], a, ca);
    setVertex(vertices[offset++], b, cb);
    setVertex(vertices[offset++], c, cc);
    setVertex(vertices[offset++], a, ca);
    setVertex(vertices[offset++], c, cc);
    setVertex(vertices[offset++], d, cd);
}

void clearRemainder(ColorNode* node, int offset) {
    Vertex* vertices = node->buffer->vertexDataAsColoredPoint2D();
    for (int i = offset; i < node->usedVertices; ++i)
        vertices[i].set(0.0f, 0.0f, 0, 0, 0, 0);
    node->usedVertices = offset;
    node->markDirty(QSGNode::DirtyGeometry);
}

void appendAntialiasedLine(Vertex* vertices, int& offset, const Point& from, const Point& to, float width,
                           const Rgba& transparent, const Rgba& solid) {
    const float dx = to.x - from.x;
    const float dy = to.y - from.y;
    const float length = std::hypot(dx, dy);
    if (length < 0.001f)
        return;
    const float nx = -dy / length;
    const float ny = dx / length;
    const float inner = std::max(0.5f, width * 0.5f);
    const float outer = inner + 1.25f;

    const Point fromOuterLow{from.x - nx * outer, from.y - ny * outer};
    const Point fromInnerLow{from.x - nx * inner, from.y - ny * inner};
    const Point fromInnerHigh{from.x + nx * inner, from.y + ny * inner};
    const Point fromOuterHigh{from.x + nx * outer, from.y + ny * outer};
    const Point toOuterLow{to.x - nx * outer, to.y - ny * outer};
    const Point toInnerLow{to.x - nx * inner, to.y - ny * inner};
    const Point toInnerHigh{to.x + nx * inner, to.y + ny * inner};
    const Point toOuterHigh{to.x + nx * outer, to.y + ny * outer};

    appendQuad(vertices, offset, fromOuterLow, toOuterLow, toInnerLow, fromInnerLow,
               transparent, transparent, solid, solid);
    appendQuad(vertices, offset, fromInnerLow, toInnerLow, toInnerHigh, fromInnerHigh,
               solid, solid, solid, solid);
    appendQuad(vertices, offset, fromInnerHigh, toInnerHigh, toOuterHigh, fromOuterHigh,
               solid, solid, transparent, transparent);
}

void appendFill(Vertex* vertices, int& offset, const Point& from, const Point& to, float baseline,
                const Rgba& top, const Rgba& bottom) {
    const Point fromBase{from.x, baseline};
    const Point toBase{to.x, baseline};
    appendQuad(vertices, offset, from, to, toBase, fromBase, top, top, bottom, bottom);
}

float catmullRom(float p0, float p1, float p2, float p3, float t) {
    const float t2 = t * t;
    const float t3 = t2 * t;
    return 0.5f * ((2.0f * p1) + (-p0 + p2) * t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2
                   + (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3);
}

float smoothStep(float t) {
    t = std::clamp(t, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

void buildGrid(ColorNode* node, float width, float height, const QColor& color) {
    Vertex* vertices = node->buffer->vertexDataAsColoredPoint2D();
    int offset = 0;
    const Rgba grid = premultiplied(color, 0.45f);
    const float thickness = 0.65f;
    const std::array<float, 3> vertical{0.25f, 0.5f, 0.75f};
    const std::array<float, 4> horizontal{0.2f, 0.4f, 0.6f, 0.8f};
    for (float fraction : vertical) {
        const float x = width * fraction;
        appendQuad(vertices, offset, {x - thickness, 0.0f}, {x + thickness, 0.0f},
                   {x + thickness, height}, {x - thickness, height}, grid, grid, grid, grid);
    }
    for (float fraction : horizontal) {
        const float y = height * fraction;
        appendQuad(vertices, offset, {0.0f, y - thickness}, {width, y - thickness},
                   {width, y + thickness}, {0.0f, y + thickness}, grid, grid, grid, grid);
    }
    clearRemainder(node, offset);
}

void buildPoint(ColorNode* node, const Point& center, float radius, const QColor& color, bool visible) {
    Vertex* vertices = node->buffer->vertexDataAsColoredPoint2D();
    int offset = 0;
    if (visible) {
        const Rgba centerColor = premultiplied(color, 1.0f);
        const Rgba edgeColor = premultiplied(color, 0.0f);
        constexpr float Tau = 6.2831853071795864769f;
        for (int segment = 0; segment < PointSegments; ++segment) {
            const float a = Tau * static_cast<float>(segment) / static_cast<float>(PointSegments);
            const float b = Tau * static_cast<float>(segment + 1) / static_cast<float>(PointSegments);
            setVertex(vertices[offset++], center, centerColor);
            setVertex(vertices[offset++], {center.x + std::cos(a) * radius, center.y + std::sin(a) * radius}, edgeColor);
            setVertex(vertices[offset++], {center.x + std::cos(b) * radius, center.y + std::sin(b) * radius}, edgeColor);
        }
    }
    clearRemainder(node, offset);
}

bool isRateChannel(const QString& channel) {
    return channel == QStringLiteral("netRx") || channel == QStringLiteral("netTx")
        || channel == QStringLiteral("diskRead") || channel == QStringLiteral("diskWrite");
}

bool isFixedChannel(const QString& channel) {
    return channel == QStringLiteral("cpu") || channel == QStringLiteral("memory") || channel == QStringLiteral("gpu")
        || channel == QStringLiteral("cpuTemp") || channel == QStringLiteral("gpuTemp");
}

} // namespace

SystemGraph::SystemGraph(QQuickItem* parent)
    : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
    m_frameTimer.setTimerType(Qt::PreciseTimer);
    m_frameTimer.setInterval(16);
    connect(&m_frameTimer, &QTimer::timeout, this, &SystemGraph::requestAnimationFrame);
    connect(this, &QQuickItem::windowChanged, this, &SystemGraph::handleWindowChanged);
    if (window())
        handleWindowChanged(window());
}

SystemGraph::~SystemGraph() {
    m_frameTimer.stop();
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
}

void SystemGraph::setSource(SystemMonitor* source) {
    if (m_source == source)
        return;
    disconnect(m_samplesConnection);
    disconnect(m_sourceDestroyedConnection);
    m_source = source;
    if (source) {
        m_samplesConnection = connect(source, &SystemMonitor::samplesChanged, this, &SystemGraph::syncFromSource);
        m_sourceDestroyedConnection = connect(source, &QObject::destroyed, this, [this] {
            m_source = nullptr;
            m_sampleCount = 0;
            emit sourceChanged();
            emit sampleCountChanged();
            updateAnimationState();
            markVisualDirty();
        });
    }
    syncFromSource();
    emit sourceChanged();
}

void SystemGraph::setActive(bool active) {
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
    updateAnimationState();
    update();
}

void SystemGraph::setAnimated(bool animated) {
    if (m_animated == animated)
        return;
    m_animated = animated;
    emit animatedChanged();
    updateAnimationState();
    markVisualDirty();
}

void SystemGraph::setChannels(const QStringList& channels) {
    if (m_channels == channels)
        return;
    m_channels = channels;
    syncFromSource();
    emit channelsChanged();
}

void SystemGraph::setColors(const QVariantList& colors) {
    if (m_colors == colors)
        return;
    m_colors = colors;
    emit colorsChanged();
    markVisualDirty();
}

void SystemGraph::setFill(bool fill) {
    if (m_fill == fill)
        return;
    m_fill = fill;
    emit fillChanged();
    markVisualDirty();
}

void SystemGraph::setShowGrid(bool showGrid) {
    if (m_showGrid == showGrid)
        return;
    m_showGrid = showGrid;
    emit showGridChanged();
    markVisualDirty();
}

void SystemGraph::setDetailPoints(bool detailPoints) {
    if (m_detailPoints == detailPoints)
        return;
    m_detailPoints = detailPoints;
    emit detailPointsChanged();
    markVisualDirty();
}

void SystemGraph::setGridColor(const QColor& color) {
    if (m_gridColor == color)
        return;
    m_gridColor = color;
    emit gridColorChanged();
    markVisualDirty();
}

void SystemGraph::setLineWidth(qreal width) {
    width = std::clamp(width, 0.5, 12.0);
    if (qFuzzyCompare(m_lineWidth, width))
        return;
    m_lineWidth = width;
    emit lineWidthChanged();
    markVisualDirty();
}

int SystemGraph::windowSeconds() const {
    return SystemMonitor::WindowSeconds;
}

QColor SystemGraph::colorForTrace(int trace) const {
    if (m_colors.isEmpty())
        return Qt::white;
    const QVariant& value = m_colors[std::min<qsizetype>(trace, m_colors.size() - 1)];
    const QColor color = value.value<QColor>();
    return color.isValid() ? color : QColor(Qt::white);
}

void SystemGraph::syncFromSource() {
    const int previousCount = m_sampleCount;
    m_sampleCount = m_source ? m_source->m_historyCount : 0;
    m_traces.resize(m_channels.size());
    for (qsizetype trace = 0; trace < m_channels.size(); ++trace)
        m_traces[trace].channel = m_channels[trace];

    for (int index = 0; index < m_sampleCount; ++index) {
        const SystemMonitor::HistorySample& sample = m_source->historyAtOldest(index);
        m_sampleTimes[index] = sample.monotonicMs;
        for (TraceSamples& trace : m_traces) {
            float value = std::numeric_limits<float>::quiet_NaN();
            if (trace.channel == QStringLiteral("cpu"))
                value = sample.cpu;
            else if (trace.channel == QStringLiteral("memory"))
                value = sample.memory;
            else if (trace.channel == QStringLiteral("gpu"))
                value = sample.gpu;
            else if (trace.channel == QStringLiteral("netRx"))
                value = sample.netRx;
            else if (trace.channel == QStringLiteral("netTx"))
                value = sample.netTx;
            else if (trace.channel == QStringLiteral("diskRead"))
                value = sample.diskRead;
            else if (trace.channel == QStringLiteral("diskWrite"))
                value = sample.diskWrite;
            else if (trace.channel == QStringLiteral("cpuTemp"))
                value = sample.cpuTemp;
            else if (trace.channel == QStringLiteral("gpuTemp"))
                value = sample.gpuTemp;
            trace.values[index] = value;
        }
    }
    if (previousCount != m_sampleCount)
        emit sampleCountChanged();
    updateAnimationState();
    markVisualDirty();
}

void SystemGraph::handleWindowChanged(QQuickWindow* window) {
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
    m_observedWindow = window;
    if (window)
        window->installEventFilter(this);
    updateAnimationState();
    markVisualDirty();
}

void SystemGraph::updateAnimationState() {
    const bool shouldAnimate = m_active && m_animated && m_sampleCount > 0 && isVisible() && m_observedWindow
        && m_observedWindow->isVisible() && m_observedWindow->isExposed();
    if (shouldAnimate) {
        if (!m_frameTimer.isActive())
            m_frameTimer.start();
    } else {
        m_frameTimer.stop();
    }
}

void SystemGraph::requestAnimationFrame() {
    if (!m_active || !m_animated || m_sampleCount == 0 || !isVisible() || !m_observedWindow
        || !m_observedWindow->isVisible() || !m_observedWindow->isExposed()) {
        m_frameTimer.stop();
        return;
    }
    update();
}

void SystemGraph::markVisualDirty() {
    if (m_active && isVisible())
        update();
}

void SystemGraph::itemChange(ItemChange change, const ItemChangeData& data) {
    QQuickItem::itemChange(change, data);
    if (change == ItemVisibleHasChanged) {
        updateAnimationState();
        if (data.boolValue)
            markVisualDirty();
    }
}

bool SystemGraph::eventFilter(QObject* watched, QEvent* event) {
    if (watched == m_observedWindow
        && (event->type() == QEvent::Expose || event->type() == QEvent::Show || event->type() == QEvent::Hide
            || event->type() == QEvent::PlatformSurface)) {
        updateAnimationState();
        if (m_active && m_observedWindow && m_observedWindow->isExposed())
            update();
    }
    return QQuickItem::eventFilter(watched, event);
}

QSGNode* SystemGraph::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) {
    if (!m_active || !isVisible() || !window() || !window()->isExposed() || width() <= 0.0 || height() <= 0.0) {
        delete oldNode;
        return nullptr;
    }

    auto* root = static_cast<GraphNode*>(oldNode);
    if (!root)
        root = new GraphNode;
    root->ensureTraceCount(m_traces.size());
    m_frameCount.fetch_add(1, std::memory_order_relaxed);

    const float graphWidth = static_cast<float>(width());
    const float graphHeight = static_cast<float>(height());
    if (root->gridWidth != graphWidth || root->gridHeight != graphHeight || root->gridColor != m_gridColor
        || root->gridVisible != m_showGrid) {
        if (m_showGrid)
            buildGrid(root->grid, graphWidth, graphHeight, m_gridColor);
        else
            root->grid->clear();
        root->gridWidth = graphWidth;
        root->gridHeight = graphHeight;
        root->gridColor = m_gridColor;
        root->gridVisible = m_showGrid;
    }

    const float plotWindowMilliseconds = static_cast<float>(windowSeconds() * 1000);
    const qint64 now = monotonicMilliseconds();
    float rateTarget = RateScaleFloor;
    for (const TraceSamples& trace : std::as_const(m_traces)) {
        if (!isRateChannel(trace.channel))
            continue;
        for (int index = 0; index < m_sampleCount; ++index) {
            const qint64 age = std::max<qint64>(0, now - m_sampleTimes[index]);
            if (age <= plotWindowMilliseconds && std::isfinite(trace.values[index]))
                rateTarget = std::max(rateTarget, trace.values[index]);
        }
    }
    if (!m_animated || m_rateScale <= 0.0f || m_lastFrameMs <= 0) {
        m_rateScale = rateTarget;
    } else {
        const float elapsed = static_cast<float>(now - m_lastFrameMs) / 1000.0f;
        const float blend = 1.0f - std::exp(-elapsed / RateScaleSeconds);
        m_rateScale += (rateTarget - m_rateScale) * blend;
        if (std::abs(rateTarget - m_rateScale) < rateTarget * 0.002f)
            m_rateScale = rateTarget;
    }
    m_lastFrameMs = now;
    const float rateScale = m_rateScale;

    const float intervalPixels = m_sampleCount > 1
        ? graphWidth * static_cast<float>(SystemMonitor::SamplePeriodMs) / plotWindowMilliseconds
        : graphWidth;
    const int subdivisions = std::clamp(static_cast<int>(std::ceil(intervalPixels / SubdivisionPixels)), 1, MaxSubdivisions);
    const int steps = std::max(1, std::min(m_sampleCount - 1, MaxIntervals)) * subdivisions;
    for (qsizetype traceIndex = 0; traceIndex < m_traces.size(); ++traceIndex) {
        const TraceSamples& trace = m_traces[traceIndex];
        const QColor color = colorForTrace(traceIndex);
        const Rgba lineTransparent = premultiplied(color, 0.0f);
        const Rgba lineSolid = premultiplied(color, 0.96f);
        const Rgba fillTop = premultiplied(color, 0.15f);
        const Rgba fillBottom = premultiplied(color, 0.015f);
        const float pointRadius = std::max(3.0f, static_cast<float>(m_lineWidth) * 2.1f);
        const float margin = m_detailPoints ? pointRadius : std::max(1.5f, static_cast<float>(m_lineWidth));
        const float plotWidth = std::max(0.0f, graphWidth - margin * 2.0f);
        const float plotHeight = std::max(0.0f, graphHeight - margin * 2.0f);
        ColorNode* fillNode = root->fills[traceIndex];
        ColorNode* lineNode = root->lines[traceIndex];
        fillNode->ensureCapacity(steps * FillVerticesPerStep);
        lineNode->ensureCapacity(steps * LineVerticesPerStep);
        Vertex* fillVertices = fillNode->buffer->vertexDataAsColoredPoint2D();
        Vertex* lineVertices = lineNode->buffer->vertexDataAsColoredPoint2D();
        int fillOffset = 0;
        int lineOffset = 0;

        const float scale = isFixedChannel(trace.channel) ? 100.0f : (isRateChannel(trace.channel) ? rateScale : 0.0f);
        const auto normalizedValue = [&trace, scale](int index) {
            const float value = trace.values[index];
            if (scale <= 0.0f || !std::isfinite(value))
                return std::numeric_limits<float>::quiet_NaN();
            return std::clamp(value / scale * 100.0f, 0.0f, 100.0f);
        };
        const auto valueAt = [&](int index) {
            float value = normalizedValue(index);
            if (m_animated && index == m_sampleCount - 1 && index > 0 && std::isfinite(value)) {
                const float previous = normalizedValue(index - 1);
                if (std::isfinite(previous)) {
                    const float progress = static_cast<float>(now - m_sampleTimes[index])
                        / static_cast<float>(ValueBlendMilliseconds);
                    value = previous + (value - previous) * smoothStep(progress);
                }
            }
            return value;
        };
        const auto pointFor = [&](int index, float value) {
            const qint64 age = std::max<qint64>(0, now - m_sampleTimes[index]);
            const float x = margin + plotWidth * (1.0f - static_cast<float>(age) / plotWindowMilliseconds);
            const float y = margin + plotHeight * (1.0f - std::clamp(value, 0.0f, 100.0f) / 100.0f);
            return Point{x, y};
        };

        for (int index = 0; index + 1 < m_sampleCount; ++index) {
            const float p1Value = valueAt(index);
            const float p2Value = valueAt(index + 1);
            if (!std::isfinite(p1Value) || !std::isfinite(p2Value))
                continue;
            const float previousValue = index > 0 ? valueAt(index - 1) : p1Value;
            const float followingValue = index + 2 < m_sampleCount ? valueAt(index + 2) : p2Value;
            const float p0Value = std::isfinite(previousValue) ? previousValue : p1Value;
            const float p3Value = std::isfinite(followingValue) ? followingValue : p2Value;
            const Point p1 = pointFor(index, p1Value);
            const Point p2 = pointFor(index + 1, p2Value);
            if (p2.x < 0.0f)
                continue;

            // The oldest samples lie beyond the left edge; the step that crosses
            // it starts where the curve meets x = 0, so the trace runs off the
            // graph smoothly instead of ending on a point that snaps each sample.
            Point previous = p1;
            for (int subdivision = 1; subdivision <= subdivisions; ++subdivision) {
                const float t = static_cast<float>(subdivision) / static_cast<float>(subdivisions);
                Point current;
                current.x = p1.x + (p2.x - p1.x) * t;
                const float value = std::clamp(catmullRom(p0Value, p1Value, p2Value, p3Value, t), 0.0f, 100.0f);
                current.y = margin + plotHeight * (1.0f - value / 100.0f);
                if (current.x > 0.0f) {
                    Point from = previous;
                    if (from.x < 0.0f) {
                        const float crossing = -previous.x / (current.x - previous.x);
                        from = Point{0.0f, previous.y + (current.y - previous.y) * crossing};
                    }
                    if (m_fill)
                        appendFill(fillVertices, fillOffset, from, current, graphHeight - margin, fillTop, fillBottom);
                    appendAntialiasedLine(lineVertices, lineOffset, from, current, static_cast<float>(m_lineWidth),
                                          lineTransparent, lineSolid);
                }
                previous = current;
            }
        }
        clearRemainder(fillNode, fillOffset);
        clearRemainder(lineNode, lineOffset);

        Point newest;
        bool newestVisible = false;
        if (m_detailPoints && m_sampleCount > 0) {
            const float newestValue = valueAt(m_sampleCount - 1);
            if (std::isfinite(newestValue)) {
                newest = pointFor(m_sampleCount - 1, newestValue);
                newestVisible = newest.x >= 0.0f && newest.x <= graphWidth;
            }
        }
        buildPoint(root->points[traceIndex], newest, pointRadius, color, newestVisible);
    }

    return root;
}
