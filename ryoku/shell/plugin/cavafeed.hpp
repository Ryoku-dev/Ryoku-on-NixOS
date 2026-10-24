#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <qqmlregistration.h>

#include <array>

class CavaFeed : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)
    Q_PROPERTY(int framerate READ framerate WRITE setFramerate NOTIFY framerateChanged)
    Q_PROPERTY(QString method READ method WRITE setMethod NOTIFY methodChanged)
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool captureActive READ captureActive WRITE setCaptureActive NOTIFY captureActiveChanged)
    Q_PROPERTY(bool autosens READ autosens WRITE setAutosens NOTIFY autosensChanged)
    Q_PROPERTY(int sensitivity READ sensitivity WRITE setSensitivity NOTIFY sensitivityChanged)
    Q_PROPERTY(int noiseReduction READ noiseReduction WRITE setNoiseReduction NOTIFY noiseReductionChanged)
    Q_PROPERTY(bool peakFollow READ peakFollow WRITE setPeakFollow NOTIFY peakFollowChanged)
    Q_PROPERTY(int staleMs READ staleMs WRITE setStaleMs NOTIFY staleMsChanged)
    Q_PROPERTY(qreal noiseFloor READ noiseFloor WRITE setNoiseFloor NOTIFY noiseFloorChanged)
    Q_PROPERTY(QList<qreal> levels READ levels NOTIFY levelsChanged)
    Q_PROPERTY(qreal energy READ energy NOTIFY energyChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool silent READ silent NOTIFY silentChanged)

public:
    explicit CavaFeed(QObject* parent = nullptr);
    ~CavaFeed() override;

    bool active() const { return m_active; }
    void setActive(bool active);

    int bars() const { return m_bars; }
    void setBars(int bars);

    int framerate() const { return m_framerate; }
    void setFramerate(int framerate);

    const QString& method() const { return m_method; }
    void setMethod(const QString& method);

    const QString& source() const { return m_source; }
    void setSource(const QString& source);

    bool captureActive() const { return m_captureActive; }
    void setCaptureActive(bool active);

    bool autosens() const { return m_autosens; }
    void setAutosens(bool autosens);

    int sensitivity() const { return m_sensitivity; }
    void setSensitivity(int sensitivity);

    int noiseReduction() const { return m_noiseReduction; }
    void setNoiseReduction(int reduction);

    bool peakFollow() const { return m_peakFollow; }
    void setPeakFollow(bool follow);

    int staleMs() const { return m_staleMs; }
    void setStaleMs(int staleMs);

    const QList<qreal>& levels() const { return m_levels; }
    qreal energy() const { return m_energy; }
    bool running() const { return m_running; }
    qreal noiseFloor() const { return m_noiseFloor; }
    void setNoiseFloor(qreal floor);

    bool silent() const { return m_silent; }

signals:
    void activeChanged();
    void barsChanged();
    void framerateChanged();
    void methodChanged();
    void sourceChanged();
    void captureActiveChanged();
    void autosensChanged();
    void sensitivityChanged();
    void noiseReductionChanged();
    void peakFollowChanged();
    void staleMsChanged();
    void noiseFloorChanged();
    void levelsChanged();
    void energyChanged();
    void runningChanged();
    void silentChanged();
    void frame();

private:
    static constexpr int MaxBars = 256;

    void restartProcess();
    void startProcess();
    void stopProcess();
    void scheduleRestart();
    void handleFinished();
    void readOutput();
    void processFrame();
    void publishFlat();
    void resetAnalysis();
    bool writeConfig();
    void setRunning(bool running);
    void setSilent(bool silent);

    QProcess m_process;
    QTimer m_restartTimer;
    QTimer m_stopTimer;
    QTimer m_staleTimer;
    QTimer m_silenceTimer;
    QElapsedTimer m_clock;
    QList<qreal> m_levels;
    std::array<unsigned char, MaxBars * 2> m_binaryFrame{};
    std::array<qreal, MaxBars> m_frameLevels{};
    qsizetype m_frameBytes = 0;
    QString m_configPath;
    bool m_configOnDisk = false;
    QString m_method = QStringLiteral("pipewire");
    QString m_source = QStringLiteral("auto");
    qreal m_energy = 0.0;
    qreal m_peak = 0.0;
    qint64 m_lastFrameMs = -1;
    int m_bars = 40;
    int m_framerate = 30;
    int m_sensitivity = 180;
    int m_noiseReduction = 45;
    int m_staleMs = 120;
    int m_restartDelayMs = 1200;
    bool m_active = false;
    bool m_captureActive = false;
    bool m_autosens = false;
    bool m_peakFollow = false;
    qreal m_noiseFloor = 0.0;
    bool m_running = false;
    bool m_silent = true;
    bool m_intentionalStop = false;
    bool m_acceptOutput = false;
    bool m_restartAfterStop = false;
};
