#include "paramsadapter.h"

#include <QMetaObject>
#include <QObject>

const char *const kEffectNames[12] = {
    "Ignite",     "Edge Fracture", "Tonal Wipe",  "Ash",       "Depth Parallax", "Bokeh Bloom",
    "Light Streaks", "Voxel Extrude", "Pixel Sort", "Rack Focus", "Topographic",   "Tonal Layers",
};

void ParamsAdapter::setSettings(QObject *settings)
{
    m_settings = settings;
    m_valueMethod = QMetaMethod();
    if (!settings)
        return;
    const QMetaObject *mo = settings->metaObject();
    const int idx = mo->indexOfMethod("userValue(QString)");
    if (idx >= 0)
        m_valueMethod = mo->method(idx);
}

QVariant ParamsAdapter::value(const QString &key) const
{
    if (!m_settings || !m_valueMethod.isValid())
        return {};
    QVariant result;
    if (!m_valueMethod.invoke(m_settings.data(), Qt::DirectConnection,
                              Q_RETURN_ARG(QVariant, result), Q_ARG(QString, key)))
        return {};
    return result;
}

MotionProfile readMotionProfile(const ParamSource &p)
{
    MotionProfile m;
    m.fastMs = p.num(QStringLiteral("motion.fastMs"), 180.0);
    m.standardMs = p.num(QStringLiteral("motion.standardMs"), 250.0);
    m.slowMs = p.num(QStringLiteral("motion.slowMs"), 450.0);
    m.scale = p.num(QStringLiteral("motion.scale"), 1.0);
    m.reduced = p.flag(QStringLiteral("motion.reduceMotion"), false);
    return m;
}

double openFadeFrom(const ParamSource &p)
{
    // Stored as a 0-100 percentage (general.openFadeFrom), used as a fraction.
    double v = p.num(QStringLiteral("general.openFadeFrom"), 0.0) / 100.0;
    if (v < 0.0)
        v = 0.0;
    else if (v > 1.0)
        v = 1.0;
    return v;
}

namespace {

// A fast/standard/slow string maps onto a motion tier.
double tierFromKey(const ParamSource &p, const QString &key, const MotionProfile &motion,
                   MotionProfile::Tier fallback)
{
    const QString v = p.text(key, QString());
    if (v == QLatin1String("fast"))
        return motion.ms(MotionProfile::Fast);
    if (v == QLatin1String("slow"))
        return motion.ms(MotionProfile::Slow);
    if (v == QLatin1String("standard"))
        return motion.ms(MotionProfile::Standard);
    return motion.ms(fallback);
}

} // namespace

double launchMotionMs(const ParamSource &p, const MotionProfile &motion)
{
    return tierFromKey(p, QStringLiteral("motion.launchSpeed"), motion, MotionProfile::Standard);
}

double filterSwapMotionMs(const ParamSource &p, const MotionProfile &motion)
{
    return tierFromKey(p, QStringLiteral("motion.filterSwapSpeed"), motion, MotionProfile::Fast);
}

FlipOptions readFlipOptions(const ParamSource &p)
{
    FlipOptions o;
    o.durationMs = p.num(QStringLiteral("components.wallpaperSelector.flipDurationMs"), 1500.0);
    o.shader = p.flag(QStringLiteral("components.wallpaperSelector.flipShader"), true);
    o.back = p.flag(QStringLiteral("components.wallpaperSelector.flipBackReveal"), true);
    const QString name = p.text(QStringLiteral("components.wallpaperSelector.flipEffect"), QStringLiteral("Ash"));
    for (int i = 0; i < 12; ++i) {
        if (name == QLatin1String(kEffectNames[i])) {
            o.effect = i;
            break;
        }
    }
    return o;
}
