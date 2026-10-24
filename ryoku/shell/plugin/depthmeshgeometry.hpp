#pragma once

#include <QQuick3DGeometry>
#include <QUrl>
#include <QByteArray>
#include <QVector3D>
#include <QtQml/qqmlregistration.h>

// A depth-displaced grid for one wallpaper layer. The cut-out's hole is
// filled from the surrounding background depth so the separate near
// silhouette is the only subject; the matte is optional (Depth renders with
// no cut-out at all).
class DepthMeshGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(FitMode fitMode READ fitMode WRITE setFitMode NOTIFY fitModeChanged)
    QML_ELEMENT
    Q_PROPERTY(QUrl depthPath READ depthPath WRITE setDepthPath NOTIFY depthPathChanged)
    Q_PROPERTY(QUrl mattePath READ mattePath WRITE setMattePath NOTIFY mattePathChanged)
    Q_PROPERTY(float imageZoom READ imageZoom WRITE setImageZoom NOTIFY imageZoomChanged)
    Q_PROPERTY(float outputAspect READ outputAspect WRITE setOutputAspect NOTIFY outputAspectChanged)
    Q_PROPERTY(float sourceAspect READ sourceAspect WRITE setSourceAspect NOTIFY sourceAspectChanged)
    Q_PROPERTY(float focusDistance READ focusDistance NOTIFY focusDistanceChanged)
    Q_PROPERTY(float backgroundDistance READ backgroundDistance NOTIFY backgroundDistanceChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY validChanged)

public:
    enum FitMode {
        Crop,
        Stretch,
    };
    Q_ENUM(FitMode)

    explicit DepthMeshGeometry(QQuick3DObject *parent = nullptr);

    QUrl depthPath() const { return m_depthPath; }
    QUrl mattePath() const { return m_mattePath; }
    float imageZoom() const { return m_imageZoom; }
    float outputAspect() const { return m_outputAspect; }
    float sourceAspect() const { return m_sourceAspect; }
    FitMode fitMode() const { return m_fitMode; }
    float focusDistance() const { return m_focusDistance; }
    float backgroundDistance() const { return m_backgroundDistance; }
    bool valid() const { return m_valid; }

    void setDepthPath(const QUrl &path);
    void setMattePath(const QUrl &path);
    void setImageZoom(float zoom);
    void setOutputAspect(float aspect);
    void setSourceAspect(float aspect);
    void setFitMode(FitMode mode);

signals:
    void depthPathChanged();
    void mattePathChanged();
    void imageZoomChanged();
    void outputAspectChanged();
    void sourceAspectChanged();
    void fitModeChanged();
    void focusDistanceChanged();
    void backgroundDistanceChanged();
    void validChanged();

private:
    struct BuildRequest;
    struct MeshData;

    static MeshData buildMesh(const BuildRequest &request);
    void scheduleRebuild();
    void rebuild();
    void applyMesh(quint64 generation, MeshData mesh);
    void setValid(bool valid);

    QUrl m_depthPath;
    QUrl m_mattePath;
    float m_imageZoom = 1.10f;
    float m_outputAspect = 16.0f / 9.0f;
    float m_sourceAspect = 16.0f / 9.0f;
    float m_focusDistance = 2.9f;
    float m_backgroundDistance = 4.0f;
    FitMode m_fitMode = Crop;
    quint64 m_generation = 0;
    bool m_valid = false;
    bool m_rebuildPending = false;
    bool m_buildRunning = false;
};
