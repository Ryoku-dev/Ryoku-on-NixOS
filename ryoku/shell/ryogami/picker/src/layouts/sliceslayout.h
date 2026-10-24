#pragma once

#include "slicebase.h"

#include <QString>

#include <unordered_map>
#include <vector>

class SlicesLayout : public SliceBase
{
public:
    QString key() const override { return QStringLiteral("slices"); }
    void configure(const LayoutContext &ctx, bool animate) override;
    void reset(const LayoutContext &ctx) override;
    void select(const LayoutContext &ctx, int from, int to) override;
    bool tick(const LayoutContext &ctx, double dt) override;
    void build(const LayoutContext &ctx, std::vector<CardVisual> &out) override;

private:
    void readParams(const LayoutContext &ctx, SliceParams &out) const override;
    float widthOf(int row, int current) const;

    std::unordered_map<int, Spring> m_widths;
    std::vector<float> m_centers;
    std::vector<int> m_visible;
};
