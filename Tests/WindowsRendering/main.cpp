#include "../../Windows/PreparedFrame.h"
#include <iostream>
#include <stdexcept>
using namespace arose;
void require(bool value) { if(!value) throw std::runtime_error("Prepared Windows draw data changed"); }
int main() {
    PreparedFrame prepared;
    size_t checked = 0;
    for(int tail : {1, 4, 16, 20}) {
        Engine engine; engine.settings.tail = tail;
        std::deque<std::array<ModernPoint,96>> previous;
        for(int tick=0; tick<2200; ++tick) {
            previous = engine.modernHistory;
            engine.step();
            if(tick>25 && tick%137!=0) continue;
            for(const auto size : {std::array<float,2>{200,125}, {1920,1080}, {1080,1920}, {3840,2160}}) {
                for(double alpha : {0.0, 0.25, 0.5, 0.999, 1.0}) {
                    prepared.prepare(engine.modernHistory, previous, alpha, size[0], size[1]);
                    require(prepared.count==engine.modernHistory.size()*96);
                    // Oracle is the former renderer's per-pass computation,
                    // including its float conversions and age/order conventions.
                    size_t index=0, age=0;
                    for(const auto& frame : engine.modernHistory) {
                        float strength=0.25f+0.75f*static_cast<float>(++age)/static_cast<float>(engine.modernHistory.size());
                        for(size_t i=0; i<frame.size(); ++i) {
                            auto p=frame[i];
                            if(previous.size()==engine.modernHistory.size())
                                p=interpolate(previous[age-1][i],p,alpha);
                            const float scale=std::min(size[0],size[1])/640;
                            const auto& actual=prepared.points[index++];
                            require(actual.x==size[0]/2+static_cast<float>(p.x)*scale);
                            require(actual.y==size[1]/2-static_cast<float>(p.y)*scale);
                            require(actual.hue==p.hue && actual.strength==strength);
                            require(actual.halo==std::min<size_t>(255,static_cast<size_t>(p.hue*256)));
                            ++checked;
                        }
                    }
                }
            }
        }
    }
    prepared.prepare({}, {}, 0.5, 1920, 1080);
    require(prepared.count==0);
    std::cout<<"PASS: "<<checked<<" prepared points exactly match the former Windows geometry, hue, opacity and order; empty/reset history clears\n";
}
