#include "borderbeam.hpp"
#include "bordermaterial.hpp"

#include <QEvent>
#include <QQuickWindow>
#include <QSGGeometry>
#include <QSGGeometryNode>

#include <algorithm>
#include <cmath>

namespace {

constexpr qreal FadeMilliseconds = 300.0;

qreal smoothstep(qreal value) {
    const qreal t = std::clamp(value, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

} // namespace

BorderBeam::BorderBeam(QQuickItem* parent)
    : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
    setAcceptedMouseButtons(Qt::NoButton);
    m_phaseClock.start();
    m_frameTimer.setInterval(16);
    m_frameTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_frameTimer, &QTimer::timeout, this, &BorderBeam::requestAnimationFrame);
    connect(this, &QQuickItem::windowChanged, this, &BorderBeam::handleWindowChanged);
    if (window())
        handleWindowChanged(window());
}

BorderBeam::~BorderBeam() {
    m_frameTimer.stop();
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
}

qreal BorderBeam::defaultDuration(BeamMode mode) {
    switch (mode) {
    case BeamMode::Line:
        return 3.1;
    case BeamMode::Rotate:
        return 1.96;
    case BeamMode::Pulse:
        return 2.3;
    }
    return 3.1;
}

void BorderBeam::setMode(const QString& mode) {
    BeamMode nextMode = BeamMode::Line;
    QString canonical = QStringLiteral("line");
    if (mode == QStringLiteral("rotate")) {
        nextMode = BeamMode::Rotate;
        canonical = QStringLiteral("rotate");
    } else if (mode == QStringLiteral("pulse")) {
        nextMode = BeamMode::Pulse;
        canonical = QStringLiteral("pulse");
    }
    if (m_mode == nextMode && m_modeName == canonical)
        return;
    m_mode = nextMode;
    m_modeName = canonical;
    emit modeChanged();
    if (!m_durationExplicit) {
        m_duration = defaultDuration(m_mode);
        emit durationChanged();
    }
    updatePhase();
    update();
}

void BorderBeam::setRadius(qreal radius) {
    const qreal bounded = std::max(radius, 0.0);
    if (qFuzzyCompare(m_radius, bounded))
        return;
    m_radius = bounded;
    emit radiusChanged();
    update();
}

void BorderBeam::setStrokeWidth(qreal width) {
    const qreal bounded = std::max(width, 0.0);
    if (qFuzzyCompare(m_strokeWidth, bounded))
        return;
    m_strokeWidth = bounded;
    emit strokeWidthChanged();
    update();
}

void BorderBeam::setColor(const QColor& color) {
    if (m_color == color)
        return;
    m_color = color;
    emit colorChanged();
    update();
}

void BorderBeam::setStrength(qreal strength) {
    const qreal bounded = std::clamp(strength, 0.0, 1.0);
    if (qFuzzyCompare(m_strength, bounded))
        return;
    m_strength = bounded;
    emit strengthChanged();
    update();
}

void BorderBeam::setDuration(qreal duration) {
    const qreal bounded = std::max(duration, 0.001);
    if (qFuzzyCompare(m_duration, bounded) && m_durationExplicit)
        return;
    m_duration = bounded;
    m_durationExplicit = true;
    emit durationChanged();
    updatePhase();
    update();
}

void BorderBeam::setActive(bool active) {
    if (m_active == active)
        return;
    advanceFade();
    m_active = active;
    m_fadeFrom = m_activeFade;
    m_fadeTarget = active ? 1.0 : 0.0;
    m_fadeClock.restart();
    emit activeChanged();
    updatePhase();
    updateAnimationState();
    update();
}

void BorderBeam::setBlur(qreal blur) {
    const qreal bounded = std::max(blur, 0.0);
    if (qFuzzyCompare(m_blur, bounded))
        return;
    m_blur = bounded;
    emit blurChanged();
    update();
}

bool BorderBeam::advanceFade() {
    if (!m_fadeClock.isValid()) {
        m_activeFade = m_fadeTarget;
        return true;
    }
    const qreal progress = std::clamp(m_fadeClock.elapsed() / FadeMilliseconds, 0.0, 1.0);
    const qreal eased = smoothstep(progress);
    m_activeFade = m_fadeFrom + (m_fadeTarget - m_fadeFrom) * eased;
    if (progress >= 1.0) {
        m_activeFade = m_fadeTarget;
        m_fadeClock.invalidate();
        return true;
    }
    return false;
}

void BorderBeam::updatePhase() {
    if (!m_phaseClock.isValid())
        m_phaseClock.start();
    const qreal seconds = m_phaseClock.elapsed() * 0.001;
    m_phase = std::fmod(seconds / std::max(m_duration, 0.001), 1.0);
}

void BorderBeam::handleWindowChanged(QQuickWindow* window) {
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
    m_observedWindow = window;
    if (m_observedWindow)
        m_observedWindow->installEventFilter(this);
    advanceFade();
    updateAnimationState();
    update();
}

void BorderBeam::updateAnimationState() {
    advanceFade();
    const bool fading = m_fadeClock.isValid();
    const bool shouldRun = (m_active || fading || m_activeFade > 0.0) && isVisible() && m_observedWindow
        && m_observedWindow->isVisible() && m_observedWindow->isExposed();
    if (shouldRun) {
        if (!m_frameTimer.isActive())
            m_frameTimer.start();
    } else {
        m_frameTimer.stop();
    }
}

void BorderBeam::requestAnimationFrame() {
    if (!isVisible() || !m_observedWindow || !m_observedWindow->isVisible() || !m_observedWindow->isExposed()) {
        m_frameTimer.stop();
        return;
    }
    const bool fadeFinished = advanceFade();
    updatePhase();
    update();
    if (!m_active && fadeFinished && m_activeFade <= 0.0)
        m_frameTimer.stop();
}

void BorderBeam::itemChange(ItemChange change, const ItemChangeData& data) {
    QQuickItem::itemChange(change, data);
    if (change == ItemVisibleHasChanged) {
        advanceFade();
        updateAnimationState();
        if (data.boolValue)
            update();
    }
}

bool BorderBeam::eventFilter(QObject* watched, QEvent* event) {
    if (watched == m_observedWindow
        && (event->type() == QEvent::Expose || event->type() == QEvent::Show || event->type() == QEvent::Hide
            || event->type() == QEvent::PlatformSurface)) {
        advanceFade();
        updatePhase();
        updateAnimationState();
        if (isVisible() && m_observedWindow && m_observedWindow->isExposed())
            update();
    }
    return QQuickItem::eventFilter(watched, event);
}

QSGNode* BorderBeam::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) {
    if (width() <= 0.0 || height() <= 0.0 || m_activeFade <= 0.001 || m_strength <= 0.0 || m_color.alpha() == 0) {
        delete oldNode;
        return nullptr;
    }

    auto* node = static_cast<QSGGeometryNode*>(oldNode);
    if (!node) {
        node = new QSGGeometryNode;
        auto* geometry = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 4);
        geometry->setDrawingMode(QSGGeometry::DrawTriangleStrip);
        geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);

        auto* material = new BorderMaterial;
        material->setFlag(QSGMaterial::Blending);
        node->setMaterial(material);
        node->setFlag(QSGNode::OwnsMaterial);
    }

    auto* vertices = node->geometry()->vertexDataAsTexturedPoint2D();
    const float itemWidth = static_cast<float>(width());
    const float itemHeight = static_cast<float>(height());
    vertices[0].set(0.0f, 0.0f, 0.0f, 0.0f);
    vertices[1].set(itemWidth, 0.0f, 1.0f, 0.0f);
    vertices[2].set(0.0f, itemHeight, 0.0f, 1.0f);
    vertices[3].set(itemWidth, itemHeight, 1.0f, 1.0f);
    node->markDirty(QSGNode::DirtyGeometry);

    auto* material = static_cast<BorderMaterial*>(node->material());
    material->size[0] = itemWidth;
    material->size[1] = itemHeight;
    material->radius = static_cast<float>(m_radius);
    material->strokeWidth = static_cast<float>(m_strokeWidth);
    material->blur = static_cast<float>(m_blur);
    material->strength = static_cast<float>(m_strength);
    material->color = m_color;
    material->phase = static_cast<float>(m_phase);
    material->activeFade = static_cast<float>(m_activeFade);
    material->mode = static_cast<int>(m_mode);
    node->markDirty(QSGNode::DirtyMaterial);
    return node;
}
