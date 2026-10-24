#pragma once

#include <QByteArray>
#include <QHash>
#include <QJSValue>
#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <functional>

class QLocalSocket;
class QTimer;
class QQmlEngine;
class QJSEngine;

class Daemon : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    using Handler = std::function<void(const QJsonValue &result, const QJsonObject &error)>;

    ~Daemon() override;

    static Daemon *create(QQmlEngine *engine, QJSEngine *jsEngine);
    static Daemon *instance() { return s_instance; }

    bool connected() const;

    Q_INVOKABLE int call(const QString &method,
                         const QVariantMap &params = {},
                         const QJSValue &callback = QJSValue());

    int call(const QString &method, const QJsonObject &params, Handler handler);

Q_SIGNALS:
    void connectedChanged();
    void event(const QString &name, const QVariantMap &data);
    void reconnected();

private:
    // Private so QML builds the singleton through create(); a public constructor makes Qt bypass it.
    explicit Daemon(QObject *parent = nullptr);
    void connectToDaemon();
    void onConnected();
    void onDisconnected();
    void onReadyRead();
    void dispatchLine(const QByteArray &line);
    int send(const QString &method, const QJsonObject &params, Handler handler);

    static QString socketPath();

    QLocalSocket *m_socket = nullptr;
    QTimer *m_reconnect = nullptr;
    QJSEngine *m_jsEngine = nullptr;
    QByteArray m_buffer;
    QHash<int, Handler> m_pending;
    int m_nextId = 1;
    int m_backoffMs = 250;
    bool m_wasConnected = false;

    static Daemon *s_instance;
};
