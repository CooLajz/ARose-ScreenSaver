#pragma once
#include <d2d1.h>
#include <wrl/client.h>
#include "PreparedFrame.h"

namespace arose {
inline D2D1_COLOR_F rainbow(double hue, float saturation, float alpha = 1) {
    double h=hue*6; int sector=static_cast<int>(h)%6; float f=static_cast<float>(h-std::floor(h));
    float p=1-saturation,q=1-f*saturation,t=1-(1-f)*saturation;
    const float c[6][3]={{1,t,p},{q,1,p},{p,1,t},{p,q,1},{t,p,1},{1,p,q}};
    return D2D1::ColorF(c[sector][0],c[sector][1],c[sector][2],alpha);
}

// Cache soft halos as textures. Sharp dots retain the original Direct2D
// subpixel ellipse rasterizer, ordering and source-over blending.
class ModernDrawing {
    template<class T> using ComPtr=Microsoft::WRL::ComPtr<T>;
    std::array<ComPtr<ID2D1RadialGradientBrush>,256> halos;
    ComPtr<ID2D1Bitmap> atlas;
    float atlasRadius=0;
    unsigned tile=0;
    bool atlasFailed=false;
    bool makeAtlas(ID2D1RenderTarget* target,float radius) {
        atlas.Reset(); atlasRadius=radius;
        // Two transparent pixels protect each tile from bilinear sampling of
        // adjacent hues. There is no scaled-down rendering of the whole rose.
        tile=static_cast<unsigned>(std::ceil(radius*2))+4;
        const unsigned side=tile*16;
        if(side>target->GetMaximumBitmapSize()) return false;
        ComPtr<ID2D1BitmapRenderTarget> cache;
        HRESULT hr=target->CreateCompatibleRenderTarget(D2D1::SizeF(float(side),float(side)),
            D2D1::SizeU(side,side),D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_PREMULTIPLIED),&cache);
        if(FAILED(hr)) return false;
        cache->SetDpi(96,96);
        cache->BeginDraw(); cache->Clear(D2D1::ColorF(0,0,0,0));
        for(size_t i=0;i<halos.size();++i) {
            auto center=D2D1::Point2F(float(i%16*tile)+float(tile)/2,float(i/16*tile)+float(tile)/2);
            auto h=halos[i].Get();
            h->SetCenter(center); h->SetRadiusX(radius); h->SetRadiusY(radius); h->SetOpacity(1);
            cache->FillEllipse(D2D1::Ellipse(center,radius,radius),h);
        }
        if(FAILED(cache->EndDraw())) return false;
        return SUCCEEDED(cache->GetBitmap(&atlas));
    }
public:
    static HRESULT createHalo(ID2D1RenderTarget* target,size_t i,ID2D1RadialGradientBrush** result) {
        auto color=rainbow(double(i)/256,0.9f);
        D2D1_GRADIENT_STOP stops[4]={{0,color},{0.2f,color},{0.55f,color},{1,color}};
        stops[0].color.a=0.85f; stops[1].color.a=0.48f; stops[2].color.a=0.12f; stops[3].color.a=0;
        ComPtr<ID2D1GradientStopCollection> collection;
        HRESULT hr=target->CreateGradientStopCollection(stops,4,&collection);
        if(SUCCEEDED(hr)) hr=target->CreateRadialGradientBrush(
            D2D1::RadialGradientBrushProperties(D2D1::Point2F(),D2D1::Point2F(),1,1),collection.Get(),result);
        return hr;
    }
    static float diameter(float width,float height,float dpi) {
        return std::max(1.0f,std::min(1.8f*dpi,std::min(width,height)/600));
    }
    void discard() {
        atlas.Reset(); for(auto& h:halos) h.Reset(); atlasRadius=0; tile=0; atlasFailed=false;
    }
    bool cached() const { return atlas.Get()!=nullptr; }
    bool prepare(ID2D1RenderTarget* target,float diameter,float glow,bool useAtlas) {
        if(glow<=0) return true;
        for(size_t i=0;i<halos.size();++i) if(!halos[i]) {
            if(FAILED(createHalo(target,i,&halos[i]))) return false;
        }
        const float radius=diameter*(4+12*glow)/2;
        if(useAtlas && (radius!=atlasRadius || (!atlas && !atlasFailed)))
            atlasFailed=!makeAtlas(target,radius);
        return true; // Cache allocation failure keeps the reference renderer.
    }
    void draw(ID2D1RenderTarget* target,ID2D1SolidColorBrush* brush,const PreparedFrame& prepared,
              float diameter,float glow,bool useAtlas) {
        if(glow>0) {
            const float radius=diameter*(4+12*glow)/2;
            for(size_t i=0;i<prepared.count;++i) {
                const auto& p=prepared.points[i];
                auto center=D2D1::Point2F(p.x,p.y);
                const float opacity=glow*p.strength*0.5f;
                if(useAtlas && atlas && atlasRadius==radius) {
                    const float x=float(p.halo%16*tile), y=float(p.halo/16*tile), half=float(tile)/2;
                    target->DrawBitmap(atlas.Get(),D2D1::RectF(p.x-half,p.y-half,p.x+half,p.y+half),opacity,
                        D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,D2D1::RectF(x,y,x+tile,y+tile));
                } else {
                    auto h=halos[p.halo].Get();
                    h->SetCenter(center); h->SetRadiusX(radius); h->SetRadiusY(radius); h->SetOpacity(opacity);
                    target->FillEllipse(D2D1::Ellipse(center,radius,radius),h);
                }
            }
        }
        for(size_t i=0;i<prepared.count;++i) {
            const auto& p=prepared.points[i];
            auto center=D2D1::Point2F(p.x,p.y);
            brush->SetColor(rainbow(p.hue,0.9f,p.strength));
            target->FillEllipse(D2D1::Ellipse(center,diameter/2,diameter/2),brush);
            if(glow>0) {
                brush->SetColor(rainbow(p.hue,0.25f,p.strength*glow*0.8f));
                target->FillEllipse(D2D1::Ellipse(center,diameter*0.275f,diameter*0.275f),brush);
            }
        }
    }
};
}
