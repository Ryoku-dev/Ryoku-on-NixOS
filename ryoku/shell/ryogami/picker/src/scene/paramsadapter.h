#pragma once

#include "params.h"

#include <QMetaMethod>
#include <QPointer>

class QObject;

// An unset key comes back invalid so ParamSource falls back to its default.
class ParamsAdapter : public ParamSource
{
public:
    ParamsAdapter() = default;

    void setSettings(QObject *settings);
    QObject *settings() const { return m_settings.data(); }

    // Drives the 1600 px small-screen classification.
    void setViewportWidth(double width) { m_viewportWidth = width; }

    QVariant value(const QString &key) const override;
    bool smallScreen() const override { return m_viewportWidth > 0.0 && m_viewportWidth <= 1600.0; }

private:
    QPointer<QObject> m_settings;
    QMetaMethod m_valueMethod;
    double m_viewportWidth = 0.0;
};

// Ordered so the effect id is the index of the setting string.
extern const char *const kEffectNames[12];

MotionProfile readMotionProfile(const ParamSource &p);

double openFadeFrom(const ParamSource &p);
double launchMotionMs(const ParamSource &p, const MotionProfile &motion);
double filterSwapMotionMs(const ParamSource &p, const MotionProfile &motion);

struct FlipOptions {
    double durationMs = 1500.0;
    bool shader = true;
    bool back = true;
    int effect = 3;
};
FlipOptions readFlipOptions(const ParamSource &p);
