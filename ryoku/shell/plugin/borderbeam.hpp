#pragma once

#include <QColor>
#include <QElapsedTimer>
#include <QPointer>
#include <QQuickItem>
#include <QTimer>
#include <QString>
#include <qqmlregistration.h>

class QEvent;
class QQuickWindow;

class BorderBeam : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(qreal strokeWidth READ strokeWidth WRITE setStrokeWidth NOTIFY strokeWidthChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(qreal strength READ strength WRITE setStrength NOTIFY strengthChanged)
    Q_PROPERTY(qreal duration READ duration WRITE setDuration NOTIFY durationChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(qreal blur READ blur WRITE setBlur NOTIFY blurChanged)

public:
    explicit BorderBeam(QQuickItem* parent = nullptr);
    ~BorderBeam() override;

    QString mode() const { return m_modeName; }
    void setMode(const QString& mode);
    qreal radius() const { return m_radius; }
    void setRadius(qreal radius);
    qreal strokeWidth() const { return m_strokeWidth; }
    void setStrokeWidth(qreal width);
    QColor color() const { return m_color; }
    void setColor(const QColor& color);
    qreal strength() const { return m_strength; }
    void setStrength(qreal strength);
    qreal duration() const { return m_duration; }
    void setDuration(qreal duration);
    bool active() const { return m_active; }
    void setActive(bool active);
    qreal blur() const { return m_blur; }
    void setBlur(qreal blur);

signals:
    void modeChanged();
    void radiusChanged();
    void strokeWidthChanged();
    void colorChanged();
    void strengthChanged();
    void durationChanged();
    void activeChanged();
    void blurChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) override;
    void itemChange(ItemChange change, const ItemChangeData& data) override;
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    enum class BeamMode {
        Line,
        Rotate,
        Pulse,
    };

    static qreal defaultDuration(BeamMode mode);
    void handleWindowChanged(QQuickWindow* window);
    void updateAnimationState();
    void requestAnimationFrame();
    bool advanceFade();
    void updatePhase();

    QPointer<QQuickWindow> m_observedWindow;
    QTimer m_frameTimer;
    QElapsedTimer m_phaseClock;
    QElapsedTimer m_fadeClock;
    QString m_modeName{QStringLiteral("line")};
    BeamMode m_mode = BeamMode::Line;
    qreal m_radius = 0.0;
    qreal m_strokeWidth = 1.5;
    QColor m_color{Qt::white};
    qreal m_strength = 1.0;
    qreal m_duration = 3.1;
    qreal m_blur = 6.0;
    qreal m_phase = 0.0;
    qreal m_activeFade = 0.0;
    qreal m_fadeFrom = 0.0;
    qreal m_fadeTarget = 0.0;
    bool m_active = false;
    bool m_durationExplicit = false;
};
