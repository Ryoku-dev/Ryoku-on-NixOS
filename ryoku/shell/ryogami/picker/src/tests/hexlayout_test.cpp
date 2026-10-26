#include "hexlayout.h"

#include <QVariant>

#include <algorithm>
#include <cstdio>
#include <vector>

namespace {

class TestParams final : public ParamSource
{
public:
    QVariant value(const QString &) const override { return {}; }
    bool smallScreen() const override { return true; }
};

bool hasCard(const std::vector<CardVisual> &cards, int row)
{
    return std::any_of(cards.cbegin(), cards.cend(), [row](const CardVisual &card) {
        return card.row == row && card.texture != CardVisual::TextureNone;
    });
}

bool settle(HexLayout &layout, LayoutContext &ctx, int frames = 180)
{
    std::vector<CardVisual> cards;
    for (int frame = 0; frame < frames; ++frame) {
        layout.tick(ctx, 1.0 / 60.0);
        cards.clear();
        layout.build(ctx, cards);
    }
    return hasCard(cards, ctx.current);
}

} // namespace

int main()
{
    TestParams params;
    MotionProfile motion;
    LayoutContext ctx;
    ctx.viewport = QSizeF(1280, 800);
    ctx.params = &params;
    ctx.motion = &motion;
    ctx.count = 600;
    ctx.current = 0;
    ctx.entrance = 1.0;

    HexLayout layout;
    layout.configure(ctx, false);
    layout.reset(ctx);
    std::vector<CardVisual> cards;
    layout.build(ctx, cards);
    if (!hasCard(cards, 0)) {
        std::fprintf(stderr, "initial hex card was not visible\n");
        return 1;
    }

    const int first = ctx.current;
    ctx.current = 594;
    layout.select(ctx, first, ctx.current);
    if (!settle(layout, ctx)) {
        std::fprintf(stderr, "far hex card stayed at zero scale\n");
        return 1;
    }

    const int last = ctx.current;
    ctx.current = 0;
    layout.select(ctx, last, ctx.current);
    if (!settle(layout, ctx)) {
        std::fprintf(stderr, "returning hex card stayed at zero scale\n");
        return 1;
    }
    return 0;
}
