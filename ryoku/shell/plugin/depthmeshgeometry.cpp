#include "depthmeshgeometry.hpp"

#include <QFileInfo>
#include <QImage>
#include <QMetaObject>
#include <QtConcurrent/QtConcurrentRun>
#include <QVector3D>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <numbers>
#include <vector>

namespace {

constexpr int kColumns = 321;
constexpr int kRows = 181;
constexpr int kRefine = 4;
constexpr int kCellCount = (kColumns - 1) * (kRows - 1);
constexpr int kMaxVertices = 400000;
constexpr double kFarDistance = 3.3;
constexpr double kDepthSpan = 0.8;
constexpr double kNearScale = 0.8;
constexpr double kFarScale = 0.8;
constexpr double kFovDegrees = 42.0;
constexpr double kRefineThreshold = 0.08;
constexpr float kPivotDepth = 0.5f;

struct Vertex {
    float x, y, z, u, v;
};

QString localPath(const QUrl &url)
{
    const QString path = url.isLocalFile() ? url.toLocalFile()
        : url.scheme().isEmpty() ? url.path(QUrl::FullyDecoded) : QString();
    return QFileInfo(path).isAbsolute() ? path : QString();
}

struct ImagePlane {
    QImage image;
    bool wide = false;

    bool load(const QUrl &url, QImage::Format format)
    {
        const QString path = localPath(url);
        if (path.isEmpty())
            return false;
        QImage loaded(path);
        if (loaded.isNull())
            return false;
        image = loaded.convertToFormat(format);
        if (image.isNull() || image.width() < 2 || image.height() < 2)
            return false;
        wide = image.format() == QImage::Format_Grayscale16;
        return true;
    }

    float read(int x, int y) const
    {
        const uchar *row = image.constScanLine(y);
        if (wide)
            return reinterpret_cast<const quint16 *>(row)[x] / 65535.0f;
        return row[x] / 255.0f;
    }

    float at(float u, float v) const
    {
        const float fx = std::clamp(u, 0.0f, 1.0f) * (image.width() - 1);
        const float fy = std::clamp(v, 0.0f, 1.0f) * (image.height() - 1);
        const int x0 = int(std::floor(fx));
        const int y0 = int(std::floor(fy));
        const int x1 = std::min(x0 + 1, image.width() - 1);
        const int y1 = std::min(y0 + 1, image.height() - 1);
        const float tx = fx - x0;
        const float ty = fy - y0;
        const float top = read(x0, y0) * (1.0f - tx) + read(x1, y0) * tx;
        const float bottom = read(x0, y1) * (1.0f - tx) + read(x1, y1) * tx;
        return top * (1.0f - ty) + bottom * ty;
    }
};

struct UvMapping {
    float scaleU = 1.0f;
    float scaleV = 1.0f;
    float offsetU = 0.0f;
    float offsetV = 0.0f;

    float u(float value) const { return offsetU + value * scaleU; }
    float v(float value) const { return offsetV + value * scaleV; }
};

float maskAt(const std::vector<float> &mask, float u, float v)
{
    const float fx = std::clamp(u * (kColumns - 1), 0.0f, float(kColumns - 1));
    const float fy = std::clamp(v * (kRows - 1), 0.0f, float(kRows - 1));
    const int x0 = int(std::floor(fx));
    const int y0 = int(std::floor(fy));
    const int x1 = std::min(x0 + 1, kColumns - 1);
    const int y1 = std::min(y0 + 1, kRows - 1);
    const float tx = fx - x0;
    const float ty = fy - y0;
    const float top = mask[y0 * kColumns + x0] * (1.0f - tx)
        + mask[y0 * kColumns + x1] * tx;
    const float bottom = mask[y1 * kColumns + x0] * (1.0f - tx)
        + mask[y1 * kColumns + x1] * tx;
    return top * (1.0f - ty) + bottom * ty;
}

void dilate(std::vector<float> &mask, int radius)
{
    std::vector<float> out(mask.size());
    for (int y = 0; y < kRows; ++y) {
        for (int x = 0; x < kColumns; ++x) {
            float value = 0.0f;
            for (int oy = -radius; oy <= radius; ++oy) {
                const int yy = std::clamp(y + oy, 0, kRows - 1);
                for (int ox = -radius; ox <= radius; ++ox) {
                    const int xx = std::clamp(x + ox, 0, kColumns - 1);
                    value = std::max(value, mask[yy * kColumns + xx]);
                }
            }
            out[y * kColumns + x] = value;
        }
    }
    mask.swap(out);
}

void blur(std::vector<float> &mask)
{
    std::vector<float> out(mask.size());
    for (int y = 0; y < kRows; ++y) {
        for (int x = 0; x < kColumns; ++x) {
            float sum = 0.0f;
            for (int oy = -1; oy <= 1; ++oy) {
                const int yy = std::clamp(y + oy, 0, kRows - 1);
                for (int ox = -1; ox <= 1; ++ox) {
                    const int xx = std::clamp(x + ox, 0, kColumns - 1);
                    sum += mask[yy * kColumns + xx];
                }
            }
            out[y * kColumns + x] = sum / 9.0f;
        }
    }
    mask.swap(out);
}

} // namespace
struct DepthMeshGeometry::BuildRequest {
    QUrl depthPath;
    QUrl mattePath;
    float imageZoom;
    float outputAspect;
    float sourceAspect;
    FitMode fitMode;
};

struct DepthMeshGeometry::MeshData {
    QByteArray vertices;
    QByteArray indices;
    QVector3D minimum;
    QVector3D maximum;
    float focusDistance = 0.0f;
    float backgroundDistance = 0.0f;
    bool valid = false;
};


DepthMeshGeometry::DepthMeshGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    setStride(sizeof(Vertex));
    setPrimitiveType(PrimitiveType::Triangles);
    addAttribute(Attribute::PositionSemantic, offsetof(Vertex, x), Attribute::F32Type);
    addAttribute(Attribute::TexCoord0Semantic, offsetof(Vertex, u), Attribute::F32Type);
    addAttribute(Attribute::IndexSemantic, 0, Attribute::U32Type);
}

void DepthMeshGeometry::setDepthPath(const QUrl &path)
{
    if (m_depthPath == path)
        return;
    m_depthPath = path;
    emit depthPathChanged();
    scheduleRebuild();
}

void DepthMeshGeometry::setMattePath(const QUrl &path)
{
    if (m_mattePath == path)
        return;
    m_mattePath = path;
    emit mattePathChanged();
    scheduleRebuild();
}

void DepthMeshGeometry::setImageZoom(float zoom)
{
    const float bounded = std::clamp(zoom, 1.0f, 1.5f);
    if (std::abs(m_imageZoom - bounded) < 1e-5f)
        return;
    m_imageZoom = bounded;
    emit imageZoomChanged();
    scheduleRebuild();
}

void DepthMeshGeometry::setOutputAspect(float aspect)
{
    const float bounded = std::clamp(aspect, 0.5f, 4.0f);
    if (std::abs(m_outputAspect - bounded) < 1e-5f)
        return;
    m_outputAspect = bounded;
    emit outputAspectChanged();
    scheduleRebuild();
}

void DepthMeshGeometry::setSourceAspect(float aspect)
{
    const float bounded = std::clamp(aspect, 0.01f, 100.0f);
    if (std::abs(m_sourceAspect - bounded) < 1e-5f)
        return;
    m_sourceAspect = bounded;
    emit sourceAspectChanged();
    scheduleRebuild();
}
void DepthMeshGeometry::setFitMode(FitMode mode)
{
    if (m_fitMode == mode)
        return;
    m_fitMode = mode;
    emit fitModeChanged();
    scheduleRebuild();
}


void DepthMeshGeometry::scheduleRebuild()
{
    ++m_generation;
    if (m_rebuildPending)
        return;
    m_rebuildPending = true;
    QMetaObject::invokeMethod(this, [this] {
        m_rebuildPending = false;
        rebuild();
    }, Qt::QueuedConnection);
}

void DepthMeshGeometry::setValid(bool valid)
{
    if (m_valid == valid)
        return;
    m_valid = valid;
    emit validChanged();
}

void DepthMeshGeometry::rebuild()
{
    if (m_buildRunning)
        return;
    m_buildRunning = true;
    setValid(false);
    setVertexData({});
    setIndexData({});

    const quint64 generation = m_generation;
    const BuildRequest request{
        m_depthPath,
        m_mattePath,
        m_imageZoom,
        m_outputAspect,
        m_sourceAspect,
        m_fitMode,
    };
    QtConcurrent::run([request] {
        return buildMesh(request);
    }).then(this, [this, generation](MeshData mesh) {
        m_buildRunning = false;
        if (generation == m_generation)
            applyMesh(generation, std::move(mesh));
        else
            rebuild();
    });
}

DepthMeshGeometry::MeshData DepthMeshGeometry::buildMesh(const BuildRequest &request)
{
    MeshData mesh;
    ImagePlane depth;
    if (!depth.load(request.depthPath, QImage::Format_Grayscale16))
        return mesh;
    ImagePlane matte;
    const bool hasMatte = matte.load(request.mattePath, QImage::Format_Alpha8);

    UvMapping mapping;
    if (request.fitMode == Crop) {
        mapping.scaleU = std::min(1.0f, request.outputAspect / request.sourceAspect);
        mapping.scaleV = std::min(1.0f, request.sourceAspect / request.outputAspect);
        mapping.offsetU = (1.0f - mapping.scaleU) * 0.5f;
        mapping.offsetV = (1.0f - mapping.scaleV) * 0.5f;
    }
    const auto depthAt = [&](float u, float v) {
        return depth.at(mapping.u(u), mapping.v(v));
    };
    const auto matteAt = [&](float u, float v) {
        return matte.at(mapping.u(u), mapping.v(v));
    };

    std::vector<float> hole(kColumns * kRows, 0.0f);
    std::vector<float> filled(kColumns * kRows, kPivotDepth);
    if (hasMatte) {
        for (int y = 0; y < kRows; ++y) {
            for (int x = 0; x < kColumns; ++x) {
                const float u = float(x) / float(kColumns - 1);
                const float v = float(y) / float(kRows - 1);
                hole[y * kColumns + x] = matteAt(u, v) > 24.0f / 255.0f ? 1.0f : 0.0f;
            }
        }
        dilate(hole, 2);
        const std::vector<float> core = hole;
        blur(hole);

        std::vector<uint8_t> known(kColumns * kRows, 0);
        std::vector<float> background;
        background.reserve(kColumns * kRows);
        for (int y = 0; y < kRows; ++y) {
            for (int x = 0; x < kColumns; ++x) {
                const int i = y * kColumns + x;
                if (core[i] > 0.5f)
                    continue;
                const float u = float(x) / float(kColumns - 1);
                const float v = float(y) / float(kRows - 1);
                filled[i] = depthAt(u, v);
                known[i] = 1;
                background.push_back(filled[i]);
            }
        }
        float fallback = kPivotDepth;
        if (!background.empty()) {
            const auto mid = background.begin() + background.size() / 2;
            std::nth_element(background.begin(), mid, background.end());
            fallback = *mid;
        }

        std::vector<int> queue;
        queue.reserve(kColumns * kRows);
        const auto pushIfUnknown = [&](int i) {
            if (!known[i])
                queue.push_back(i);
        };
        for (int y = 0; y < kRows; ++y) {
            for (int x = 0; x < kColumns; ++x) {
                const int i = y * kColumns + x;
                if (known[i])
                    continue;
                if ((x > 0 && known[i - 1]) || (x + 1 < kColumns && known[i + 1])
                    || (y > 0 && known[i - kColumns]) || (y + 1 < kRows && known[i + kColumns]))
                    queue.push_back(i);
            }
        }
        for (size_t head = 0; head < queue.size(); ++head) {
            const int i = queue[head];
            if (known[i])
                continue;
            const int x = i % kColumns;
            const int y = i / kColumns;
            float sum = 0.0f;
            int count = 0;
            if (x > 0 && known[i - 1]) { sum += filled[i - 1]; ++count; }
            if (x + 1 < kColumns && known[i + 1]) { sum += filled[i + 1]; ++count; }
            if (y > 0 && known[i - kColumns]) { sum += filled[i - kColumns]; ++count; }
            if (y + 1 < kRows && known[i + kColumns]) { sum += filled[i + kColumns]; ++count; }
            if (count == 0)
                continue;
            filled[i] = sum / float(count);
            known[i] = 1;
            if (x > 0) pushIfUnknown(i - 1);
            if (x + 1 < kColumns) pushIfUnknown(i + 1);
            if (y > 0) pushIfUnknown(i - kColumns);
            if (y + 1 < kRows) pushIfUnknown(i + kColumns);
        }
        for (int i = 0; i < kColumns * kRows; ++i)
            if (!known[i])
                filled[i] = fallback;
    } else {
        for (int y = 0; y < kRows; ++y) {
            for (int x = 0; x < kColumns; ++x) {
                const float u = float(x) / float(kColumns - 1);
                const float v = float(y) / float(kRows - 1);
                filled[y * kColumns + x] = depthAt(u, v);
            }
        }
    }

    const float pivotDistance = float(kFarDistance - double(kPivotDepth) * kDepthSpan);
    const auto distanceAtDepth = [&](float value) {
        if (value >= kPivotDepth)
            return pivotDistance - (value - kPivotDepth) * float(kDepthSpan * kNearScale);
        return pivotDistance + (kPivotDepth - value) * float(kDepthSpan * kFarScale);
    };
    const auto sampleDepth = [&](float u, float v) {
        const float value = depthAt(u, v);
        if (!hasMatte)
            return value;
        const float weight = std::clamp(maskAt(hole, u, v), 0.0f, 1.0f);
        return value * (1.0f - weight) + maskAt(filled, u, v) * weight;
    };

    std::vector<uint8_t> refineCell(kCellCount, 0);
    int refineCount = 0;
    const int finestColumns = (kColumns - 1) * kRefine + 1;
    const int finestRows = (kRows - 1) * kRefine + 1;
    for (int y = 0; y + 1 < kRows; ++y) {
        for (int x = 0; x + 1 < kColumns; ++x) {
            float cellMin = 1.0f;
            float cellMax = 0.0f;
            for (int sy = 0; sy <= kRefine; ++sy) {
                for (int sx = 0; sx <= kRefine; ++sx) {
                    const float u = float(x * kRefine + sx) / float(finestColumns - 1);
                    const float v = float(y * kRefine + sy) / float(finestRows - 1);
                    const float value = sampleDepth(u, v);
                    cellMin = std::min(cellMin, value);
                    cellMax = std::max(cellMax, value);
                }
            }
            if (cellMax - cellMin > kRefineThreshold) {
                refineCell[y * (kColumns - 1) + x] = 1;
                ++refineCount;
            }
        }
    }

    int refinement = kRefine;
    const qsizetype baseVertexCount = qsizetype(kColumns) * kRows;
    while (refinement > 1) {
        const qsizetype addedPerCell = (refinement + 1) * (refinement + 1) - 4;
        if (baseVertexCount + qsizetype(refineCount) * addedPerCell <= kMaxVertices)
            break;
        refinement /= 2;
    }
    if (refinement == 1)
        refineCount = 0;

    const int fineColumns = (kColumns - 1) * refinement + 1;
    const int fineRows = (kRows - 1) * refinement + 1;
    const quint32 missing = std::numeric_limits<quint32>::max();
    const quint32 pending = missing - 1;
    std::vector<quint32> fineIndex(size_t(fineColumns) * fineRows, missing);
    for (int y = 0; y < kRows; ++y)
        for (int x = 0; x < kColumns; ++x)
            fineIndex[size_t(y * refinement) * fineColumns + x * refinement]
                = quint32(y * kColumns + x);

    qsizetype vertexCapacity = baseVertexCount;
    for (int y = 0; y + 1 < kRows; ++y) {
        for (int x = 0; x + 1 < kColumns; ++x) {
            if (refinement == 1 || !refineCell[y * (kColumns - 1) + x])
                continue;
            for (int sy = 0; sy <= refinement; ++sy) {
                for (int sx = 0; sx <= refinement; ++sx) {
                    quint32 &index = fineIndex[size_t(y * refinement + sy) * fineColumns
                        + x * refinement + sx];
                    if (index == missing) {
                        index = pending;
                        ++vertexCapacity;
                    }
                }
            }
        }
    }


    float minX = std::numeric_limits<float>::max();
    float minY = minX;
    float minZ = minX;
    float maxX = std::numeric_limits<float>::lowest();
    float maxY = maxX;
    float maxZ = maxX;
    double maximumDistance = 0.0;
    const double tangent = std::tan(kFovDegrees * std::numbers::pi / 360.0);

    mesh.vertices = QByteArray(vertexCapacity * sizeof(Vertex), Qt::Uninitialized);
    auto *vertices = reinterpret_cast<Vertex *>(mesh.vertices.data());
    qsizetype vertexCount = 0;
    const auto addVertex = [&](float u, float v, float value) {
        if (vertexCount >= vertexCapacity)
            return missing;
        const float distance = distanceAtDepth(value);
        maximumDistance = std::max(maximumDistance, double(distance));
        const Vertex vertex{
            float((u * 2.0 - 1.0) * request.imageZoom * distance * tangent * request.outputAspect),
            float((1.0 - v * 2.0) * request.imageZoom * distance * tangent),
            -distance,
            mapping.u(u),
            1.0f - mapping.v(v),
        };
        minX = std::min(minX, vertex.x);
        minY = std::min(minY, vertex.y);
        minZ = std::min(minZ, vertex.z);
        maxX = std::max(maxX, vertex.x);
        maxY = std::max(maxY, vertex.y);
        maxZ = std::max(maxZ, vertex.z);
        vertices[vertexCount] = vertex;
        return quint32(vertexCount++);
    };

    for (int y = 0; y < kRows; ++y) {
        for (int x = 0; x < kColumns; ++x) {
            const float u = float(x) / float(kColumns - 1);
            const float v = float(y) / float(kRows - 1);
            addVertex(u, v, sampleDepth(u, v));
        }
    }

    const qsizetype indexCount = qsizetype(kCellCount - refineCount) * 6
        + qsizetype(refineCount) * 6 * refinement * refinement;
    mesh.indices = QByteArray(indexCount * sizeof(quint32), Qt::Uninitialized);
    auto *indices = reinterpret_cast<quint32 *>(mesh.indices.data());
    qsizetype indexCursor = 0;
    const auto appendTriangle = [&](quint32 a, quint32 b, quint32 c) {
        indices[indexCursor++] = a;
        indices[indexCursor++] = b;
        indices[indexCursor++] = c;
    };



    for (int y = 0; y + 1 < kRows; ++y) {
        for (int x = 0; x + 1 < kColumns; ++x) {
            const int tl = y * kColumns + x;
            const int tr = tl + 1;
            const int bl = tl + kColumns;
            const int br = bl + 1;
            const bool refined = refinement > 1 && refineCell[y * (kColumns - 1) + x];
            if (!refined) {
                appendTriangle(tl, bl, tr);
                appendTriangle(tr, bl, br);
                continue;
            }

            std::array<quint32, (kRefine + 1) * (kRefine + 1)> patch{};
            for (int sy = 0; sy <= refinement; ++sy) {
                for (int sx = 0; sx <= refinement; ++sx) {
                    const int gx = x * refinement + sx;
                    const int gy = y * refinement + sy;
                    quint32 &index = fineIndex[size_t(gy) * fineColumns + gx];
                    if (index == pending) {
                        const float u = float(gx) / float(fineColumns - 1);
                        const float v = float(gy) / float(fineRows - 1);
                        index = addVertex(u, v, sampleDepth(u, v));
                    }
                    patch[sy * (kRefine + 1) + sx] = index;
                }
            }
            for (int sy = 0; sy < refinement; ++sy) {
                for (int sx = 0; sx < refinement; ++sx) {
                    const int a = sy * (kRefine + 1) + sx;
                    const int b = a + 1;
                    const int c = a + kRefine + 1;
                    const int d = c + 1;
                    appendTriangle(patch[a], patch[c], patch[b]);
                    appendTriangle(patch[b], patch[c], patch[d]);
                }
            }
        }
    }

    if (vertexCount != vertexCapacity || vertexCount > kMaxVertices
        || indexCursor != indexCount)
        return {};
    mesh.minimum = QVector3D(minX, minY, minZ);
    mesh.maximum = QVector3D(maxX, maxY, maxZ);
    mesh.backgroundDistance = float(maximumDistance + 0.25);
    mesh.focusDistance = pivotDistance;
    mesh.valid = true;
    return mesh;
}

void DepthMeshGeometry::applyMesh(quint64 generation, MeshData mesh)
{
    if (generation != m_generation || !mesh.valid)
        return;

    setVertexData(mesh.vertices);
    setIndexData(mesh.indices);
    setBounds(mesh.minimum, mesh.maximum);
    if (std::abs(m_backgroundDistance - mesh.backgroundDistance) > 1e-5f) {
        m_backgroundDistance = mesh.backgroundDistance;
        emit backgroundDistanceChanged();
    }
    if (std::abs(m_focusDistance - mesh.focusDistance) > 1e-5f) {
        m_focusDistance = mesh.focusDistance;
        emit focusDistanceChanged();
    }
    setValid(true);
    update();
}
