#include "catalogs.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QPainter>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>

namespace {
constexpr int kThemeDebounceMs = 600;
constexpr int kRiceDebounceMs = 1200;

QString dataHome()
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    QString base = env.value(QStringLiteral("XDG_DATA_HOME"));
    if (base.isEmpty())
        base = QDir(QDir::homePath()).filePath(QStringLiteral(".local/share"));
    return base;
}

QString configHome()
{
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    QString base = env.value(QStringLiteral("XDG_CONFIG_HOME"));
    if (base.isEmpty())
        base = QDir(QDir::homePath()).filePath(QStringLiteral(".config"));
    return base;
}

QStringList jsonStrings(const QJsonValue &v)
{
    QStringList out;
    const QJsonArray arr = v.toArray();
    out.reserve(arr.size());
    for (const QJsonValue &e : arr) {
        const QString s = e.toString();
        if (!s.isEmpty())
            out.append(s);
    }
    return out;
}
}

QVariantMap Theme::toVariantMap() const
{
    return {
        {QStringLiteral("id"), id},
        {QStringLiteral("label"), label},
        {QStringLiteral("provider"), provider},
        {QStringLiteral("swatches"), swatches},
        {QStringLiteral("dark"), dark},
        {QStringLiteral("preview"), preview},
    };
}

QVariantMap Rice::toVariantMap() const
{
    return {
        {QStringLiteral("slug"), slug},
        {QStringLiteral("name"), name},
        {QStringLiteral("author"), author},
        {QStringLiteral("blurb"), blurb},
        {QStringLiteral("tags"), tags},
        {QStringLiteral("createdWith"), createdWith},
        {QStringLiteral("compat"), compat},
        {QStringLiteral("active"), active},
        {QStringLiteral("live"), live},
        {QStringLiteral("preview"), preview},
    };
}

Catalogs::Catalogs(QObject *parent)
    : QObject(parent)
    , m_themeProc(new QProcess(this))
    , m_riceProc(new QProcess(this))
    , m_themeDebounce(new QTimer(this))
    , m_riceDebounce(new QTimer(this))
    , m_watcher(new QFileSystemWatcher(this))
{
    m_themeDebounce->setSingleShot(true);
    m_themeDebounce->setInterval(kThemeDebounceMs);
    m_riceDebounce->setSingleShot(true);
    m_riceDebounce->setInterval(kRiceDebounceMs);
    connect(m_themeDebounce, &QTimer::timeout, this, &Catalogs::loadThemes);
    connect(m_riceDebounce, &QTimer::timeout, this, &Catalogs::loadRices);

    connect(m_themeProc, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
        parseThemes(m_themeProc->readAllStandardOutput());
    });
    connect(m_riceProc, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
        parseRices(m_riceProc->readAllStandardOutput());
    });

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &path) {
        if (m_riceWatchPaths.contains(path))
            m_riceDebounce->start();
        else
            m_themeDebounce->start();
    });
}

void Catalogs::start()
{
    const QString themesDir = QDir(dataHome()).filePath(QStringLiteral("ryoku/themes"));
    const QString ricesDir = QDir(configHome()).filePath(QStringLiteral("ryoku/rices"));
    // The picker saves and imports rices itself; without the folder there is nothing to
    // watch, and the first rice would never appear until the picker restarted.
    QDir().mkpath(ricesDir);
    if (QFileInfo::exists(themesDir))
        m_watcher->addPath(themesDir);
    refreshRiceWatches();
    loadThemes();
    loadRices();
}

void Catalogs::refreshRiceWatches()
{
    const QString root = QDir(configHome()).filePath(QStringLiteral("ryoku/rices"));
    QStringList paths{root};
    const QFileInfoList rices = QDir(root).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    paths.reserve(rices.size() + 1);
    for (const QFileInfo &rice : rices)
        paths.append(rice.absoluteFilePath());

    if (!m_riceWatchPaths.isEmpty())
        m_watcher->removePaths(m_riceWatchPaths);
    m_riceWatchPaths = paths;
    m_watcher->addPaths(m_riceWatchPaths);
}

const Theme *Catalogs::theme(const QString &id) const
{
    for (const Theme &t : m_themes) {
        if (t.id == id)
            return &t;
    }
    return nullptr;
}

const Rice *Catalogs::rice(const QString &slug) const
{
    for (const Rice &r : m_rices) {
        if (r.slug == slug)
            return &r;
    }
    return nullptr;
}

void Catalogs::loadThemes()
{
    if (m_themeProc->state() != QProcess::NotRunning)
        return;
    m_themeProc->start(QStringLiteral("ryoku-shell"),
                       {QStringLiteral("theme"), QStringLiteral("catalog")});
}

void Catalogs::loadRices()
{
    if (m_riceProc->state() != QProcess::NotRunning)
        return;
    m_riceProc->start(QStringLiteral("ryoku-hub"),
                      {QStringLiteral("rice"), QStringLiteral("list")});
}

void Catalogs::parseThemes(const QByteArray &json)
{
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isArray())
        return;
    QVector<Theme> themes;
    const QJsonArray arr = doc.array();
    themes.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        // The two dynamic variants (Default, Wallpaper) are not fixed palettes.
        if (o.value(QStringLiteral("dynamic")).toBool())
            continue;
        Theme t;
        t.id = o.value(QStringLiteral("id")).toString();
        t.label = o.value(QStringLiteral("label")).toString();
        t.provider = o.value(QStringLiteral("provider")).toString();
        t.swatches = jsonStrings(o.value(QStringLiteral("sw")));
        t.dark = o.value(QStringLiteral("dark")).toBool();
        t.preview = o.value(QStringLiteral("preview")).toString();
        if (!t.id.isEmpty())
            themes.append(t);
    }
    m_themes = std::move(themes);
    ++m_swatchGen;
    ensureSwatchPreviews();
    Q_EMIT themesChanged();
}

namespace {

// A theme with no store art shows its palette, one band per role.
QImage paintSwatches(const QStringList &swatches)
{
    QImage img(480, 270, QImage::Format_RGB32);
    QPainter p(&img);
    const int n = int(swatches.size());
    for (int i = 0; i < n; ++i) {
        const int x0 = img.width() * i / n;
        const int x1 = img.width() * (i + 1) / n;
        p.fillRect(x0, 0, x1 - x0, img.height(), QColor(swatches.at(i)));
    }
    return img;
}

} // namespace

void Catalogs::ensureSwatchPreviews()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/ryogami/theme-swatches");
    QVector<int> rows;
    QStringList paths;
    QVector<QStringList> palettes;
    for (int i = 0; i < m_themes.size(); ++i) {
        Theme &t = m_themes[i];
        if (!t.preview.isEmpty() || t.swatches.isEmpty())
            continue;
        const QByteArray digest = QCryptographicHash::hash(t.swatches.join(QLatin1Char(',')).toUtf8(),
                                                           QCryptographicHash::Sha1).toHex().left(12);
        const QString path = dir + QLatin1Char('/') + QString::fromLatin1(digest) + QStringLiteral(".png");
        if (QFileInfo::exists(path)) {
            t.preview = path;
            continue;
        }
        rows.append(i);
        paths.append(path);
        palettes.append(t.swatches);
    }
    if (rows.isEmpty())
        return;
    const quint64 gen = m_swatchGen;
    QThreadPool::globalInstance()->start([this, gen, dir, rows, paths, palettes] {
        QDir().mkpath(dir);
        for (int k = 0; k < paths.size(); ++k)
            paintSwatches(palettes.at(k)).save(paths.at(k), "PNG");
        QMetaObject::invokeMethod(this, [this, gen, rows, paths] {
            if (gen != m_swatchGen)
                return;
            for (int k = 0; k < rows.size(); ++k) {
                if (rows.at(k) < m_themes.size() && QFileInfo::exists(paths.at(k)))
                    m_themes[rows.at(k)].preview = paths.at(k);
            }
            Q_EMIT themesChanged();
        }, Qt::QueuedConnection);
    });
}

void Catalogs::parseRices(const QByteArray &json)
{
    refreshRiceWatches();
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isArray())
        return;
    QVector<Rice> rices;
    const QJsonArray arr = doc.array();
    rices.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Rice r;
        r.slug = o.value(QStringLiteral("slug")).toString();
        r.name = o.value(QStringLiteral("name")).toString();
        r.author = o.value(QStringLiteral("author")).toString();
        r.blurb = o.value(QStringLiteral("blurb")).toString();
        r.tags = jsonStrings(o.value(QStringLiteral("tags")));
        r.createdWith = o.value(QStringLiteral("createdWith")).toString();
        r.compat = o.value(QStringLiteral("compat")).toString();
        r.active = o.value(QStringLiteral("active")).toBool();
        r.live = o.value(QStringLiteral("live")).toBool();
        // The Hub lists previews as file:// URLs; the card decoder reads plain paths.
        const QString preview = o.value(QStringLiteral("preview")).toString();
        const QUrl previewUrl(preview);
        r.preview = previewUrl.isLocalFile() ? previewUrl.toLocalFile() : preview;
        if (!r.slug.isEmpty())
            rices.append(r);
    }
    m_rices = std::move(rices);
    Q_EMIT ricesChanged();
}
