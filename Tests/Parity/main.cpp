#include "../../Windows/RoseEngine.h"
#include "../../Windows/FrameTiming.h"
#include <iostream>
#include <iomanip>
#include <stdexcept>
using namespace arose;
uint64_t hashPixels(const std::vector<uint8_t>& pixels) {
    uint64_t hash=14695981039346656037ULL;
    for(auto p:pixels) { hash^=p; hash*=1099511628211ULL; }
    return hash;
}
int main(int argc,char**) {
    if(argc>1) {
        for(auto dimensions : {std::pair<int,int>{2560,1280}, {1280,2560}}) {
            Engine base, enlarged;
            base.settings.appearance=enlarged.settings.appearance=0;
            base.settings.tail=enlarged.settings.tail=1;
            base.resizeRaster(800,640);
            enlarged.resizeRaster(dimensions.first,dimensions.second);
            for(int i=0;i<100;++i) { base.step(); enlarged.step(); }
            if(base.savedFigure()!=enlarged.savedFigure()) return 14;
            std::vector<uint8_t> expected(enlarged.pixels.size());
            for(int y=0;y<640;++y) for(int x=0;x<800;++x) if(base.pixels[y*800+x]) {
                int xx=dimensions.first/2+(x-400)*2, yy=dimensions.second/2+(y-320)*2;
                expected[yy*dimensions.first+xx]=base.pixels[y*800+x];
            }
            if(expected!=enlarged.pixels) return 15;
            auto state=enlarged.savedFigure(); enlarged.resizeRaster(320,256);
            if(enlarged.savedFigure()!=state || enlarged.pixels.size()!=320*256 ||
               std::any_of(enlarged.pixels.begin(),enlarged.pixels.end(),[](uint8_t c){return c!=0;})) return 16;
        }
        std::cout<<"PASS: native retro scaling preserves proportions, single pixels and figure state\n";
        Engine fixedSmall, fixedLarge;
        fixedSmall.settings.appearance=fixedLarge.settings.appearance=0;
        fixedSmall.settings.scaleRetro=fixedLarge.settings.scaleRetro=0;
        fixedSmall.settings.tail=fixedLarge.settings.tail=1;
        fixedLarge.resizeRaster(1600,1200);
        for(int i=0;i<100;++i) { fixedSmall.step(); fixedLarge.step(); }
        std::vector<uint8_t> fixedExpected(1600*1200);
        for(int y=0;y<600;++y) for(int x=0;x<800;++x)
            fixedExpected[(y+300)*1600+x+400]=fixedSmall.pixels[y*800+x];
        if(fixedExpected!=fixedLarge.pixels || fixedSmall.savedFigure()!=fixedLarge.savedFigure()) return 17;
        for(int speed=1; speed<=5; ++speed) {
            Engine opening; opening.settings.speed=speed;
            opening.step();
            if(opening.savedFigure()[22] != 1440-speed) return 12;
            opening.step();
            const auto point=opening.modernHistory.back()[0];
            const double angle=speed*std::acos(-1.0)/720;
            if(std::abs(point.x-std::cos(angle))>1e-12 || std::abs(point.y-std::sin(angle))>1e-12) return 13;
        }
        std::cout<<"PASS: original initial phase and doubled global rotation at all five speeds\n";
        for(int hz : {60, 120, 144}) {
            FrameTiming timing;
            int steps = 0;
            for(int i=0; i<hz*10; ++i) {
                steps += timing.advance(1.0/hz);
                if(timing.alpha()<0 || timing.alpha()>1) return 6;
            }
            if(steps!=500) return 7;
        }
        FrameTiming jittered;
        int jitteredSteps=0;
        for(int i=0;i<100;++i) for(double elapsed : {0.010,0.028,0.012,0.016,0.034})
            jitteredSteps+=jittered.advance(elapsed);
        if(jitteredSteps!=500) return 11;
        FrameTiming delayed;
        if(delayed.advance(4.0)!=5 || delayed.alpha()>1e-9) return 8;
        const ModernPoint a{0,0,0.99}, b{10,20,0.01};
        auto midpoint=interpolate(a,b,0.5);
        if(std::abs(midpoint.x-5)>1e-9 || std::abs(midpoint.y-10)>1e-9 || std::min(midpoint.hue,1-midpoint.hue)>1e-9) return 9;
        // Interpolated constant motion must advance equally at every 60 Hz redraw,
        // including redraws where no new simulation step was needed.
        FrameTiming timing;
        int steps=1;
        double previous=0;
        for(int i=0;i<600;++i) {
            steps+=timing.advance(1.0/60);
            double displayed=steps-1+timing.alpha();
            if(std::abs(displayed-previous-50.0/60)>1e-9) return 10;
            previous=displayed;
        }
        std::cout<<"PASS: 50 Hz timing at 60/120/144 Hz, smooth interpolation and stall recovery\n";
        Settings defaults;
        if(defaults.appearance!=1 || defaults.glow!=80 || defaults.tail!=16) return 1;
        Settings invalid; invalid.appearance=8; invalid.speed=-1; invalid.tail=19; invalid.palette=99; invalid.glow=200; invalid.validate();
        if(invalid.appearance!=1 || invalid.speed!=1 || invalid.tail!=16 || invalid.palette!=2 || invalid.glow!=100) return 2;
        for(int palette=0;palette<3;++palette) {
            Engine e; e.settings.appearance=0; e.settings.palette=palette;
            for(int f=0;f<200000;++f) e.step();
            for(auto p:e.pixels) if(p>(palette==0?1:palette==1?12:96)) return 3;
        }
        for(int tail:{1,20}) {
            Engine e; e.settings.tail=tail;
            for(int f=0;f<2000;++f) e.step();
            if(e.modernHistory.size()!=static_cast<size_t>(tail)) return 4;
            for(const auto& points:e.modernHistory) for(auto p:points)
                if(!std::isfinite(p.x)||!std::isfinite(p.y)||p.hue<0||p.hue>=1) return 5;
        }
        std::cout<<"PASS: 600,000 original frames, modern histories and settings\n"; return 0;
    }
    std::cout<<std::setprecision(17);
    for(int modern=0;modern<2;++modern) for(int palette=0;palette<3;++palette) {
        Engine e; e.settings.appearance=modern; e.settings.palette=palette; e.settings.tail=16;
        for(int frame=1;frame<=10000;++frame) {
            e.step();
            if(frame==1||frame==200||frame==1000||frame==10000) {
                std::cout<<modern<<' '<<palette<<' '<<frame<<' '<<hashPixels(e.pixels);
                if(modern) for(int i:{0,17,95}) { auto p=e.modernHistory.back()[i]; std::cout<<' '<<p.x<<' '<<p.y<<' '<<p.hue; }
                std::cout<<'\n';
            }
        }
        for(auto c:Engine::palette(palette)) std::cout<<c<<' '; std::cout<<'\n';
    }
}
