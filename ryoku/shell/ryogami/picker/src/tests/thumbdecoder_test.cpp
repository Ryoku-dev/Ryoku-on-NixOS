#include "thumbdecoder.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QImage>
#include <QSet>
#include <QTemporaryDir>
#include <QTimer>

#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir;
    const QString path = dir.filePath(QStringLiteral("thumb.png"));
    QImage image(64, 36, QImage::Format_RGBA8888);
    image.fill(Qt::red);
    if (!image.save(path)) {
        std::fprintf(stderr, "could not create thumbnail fixture\n");
        return 1;
    }

    ThumbDecoder decoder;
    decoder.setTileSizes(QSize(128, 72), QSize(64, 36));
    decoder.retain(QSet<QString>{QStringLiteral("old")});

    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&decoder, &ThumbDecoder::ready, &loop, &QEventLoop::quit,
                     Qt::QueuedConnection);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);

    decoder.request(QStringLiteral("new"), path, ThumbDecoder::Far, 1);
    decoder.retain(QSet<QString>{QStringLiteral("new")});
    timeout.start(2000);
    if (!decoder.hasResults())
        loop.exec();

    const auto results = decoder.take(4);
    if (results.size() != 1 || results.front().image.key != QLatin1String("new")) {
        std::fprintf(stderr, "newly visible thumbnail request was discarded\n");
        return 1;
    }
    return 0;
}
