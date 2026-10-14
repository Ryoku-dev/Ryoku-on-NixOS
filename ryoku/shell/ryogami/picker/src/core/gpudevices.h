#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Vulkan devices as {id: "uuid:<hex>", name, unavailable}, the ids the wallpaper
// renderer accepts for performance.gpuDevice. An NVIDIA card its kernel driver
// lists but Vulkan cannot open is included with unavailable set to "restart"
// (a driver update waits for a reboot) or "driver".
class GpuDevices : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)

public:
    static GpuDevices *create(QQmlEngine *engine, QJSEngine *jsEngine);

    QVariantList devices();

Q_SIGNALS:
    void devicesChanged();

private:
    // Private so QML builds the singleton through create(); a public constructor makes Qt bypass it.
    explicit GpuDevices(QObject *parent = nullptr);

    QVariantList m_devices;
    bool m_started = false;
};
