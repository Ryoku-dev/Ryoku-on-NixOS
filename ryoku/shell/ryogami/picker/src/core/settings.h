#pragma once

#include "params.h"

#include <QHash>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Daemon;
class QTimer;
class QQmlEngine;
class QJSEngine;

class Settings : public QObject, public ParamSource
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int viewportWidth READ viewportWidth WRITE setViewportWidth NOTIFY viewportWidthChanged)
    Q_PROPERTY(QVariantMap caps READ caps NOTIFY schemaChanged)
    Q_PROPERTY(QVariantMap availability READ availability NOTIFY schemaChanged)

public:

    static Settings *create(QQmlEngine *engine, QJSEngine *jsEngine);
    static Settings *instance() { return s_instance; }

    bool ready() const { return m_ready; }
    bool busy() const { return !m_pending.isEmpty() || m_writesInFlight > 0; }
    int viewportWidth() const { return m_viewportWidth; }
    void setViewportWidth(int width);

    Q_INVOKABLE QVariant value(const QString &key) const override;
    bool smallScreen() const override;

    // Invalid when the user never set the key, so a caller can pick a size-class default.
    Q_INVOKABLE QVariant userValue(const QString &key) const;

    Q_INVOKABLE void set(const QString &key, const QVariant &value);
    Q_INVOKABLE void reset(const QString &key);
    Q_INVOKABLE QVariantMap spec(const QString &key) const;
    Q_INVOKABLE QVariant defaultOf(const QString &key) const;
    Q_INVOKABLE bool isDefault(const QString &key) const;
    // Send any pending coalesced writes now (called when the picker hides).
    Q_INVOKABLE void flush();

    // cap() treats an absent capability as false; available() treats an absent source as true.
    QVariantMap caps() const { return m_caps; }
    QVariantMap availability() const { return m_availability; }
    Q_INVOKABLE bool cap(const QString &name) const { return m_caps.value(name).toBool(); }
    Q_INVOKABLE bool available(const QString &name) const { return m_availability.value(name, true).toBool(); }

Q_SIGNALS:
    void readyChanged();
    void busyChanged();
    void changed(const QString &key, const QVariant &value);
    void viewportWidthChanged();
    void schemaChanged();

private:
    // Private so QML builds the singleton through create(); a public constructor makes Qt bypass it.
    explicit Settings(QObject *parent = nullptr);
    void onReconnected();
    void fetchSchema();
    void fetchValues();
    void onEvent(const QString &name, const QVariantMap &data);
    void applyIncoming(const QVariantMap &values);
    void resync(const QStringList &keys);
    QVariant effectiveDefault(const QString &key) const;
    void maybeReady();

    Daemon *m_daemon = nullptr;
    QTimer *m_flush = nullptr;
    QHash<QString, QVariantMap> m_schema;   // key -> {type, default, defaultSmall, min, max, step, options, store}
    QVariantMap m_user;                     // user-set values only
    QVariantMap m_pending;                  // writes awaiting the coalesced RPC
    QVariantMap m_caps;
    QVariantMap m_availability;
    int m_revision = 0;
    int m_writesInFlight = 0;
    int m_viewportWidth = 0;
    bool m_ready = false;
    bool m_schemaLoaded = false;
    bool m_valuesLoaded = false;
    static Settings *s_instance;
};
