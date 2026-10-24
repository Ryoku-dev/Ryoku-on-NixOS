#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

struct Entry {
    QString key;
    QString name;
    QString type;        // "static" | "video" | "we"
    QString path;
    QString thumb;       // 640x360 webp: far tier and near fallback
    QString thumbSm;     // 240x135 webp
    QString videoFile;
    QString videoPrev;
    QString weId;
    QString weType;      // WE project type: "scene" | "video"
    QString title;
    QString preview;
    QStringList tags;
    int favourite = 0;
    int hue = 99;        // bucket 0-11, 99 desaturated
    int sat = 0;         // 0-100
    int richness = 0;
    qint64 filesize = 0;
    int width = 0;
    int height = 0;
    qint64 mtime = 0;
    int applyCount = 0;

    static QStringList stringList(const QJsonValue &v)
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

    // The daemon stores tags as a comma-joined string in its JSON index; accept that as well as
    // a plain array so the model's tag list is never silently empty.
    static QStringList tagList(const QJsonValue &v)
    {
        if (v.isArray())
            return stringList(v);
        QStringList out;
        const QStringList parts = v.toString().split(QLatin1Char(','), Qt::SkipEmptyParts);
        for (const QString &p : parts) {
            const QString s = p.trimmed();
            if (!s.isEmpty())
                out.append(s);
        }
        return out;
    }

    static Entry fromJson(const QJsonObject &o)
    {
        Entry e;
        e.name = o.value(QStringLiteral("name")).toString();
        e.key = o.value(QStringLiteral("key")).toString();
        if (e.key.isEmpty())
            e.key = e.name;
        e.type = o.value(QStringLiteral("type")).toString();
        e.path = o.value(QStringLiteral("path")).toString();
        e.thumb = o.value(QStringLiteral("thumb")).toString();
        e.thumbSm = o.value(QStringLiteral("thumb_sm")).toString();
        e.videoFile = o.value(QStringLiteral("video_file")).toString();
        e.videoPrev = o.value(QStringLiteral("video_prev")).toString();
        e.weId = o.value(QStringLiteral("we_id")).toString();
        e.weType = o.value(QStringLiteral("we_type")).toString();
        e.title = o.value(QStringLiteral("title")).toString();
        e.preview = o.value(QStringLiteral("preview")).toString();
        e.tags = tagList(o.value(QStringLiteral("tags")));
        e.favourite = o.value(QStringLiteral("favourite")).toInt();
        e.hue = o.contains(QStringLiteral("hue")) ? o.value(QStringLiteral("hue")).toInt(99) : 99;
        e.sat = o.value(QStringLiteral("sat")).toInt();
        e.richness = o.value(QStringLiteral("richness")).toInt();
        e.filesize = static_cast<qint64>(o.value(QStringLiteral("filesize")).toDouble());
        e.width = o.value(QStringLiteral("width")).toInt();
        e.height = o.value(QStringLiteral("height")).toInt();
        e.mtime = static_cast<qint64>(o.value(QStringLiteral("mtime")).toDouble());
        e.applyCount = o.value(QStringLiteral("apply_count")).toInt();
        return e;
    }

    QVariantMap toVariantMap() const
    {
        return {
            {QStringLiteral("key"), key},
            {QStringLiteral("name"), name},
            {QStringLiteral("type"), type},
            {QStringLiteral("path"), path},
            {QStringLiteral("thumb"), thumb},
            {QStringLiteral("thumbSm"), thumbSm},
            {QStringLiteral("videoFile"), videoFile},
            {QStringLiteral("videoPrev"), videoPrev},
            {QStringLiteral("weId"), weId},
            {QStringLiteral("weType"), weType},
            {QStringLiteral("title"), title},
            {QStringLiteral("preview"), preview},
            {QStringLiteral("tags"), tags},
            {QStringLiteral("favourite"), favourite},
            {QStringLiteral("hue"), hue},
            {QStringLiteral("sat"), sat},
            {QStringLiteral("richness"), richness},
            {QStringLiteral("filesize"), filesize},
            {QStringLiteral("width"), width},
            {QStringLiteral("height"), height},
            {QStringLiteral("mtime"), mtime},
            {QStringLiteral("applyCount"), applyCount},
        };
    }
};
