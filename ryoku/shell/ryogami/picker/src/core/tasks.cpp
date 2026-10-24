#include "tasks.h"

#include "daemon.h"

#include <QJSEngine>
#include <QJsonArray>
#include <QJsonObject>
#include <QQmlEngine>

namespace {

const QString kRunning = QStringLiteral("running");
const QString kFailed = QStringLiteral("failed");
const QString kStatusEvent = QStringLiteral("ryogami.task.status");
// The daemon keeps this many finished tasks too; older ones leave both lists.
constexpr int kKeepFinished = 4;

}

Tasks::Tasks(QObject *parent)
    : QObject(parent)
{
}

Tasks *Tasks::create(QQmlEngine *engine, QJSEngine *)
{
    auto *tasks = new Tasks;
    QJSEngine::setObjectOwnership(tasks, QJSEngine::CppOwnership);
    tasks->m_daemon = engine->singletonInstance<Daemon *>(QStringLiteral("Ryoku.Ryogami"), QStringLiteral("Daemon"));
    if (tasks->m_daemon) {
        connect(tasks->m_daemon, &Daemon::reconnected, tasks, &Tasks::refresh);
        connect(tasks->m_daemon, &Daemon::event, tasks, [tasks](const QString &name, const QVariantMap &data) {
            if (name == kStatusEvent)
                tasks->upsert(data);
        });
        if (tasks->m_daemon->connected())
            tasks->refresh();
    }
    return tasks;
}

void Tasks::control(const QString &id, const QString &action)
{
    if (m_daemon)
        m_daemon->call(QStringLiteral("task.control"),
                       QJsonObject{{QStringLiteral("id"), id}, {QStringLiteral("action"), action}},
                       [](const QJsonValue &, const QJsonObject &) {});
}

void Tasks::refresh()
{
    m_daemon->call(QStringLiteral("task.list"), QJsonObject{}, [this](const QJsonValue &result, const QJsonObject &error) {
        if (!error.isEmpty())
            return;
        m_order.clear();
        m_byId.clear();
        const QJsonArray list = result.toObject().value(QStringLiteral("tasks")).toArray();
        for (const QJsonValue &v : list) {
            const QVariantMap task = v.toObject().toVariantMap();
            const QString id = task.value(QStringLiteral("id")).toString();
            m_order.append(id);
            m_byId.insert(id, task);
        }
        rebuildBar();
    });
}

void Tasks::upsert(const QVariantMap &task)
{
    const QString id = task.value(QStringLiteral("id")).toString();
    if (id.isEmpty())
        return;
    // A restarted task moves to the end, as the daemon orders it.
    m_order.removeAll(id);
    m_order.append(id);
    m_byId.insert(id, task);
    int finished = 0;
    for (int i = m_order.size() - 1; i >= 0; --i) {
        const QString &key = m_order.at(i);
        if (m_byId.value(key).value(QStringLiteral("state")).toString() == kRunning)
            continue;
        if (++finished > kKeepFinished) {
            m_byId.remove(key);
            m_order.removeAt(i);
        }
    }
    rebuildBar();
}

void Tasks::rebuildBar()
{
    QVariantList bar;
    for (const QString &id : m_order) {
        const QVariantMap &task = m_byId[id];
        if (task.value(QStringLiteral("state")).toString() == kRunning)
            bar.append(task);
    }
    if (bar.isEmpty() && !m_order.isEmpty()) {
        const QVariantMap &last = m_byId[m_order.last()];
        if (last.value(QStringLiteral("state")).toString() == kFailed)
            bar.append(last);
    }
    if (bar == m_bar)
        return;
    m_bar = bar;
    Q_EMIT changed();
}
