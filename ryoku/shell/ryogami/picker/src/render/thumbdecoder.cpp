#include "thumbdecoder.h"

#include <QImageReader>
#include <QMutexLocker>

#include <algorithm>
#include <cmath>

namespace {

QString tokenFor(const QString &key, ThumbDecoder::Tier tier)
{
    return key + QLatin1Char('|') + QString::number(int(tier));
}

QString keyFor(const QString &token)
{
    const int cut = token.lastIndexOf(QLatin1Char('|'));
    return cut < 0 ? token : token.left(cut);
}

int mipCount(QSize layer)
{
    return int(std::floor(std::log2(std::max(1, std::max(layer.width(), layer.height()))))) + 1;
}

QSize fitted(QSize source, QSize box)
{
    if (!source.isValid() || source.isEmpty())
        return box;
    const double scale = std::min({1.0, double(box.width()) / source.width(), double(box.height()) / source.height()});
    return QSize(std::max(1, int(std::lround(source.width() * scale))),
                 std::max(1, int(std::lround(source.height() * scale))));
}

// Animated previews often open on a black frame, which would stand in for the whole item.
bool blankFrame(const QImage &image)
{
    const int stepX = std::max(1, image.width() / 8);
    const int stepY = std::max(1, image.height() / 8);
    for (int y = stepY / 2; y < image.height(); y += stepY) {
        for (int x = stepX / 2; x < image.width(); x += stepX) {
            if (qGray(image.pixel(x, y)) > 12)
                return false;
        }
    }
    return true;
}
QImage decodeScaled(const QString &path, QSize box, QSize &sourceOut)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize source = reader.size();
    reader.setScaledSize(fitted(source, box));
    QImage image = reader.read();
    for (int skipped = 0; skipped < 8 && !image.isNull() && reader.supportsAnimation() && blankFrame(image); ++skipped) {
        QImage next = reader.read();
        if (next.isNull())
            break;
        image = std::move(next);
    }
    if (image.isNull())
        return QImage();
    if (image.width() > box.width() || image.height() > box.height())
        image = image.scaled(box, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    sourceOut = source.isValid() ? source : image.size();
    return std::move(image).convertToFormat(QImage::Format_RGBA8888);
}

// Pads the image out to the full tile box, smearing the edge pixels into the
// border. Blurred cards and the backdrop sample past their content edges and
// across whole mip levels; texels no upload covers hold whatever the driver
// left in that VRAM, so the flash of arbitrary colour some machines show while
// scrolling is undefined memory that reads as clean black on others.
QImage padToBox(const QImage &image, QSize box)
{
    if (image.size() == box)
        return image;
    QImage padded(box, QImage::Format_RGBA8888);
    constexpr int bpp = 4;
    for (int y = 0; y < image.height(); ++y) {
        uchar *dst = padded.scanLine(y);
        const uchar *src = image.constScanLine(y);
        std::memcpy(dst, src, size_t(image.width()) * bpp);
        for (int x = image.width(); x < box.width(); ++x)
            std::memcpy(dst + size_t(x) * bpp, src + size_t(image.width() - 1) * bpp, bpp);
    }
    for (int y = image.height(); y < box.height(); ++y)
        std::memcpy(padded.scanLine(y), padded.constScanLine(image.height() - 1),
                    size_t(box.width()) * bpp);
    return padded;
}

}

ThumbDecoder::ThumbDecoder(QObject *parent)
    : QObject(parent)
    , m_nearTile(1024, 576)
    , m_farTile(256, 160)
{
    m_pool.setMaxThreadCount(std::clamp(QThread::idealThreadCount() / 2, 2, 6));
    m_pool.setExpiryTimeout(2000);
}

ThumbDecoder::~ThumbDecoder()
{
    m_pool.clear();
    m_pool.waitForDone();
}

void ThumbDecoder::setTileSizes(QSize near, QSize far)
{
    m_nearTile = near;
    m_farTile = far;
}

bool ThumbDecoder::pending(const QString &key, Tier tier) const
{
    QMutexLocker lock(&m_mutex);
    return m_inflight.contains(tokenFor(key, tier));
}

bool ThumbDecoder::wantedLocked(const QString &key) const
{
    return !m_retaining || m_wanted.contains(key);
}

void ThumbDecoder::request(const QString &key, const QString &path, Tier tier, int priority)
{
    request(key, path, QString(), tier, priority);
}

void ThumbDecoder::request(const QString &key, const QString &path, const QString &fallback, Tier tier, int priority)
{
    const QString token = tokenFor(key, tier);
    quint64 requestId;
    int generation;
    {
        QMutexLocker lock(&m_mutex);
        m_wanted.insert(key);
        if (m_inflight.contains(token))
            return;
        m_inflight.insert(token);
        requestId = ++m_nextRequest;
        m_requests.insert(token, requestId);
        generation = m_generation.load();
    }
    const QSize box = tier == Near ? m_nearTile : m_farTile;
    const int levels = tier == Near ? mipCount(m_nearTile) : 1;
    m_pool.start([this, key, path, fallback, tier, box, levels, token, requestId, generation] {
        {
            QMutexLocker lock(&m_mutex);
            if (generation != m_generation.load() || m_requests.value(token) != requestId
                || !m_inflight.contains(token) || !wantedLocked(key)) {
                if (m_requests.value(token) == requestId) {
                    m_requests.remove(token);
                    m_inflight.remove(token);
                }
                return;
            }
        }
        QSize source;
        QImage image = decodeScaled(path, box, source);
        if (image.isNull() && !fallback.isEmpty())
            image = decodeScaled(fallback, box, source);
        if (image.isNull()) {
            QMutexLocker lock(&m_mutex);
            if (m_requests.value(token) == requestId) {
                m_requests.remove(token);
                m_inflight.remove(token);
            }
            return;
        }
        const QSize content = image.size();
        QImage base = padToBox(image, box);
        Result result{tier, TierImage{key, content, {}}, source};
        result.image.levels.push_back(std::move(base));
        for (int level = 1; level < levels; ++level) {
            const QSize next(std::max(1, box.width() / (1 << level)),
                             std::max(1, box.height() / (1 << level)));
            result.image.levels.push_back(result.image.levels[size_t(level - 1)].scaled(
                next, Qt::IgnoreAspectRatio, Qt::SmoothTransformation));
        }
        finish(std::move(result), token, requestId, generation);
    }, priority);
}

void ThumbDecoder::finish(Result &&result, const QString &token, quint64 requestId, int generation)
{
    {
        QMutexLocker lock(&m_mutex);
        if (generation != m_generation.load() || !m_inflight.contains(token)
            || m_requests.value(token) != requestId)
            return;
        m_results.push_back(std::move(result));
    }
    Q_EMIT ready();
}

std::vector<ThumbDecoder::Result> ThumbDecoder::take(int maxCount)
{
    QMutexLocker lock(&m_mutex);
    const size_t n = std::min(m_results.size(), size_t(std::max(0, maxCount)));
    std::vector<Result> out;
    out.reserve(n);
    for (size_t i = 0; i < n; ++i) {
        const QString token = tokenFor(m_results[i].image.key, m_results[i].tier);
        m_inflight.remove(token);
        m_requests.remove(token);
        out.push_back(std::move(m_results[i]));
    }
    m_results.erase(m_results.begin(), m_results.begin() + qsizetype(n));
    return out;
}

bool ThumbDecoder::hasResults() const
{
    QMutexLocker lock(&m_mutex);
    return !m_results.empty();
}

void ThumbDecoder::invalidate(const QString &key)
{
    QMutexLocker lock(&m_mutex);
    for (Tier tier : {Near, Far}) {
        const QString token = tokenFor(key, tier);
        m_inflight.remove(token);
        m_requests.remove(token);
    }
    m_results.erase(std::remove_if(m_results.begin(), m_results.end(),
                                   [&key](const Result &r) { return r.image.key == key; }),
                    m_results.end());
}

void ThumbDecoder::cancelQueued()
{
    QMutexLocker lock(&m_mutex);
    ++m_generation;
    m_inflight.clear();
    m_requests.clear();
    m_results.clear();
}

void ThumbDecoder::retain(const QSet<QString> &keys)
{
    QMutexLocker lock(&m_mutex);
    m_retaining = true;
    m_wanted = keys;
    // Clearing the request identity makes a finishing worker discard its result.
    for (auto it = m_inflight.begin(); it != m_inflight.end();) {
        if (keys.contains(keyFor(*it))) {
            ++it;
        } else {
            m_requests.remove(*it);
            it = m_inflight.erase(it);
        }
    }
    m_results.erase(std::remove_if(m_results.begin(), m_results.end(),
                                   [&keys](const Result &r) { return !keys.contains(r.image.key); }),
                    m_results.end());
}
