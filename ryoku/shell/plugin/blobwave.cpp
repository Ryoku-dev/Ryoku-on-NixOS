#include "blobwave.hpp"
#include "blobgroup.hpp"

#include <algorithm>
#include <cmath>

namespace {
float smoothstep(float edge0, float edge1, float value) {
    const float t = std::clamp((value - edge0) / (edge1 - edge0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

float sample(const QList<qreal>& values, float position) {
    if (values.isEmpty())
        return 0.0f;
    if (values.size() == 1)
        return static_cast<float>(values.front());

    const float bounded = std::clamp(position, 0.0f, static_cast<float>(values.size() - 1));
    const int left = static_cast<int>(std::floor(bounded));
    const int right = std::min(left + 1, static_cast<int>(values.size() - 1));
    const float fraction = bounded - static_cast<float>(left);
    return std::lerp(static_cast<float>(values[left]), static_cast<float>(values[right]), fraction);
}

float resampleState(const std::array<float, 64>& values, int count, float u) {
    if (count <= 1)
        return values[0];
    const float position = u * static_cast<float>(count - 1);
    const int left = static_cast<int>(std::floor(position));
    const int right = std::min(left + 1, count - 1);
    return std::lerp(values[left], values[right], position - static_cast<float>(left));
}
}

BlobWave::BlobWave(QQuickItem* parent)
    : BlobRect(parent) {
    setDeformScale(0.0);
}

BlobWave::~BlobWave() {
    if (!m_group)
        return;
    auto* group = m_group;
    group->removeShape(this);
    group->removeWave(this);
    m_group = nullptr;
}

void BlobWave::setLevels(const QList<qreal>& levels) {
    if (m_levels == levels)
        return;
    m_levels = levels;
    rebuildTargets();
    emit levelsChanged();
    startIfNeeded();
}

void BlobWave::setPoints(int points) {
    const int bounded = std::clamp(points, 2, 64);
    if (m_points == bounded)
        return;
    m_points = bounded;
    relayout();
    rebuildTargets();
    emit pointsChanged();
    startIfNeeded();
}

void BlobWave::setAmplitude(qreal amplitude) {
    const qreal bounded = std::isfinite(amplitude) ? std::max(amplitude, 0.0) : 0.0;
    if (qFuzzyCompare(m_amplitude, bounded))
        return;
    m_amplitude = bounded;
    rebuildTargets();
    emit amplitudeChanged();
    startIfNeeded();
}
void BlobWave::setGain(qreal gain) {
    const qreal bounded = std::isfinite(gain) ? std::max(gain, 0.0) : 0.0;
    if (qFuzzyCompare(m_gain, bounded))
        return;
    m_gain = bounded;
    rebuildTargets();
    emit gainChanged();
    startIfNeeded();
}

void BlobWave::setMirror(bool mirror) {
    if (m_mirror == mirror)
        return;
    m_mirror = mirror;
    rebuildTargets();
    emit mirrorChanged();
    startIfNeeded();
}

void BlobWave::setEdgeInset(qreal edgeInset) {
    const qreal bounded = std::isfinite(edgeInset) ? std::max(edgeInset, 0.0) : 0.0;
    if (qFuzzyCompare(m_edgeInset, bounded))
        return;
    m_edgeInset = bounded;
    relayout();
    rebuildTargets();
    emit edgeInsetChanged();
    startIfNeeded();
}

void BlobWave::setWaveStiffness(qreal stiffness) {
    const qreal bounded = std::isfinite(stiffness) ? std::max(stiffness, 0.0) : 0.0;
    if (qFuzzyCompare(m_waveStiffness, bounded))
        return;
    m_waveStiffness = bounded;
    emit waveStiffnessChanged();
    startIfNeeded();
}

void BlobWave::setWaveDamping(qreal damping) {
    const qreal bounded = std::isfinite(damping) ? std::max(damping, 0.0) : 0.0;
    if (qFuzzyCompare(m_waveDamping, bounded))
        return;
    m_waveDamping = bounded;
    emit waveDampingChanged();
    startIfNeeded();
}

void BlobWave::setStepped(bool stepped) {
    if (m_stepped == stepped)
        return;
    m_stepped = stepped;
    relayout();
    rebuildTargets();
    emit steppedChanged();
    startIfNeeded();
    if (m_group && m_group->waves().contains(this))
        m_group->markShapeDirty(this);
}

void BlobWave::setBlockPitch(qreal pitch) {
    const qreal bounded = std::isfinite(pitch) ? std::max(pitch, 0.0) : 0.0;
    if (qFuzzyCompare(m_blockPitch + 1.0, bounded + 1.0))
        return;
    m_blockPitch = bounded;
    relayout();
    rebuildTargets();
    emit blockPitchChanged();
    startIfNeeded();
    if (m_group && m_group->waves().contains(this))
        m_group->markShapeDirty(this);
}

void BlobWave::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    BlobRect::geometryChange(newGeometry, oldGeometry);
    if (!qFuzzyCompare(newGeometry.width(), oldGeometry.width())) {
        relayout();
        rebuildTargets();
        startIfNeeded();
    }
}

void BlobWave::updatePolish() {
    BlobRect::updatePolish();
    if (!m_active)
        return;

    QMetaObject::invokeMethod(
        this,
        [this]() {
            if (m_active && m_group && m_group->waves().contains(this))
                m_group->markShapeDirty(this);
        },
        Qt::QueuedConnection);
}

void BlobWave::updatePhysics() {
    BlobRect::updatePhysics();
    if (!m_active)
        return;

    if (!m_elapsed.isValid()) {
        m_elapsed.start();
        return;
    }

    const float dt = std::min(static_cast<float>(m_elapsed.restart()) / 1000.0f, 0.1f);
    if (dt <= 0.0f)
        return;

    const int steps = std::max(1, static_cast<int>(std::ceil(dt / 0.008f)));
    const float h = dt / static_cast<float>(steps);
    const float stiffness = static_cast<float>(m_waveStiffness);
    const float fallDamping = m_stepped ? 2.0f * std::sqrt(stiffness) : static_cast<float>(m_waveDamping);
    const float riseTau = m_stepped ? 0.012f : 0.018f;

    for (int step = 0; step < steps; ++step) {
        const float riseBlend = 1.0f - std::exp(-h / riseTau);
        for (int i = 0; i < m_count; ++i) {
            if (m_targets[i] > m_heights[i]) {
                m_heights[i] += (m_targets[i] - m_heights[i]) * riseBlend;
                m_velocities[i] = 0.0f;
                continue;
            }
            m_velocities[i] =
                (m_velocities[i] - stiffness * (m_heights[i] - m_targets[i]) * h) / (1.0f + fallDamping * h);
            m_heights[i] += m_velocities[i] * h;
        }
    }

    bool hasTarget = false;
    bool displaced = false;
    bool inMotion = false;
    for (int i = 0; i < m_count; ++i) {
        hasTarget = hasTarget || m_targets[i] > 0.0f;
        displaced = displaced || std::abs(m_heights[i]) > 0.05f;
        inMotion = inMotion || std::abs(m_velocities[i]) > 0.5f;
    }
    setMoving(displaced || inMotion);

    if (!hasTarget && !displaced && !inMotion) {
        std::fill(m_heights.begin(), m_heights.end(), 0.0f);
        std::fill(m_velocities.begin(), m_velocities.end(), 0.0f);
        m_active = false;
        m_elapsed.invalidate();
        setMoving(false);
    }
}

void BlobWave::registerWithGroup() {
    BlobRect::registerWithGroup();
    if (!m_group)
        return;
    m_group->addWave(this);
    relayout();
    rebuildTargets();
    startIfNeeded();
}

void BlobWave::unregisterFromGroup() {
    auto* group = m_group;
    BlobRect::unregisterFromGroup();
    if (group)
        group->removeWave(this);
    m_active = false;
    m_elapsed.invalidate();
    setMoving(false);
}

void BlobWave::relayout() {
    const float widthPx = std::max(0.0f, static_cast<float>(width()));
    int count = m_points;
    float start = 0.0f;
    float end = widthPx;

    if (m_stepped) {
        const float inset = std::min(static_cast<float>(m_edgeInset), widthPx * 0.25f);
        const float inner = std::max(0.0f, widthPx - 2.0f * inset);
        const float naturalPitch = inner / static_cast<float>(m_points);
        const float pitch = m_blockPitch > 0.0 ? std::max(static_cast<float>(m_blockPitch), naturalPitch)
                                               : naturalPitch;
        count = pitch > 0.0f ? std::clamp(static_cast<int>(std::floor(inner / pitch)), 2, m_points) : 2;
        const float used = std::min(inner, pitch * static_cast<float>(count));
        start = (widthPx - used) * 0.5f;
        end = start + used;
    }

    m_spanStart = start;
    m_spanEnd = end;
    if (count == m_count)
        return;

    const auto oldHeights = m_heights;
    const auto oldVelocities = m_velocities;
    const int oldCount = m_count;
    m_count = count;
    for (int i = 0; i < m_count; ++i) {
        const float u = static_cast<float>(i) / static_cast<float>(std::max(m_count - 1, 1));
        m_heights[i] = resampleState(oldHeights, oldCount, u);
        m_velocities[i] = resampleState(oldVelocities, oldCount, u);
    }
    std::fill(m_heights.begin() + m_count, m_heights.end(), 0.0f);
    std::fill(m_velocities.begin() + m_count, m_velocities.end(), 0.0f);
}

void BlobWave::rebuildTargets() {
    std::array<float, 64> sampled{};
    const float widthPx = static_cast<float>(width());
    const float spanPx = m_spanEnd - m_spanStart;
    const float amplitudePx = static_cast<float>(m_amplitude);
    const float insetPx = static_cast<float>(m_edgeInset);
    const int bandCount = static_cast<int>(m_levels.size());

    if (bandCount > 0 && spanPx > 0.0f && amplitudePx > 0.0f) {
        // Smooth points sit on the ends of the span; blocks are sampled at their centres.
        const auto position = [this](int i) {
            return m_stepped ? (static_cast<float>(i) + 0.5f) / static_cast<float>(m_count)
                             : static_cast<float>(i) / static_cast<float>(m_count - 1);
        };

        for (int i = 0; i < m_count; ++i) {
            const float u = position(i);
            const float band = (m_mirror ? std::abs(2.0f * u - 1.0f) : u) * static_cast<float>(bandCount - 1);
            sampled[i] = std::clamp(sample(m_levels, band), 0.0f, 1.0f);
        }

        for (int i = 0; i < m_count; ++i) {
            const int left = std::max(i - 1, 0);
            const int right = std::min(i + 1, m_count - 1);
            const float sampledLevel = m_stepped
                ? sampled[i]
                : 0.25f * sampled[left] + 0.5f * sampled[i] + 0.25f * sampled[right];
            const float level = std::max(0.0f, (sampledLevel - 0.02f) / 0.98f);
            const float lift = std::min(1.0f, level * static_cast<float>(m_gain));
            float window = 1.0f;
            if (!m_stepped && insetPx > 0.0f) {
                const float x = position(i) * widthPx;
                window = smoothstep(0.0f, insetPx, std::min(x, widthPx - x));
            }
            m_targets[i] = lift * window * amplitudePx;
        }
    } else {
        std::fill_n(m_targets.begin(), m_count, 0.0f);
    }

    std::fill(m_targets.begin() + m_count, m_targets.end(), 0.0f);
}

void BlobWave::startIfNeeded() {
    bool hasTarget = false;
    bool displaced = false;
    bool inMotion = false;
    for (int i = 0; i < m_count; ++i) {
        hasTarget = hasTarget || m_targets[i] > 0.0f;
        displaced = displaced || std::abs(m_heights[i]) > 0.05f;
        inMotion = inMotion || std::abs(m_velocities[i]) > 0.5f;
    }
    const bool needsFrames = hasTarget || displaced || inMotion;

    if (!needsFrames) {
        std::fill(m_heights.begin(), m_heights.end(), 0.0f);
        std::fill(m_velocities.begin(), m_velocities.end(), 0.0f);
        m_active = false;
        m_elapsed.invalidate();
        setMoving(false);
        return;
    }

    if (!m_group || !m_group->waves().contains(this))
        return;

    setMoving(displaced || inMotion);
    if (!m_active) {
        m_active = true;
        m_elapsed.start();
    }
    m_group->markShapeDirty(this);
}

void BlobWave::setMoving(bool moving) {
    if (m_moving == moving)
        return;
    m_moving = moving;
    emit movingChanged();
}
