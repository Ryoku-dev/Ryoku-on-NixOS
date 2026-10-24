#include "daemon.h"

#include <QDir>
#include <QJSEngine>
#include <QPointer>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QProcessEnvironment>
#include <QTimer>

Daemon *Daemon::s_instance = nullptr;

Daemon::Daemon(QObject *parent)
    : QObject(parent)
    , m_socket(new QLocalSocket(this))
    , m_reconnect(new QTimer(this))
{
    m_reconnect->setSingleShot(true);
    connect(m_reconnect, &QTimer::timeout, this, &Daemon::connectToDaemon);
    connect(m_socket, &QLocalSocket::connected, this, &Daemon::onConnected);
    connect(m_socket, &QLocalSocket::disconnected, this, &Daemon::onDisconnected);
    connect(m_socket, &QLocalSocket::errorOccurred, this, &Daemon::onDisconnected);
    connect(m_socket, &QLocalSocket::readyRead, this, &Daemon::onReadyRead);
    connectToDaemon();
}

Daemon::~Daemon() = default;

Daemon *Daemon::create(QQmlEngine *, QJSEngine *jsEngine)
{
    if (!s_instance) {
        s_instance = new Daemon;
        // Own the singleton in C++; the engine must not delete it.
        QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    }
    s_instance->m_jsEngine = jsEngine;
    return s_instance;
}

QString Daemon::socketPath()
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    const QString runtime = env.value(QStringLiteral("XDG_RUNTIME_DIR"));
    if (!runtime.isEmpty())
        return QDir(runtime).filePath(QStringLiteral("ryogami.sock"));
    return QStringLiteral("/tmp/ryogami.sock");
}

bool Daemon::connected() const
{
    return m_socket->state() == QLocalSocket::ConnectedState;
}

void Daemon::connectToDaemon()
{
    if (m_socket->state() != QLocalSocket::UnconnectedState)
        return;
    m_socket->connectToServer(socketPath());
}

void Daemon::onConnected()
{
    m_backoffMs = 250;
    m_buffer.clear();
    m_wasConnected = true;
    Q_EMIT connectedChanged();
    send(QStringLiteral("subscribe"), {}, nullptr);
    Q_EMIT reconnected();
}

void Daemon::onDisconnected()
{
    // Fail every in-flight call so callers are not left waiting forever.
    if (!m_pending.isEmpty()) {
        const QJsonObject err{{QStringLiteral("code"), -1},
                              {QStringLiteral("message"), QStringLiteral("disconnected")}};
        const auto handlers = m_pending;
        m_pending.clear();
        for (const Handler &h : handlers) {
            if (h)
                h(QJsonValue::Undefined, err);
        }
    }
    if (m_wasConnected) {
        m_wasConnected = false;
        Q_EMIT connectedChanged();
    }
    if (m_socket->state() != QLocalSocket::UnconnectedState)
        m_socket->abort();
    if (!m_reconnect->isActive()) {
        m_reconnect->start(m_backoffMs);
        m_backoffMs = qMin(m_backoffMs * 2, 2000);
    }
}

void Daemon::onReadyRead()
{
    m_buffer += m_socket->readAll();
    int newline;
    while ((newline = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(newline);
        m_buffer.remove(0, newline + 1);
        if (!line.isEmpty())
            dispatchLine(line);
    }
}

void Daemon::dispatchLine(const QByteArray &line)
{
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(line, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject())
        return;
    const QJsonObject obj = doc.object();

    if (obj.contains(QStringLiteral("event"))) {
        Q_EMIT event(obj.value(QStringLiteral("event")).toString(),
                     obj.value(QStringLiteral("data")).toObject().toVariantMap());
        return;
    }
    if (obj.contains(QStringLiteral("id"))) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        const Handler handler = m_pending.take(id);
        if (!handler)
            return;
        if (obj.contains(QStringLiteral("error")))
            handler(QJsonValue::Undefined, obj.value(QStringLiteral("error")).toObject());
        else
            handler(obj.value(QStringLiteral("result")), QJsonObject());
    }
}

int Daemon::send(const QString &method, const QJsonObject &params, Handler handler)
{
    const int id = m_nextId++;
    if (handler)
        m_pending.insert(id, std::move(handler));
    QJsonObject req{{QStringLiteral("method"), method},
                    {QStringLiteral("params"), params},
                    {QStringLiteral("id"), id}};
    if (connected()) {
        QByteArray payload = QJsonDocument(req).toJson(QJsonDocument::Compact);
        payload += '\n';
        m_socket->write(payload);
        m_socket->flush();
    } else if (m_pending.contains(id)) {
        // Report on the next event-loop turn so the caller always sees an asynchronous result.
        const Handler pending = m_pending.take(id);
        QMetaObject::invokeMethod(this, [pending]() {
            pending(QJsonValue::Undefined,
                    QJsonObject{{QStringLiteral("code"), -1},
                                {QStringLiteral("message"), QStringLiteral("not connected")}});
        }, Qt::QueuedConnection);
    }
    return id;
}

int Daemon::call(const QString &method, const QJsonObject &params, Handler handler)
{
    return send(method, params, std::move(handler));
}

int Daemon::call(const QString &method, const QVariantMap &params, const QJSValue &callback)
{
    Handler handler;
    if (callback.isCallable()) {
        QJSValue cb = callback;
        // A raw engine pointer survives the engine: a reply landing during
        // teardown would call into freed memory. QPointer goes null with it.
        const QPointer<QJSEngine> engine = m_jsEngine;
        handler = [cb, engine](const QJsonValue &result, const QJsonObject &error) mutable {
            if (!engine)
                return;
            QJSValueList args;
            if (!error.isEmpty()) {
                args << QJSValue(QJSValue::NullValue)
                     << engine->toScriptValue(error.toVariantMap());
            } else {
                // Through QVariant, nested lists reach JS as Qt sequences that
                // fail Array.isArray; the JSON value converts to native arrays.
                args << engine->toScriptValue(result)
                     << QJSValue(QJSValue::NullValue);
            }
            cb.call(args);
        };
    }
    return send(method, QJsonObject::fromVariantMap(params), std::move(handler));
}
