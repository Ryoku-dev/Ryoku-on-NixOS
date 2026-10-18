#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

class QProcess;
class QTimer;
class QFileSystemWatcher;

struct Theme {
    QString id;
    QString label;
    QString provider;
    QStringList swatches;   // seven role hexes: surface, onSurface, primary, ...
    bool dark = false;
    QString preview;

    QVariantMap toVariantMap() const;
};

struct Rice {
    QString slug;
    QString name;
    QString author;
    QString blurb;
    QStringList tags;
    QString createdWith;
    QString compat;
    bool active = false;
    bool live = false;
    QString preview;

    QVariantMap toVariantMap() const;
};

// Read through short-lived child processes off the GUI thread, then refreshed on change.
class Catalogs : public QObject
{
    Q_OBJECT
public:
    explicit Catalogs(QObject *parent = nullptr);

    void start();

    const QVector<Theme> &themes() const { return m_themes; }
    const QVector<Rice> &rices() const { return m_rices; }
    const Theme *theme(const QString &id) const;
    const Rice *rice(const QString &slug) const;

Q_SIGNALS:
    void themesChanged();
    void ricesChanged();

private:
    void loadThemes();
    void loadRices();
    void parseThemes(const QByteArray &json);
    void parseRices(const QByteArray &json);
    void refreshRiceWatches();
    void ensureSwatchPreviews();

    QProcess *m_themeProc = nullptr;
    QProcess *m_riceProc = nullptr;
    QTimer *m_themeDebounce = nullptr;
    QTimer *m_riceDebounce = nullptr;
    QFileSystemWatcher *m_watcher = nullptr;
    QStringList m_riceWatchPaths;
    QVector<Theme> m_themes;
    QVector<Rice> m_rices;
    quint64 m_swatchGen = 0;
};
