#pragma once
#include "FrameTiming.h"

namespace arose {
// Per-window scratch space: interpolation and geometry are shared by glow and
// point passes. Fixed capacity covers the longest supported trail without growth.
struct PreparedPoint {
    float x, y, strength;
    double hue;
    size_t halo;
};
struct PreparedFrame {
    std::array<PreparedPoint, 20 * 96> points{};
    size_t count = 0;
    void prepare(const std::deque<std::array<ModernPoint, 96>>& current,
                 const std::deque<std::array<ModernPoint, 96>>& previous,
                 double alpha, float width, float height) {
        count = 0;
        const float scale = std::min(width, height) / 640;
        size_t age = 0;
        for (const auto& frame : current) {
            const float strength = 0.25f + 0.75f * static_cast<float>(++age) / static_cast<float>(current.size());
            for (size_t i = 0; i < frame.size(); ++i) {
                auto p = frame[i];
                if (previous.size() == current.size()) p = interpolate(previous[age - 1][i], p, alpha);
                if (count == points.size()) return; // Defensive bound; Settings caps trails at 20.
                points[count++] = {width / 2 + static_cast<float>(p.x) * scale,
                                   height / 2 - static_cast<float>(p.y) * scale,
                                   strength, p.hue, std::min<size_t>(255, static_cast<size_t>(p.hue * 256))};
            }
        }
    }
};
}
