#pragma once

#include <QColor>
#include <QSGMaterial>
#include <QSGMaterialShader>

class BorderMaterial final : public QSGMaterial {
public:
    QSGMaterialType* type() const override;
    QSGMaterialShader* createShader(QSGRendererInterface::RenderMode) const override;
    int compare(const QSGMaterial* other) const override;

    float size[2]{0.0f, 0.0f};
    float radius = 0.0f;
    float strokeWidth = 1.5f;
    float blur = 6.0f;
    float strength = 1.0f;
    QColor color{Qt::white};
    float phase = 0.0f;
    float activeFade = 0.0f;
    int mode = 0;
};

class BorderMaterialShader final : public QSGMaterialShader {
public:
    BorderMaterialShader();
    bool updateUniformData(RenderState& state, QSGMaterial* newMaterial, QSGMaterial* oldMaterial) override;
};
