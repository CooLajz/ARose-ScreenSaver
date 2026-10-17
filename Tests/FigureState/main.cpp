#include "../../Windows/RoseEngine.h"
#include <cstdlib>
#include <iostream>
using namespace arose;
void check(bool value) { if(!value) std::abort(); }
int main() {
    for(int modern:{0,1}) {
        Engine original; original.settings.appearance=modern;
        for(int n=0;n<23719;++n) original.step();
        auto state=original.savedFigure();
        Engine restored; restored.settings=original.settings;
        check(restored.restoreFigure(state));
        for(int n=0;n<1000;++n) {
            original.step(); restored.step(); check(original.savedFigure()==restored.savedFigure());
            if(modern) {
                const auto& a=original.modernHistory.back(); const auto& b=restored.modernHistory.back();
                for(size_t i=0;i<a.size();++i) check(a[i].x==b[i].x && a[i].y==b[i].y && a[i].hue==b[i].hue);
            } else if(n>=40) check(original.pixels==restored.pixels);
        }
        for(auto pair:std::vector<std::pair<int,int64_t>>{{0,2},{1,-1},{11,1440},{13,1},{13,999},{16,-1},{16,1},{17,999999},{22,1440},{23,96},{8,INT64_MAX}}) {
            auto invalid=state; invalid[pair.first]=pair.second;
            auto before=restored.savedFigure(); check(!restored.restoreFigure(invalid)); check(before==restored.savedFigure());
        }
    }
    std::cout << "OK: Windows saved figures resume exact state and reject invalid data.\n";
}
