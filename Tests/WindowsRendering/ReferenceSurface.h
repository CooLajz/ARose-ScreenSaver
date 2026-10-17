#pragma once
#include <wincodec.h>
#include <stdexcept>
#include <string>
#include "../../Windows/ModernDrawing.h"
namespace arose::test {
template<class T> using ComPtr=Microsoft::WRL::ComPtr<T>;
inline void check(HRESULT hr) { if(FAILED(hr)) throw std::runtime_error("Direct2D image test failed: "+std::to_string(static_cast<unsigned>(hr))); }
struct Surface {
    ComPtr<IWICBitmap> image;
    ComPtr<ID2D1RenderTarget> target;
    ComPtr<ID2D1SolidColorBrush> brush;
    ModernDrawing drawing;
    UINT width,height;
    Surface(IWICImagingFactory* wic,ID2D1Factory* d2d,UINT w,UINT h):width(w),height(h) {
        check(wic->CreateBitmap(w,h,GUID_WICPixelFormat32bppPBGRA,WICBitmapCacheOnLoad,&image));
        auto props=D2D1::RenderTargetProperties(); props.dpiX=props.dpiY=96;
        check(d2d->CreateWicBitmapRenderTarget(image.Get(),props,&target));
        check(target->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White),&brush));
    }
    std::vector<BYTE> render(const PreparedFrame& frame,float diameter,float glow,bool cached) {
        if(!drawing.prepare(target.Get(),diameter,glow,cached) || (cached && glow>0 && !drawing.cached()))
            throw std::runtime_error("Halo atlas was not created");
        target->BeginDraw(); target->Clear(D2D1::ColorF(D2D1::ColorF::Black));
        drawing.draw(target.Get(),brush.Get(),frame,diameter,glow,cached);
        check(target->EndDraw());
        std::vector<BYTE> pixels(size_t(width)*height*4);
        check(image->CopyPixels(nullptr,width*4,static_cast<UINT>(pixels.size()),pixels.data()));
        return pixels;
    }
};
}
