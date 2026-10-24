#pragma once

#include "blobmaterial.hpp"

#include <qmatrix4x4.h>
#include <qquickitem.h>
#include <qvector.h>

class BlobGroup;
class BlobWave;

class BlobShape : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(BlobGroup* group READ group WRITE setGroup NOTIFY groupChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(QMatrix4x4 deformMatrix READ deformMatrix NOTIFY deformMatrixChanged)
    Q_PROPERTY(QMatrix4x4 rawDeformMatrix READ rawDeformMatrix NOTIFY rawDeformMatrixChanged)
    Q_PROPERTY(bool sinks READ sinks WRITE setSinks NOTIFY sinksChanged)

    friend class BlobGroup;

public:
    explicit BlobShape(QQuickItem* parent = nullptr);
    ~BlobShape() override = default;

    BlobGroup* group() const { return m_group; }

    void setGroup(BlobGroup* g);

    qreal radius() const { return m_radius; }

    void setRadius(qreal r);

    QMatrix4x4 deformMatrix() const { return m_centeredDeformMatrix; }

    QMatrix4x4 rawDeformMatrix() const { return m_deformMatrix; }

    // whether the inverted border pockets around this shape (border sinks). a
    // docked island wants the pocket; a melting popout must slide in flush.
    bool sinks() const { return m_sinks; }

    void setSinks(bool s);

signals:
    void groupChanged();
    void radiusChanged();
    void deformMatrixChanged();
    void rawDeformMatrixChanged();
    void sinksChanged();

protected:
    void componentComplete() override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;
    void updatePolish() override;
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) override;

    virtual bool isInvertedRect() const { return false; }

    virtual bool isExcluded(const BlobShape* /*other*/) const { return false; }

    virtual void cornerRadii(float out[4]) const;

    virtual void updatePhysics() {}

    virtual void registerWithGroup();
    virtual void unregisterFromGroup();
    void updateCenteredDeformMatrix();
    bool refreshWaveData(BlobWave* const* waves, int count);

    BlobGroup* m_group = nullptr;
    qreal m_radius = 0;
    bool m_sinks = true;
    QMatrix4x4 m_deformMatrix; // identity by default
    QMatrix4x4 m_centeredDeformMatrix;

    // Cached data from updatePolish
    float m_cachedPaddedX = 0;
    float m_cachedPaddedY = 0;
    float m_cachedPaddedW = 0;
    float m_cachedPaddedH = 0;
    QRectF m_localPaddedRect;
    QVector<BlobRectData> m_cachedRects;
    int m_cachedMyIndex = -2;
    float m_pendingDx = 0;
    float m_pendingDy = 0;
    bool m_cachedHasInverted = false;
    float m_cachedInvertedRadius = 0;
    float m_cachedInvertedOuter[4] = {};
    float m_cachedInvertedInner[4] = {};
    float m_cachedWaveInfo[4][4] = {
        { 0, 0, 0, -1 },
        { 0, 0, 0, -1 },
        { 0, 0, 0, -1 },
        { 0, 0, 0, -1 },
    };
    float m_cachedWaveData[4][64] = {};
    BlobWave* m_cachedWaves[4] = {};
};
