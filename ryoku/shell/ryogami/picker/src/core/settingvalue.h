#pragma once

#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include <QtQml/qqmlparserstatus.h>

class Settings;

class SettingValue : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(QVariant value READ value NOTIFY valueChanged)
    Q_PROPERTY(QVariantMap spec READ spec NOTIFY specChanged)
    Q_PROPERTY(bool isDefault READ isDefault NOTIFY valueChanged)

public:
    explicit SettingValue(QObject *parent = nullptr);

    QString key() const { return m_key; }
    void setKey(const QString &key);

    QVariant value() const;
    QVariantMap spec() const;
    bool isDefault() const;

    Q_INVOKABLE void set(const QVariant &value);
    Q_INVOKABLE void reset();

    void classBegin() override {}
    void componentComplete() override;

Q_SIGNALS:
    void keyChanged();
    void valueChanged();
    void specChanged();

private:
    void onChanged(const QString &key, const QVariant &value);
    void onReadyChanged();

    Settings *m_settings = nullptr;
    QString m_key;
};
