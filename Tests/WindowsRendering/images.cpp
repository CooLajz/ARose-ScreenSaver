#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <iostream>
#include "ReferenceSurface.h"
using namespace arose;
using namespace arose::test;
int main() try {
    check(CoInitializeEx(nullptr,COINIT_MULTITHREADED));
    ComPtr<IWICImagingFactory> wic;
    check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&wic)));
    ComPtr<ID2D1Factory> d2d;
    check(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,d2d.GetAddressOf()));
    Engine engine; std::deque<std::array<ModernPoint,96>> previous;
    for(int i=0;i<1551;++i) { previous=engine.modernHistory; engine.step(); }
    int worst=0; double worstEnergy=0; size_t cases=0;
    for(const auto size : {std::array<UINT,2>{800,600},{1280,720},{1080,1920},{3840,2160}}) {
        Surface reference(wic.Get(),d2d.Get(),size[0],size[1]),cached(wic.Get(),d2d.Get(),size[0],size[1]);
        for(float dpi:{1.0f,1.5f}) for(float glow:{0.0f,0.8f,1.0f}) for(double alpha:{0.0,0.35,0.99}) {
            PreparedFrame frame; frame.prepare(engine.modernHistory,previous,alpha,float(size[0]),float(size[1]));
            const float diameter=ModernDrawing::diameter(float(size[0]),float(size[1]),dpi);
            auto a=reference.render(frame,diameter,glow,false),b=cached.render(frame,diameter,glow,true);
            uint64_t sumA=0,sumB=0; int maximum=0;
            for(size_t i=0;i<a.size();++i) if(i%4!=3) {
                maximum=std::max(maximum,std::abs(int(a[i])-int(b[i]))); sumA+=a[i]; sumB+=b[i];
            }
            const double energy=sumA?100*std::abs(double(sumB)-double(sumA))/double(sumA):0;
            worst=std::max(worst,maximum); worstEnergy=std::max(worstEnergy,energy); ++cases;
            std::cout<<size[0]<<'x'<<size[1]<<" dpi="<<dpi<<" glow="<<glow<<" alpha="<<alpha
                <<" max="<<maximum<<" energy_percent="<<energy<<'\n';
            // Glow zero stays byte-identical. Cached halos allow bounded
            // bilinear resampling error, not a different blend or point shape.
            if((glow==0 && a!=b) || maximum>12 || energy>3)
                throw std::runtime_error("Cached halo image differs beyond the acceptance limit");
        }
        // Explicitly exercise device-resource invalidation and rebuilding.
        cached.drawing.discard();
        if(!cached.drawing.prepare(cached.target.Get(),1.8f,0.8f,true) || !cached.drawing.cached())
            throw std::runtime_error("Halo atlas recreation failed");
    }
    std::cout<<"PASS: "<<cases<<" images; worst channel difference "<<worst<<"/255; worst RGB energy difference "<<worstEnergy<<"%\n";
    return 0;
} catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
