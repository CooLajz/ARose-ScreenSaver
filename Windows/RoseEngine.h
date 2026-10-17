#pragma once
// C++ port of Sources/Core/RoseEngine.swift. See THIRD_PARTY_NOTICES.md.
#include "RoseTables.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <vector>

namespace arose {
struct Point { int x = 0, y = 0; };
struct ModernPoint { double x, y, hue; };
struct Settings {
    int appearance = 1, speed = 3, tail = 16, palette = 2, glow = 80, debugCPU = 0;
    void validate() {
        debugCPU = debugCPU == 1 ? 1 : 0;
        appearance = std::clamp(appearance, 0, 1);
        speed = std::clamp(speed, 1, 5);
        const int lengths[] = {1, 4, 8, 12, 16, 20};
        if (std::find(std::begin(lengths), std::end(lengths), tail) == std::end(lengths)) tail = 16;
        palette = std::clamp(palette, 0, 2);
        glow = std::clamp(glow, 0, 100);
    }
};
class Engine {
    struct Track {
        int angle = 0, base = 0, color = 0;
        std::array<Point, 20> history{};
    };
    struct Sequence {
        const std::vector<int>& entries;
        size_t index = 0;
        int counter = 0;
        void advance(int current, int& target, int& delta) {
            if (counter != entries[index]) { ++counter; return; }
            target = entries[index + 1];
            delta = entries[index + 2] * (target < current ? -1 : 1);
            index = (index + 3) % entries.size(); counter = 0;
        }
    };
    std::array<Track, 96> tracks{};
    std::array<int, 1440> sine{}, cosine{};
    int radiusA = 0, targetA = 150, deltaA = 1;
    int radiusB = 0, targetB = 0, deltaB = 1;
    int frequency = 0, targetFrequency = 0, deltaFrequency = 1;
    int rotation = 0, mode = 1, modeCounter = 0, slot = 0;
    size_t modeIndex = 0;
    bool changed = false;
    Sequence a{tables::radiusA}, b{tables::radiusB}, f{tables::frequency};
    static int wrap(int n) { return (n % 1440 + 1440) % 1440; }
    void plot(Point p, uint8_t color) {
        if (p.x >= 0 && p.x < width && p.y >= 0 && p.y < height)
            pixels[static_cast<size_t>(p.y * width + p.x)] = color;
    }
public:
    static constexpr int width = 800, height = 600;
    Settings settings;
    uint64_t frame = 0;
    std::vector<uint8_t> pixels = std::vector<uint8_t>(width * height);
    std::deque<std::array<ModernPoint, 96>> modernHistory;
    Engine() {
        float angle = 0;
        uint64_t bits = 0x3f71df46a2529d39ULL;
        double increment; std::memcpy(&increment, &bits, sizeof increment);
        for (size_t i = 0; i < sine.size(); ++i) {
            sine[i] = static_cast<int>(std::sin(double(angle)) * 4096);
            cosine[i] = static_cast<int>(std::cos(double(angle)) * 4096);
            angle = static_cast<float>(double(angle) + increment);
        }
        for (int i = 0; i < 96; ++i) tracks[i].angle = tracks[i].base = i * 15, tracks[i].color = i;
    }
    void step() {
        const int length = std::clamp(settings.tail, 1, 20);
        slot %= length;
        for (const auto& t : tracks) plot(t.history[slot], 0);
        const int sr = sine[rotation], cr = cosine[rotation];
        constexpr double radians = 3.14159265358979323846 / 720;
        const double ms = std::sin(rotation * radians), mc = std::cos(rotation * radians);
        std::array<ModernPoint, 96> points{};
        for (size_t i = 0; i < tracks.size(); ++i) {
            auto& t = tracks[i];
            if (settings.appearance == 1) {
                const double theta = t.angle * radians, phi = double(frequency) * t.base / 200 * radians;
                const double u = radiusA * std::sin(theta) + radiusB * std::sin(phi);
                const double v = radiusA * std::cos(theta) + radiusB * std::cos(phi);
                points[i] = {v * mc - u * ms, v * ms + u * mc, std::fmod(double(i) / 96 + double(frame) / 1200, 1)};
            }
            const int phi = wrap(frequency * t.base / 200);
            const int u = (radiusA * sine[t.angle] + radiusB * sine[phi]) / 4096;
            const int v = (radiusA * cosine[t.angle] + radiusB * cosine[phi]) / 4096;
            Point p{400 + (v * cr - u * sr) / 4096, 300 - (v * sr + u * cr) / 4096};
            t.history[slot] = p;
            plot(p, static_cast<uint8_t>(settings.palette == 0 ? 1 : settings.palette == 1 ? t.color / 8 + 1 : t.color + 1));
            t.color = (t.color + 1) % 96;
        }
        if (settings.appearance == 1) {
            modernHistory.push_back(points);
            while (modernHistory.size() > static_cast<size_t>(length)) modernHistory.pop_front();
        }
        const int increment = std::clamp(settings.speed, 1, 5) * (settings.appearance == 0 && settings.palette == 1 ? 2 : 1);
        if (mode == 1) rotation = wrap(rotation + increment);
        if (mode == 2 || changed) for (auto& t : tracks) t.angle = wrap(t.angle - increment);
        slot = (slot + 1) % length;
        changed = true;
        if (frequency != targetFrequency) { frequency += deltaFrequency; changed = false; }
        if (radiusA != targetA) { radiusA += deltaA; changed = false; }
        if (radiusB != targetB) { radiusB += deltaB; changed = false; }
        a.advance(radiusA, targetA, deltaA); b.advance(radiusB, targetB, deltaB); f.advance(frequency, targetFrequency, deltaFrequency);
        if (modeCounter == tables::rotation[modeIndex]) {
            mode = tables::rotation[modeIndex + 1]; modeIndex = (modeIndex + 2) % tables::rotation.size(); modeCounter = 0;
        } else ++modeCounter;
        ++frame;
    }
    static std::array<uint32_t, 256> palette(int mode) {
        std::array<uint32_t, 256> colors{};
        if (mode == 0) { colors[1] = 0xffffff; return colors; }
        const uint32_t ecs[] = {0xff0000,0xff8800,0xffff00,0x88ff00,0x00ff00,0x00ff88,0x00ffff,0x0088ff,0x0000ff,0x8800ff,0xff00ff,0xff0088};
        if (mode == 1) { std::copy(std::begin(ecs), std::end(ecs), colors.begin() + 1); return colors; }
        for (int i = 0; i < 96; ++i) {
            const uint32_t v = (i % 16) * 17;
            const uint32_t rgb[] = {0xff0000 | (v << 8), ((255-v)<<16)|0xff00, 0xff00|v, ((255-v)<<8)|0xff, (v<<16)|0xff, 0xff0000|(255-v)};
            colors[i+1] = rgb[i/16];
        }
        return colors;
    }
};
}
