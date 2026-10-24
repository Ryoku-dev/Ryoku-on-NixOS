#include "bordermaterial.hpp"

#include <QMatrix4x4>

#include <cstring>

QSGMaterialType* BorderMaterial::type() const {
    static QSGMaterialType type;
    return &type;
}

QSGMaterialShader* BorderMaterial::createShader(QSGRendererInterface::RenderMode) const {
    return new BorderMaterialShader;
}

int BorderMaterial::compare(const QSGMaterial* other) const {
    if (this < other)
        return -1;
    if (this > other)
        return 1;
    return 0;
}

BorderMaterialShader::BorderMaterialShader() {
    setShaderFileName(VertexStage, QStringLiteral(":/shaders/beam.vert.qsb"));
    setShaderFileName(FragmentStage, QStringLiteral(":/shaders/beam.frag.qsb"));
}

bool BorderMaterialShader::updateUniformData(RenderState& state, QSGMaterial* newMaterial, QSGMaterial* oldMaterial) {
    Q_UNUSED(oldMaterial);
    auto* material = static_cast<BorderMaterial*>(newMaterial);
    QByteArray* buffer = state.uniformData();
    Q_ASSERT(buffer->size() >= 124);

    if (state.isMatrixDirty()) {
        const QMatrix4x4 matrix = state.combinedMatrix();
        memcpy(buffer->data(), matrix.constData(), 64);
    }
    if (state.isOpacityDirty()) {
        const float opacity = state.opacity();
        memcpy(buffer->data() + 64, &opacity, 4);
    }

    memcpy(buffer->data() + 72, material->size, 8);
    memcpy(buffer->data() + 80, &material->radius, 4);
    memcpy(buffer->data() + 84, &material->strokeWidth, 4);
    memcpy(buffer->data() + 88, &material->blur, 4);
    memcpy(buffer->data() + 92, &material->strength, 4);

    const float color[4] = {
        static_cast<float>(material->color.redF()),
        static_cast<float>(material->color.greenF()),
        static_cast<float>(material->color.blueF()),
        static_cast<float>(material->color.alphaF()),
    };
    memcpy(buffer->data() + 96, color, 16);
    memcpy(buffer->data() + 112, &material->phase, 4);
    memcpy(buffer->data() + 116, &material->activeFade, 4);
    memcpy(buffer->data() + 120, &material->mode, 4);
    return true;
}
