#include "settingvalue.h"

#include "settings.h"

#include <QQmlEngine>

SettingValue::SettingValue(QObject *parent)
    : QObject(parent)
{
}

void SettingValue::componentComplete()
{
    if (QQmlEngine *engine = qmlEngine(this)) {
        m_settings = engine->singletonInstance<Settings *>(
            QStringLiteral("Ryoku.Ryogami"), QStringLiteral("Settings"));
    }
    if (!m_settings)
        m_settings = Settings::instance();
    if (m_settings) {
        connect(m_settings, &Settings::changed, this, &SettingValue::onChanged);
        connect(m_settings, &Settings::readyChanged, this, &SettingValue::onReadyChanged);
    }
    if (!m_key.isEmpty()) {
        Q_EMIT valueChanged();
        Q_EMIT specChanged();
    }
}

void SettingValue::setKey(const QString &key)
{
    if (m_key == key)
        return;
    m_key = key;
    Q_EMIT keyChanged();
    Q_EMIT specChanged();
    Q_EMIT valueChanged();
}

QVariant SettingValue::value() const
{
    return m_settings ? m_settings->value(m_key) : QVariant();
}

QVariantMap SettingValue::spec() const
{
    return m_settings ? m_settings->spec(m_key) : QVariantMap();
}

bool SettingValue::isDefault() const
{
    return m_settings ? m_settings->isDefault(m_key) : true;
}

void SettingValue::set(const QVariant &value)
{
    if (m_settings && !m_key.isEmpty())
        m_settings->set(m_key, value);
}

void SettingValue::reset()
{
    if (m_settings && !m_key.isEmpty())
        m_settings->reset(m_key);
}

void SettingValue::onChanged(const QString &key, const QVariant &)
{
    if (key == m_key)
        Q_EMIT valueChanged();
}

void SettingValue::onReadyChanged()
{
    Q_EMIT specChanged();
    Q_EMIT valueChanged();
}
