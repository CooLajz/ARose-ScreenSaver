#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <iostream>
#include <memory>
#include "ReferenceSurface.h"
#include "../../Windows/GpuDrawing.h"
using namespace arose;
using namespace arose::test;
int main() try {
    check(CoInitializeEx(nullptr,COINIT_MULTITHREADED));
    {
        ComPtr<ID3D11Device> probe;
        const D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_0};
        if(FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            levels,1,D3D11_SDK_VERSION,&probe,nullptr,nullptr))) {
            std::cout<<"SKIP: hardware Direct3D 11 is unavailable\n"; return 77;
        }
    }
    auto gpu=std::make_unique<GpuDrawing>();
    Engine engine; std::deque<std::array<ModernPoint,96>> previous;
    for(int i=0;i<1551;++i) { previous=engine.modernHistory; engine.step(); }
    size_t cases=0; int worst=0; double worstEnergy=0,worstRms=0; bool acceptable=true;
    for(const auto size:{std::array<UINT,2>{800,600},{1280,720},{1080,1920},{3840,2160}}) {
        ModernDrawing reference;
        for(float dpi:{1.0f,1.5f}) for(float glow:{0.0f,0.8f,1.0f}) for(double alpha:{0.0,0.35,0.99}) {
            PreparedFrame frame; frame.prepare(engine.modernHistory,previous,alpha,float(size[0]),float(size[1]));
            float diameter=ModernDrawing::diameter(float(size[0]),float(size[1]),dpi);
            if(!gpu->prepare(nullptr,size[0],size[1],diameter,glow) || !gpu->draw(frame,glow))
                throw std::runtime_error("Hardware GPU preparation/draw failed");
            if(gpu->calls()!=(glow>0?2u:1u)) throw std::runtime_error("GPU draw calls are not batched");
            std::vector<BYTE> actual; if(!gpu->readback(actual)) throw std::runtime_error("GPU readback failed");
            // Compare both paths on the same actual hardware surface. WIC's
            // software blending is covered independently by rendering-images.
            auto native=gpu->beginOverlay();
            if(!native || !reference.prepare(native,diameter,glow,false)) throw std::runtime_error("Hardware reference preparation failed");
            native->Clear(D2D1::ColorF(D2D1::ColorF::Black));
            reference.draw(native,gpu->overlayBrush(),frame,diameter,glow,false);
            if(!gpu->endOverlay()) throw std::runtime_error("Hardware reference drawing failed");
            std::vector<BYTE> expected; if(!gpu->readback(expected)) throw std::runtime_error("Hardware reference readback failed");
            uint64_t a=0,b=0; double squared=0; int maximum=0;
            for(size_t i=0;i<expected.size();++i) if(i%4!=3) {
                int delta=int(expected[i])-int(actual[i]); maximum=std::max(maximum,std::abs(delta));
                squared+=delta*delta; a+=expected[i]; b+=actual[i];
            }
            double energy=a?100*std::abs(double(b)-double(a))/double(a):0;
            double rms=std::sqrt(squared/(double(size[0])*size[1]*3));
            worst=std::max(worst,maximum); worstEnergy=std::max(worstEnergy,energy); worstRms=std::max(worstRms,rms); ++cases;
            std::cout<<size[0]<<'x'<<size[1]<<" dpi="<<dpi<<" glow="<<glow<<" alpha="<<alpha
                <<" max="<<maximum<<" energy_percent="<<energy<<" rms="<<rms<<'\n';
            // The native ellipse rasterizer has discrete subpixel changes.
            // Phase interpolation is bounded and checked against real GPU output;
            // the independent unchanged D2D halo limits remain in rendering-images.
            // Bound both isolated jumps of the native rasterizer and aggregate
            // error. The RMS bound includes the accepted windows-2025 baseline
            // (0.423565/255) while still rejecting broad changes.
            if(maximum>40 || energy>(glow==0?1.0:3.0) || rms>0.45)
                acceptable=false;
        }
        // Check D2D/DirectWrite overlay interoperability after each resize.
        auto target=gpu->beginOverlay(); if(!target) throw std::runtime_error("GPU overlay initialization failed");
        gpu->overlayBrush()->SetColor(D2D1::ColorF(D2D1::ColorF::White));
        target->FillRectangle(D2D1::RectF(0,0,8,8),gpu->overlayBrush());
        if(!gpu->endOverlay()) throw std::runtime_error("GPU overlay draw failed");
        std::vector<BYTE> overlay; if(!gpu->readback(overlay) || overlay[0]!=255 || overlay[1]!=255 || overlay[2]!=255)
            throw std::runtime_error("GPU overlay pixels are missing");
    }
    // Recreate the entire device path, clear empty history and disable glow.
    gpu=std::make_unique<GpuDrawing>();
    if(!gpu->prepare(nullptr,800,600,1,0) || !gpu->draw({},0)) throw std::runtime_error("GPU recreation failed");
    std::vector<BYTE> empty; if(!gpu->readback(empty)) throw std::runtime_error("Empty GPU readback failed");
    for(size_t i=0;i<empty.size();++i) if(i%4!=3 && empty[i]!=0) throw std::runtime_error("Empty GPU frame was not cleared");
    std::cout<<(acceptable?"PASS: ":"FAIL: ")<<cases<<" hardware GPU images; max "<<worst<<"/255, RGB energy "<<worstEnergy<<"%, RMS "<<worstRms<<"/255; overlay and device recreation\n";
    return acceptable?0:1;
} catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
