#pragma once

#include <algorithm>
#include <cmath>

// Duration is the settle time: omega = 6.64 / seconds, critically damped unless zeta < 1.
struct Spring {
    double x = 0;
    double v = 0;
    double target = 0;
    double k = 0;
    double c = 0;
    // Pixel springs keep the default; normalised 0..1 springs use a finer one.
    double epsilon = 0.05;

    static Spring forDuration(double value, double ms, double zeta = 1.0)
    {
        Spring s;
        s.x = s.target = value;
        s.setDuration(ms, zeta);
        return s;
    }

    void setDuration(double ms, double zeta = 1.0)
    {
        const double omega = 6.64 / std::max(ms, 1.0) * 1000.0;
        k = omega * omega;
        c = 2.0 * std::sqrt(k) * std::max(zeta, 0.05);
    }

    void snap(double value)
    {
        x = target = value;
        v = 0;
    }

    bool settled() const { return std::abs(x - target) < epsilon && std::abs(v) < epsilon * 10.0; }

    // Returns true while still moving.
    bool tick(double dt)
    {
        if (settled()) {
            x = target;
            v = 0;
            return false;
        }
        constexpr double hop = 1.0 / 240.0;
        double remaining = std::min(dt, 0.05);
        while (remaining > 0) {
            const double step = std::min(hop, remaining);
            v += (-k * (x - target) - c * v) * step;
            x += v * step;
            remaining -= step;
        }
        if (settled()) {
            x = target;
            v = 0;
            return false;
        }
        return true;
    }
};

// For parameter morphs, where a spring would overshoot topology changes.
inline double approachK(double dt, double tau)
{
    return 1.0 - std::exp(-std::min(dt, 0.05) / std::max(tau, 1e-4));
}
