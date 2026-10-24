#pragma once

#include <QColor>
#include <QMetaObject>
#include <QPointF>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QString>
#include <QVector>
#include <qqmlregistration.h>

#include <atomic>

class QEvent;
class QQuickWindow;

class ThinkingOrb : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString state READ state WRITE setState NOTIFY stateChanged)
    Q_PROPERTY(QString preset READ preset WRITE setPreset NOTIFY presetChanged)
    Q_PROPERTY(QColor ink READ ink WRITE setInk NOTIFY inkChanged)
    Q_PROPERTY(bool animated READ animated WRITE setAnimated NOTIFY animatedChanged)
    Q_PROPERTY(qreal speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(qulonglong frameCount READ frameCount)

public:
    explicit ThinkingOrb(QQuickItem* parent = nullptr);
    ~ThinkingOrb() override;

    QString state() const { return m_stateName; }
    void setState(const QString& state);
    QString preset() const { return m_preset; }
    void setPreset(const QString& preset);
    QColor ink() const { return m_ink; }
    void setInk(const QColor& ink);
    bool animated() const { return m_animated; }
    void setAnimated(bool animated);
    qreal speed() const { return m_speed; }
    void setSpeed(qreal speed);
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    qulonglong frameCount() const { return m_frameCount.load(std::memory_order_relaxed); }

    void paint(QPainter* painter) override;

signals:
    void stateChanged();
    void presetChanged();
    void inkChanged();
    void animatedChanged();
    void speedChanged();
    void pausedChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData& data) override;
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    enum class OrbState {
        Breathing,
        Listening,
        Connecting,
        Searching,
        Working,
        Solving,
        Composing,
        Weaving,
        Shaping,
    };

    struct Dot {
        QPointF position;
        qreal radius = 1.0;
        qreal alpha = 1.0;
    };

    static OrbState stateFromName(const QString& state, QString* canonicalName);
    static qint64 monotonicMilliseconds();

    void handleWindowChanged(QQuickWindow* window);
    void updateAnimationState();
    void requestAnimationFrame();
    void resizeFrames();
    void generateFrame(OrbState state, qreal phase, QVector<Dot>& frame, qreal& linkAlpha) const;
    qreal phaseForPaint(qint64 now) const;
    qreal representativePhase() const;

    QPointer<QQuickWindow> m_observedWindow;
    QMetaObject::Connection m_afterAnimatingConnection;
    QTimer m_frameDelayTimer;
    bool m_frameClockRunning = false;
    qint64 m_lastFrameRequestedAt = 0;
    QString m_stateName{QStringLiteral("breathing")};
    QString m_preset{QStringLiteral("avatar")};
    QColor m_ink{Qt::white};
    OrbState m_state = OrbState::Breathing;
    bool m_animated = true;
    bool m_paused = false;
    qreal m_speed = 1.0;
    int m_dotCount = 96;
    qint64 m_stateStartedAt = 0;
    qint64 m_crossfadeStartedAt = 0;
    QVector<Dot> m_frame;
    QVector<Dot> m_previousFrame;
    QVector<Dot> m_lastPaintedFrame;
    bool m_havePaintedFrame = false;
    qreal m_previousLinkAlpha = 0.0;
    qreal m_lastLinkAlpha = 0.0;
    std::atomic<qulonglong> m_frameCount{0};
};
