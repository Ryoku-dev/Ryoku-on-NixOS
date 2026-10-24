#include "gpudevices.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QLibrary>
#include <QThreadPool>
#include <QVariantMap>

#include <algorithm>
#include <vector>

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

namespace {

struct Device {
    QString id;
    QString name;
    // Why a card the kernel driver knows is missing from Vulkan; empty when usable.
    QString unavailable;
};

// The id is the device UUID, the same identity the renderer matches on.
std::vector<Device> enumerate()
{
    QLibrary lib(QStringLiteral("vulkan"), 1);
    if (!lib.load())
        return {};
    auto getProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(lib.resolve("vkGetInstanceProcAddr"));
    if (!getProc)
        return {};
    auto createInstance = reinterpret_cast<PFN_vkCreateInstance>(getProc(nullptr, "vkCreateInstance"));
    if (!createInstance)
        return {};

    VkApplicationInfo app{};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "ryogami";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    info.pApplicationInfo = &app;
    VkInstance instance = VK_NULL_HANDLE;
    if (createInstance(&info, nullptr, &instance) != VK_SUCCESS)
        return {};

    auto destroy = reinterpret_cast<PFN_vkDestroyInstance>(getProc(instance, "vkDestroyInstance"));
    auto enumerateDevices = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(
        getProc(instance, "vkEnumeratePhysicalDevices"));
    auto properties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(
        getProc(instance, "vkGetPhysicalDeviceProperties"));
    auto properties2 = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties2>(
        getProc(instance, "vkGetPhysicalDeviceProperties2"));

    std::vector<Device> out;
    uint32_t count = 0;
    if (enumerateDevices && properties && properties2
        && enumerateDevices(instance, &count, nullptr) == VK_SUCCESS && count > 0) {
        std::vector<VkPhysicalDevice> physical(count);
        enumerateDevices(instance, &count, physical.data());
        for (VkPhysicalDevice device : physical) {
            VkPhysicalDeviceProperties props{};
            properties(device, &props);
            if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU || props.apiVersion < VK_API_VERSION_1_1)
                continue;
            VkPhysicalDeviceIDProperties ids{};
            ids.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES;
            VkPhysicalDeviceProperties2 props2{};
            props2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
            props2.pNext = &ids;
            properties2(device, &props2);
            QString id = QStringLiteral("uuid:");
            for (uint8_t byte : ids.deviceUUID)
                id += QStringLiteral("%1").arg(byte, 2, 16, QLatin1Char('0'));
            out.push_back({id, QString::fromUtf8(props.deviceName)});
        }
    }
    if (destroy)
        destroy(instance, nullptr);

    std::sort(out.begin(), out.end(), [](const Device &a, const Device &b) {
        return a.name != b.name ? a.name < b.name : a.id < b.id;
    });
    out.erase(std::unique(out.begin(), out.end(),
                          [](const Device &a, const Device &b) { return a.id == b.id; }),
              out.end());
    return out;
}

// An NVIDIA driver update replaces the libraries at once while the old kernel
// module stays loaded until a restart; until then Vulkan cannot open the card.
bool nvidiaRestartPending()
{
    QFile module(QStringLiteral("/sys/module/nvidia/version"));
    if (!module.open(QIODevice::ReadOnly))
        return false;
    const QString loaded = QString::fromUtf8(module.readAll()).trimmed();
    if (loaded.isEmpty())
        return false;
    for (const char *dir : {"/usr/lib64", "/usr/lib", "/usr/lib/x86_64-linux-gnu"}) {
        const QFileInfo lib(QStringLiteral("%1/libEGL_nvidia.so.0").arg(QLatin1String(dir)));
        if (!lib.exists())
            continue;
        const QString target = lib.canonicalFilePath();
        const QString version = target.mid(target.lastIndexOf(QLatin1String(".so.")) + 4);
        return !version.isEmpty() && version != loaded;
    }
    return false;
}

// The kernel driver lists its cards even when Vulkan cannot reach them, so the
// setting can still name the card the user picked. Its GPU UUID is the Vulkan
// deviceUUID written with dashes.
std::vector<Device> nvidiaKernelGpus()
{
    std::vector<Device> out;
    const QDir root(QStringLiteral("/proc/driver/nvidia/gpus"));
    for (const QString &bus : root.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        QFile info(root.filePath(bus + QStringLiteral("/information")));
        if (!info.open(QIODevice::ReadOnly))
            continue;
        QString model, uuid;
        for (const QByteArray &line : info.readAll().split('\n')) {
            const int colon = line.indexOf(':');
            if (colon < 0)
                continue;
            const QByteArray key = line.left(colon).trimmed();
            const QString value = QString::fromUtf8(line.mid(colon + 1)).trimmed();
            if (key == "Model")
                model = value;
            else if (key == "GPU UUID")
                uuid = value;
        }
        QString hex = uuid.startsWith(QLatin1String("GPU-")) ? uuid.mid(4).remove(QLatin1Char('-')).toLower()
                                                            : QString();
        if (hex.size() == 32 && !model.isEmpty())
            out.push_back({QStringLiteral("uuid:") + hex, model, QString()});
    }
    return out;
}

std::vector<Device> listDevices()
{
    std::vector<Device> found = enumerate();
    const std::vector<Device> kernel = nvidiaKernelGpus();
    const QString reason = nvidiaRestartPending() ? QStringLiteral("restart") : QStringLiteral("driver");
    for (Device d : kernel) {
        const bool reachable = std::any_of(found.begin(), found.end(),
                                           [&](const Device &v) { return v.id == d.id; });
        if (reachable)
            continue;
        d.unavailable = reason;
        found.push_back(d);
    }
    return found;
}

} // namespace

GpuDevices::GpuDevices(QObject *parent)
    : QObject(parent)
{
}

GpuDevices *GpuDevices::create(QQmlEngine *, QJSEngine *)
{
    static GpuDevices *instance = nullptr;
    if (!instance) {
        instance = new GpuDevices;
        QJSEngine::setObjectOwnership(instance, QJSEngine::CppOwnership);
    }
    return instance;
}

QVariantList GpuDevices::devices()
{
    if (!m_started) {
        m_started = true;
        // Creating a Vulkan instance loads every driver, far too slow for the GUI thread.
        GpuDevices *self = this;
        QThreadPool::globalInstance()->start([self] {
            const std::vector<Device> found = listDevices();
            QVariantList list;
            for (const Device &d : found) {
                const bool twin = std::count_if(found.begin(), found.end(),
                                                [&](const Device &o) { return o.name == d.name; }) > 1;
                list.append(QVariantMap{
                    {QStringLiteral("id"), d.id},
                    {QStringLiteral("name"), twin ? QStringLiteral("%1 (%2)").arg(d.name, d.id) : d.name},
                    {QStringLiteral("unavailable"), d.unavailable},
                });
            }
            QMetaObject::invokeMethod(
                self,
                [self, list] {
                    self->m_devices = list;
                    Q_EMIT self->devicesChanged();
                },
                Qt::QueuedConnection);
        });
    }
    return m_devices;
}
