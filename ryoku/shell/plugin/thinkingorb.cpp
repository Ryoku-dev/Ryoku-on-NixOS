#include "thinkingorb.hpp"

#include <QEvent>
#include <QPainter>
#include <QQuickWindow>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <utility>

namespace {

constexpr qreal Pi = 3.14159265358979323846;
constexpr qreal Tau = Pi * 2.0;
constexpr qint64 CrossfadeMilliseconds = 240;
constexpr qint64 MinimumFrameIntervalMilliseconds = 15;
constexpr qreal SolvingCycleSeconds = 3.0;

qreal clamp01(qreal value) {
    return std::clamp(value, 0.0, 1.0);
}

qreal smoothstep(qreal value) {
    const qreal t = clamp01(value);
    return t * t * (3.0 - 2.0 * t);
}

qreal wrapAngle(qreal angle) {
    return angle - Tau * std::floor((angle + Pi) / Tau);
}

qreal signedPower(qreal value, qreal power) {
    return std::copysign(std::pow(std::abs(value), power), value);
}

qreal noise(int seed) {
    const qreal value = std::sin(static_cast<qreal>(seed) * 91.3458 + 17.234) * 43758.5453;
    return value - std::floor(value);
}

QPointF polygonPoint(const QPointF* vertices, int count, qreal unit) {
    const qreal scaled = (unit - std::floor(unit)) * count;
    const int edge = std::min(static_cast<int>(scaled), count - 1);
    const qreal along = scaled - edge;
    return vertices[edge] * (1.0 - along) + vertices[(edge + 1) % count] * along;
}

} // namespace

ThinkingOrb::ThinkingOrb(QQuickItem* parent)
    : QQuickPaintedItem(parent)
    , m_stateStartedAt(monotonicMilliseconds()) {
    setAntialiasing(true);
    m_frameDelayTimer.setSingleShot(true);
    m_frameDelayTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_frameDelayTimer, &QTimer::timeout, this, &ThinkingOrb::requestAnimationFrame);
    connect(this, &QQuickItem::windowChanged, this, &ThinkingOrb::handleWindowChanged);
    resizeFrames();
    if (window())
        handleWindowChanged(window());
}

ThinkingOrb::~ThinkingOrb() {
    m_frameDelayTimer.stop();
    QObject::disconnect(m_afterAnimatingConnection);
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
}

ThinkingOrb::OrbState ThinkingOrb::stateFromName(const QString& state, QString* canonicalName) {
    struct StateName {
        const char* name;
        OrbState state;
    };
    static constexpr std::array states{
        StateName{"breathing", OrbState::Breathing},
        StateName{"listening", OrbState::Listening},
        StateName{"connecting", OrbState::Connecting},
        StateName{"searching", OrbState::Searching},
        StateName{"working", OrbState::Working},
        StateName{"solving", OrbState::Solving},
        StateName{"composing", OrbState::Composing},
        StateName{"weaving", OrbState::Weaving},
        StateName{"shaping", OrbState::Shaping},
    };
    for (const auto& entry : states) {
        if (state == QLatin1String(entry.name)) {
            if (canonicalName)
                *canonicalName = state;
            return entry.state;
        }
    }
    if (canonicalName)
        *canonicalName = QStringLiteral("breathing");
    return OrbState::Breathing;
}

qint64 ThinkingOrb::monotonicMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

void ThinkingOrb::setState(const QString& state) {
    QString canonical;
    const OrbState nextState = stateFromName(state, &canonical);
    if (m_state == nextState && m_stateName == canonical)
        return;

    qreal unusedLinkAlpha = 0.0;
    if (m_havePaintedFrame) {
        m_previousFrame = m_lastPaintedFrame;
        m_previousLinkAlpha = m_lastLinkAlpha;
    } else {
        generateFrame(m_state, representativePhase(), m_previousFrame, unusedLinkAlpha);
        m_previousLinkAlpha = unusedLinkAlpha;
    }

    const qint64 now = monotonicMilliseconds();
    m_state = nextState;
    m_stateName = canonical;
    m_stateStartedAt = now;
    m_crossfadeStartedAt = now;
    emit stateChanged();
    update();
    updateAnimationState();
}

void ThinkingOrb::setPreset(const QString& preset) {
    const QString canonical = preset == QStringLiteral("inline") ? QStringLiteral("inline") : QStringLiteral("avatar");
    if (m_preset == canonical)
        return;
    m_preset = canonical;
    m_dotCount = m_preset == QStringLiteral("inline") ? 28 : 96;
    resizeFrames();
    emit presetChanged();
    update();
}

void ThinkingOrb::setInk(const QColor& ink) {
    if (m_ink == ink)
        return;
    m_ink = ink;
    emit inkChanged();
    update();
}

void ThinkingOrb::setAnimated(bool animated) {
    if (m_animated == animated)
        return;
    m_animated = animated;
    emit animatedChanged();
    updateAnimationState();
    update();
}

void ThinkingOrb::setSpeed(qreal speed) {
    const qreal bounded = std::max(speed, 0.0);
    if (qFuzzyCompare(m_speed, bounded))
        return;
    m_speed = bounded;
    emit speedChanged();
    updateAnimationState();
    update();
}

void ThinkingOrb::setPaused(bool paused) {
    if (m_paused == paused)
        return;
    m_paused = paused;
    emit pausedChanged();
    updateAnimationState();
    update();
}

void ThinkingOrb::resizeFrames() {
    m_frame.resize(m_dotCount);
    m_previousFrame.resize(m_dotCount);
    m_lastPaintedFrame.resize(m_dotCount);
    m_havePaintedFrame = false;
    m_previousLinkAlpha = 0.0;
    m_lastLinkAlpha = 0.0;
}

void ThinkingOrb::handleWindowChanged(QQuickWindow* window) {
    m_frameDelayTimer.stop();
    QObject::disconnect(m_afterAnimatingConnection);
    if (m_observedWindow)
        m_observedWindow->removeEventFilter(this);
    m_observedWindow = window;
    m_frameClockRunning = false;
    m_lastFrameRequestedAt = 0;
    if (m_observedWindow) {
        m_observedWindow->installEventFilter(this);
        m_afterAnimatingConnection = connect(
            m_observedWindow, &QQuickWindow::afterAnimating, this, &ThinkingOrb::requestAnimationFrame);
    }
    updateAnimationState();
    update();
}

void ThinkingOrb::updateAnimationState() {
    const bool shouldRun = m_animated && !m_paused && m_speed > 0.0 && isVisible() && m_observedWindow
        && m_observedWindow->isVisible() && m_observedWindow->isExposed();
    if (!shouldRun) {
        m_frameDelayTimer.stop();
        m_frameClockRunning = false;
        return;
    }
    if (m_frameClockRunning)
        return;

    m_frameClockRunning = true;
    m_lastFrameRequestedAt = monotonicMilliseconds();
    update();
    m_observedWindow->update();
}

void ThinkingOrb::requestAnimationFrame() {
    if (!m_animated || m_paused || m_speed <= 0.0 || !isVisible() || !m_observedWindow
        || !m_observedWindow->isVisible() || !m_observedWindow->isExposed()) {
        m_frameDelayTimer.stop();
        m_frameClockRunning = false;
        return;
    }
    if (!m_frameClockRunning)
        return;

    const qint64 now = monotonicMilliseconds();
    const qint64 elapsed = now - m_lastFrameRequestedAt;
    if (elapsed < MinimumFrameIntervalMilliseconds) {
        if (!m_frameDelayTimer.isActive())
            m_frameDelayTimer.start(static_cast<int>(MinimumFrameIntervalMilliseconds - elapsed));
        return;
    }

    m_frameDelayTimer.stop();
    m_lastFrameRequestedAt = now;
    update();
    m_observedWindow->update();
}

void ThinkingOrb::itemChange(ItemChange change, const ItemChangeData& data) {
    QQuickPaintedItem::itemChange(change, data);
    if (change == ItemVisibleHasChanged) {
        updateAnimationState();
        if (data.boolValue)
            update();
    }
}

bool ThinkingOrb::eventFilter(QObject* watched, QEvent* event) {
    if (watched == m_observedWindow
        && (event->type() == QEvent::Expose || event->type() == QEvent::Show || event->type() == QEvent::Hide
            || event->type() == QEvent::PlatformSurface)) {
        updateAnimationState();
        if (isVisible() && m_observedWindow && m_observedWindow->isExposed())
            update();
    }
    return QQuickPaintedItem::eventFilter(watched, event);
}

qreal ThinkingOrb::representativePhase() const {
    switch (m_state) {
    case OrbState::Breathing:
        return 0.7;
    case OrbState::Listening:
        return 0.55;
    case OrbState::Connecting:
        return 3.2;
    case OrbState::Searching:
        return 0.8;
    case OrbState::Working:
        return 0.65;
    case OrbState::Solving:
        return SolvingCycleSeconds;
    case OrbState::Composing:
        return 0.45;
    case OrbState::Weaving:
        return 0.45;
    case OrbState::Shaping:
        return 2.25;
    }
    return 0.0;
}

qreal ThinkingOrb::phaseForPaint(qint64 now) const {
    if (!m_animated)
        return representativePhase();
    if (m_state == OrbState::Solving) {
        const qreal elapsed = static_cast<qreal>(now - m_stateStartedAt) * 0.001 * m_speed;
        return std::min(elapsed, SolvingCycleSeconds);
    }
    return static_cast<qreal>(now) * 0.001 * m_speed;
}

void ThinkingOrb::generateFrame(OrbState state, qreal phase, QVector<Dot>& frame, qreal& linkAlpha) const {
    const int count = frame.size();
    linkAlpha = 0.0;

    switch (state) {
    case OrbState::Breathing: {
        const qreal ringRadius = 0.69 + 0.035 * std::sin(phase * 0.82);
        const qreal aspect = 0.94 + 0.045 * std::sin(phase * 0.53 + 1.1);
        const qreal roundness = 2.0 + 0.34 * std::sin(phase * 0.41 + 0.7);
        const qreal exponent = 2.0 / roundness;
        for (int i = 0; i < count; ++i) {
            const qreal angle = Tau * i / count;
            frame[i] = {{ringRadius * signedPower(std::cos(angle), exponent),
                            ringRadius * aspect * signedPower(std::sin(angle), exponent)},
                1.0,
                0.72 + 0.28 * std::sin(angle + phase * 0.36) * std::sin(angle + phase * 0.36)};
        }
        break;
    }
    case OrbState::Listening: {
        constexpr int rings = 4;
        for (int i = 0; i < count; ++i) {
            const int ring = std::min(i * rings / count, rings - 1);
            const int first = ring * count / rings;
            const int last = (ring + 1) * count / rings;
            const int ringCount = std::max(last - first, 1);
            const qreal angle = Tau * (i - first) / ringCount + ring * 0.16;
            const qreal baseRadius = 0.22 + ring * 0.16;
            const qreal wave = 0.055 * std::sin(angle * 3.0 - phase * 4.4 + ring * 0.8);
            const qreal radius = baseRadius + wave;
            frame[i] = {{radius * std::cos(angle), radius * std::sin(angle)},
                0.86 + 0.16 * ring,
                0.52 + 0.46 * (0.5 + 0.5 * std::sin(angle * 3.0 - phase * 4.4))};
        }
        break;
    }
    case OrbState::Connecting: {
        const qreal cycle = std::fmod(std::max(phase, 0.0), 4.2) / 4.2;
        const qreal lock = smoothstep((cycle - 0.30) / 0.42);
        linkAlpha = smoothstep((lock - 0.45) / 0.55) * 0.34;
        constexpr qreal goldenAngle = Pi * (3.0 - 2.2360679774997896964);
        for (int i = 0; i < count; ++i) {
            const qreal y3 = 1.0 - 2.0 * (i + 0.5) / count;
            const qreal sphereRadius = std::sqrt(std::max(0.0, 1.0 - y3 * y3));
            const qreal longitude = goldenAngle * i;
            const QPointF target(0.72 * sphereRadius * std::cos(longitude), 0.72 * y3);
            const qreal driftAngle = Tau * noise(i * 3 + 1) + phase * (0.34 + 0.18 * noise(i * 3 + 2));
            const qreal driftRadius = 0.22 + 0.55 * noise(i * 3 + 3);
            const QPointF drift(driftRadius * std::cos(driftAngle), driftRadius * std::sin(driftAngle));
            frame[i] = {drift * (1.0 - lock) + target * lock,
                0.82 + 0.30 * noise(i + 90),
                0.38 + 0.62 * lock};
        }
        break;
    }
    case OrbState::Searching:
    case OrbState::Solving: {
        constexpr int bands = 7;
        qreal solved = 1.0;
        if (state == OrbState::Solving) {
            const qreal progress = clamp01(phase / SolvingCycleSeconds);
            solved = smoothstep((progress - 2.0 / 3.0) * 3.0);
        }
        const qreal sweep = state == OrbState::Searching ? phase * 1.45 : 0.0;
        for (int i = 0; i < count; ++i) {
            const int band = std::min(i * bands / count, bands - 1);
            const int first = band * count / bands;
            const int last = (band + 1) * count / bands;
            const int bandCount = std::max(last - first, 1);
            const qreal latitude = -1.08 + 2.16 * (band + 0.5) / bands;
            qreal offset = 0.0;
            if (state == OrbState::Solving) {
                const qreal scrambled = (noise(band * 19 + 7) - 0.5) * Tau;
                offset = scrambled * (0.78 + 0.22 * std::sin(phase * 2.1 + band)) * (1.0 - solved);
            }
            const qreal longitude = Tau * (i - first) / bandCount + offset;
            const qreal cosLatitude = std::cos(latitude);
            const qreal x = cosLatitude * std::sin(longitude);
            const qreal y = std::sin(latitude);
            const qreal z = cosLatitude * std::cos(longitude);
            qreal alpha = z >= 0.0 ? 0.82 : 0.24;
            qreal radius = 0.72 + 0.34 * (z + 1.0) * 0.5;
            if (state == OrbState::Searching) {
                const qreal meridianDistance = std::abs(wrapAngle(longitude - sweep));
                const qreal beam = std::exp(-meridianDistance * meridianDistance / 0.055);
                alpha = std::min(1.0, alpha + beam * 0.72);
                radius += beam * 0.36;
            } else {
                alpha = alpha * (0.72 + 0.28 * solved);
            }
            frame[i] = {{x * 0.74, y * 0.74}, radius, alpha};
        }
        break;
    }
    case OrbState::Working: {
        constexpr std::array<qreal, 3> tilt{0.34, -0.52, 0.82};
        constexpr std::array<qreal, 3> spin{1.34, -1.08, 0.86};
        for (int i = 0; i < count; ++i) {
            const int orbit = i % 3;
            const int ordinal = i / 3;
            const int orbitCount = (count + 2 - orbit) / 3;
            const qreal angle = Tau * ordinal / std::max(orbitCount, 1) + phase * spin[orbit];
            qreal x = (0.47 + orbit * 0.10) * std::cos(angle);
            qreal y = (0.24 + orbit * 0.035) * std::sin(angle);
            qreal z = (0.47 + orbit * 0.10) * std::sin(angle);
            const qreal cosine = std::cos(tilt[orbit]);
            const qreal sine = std::sin(tilt[orbit]);
            const qreal rotatedY = y * cosine - z * sine;
            const qreal rotatedZ = y * sine + z * cosine;
            const qreal planeTurn = orbit * 1.02;
            const qreal screenX = x * std::cos(planeTurn) - rotatedY * std::sin(planeTurn);
            const qreal screenY = x * std::sin(planeTurn) + rotatedY * std::cos(planeTurn);
            frame[i] = {{screenX, screenY}, 0.68 + 0.48 * (rotatedZ + 0.7) / 1.4, 0.34 + 0.62 * (rotatedZ + 0.7) / 1.4};
        }
        break;
    }
    case OrbState::Composing: {
        constexpr int bands = 4;
        for (int i = 0; i < count; ++i) {
            const int band = std::min(i * bands / count, bands - 1);
            const int first = band * count / bands;
            const int last = (band + 1) * count / bands;
            const int bandCount = std::max(last - first, 2);
            const qreal along = static_cast<qreal>(i - first) / (bandCount - 1);
            const qreal x = -0.72 + along * 1.44;
            const qreal y = -0.32 + band * 0.215 + 0.075 * std::sin(x * 5.2 - phase * 2.8 + band * 0.72);
            frame[i] = {{x, y}, 0.82 + 0.12 * band, 0.56 + 0.38 * (0.5 + 0.5 * std::sin(x * 3.0 - phase + band))};
        }
        break;
    }
    case OrbState::Weaving: {
        for (int i = 0; i < count; ++i) {
            const int strand = i % 3;
            const int ordinal = i / 3;
            const int strandCount = (count + 2 - strand) / 3;
            const qreal along = static_cast<qreal>(ordinal) / std::max(strandCount - 1, 1);
            const qreal x = -0.72 + 1.44 * along;
            const qreal wavePhase = along * Tau * 1.35 - phase * 1.8 + strand * Tau / 3.0;
            const qreal depth = std::cos(wavePhase);
            const qreal y = 0.43 * std::sin(wavePhase) * std::sqrt(std::max(0.0, 1.0 - x * x * 0.75));
            frame[i] = {{x, y}, 0.72 + 0.38 * (depth + 1.0) * 0.5, 0.30 + 0.68 * (depth + 1.0) * 0.5};
        }
        break;
    }
    case OrbState::Shaping: {
        constexpr std::array triangle{
            QPointF(0.0, -0.78), QPointF(0.68, 0.39), QPointF(-0.68, 0.39)};
        constexpr std::array square{
            QPointF(-0.57, -0.57), QPointF(0.57, -0.57), QPointF(0.57, 0.57), QPointF(-0.57, 0.57)};
        const qreal cycle = std::fmod(std::max(phase, 0.0), 4.5) / 4.5;
        const int segment = std::min(static_cast<int>(cycle * 3.0), 2);
        const qreal blend = smoothstep(cycle * 3.0 - segment);
        for (int i = 0; i < count; ++i) {
            const qreal unit = static_cast<qreal>(i) / count;
            const qreal angle = unit * Tau - Pi * 0.5;
            const QPointF circle(0.68 * std::cos(angle), 0.68 * std::sin(angle));
            const QPointF tri = polygonPoint(triangle.data(), triangle.size(), unit);
            const QPointF quad = polygonPoint(square.data(), square.size(), unit);
            QPointF from;
            QPointF to;
            if (segment == 0) {
                from = circle;
                to = tri;
            } else if (segment == 1) {
                from = tri;
                to = quad;
            } else {
                from = quad;
                to = circle;
            }
            frame[i] = {from * (1.0 - blend) + to * blend, 1.0, 0.82};
        }
        break;
    }
    }
}

void ThinkingOrb::paint(QPainter* painter) {
    if (width() <= 0.0 || height() <= 0.0 || m_dotCount <= 0)
        return;

    const qint64 now = monotonicMilliseconds();
    qreal linkAlpha = 0.0;
    generateFrame(m_state, phaseForPaint(now), m_frame, linkAlpha);

    qreal transition = 1.0;
    if (m_animated && m_crossfadeStartedAt > 0)
        transition = smoothstep(static_cast<qreal>(now - m_crossfadeStartedAt) / CrossfadeMilliseconds);

    for (int i = 0; i < m_dotCount; ++i) {
        if (transition < 1.0) {
            const Dot& oldDot = m_previousFrame[i];
            Dot& dot = m_frame[i];
            dot.position = oldDot.position * (1.0 - transition) + dot.position * transition;
            dot.radius = oldDot.radius * (1.0 - transition) + dot.radius * transition;
            dot.alpha = oldDot.alpha * (1.0 - transition) + dot.alpha * transition;
        }
        m_lastPaintedFrame[i] = m_frame[i];
    }
    m_lastLinkAlpha = m_previousLinkAlpha * (1.0 - transition) + linkAlpha * transition;
    m_havePaintedFrame = true;

    const qreal side = std::min(width(), height());
    const QPointF center(width() * 0.5, height() * 0.5);
    const qreal scale = side * 0.5;
    const qreal baseRadius = side * (m_preset == QStringLiteral("inline") ? 0.050 : 0.022);

    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setPen(Qt::NoPen);

    if (m_lastLinkAlpha > 0.001) {
        QColor hairline = m_ink;
        hairline.setAlphaF(hairline.alphaF() * m_lastLinkAlpha);
        QPen pen(hairline, std::max<qreal>(0.6, side * 0.006));
        pen.setCapStyle(Qt::RoundCap);
        painter->setPen(pen);
        for (int i = 0; i < m_dotCount; ++i) {
            int links = 0;
            for (int j = i + 1; j < m_dotCount && links < 2; ++j) {
                const QPointF delta = m_frame[j].position - m_frame[i].position;
                const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
                if (distanceSquared < 0.075) {
                    painter->drawLine(center + m_frame[i].position * scale, center + m_frame[j].position * scale);
                    ++links;
                }
            }
        }
        painter->setPen(Qt::NoPen);
    }

    painter->setBrush(m_ink);
    for (const Dot& dot : std::as_const(m_frame)) {
        painter->setOpacity(clamp01(dot.alpha));
        const QPointF position = center + dot.position * scale;
        const qreal radius = std::max<qreal>(0.35, baseRadius * dot.radius);
        painter->drawEllipse(position, radius, radius);
    }
    painter->setOpacity(1.0);
    m_frameCount.fetch_add(1, std::memory_order_relaxed);
}
