#pragma once
#include "RoseEngine.h"
namespace arose {
// Simulation stays at PAL 50 Hz; rendering can follow a 60/120/144 Hz display.
struct FrameTiming {
    double remainder = 0;
    int advance(double seconds) {
        remainder += std::clamp(seconds, 0.0, 0.1);
        int steps = static_cast<int>((remainder + 1e-12) / 0.02);
        remainder = std::max(0.0, remainder - steps * 0.02);
        return steps;
    }
    double alpha() const { return std::clamp(remainder / 0.02, 0.0, 1.0); }
};
inline ModernPoint interpolate(ModernPoint previous, ModernPoint current, double alpha) {
    double hueDelta = current.hue - previous.hue;
    if (hueDelta > 0.5) hueDelta -= 1;
    if (hueDelta < -0.5) hueDelta += 1;
    double hue = previous.hue + hueDelta * alpha;
    hue -= std::floor(hue);
    return {previous.x + (current.x - previous.x) * alpha,
            previous.y + (current.y - previous.y) * alpha, hue};
}
}
