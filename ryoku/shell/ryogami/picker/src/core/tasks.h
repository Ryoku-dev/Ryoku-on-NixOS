#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Daemon;
class QQmlEngine;
class QJSEngine;

// The daemon's background jobs, reduced to what the filter bar shows: every
// running task, or the last one when it failed (skwd's bar_tasks).
class Tasks : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList bar READ bar NOTIFY changed)

public:
    static Tasks *create(QQmlEngine *engine, QJSEngine *jsEngine);

    QVariantList bar() const { return m_bar; }

    Q_INVOKABLE void control(const QString &id, const QString &action);

Q_SIGNALS:
    void changed();

private:
    // Private so QML builds the singleton through create(); a public constructor makes Qt bypass it.
    explicit Tasks(QObject *parent = nullptr);
    void refresh();
    void upsert(const QVariantMap &task);
    void rebuildBar();

    Daemon *m_daemon = nullptr;
    QStringList m_order;
    QHash<QString, QVariantMap> m_byId;
    QVariantList m_bar;
};
