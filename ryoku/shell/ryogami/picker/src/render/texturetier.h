#pragma once

#include <QHash>
#include <QImage>
#include <QRectF>
#include <QSize>
#include <QString>

#include <memory>
#include <vector>

class QRhi;
class QRhiResourceUpdateBatch;
class QRhiTexture;

// Level 0 and its mip chain, each padded to the full tile box; content is the
// aspect-fitted image inside that box.
struct TierImage {
    QString key;
    QSize content;
    std::vector<QImage> levels;
};

// Near tiers hold one card per layer with mips; far tiers pack many small tiles per layer.
class TextureTier
{
public:
    struct Slot {
        int layer = 0;
        QRectF uv;  // origin and size inside the layer, normalized
    };

    TextureTier(QSize layerSize, QSize tileSize, int initialLayers, int maxLayers, int mipLevels);
    ~TextureTier();

    const Slot *find(const QString &key);
    bool contains(const QString &key) const { return m_index.contains(key); }

    // False when every tile is pinned by the last two frames.
    bool admit(TierImage &&image);
    void reserve(int tiles);
    // Evicts one key without disturbing any other resident texture.
    bool invalidate(const QString &key);

    // Tiles used in the previous two frames are protected.
    void beginFrame();

    // True when the QRhiTexture object changed and bindings must be rebuilt.
    bool commit(QRhi *rhi, QRhiResourceUpdateBatch *batch);

    QRhiTexture *texture() const { return m_texture.get(); }
    // Layers the live texture actually has; may be below the logical count
    // when a grown array failed to allocate until the next successful commit.
    int liveLayers() const { return m_texture ? m_textureLayers : 0; }
    int mipLevels() const { return m_mipLevels; }
    QSize tileSize() const { return m_tile; }
    int capacity() const { return m_maxLayers * tilesPerLayer(); }
    int resident() const { return int(m_index.size()); }

    void releaseResources();

private:
    struct Tile {
        QString key;
        quint64 lastUsed = 0;
        Slot slot;
    };
    struct Pending {
        int tile = -1;
        std::vector<QImage> levels;
    };

    int tilesPerLayer() const;
    int tileCount() const { return m_layers * tilesPerLayer(); }
    QRect tileRect(int tile) const;
    int acquireTile();

    QSize m_layerSize;
    QSize m_tile;
    int m_layers;
    int m_maxLayers;
    int m_mipLevels;
    quint64 m_frame = 2;

    std::vector<Tile> m_tiles;
    std::vector<int> m_free;
    QHash<QString, int> m_index;
    std::vector<Pending> m_pending;

    std::unique_ptr<QRhiTexture> m_texture;
    int m_textureLayers = 0;
};
