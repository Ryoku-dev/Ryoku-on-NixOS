#pragma once

#include "catalogs.h"
#include "entry.h"

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>
#include <QtQml/qqmlregistration.h>

class Daemon;
class QTimer;
class QQmlEngine;
class QJSEngine;

class Library : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap currentByOutput READ currentByOutput NOTIFY currentChanged)
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY outputsChanged)

public:

    static Library *create(QQmlEngine *engine, QJSEngine *jsEngine);
    static Library *instance() { return s_instance; }

    const QVector<Entry> &wallpapers() const { return m_wallpapers; }
    const QVector<Entry> &workshop() const { return m_workshop; }
    const QVector<Theme> &themes() const { return m_catalogs->themes(); }
    const QVector<Rice> &rices() const { return m_catalogs->rices(); }
    bool isApplied(const QString &key) const { return m_appliedKeys.contains(key); }

    QVariantMap currentByOutput() const { return m_currentByOutput; }
    QVariantList outputs() const { return m_outputs; }

    Q_INVOKABLE QVariantMap entry(const QString &collection, const QString &key) const;
    Q_INVOKABLE void refreshOutputs();
    Q_INVOKABLE QStringList folders(const QString &collection) const;
    Q_INVOKABLE QVariantMap tagHistogram(const QString &collection) const;
    // Entries, thumbnails and downloads carry plain paths; an Image needs a URL.
    Q_INVOKABLE static QUrl fileUrl(const QString &path);

Q_SIGNALS:
    void changed(const QString &collection);
    void currentChanged();
    void outputsChanged();

private:
    // Private so QML builds the singleton through create(); a public constructor makes Qt bypass it.
    explicit Library(QObject *parent = nullptr);
    void onReconnected();
    void onEvent(const QString &name, const QVariantMap &data);
    void fetchWallpapers();
    void fetchWorkshop();
    void assembleOutputs();
    void upsertWallpaper(const Entry &entry);
    void upsertWorkshop(const Entry &entry);
    void removeWallpaper(const QString &name, const QString &type);
    void rebuildWallIndex();
    void flushCached();

    Daemon *m_daemon = nullptr;
    Catalogs *m_catalogs = nullptr;
    QTimer *m_cachedFlush = nullptr;
    QVector<Entry> m_wallpapers;
    QVector<Entry> m_workshop;
    QHash<QString, int> m_wallIndex;   // key -> row in m_wallpapers
    QSet<QString> m_appliedKeys;
    bool m_workshopDirty = false;
    QVariantMap m_currentByOutput;
    QVariantList m_outputs;
    QVariantMap m_rawOutputs;
    QString m_focusedOutput;

    static Library *s_instance;
};
