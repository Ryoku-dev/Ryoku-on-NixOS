#pragma once

#include <QAbstractAnimation>

#include <functional>

// Ticks once per rendered frame, paced by vsync, only while started.
class FrameTicker : public QAbstractAnimation
{
public:
    explicit FrameTicker(std::function<void()> tick, QObject *parent = nullptr)
        : QAbstractAnimation(parent)
        , m_tick(std::move(tick))
    {
    }

    int duration() const override { return -1; }

protected:
    void updateCurrentTime(int) override { m_tick(); }

private:
    std::function<void()> m_tick;
};
