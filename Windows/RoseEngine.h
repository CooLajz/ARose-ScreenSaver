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
    int appearance = 1, speed = 3, tail = 16, palette = 2, glow = 80, debugCPU = 0, resumeFigure = 0;
    void validate() {
        debugCPU = debugCPU == 1 ? 1 : 0;
        resumeFigure = resumeFigure == 1 ? 1 : 0;
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
    // Versioned field order shared with RoseEngine.swift; no raw struct serialization.
    using FigureState = std::array<int64_t, 24>;
    FigureState savedFigure() const {
        return {1, static_cast<int64_t>(frame), radiusA, targetA, deltaA, radiusB, targetB, deltaB,
            frequency, targetFrequency, deltaFrequency, rotation, mode, static_cast<int64_t>(modeIndex),
            modeCounter, changed ? 1 : 0, static_cast<int64_t>(a.index), a.counter,
            static_cast<int64_t>(b.index), b.counter, static_cast<int64_t>(f.index), f.counter,
            tracks[0].angle, tracks[0].color};
    }
    bool restoreFigure(const FigureState& v) {
        auto between=[](int64_t x,int64_t lo,int64_t hi) { return x>=lo && x<=hi; };
        if(v[0]!=1 || !between(v[1],0,1000000000000LL)) return false;
        for(int i:{2,3,5,6}) if(!between(v[i],-100000,100000)) return false;
        for(int i:{8,9}) if(!between(v[i],-1000000,1000000)) return false;
        for(int i:{4,7,10}) if(!between(v[i],-30,30)) return false;
        if(!between(v[11],0,1439) || !between(v[12],0,2) ||
           !between(v[13],0,static_cast<int64_t>(tables::rotation.size())-1) || v[13]%2 ||
           !between(v[14],0,tables::rotation[static_cast<size_t>(v[13])]) ||
           !between(v[15],0,1) || !between(v[22],0,1439) || !between(v[23],0,95)) return false;
        const std::vector<int>* sequences[]={&tables::radiusA,&tables::radiusB,&tables::frequency};
        for(int n=0;n<3;++n) {
            int i=16+2*n; const auto& table=*sequences[n];
            if(!between(v[i],0,static_cast<int64_t>(table.size())-1) || v[i]%3 ||
               !between(v[i+1],0,table[static_cast<size_t>(v[i])])) return false;
        }
        frame=static_cast<uint64_t>(v[1]); radiusA=int(v[2]); targetA=int(v[3]); deltaA=int(v[4]);
        radiusB=int(v[5]); targetB=int(v[6]); deltaB=int(v[7]);
        frequency=int(v[8]); targetFrequency=int(v[9]); deltaFrequency=int(v[10]);
        rotation=int(v[11]); mode=int(v[12]); modeIndex=static_cast<size_t>(v[13]); modeCounter=int(v[14]); changed=v[15]==1;
        a.index=static_cast<size_t>(v[16]); a.counter=int(v[17]); b.index=static_cast<size_t>(v[18]); b.counter=int(v[19]);
        f.index=static_cast<size_t>(v[20]); f.counter=int(v[21]);
        for(size_t i=0;i<tracks.size();++i) {
            tracks[i].angle=wrap(int(v[22])+tracks[i].base); tracks[i].color=(int(v[23])+int(i))%96; tracks[i].history={};
        }
        slot=0; std::fill(pixels.begin(),pixels.end(),uint8_t{0}); modernHistory.clear();
        return true;
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
