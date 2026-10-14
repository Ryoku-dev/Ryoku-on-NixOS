#pragma once

#include "texturetier.h"

#include <atomic>

#include <QHash>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QSize>
#include <QString>
#include <QThreadPool>

#include <vector>

class ThumbDecoder : public QObject
{
    Q_OBJECT
public:
    enum Tier { Near = 1, Far = 2 };

    struct Result {
        Tier tier;
        TierImage image;
        QSize sourceSize;
    };

    explicit ThumbDecoder(QObject *parent = nullptr);
    ~ThumbDecoder() override;

    void setTileSizes(QSize near, QSize far);

    void request(const QString &key, const QString &path, Tier tier, int priority);
    void request(const QString &key, const QString &path, const QString &fallback, Tier tier, int priority);
    bool pending(const QString &key, Tier tier) const;

    std::vector<Result> take(int maxCount);
    bool hasResults() const;

    void invalidate(const QString &key);
    void cancelQueued();

    // Pass the visible key set each sync to keep the queue bounded.
    void retain(const QSet<QString> &keys);

Q_SIGNALS:
    // Emitted from a worker thread whenever the mailbox gains an image.
    void ready();

private:
    void finish(Result &&result, const QString &token, quint64 requestId, int generation);
    bool wantedLocked(const QString &key) const;

    QThreadPool m_pool;
    mutable QMutex m_mutex;
    QSet<QString> m_inflight;
    QHash<QString, quint64> m_requests;
    QSet<QString> m_wanted;
    bool m_retaining = false;
    std::vector<Result> m_results;
    std::atomic<int> m_generation{0};
    quint64 m_nextRequest = 0;
    QSize m_nearTile;
    QSize m_farTile;
};
