#pragma once

#include "blobrect.hpp"

#include <array>
#include <qelapsedtimer.h>
#include <qlist.h>
#include <qqmlengine.h>

class BlobWave : public BlobRect {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QList<qreal> levels READ levels WRITE setLevels NOTIFY levelsChanged)
    Q_PROPERTY(int points READ points WRITE setPoints NOTIFY pointsChanged)
    Q_PROPERTY(qreal amplitude READ amplitude WRITE setAmplitude NOTIFY amplitudeChanged)
    Q_PROPERTY(qreal gain READ gain WRITE setGain NOTIFY gainChanged)
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY mirrorChanged)
    Q_PROPERTY(qreal edgeInset READ edgeInset WRITE setEdgeInset NOTIFY edgeInsetChanged)
    Q_PROPERTY(qreal waveStiffness READ waveStiffness WRITE setWaveStiffness NOTIFY waveStiffnessChanged)
    Q_PROPERTY(qreal waveDamping READ waveDamping WRITE setWaveDamping NOTIFY waveDampingChanged)
    Q_PROPERTY(bool stepped READ stepped WRITE setStepped NOTIFY steppedChanged)
    Q_PROPERTY(qreal blockPitch READ blockPitch WRITE setBlockPitch NOTIFY blockPitchChanged)
    Q_PROPERTY(bool moving READ moving NOTIFY movingChanged)

public:
    explicit BlobWave(QQuickItem* parent = nullptr);
    ~BlobWave() override;

    const QList<qreal>& levels() const { return m_levels; }
    void setLevels(const QList<qreal>& levels);

    int points() const { return m_points; }
    void setPoints(int points);

    qreal amplitude() const { return m_amplitude; }
    void setAmplitude(qreal amplitude);
    qreal gain() const { return m_gain; }
    void setGain(qreal gain);

    bool mirror() const { return m_mirror; }
    void setMirror(bool mirror);

    qreal edgeInset() const { return m_edgeInset; }
    void setEdgeInset(qreal edgeInset);

    qreal waveStiffness() const { return m_waveStiffness; }
    void setWaveStiffness(qreal stiffness);

    qreal waveDamping() const { return m_waveDamping; }
    void setWaveDamping(qreal damping);

    // Stepped draws one square block per level instead of a smooth curve.
    bool stepped() const { return m_stepped; }
    void setStepped(bool stepped);

    // Block spacing for the stepped wave.
    qreal blockPitch() const { return m_blockPitch; }
    void setBlockPitch(qreal pitch);

    bool moving() const { return m_moving; }

    // The live layout: how many heights are in use and the local x range they
    // cover. A stepped wave keeps clear of its rounded ends.
    int count() const { return m_count; }
    float spanStart() const { return m_spanStart; }
    float spanEnd() const { return m_spanEnd; }
    const std::array<float, 64>& waveHeights() const { return m_heights; }

signals:
    void levelsChanged();
    void pointsChanged();
    void amplitudeChanged();
    void gainChanged();
    void mirrorChanged();
    void edgeInsetChanged();
    void waveStiffnessChanged();
    void waveDampingChanged();
    void steppedChanged();
    void blockPitchChanged();
    void movingChanged();

protected:
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;
    void updatePolish() override;
    void updatePhysics() override;
    void registerWithGroup() override;
    void unregisterFromGroup() override;

private:
    void relayout();
    void rebuildTargets();
    void startIfNeeded();
    void setMoving(bool moving);

    QList<qreal> m_levels;
    std::array<float, 64> m_targets{};
    std::array<float, 64> m_heights{};
    std::array<float, 64> m_velocities{};
    QElapsedTimer m_elapsed;
    int m_points = 24;
    int m_count = 24;
    float m_spanStart = 0.0f;
    float m_spanEnd = 0.0f;
    qreal m_amplitude = 22.0;
    qreal m_gain = 1.0;
    qreal m_edgeInset = 28.0;
    qreal m_waveStiffness = 170.0;
    qreal m_waveDamping = 13.0;
    qreal m_blockPitch = 0.0;
    bool m_mirror = true;
    bool m_stepped = false;
    bool m_active = false;
    bool m_moving = false;
};
