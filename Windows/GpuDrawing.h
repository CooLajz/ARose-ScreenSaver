#pragma once
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d2d1_1.h>
#include <d3dcompiler.h>
#include <cstring>
#include "ModernDrawing.h"

namespace arose {
// A few instanced draws replace thousands of per-point Direct2D calls.
// Direct2D creates the small reference atlases only when their size changes.
// Production never reads the frame back from the GPU.
class GpuDrawing {
    template<class T> using ComPtr=Microsoft::WRL::ComPtr<T>;
    struct Apartment {
        HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
        ~Apartment() { if(SUCCEEDED(hr)) CoUninitialize(); }
    } apartment;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<IDXGISwapChain1> swap;
    ComPtr<ID3D11Texture2D> output;
    ComPtr<ID3D11RenderTargetView> view;
    ComPtr<ID3D11VertexShader> vertexShader;
    ComPtr<ID3D11PixelShader> haloShader,pointShader;
    ComPtr<ID3D11InputLayout> layout;
    ComPtr<ID3D11Buffer> instances,constants;
    ComPtr<ID3D11BlendState> blend;
    ComPtr<ID3D11RasterizerState> rasterizer;
    ComPtr<ID3D11SamplerState> linear;
    ComPtr<ID3D11ShaderResourceView> halos,coverage;
    ComPtr<ID2D1Factory1> overlayFactory;
    ComPtr<ID2D1Device> overlayDevice;
    ComPtr<ID2D1DeviceContext> overlay;
    ComPtr<ID2D1Bitmap1> overlayBitmap;
    ComPtr<ID2D1SolidColorBrush> overlayInk;
    float pointDiameter=0,haloRadius=0;
    unsigned pointTile=0,haloTile=0;
    UINT width=0,height=0;
    unsigned drawCalls=0;
    bool pipelineReady=false;
    // Avoid aligning every sample to the rasterizer's power-of-two subpixel
    // grid. Dense sampling bounds tiny-point differences without per-frame AA.
    static constexpr unsigned phaseSteps=127,phases=phaseSteps+1;
    struct Instance { float rect[4],parameters[4],color[4]; };
    std::array<Instance,20*96*3> sprites{};
    static_assert(sizeof(Instance)==48,"GPU instance layout changed");
    bool ensureD2DDevice() {
        if(overlayDevice) return true;
        if(FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,overlayFactory.GetAddressOf()))) return false;
        ComPtr<IDXGIDevice> dxgi; if(FAILED(device.As(&dxgi))) return false;
        return SUCCEEDED(overlayFactory->CreateDevice(dxgi.Get(),&overlayDevice));
    }
    bool atlasSurface(UINT w,UINT h,ComPtr<ID3D11Texture2D>& texture,ComPtr<ID2D1DeviceContext>& target) {
        if(!ensureD2DDevice()) return false;
        D3D11_TEXTURE2D_DESC desc{};
        desc.Width=w; desc.Height=h; desc.MipLevels=desc.ArraySize=1;
        desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count=1;
        desc.BindFlags=D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_RENDER_TARGET;
        if(FAILED(device->CreateTexture2D(&desc,nullptr,&texture)) ||
            FAILED(overlayDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE,&target))) return false;
        ComPtr<IDXGISurface> surface; if(FAILED(texture.As(&surface))) return false;
        auto props=D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_PREMULTIPLIED),96,96);
        ComPtr<ID2D1Bitmap1> bitmap;
        if(FAILED(target->CreateBitmapFromDxgiSurface(surface.Get(),&props,&bitmap))) return false;
        target->SetTarget(bitmap.Get()); target->SetDpi(96,96); return true;
    }
    bool preparePoints(float diameter) {
        if(coverage && diameter==pointDiameter) return true;
        const unsigned cell=2*static_cast<unsigned>(std::ceil(diameter/2))+4, side=cell*phases;
        const float pad=float(cell/2);
        ComPtr<ID3D11Texture2D> texture; ComPtr<ID2D1DeviceContext> target;
        if(!atlasSurface(side,side*2,texture,target)) return false;
        ComPtr<ID2D1SolidColorBrush> white;
        if(FAILED(target->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White),&white))) return false;
        target->BeginDraw(); target->Clear(D2D1::ColorF(0,0,0,0));
        const float originX=512,originY=512;
        for(unsigned slice=0;slice<2;++slice) {
            const float radius=diameter*(slice==0?0.5f:0.275f);
            for(unsigned y=0;y<phases;++y) for(unsigned x=0;x<phases;++x) {
                target->SetTransform(D2D1::Matrix3x2F::Translation(float(x*cell)+pad-originX,float(slice*side+y*cell)+pad-originY));
                auto center=D2D1::Point2F(originX+float(x)/phaseSteps,originY+float(y)/phaseSteps);
                target->FillEllipse(D2D1::Ellipse(center,radius,radius),white.Get());
            }
        }
        if(FAILED(target->EndDraw())) return false;
        target->SetTarget(nullptr); coverage.Reset();
        if(FAILED(device->CreateShaderResourceView(texture.Get(),nullptr,&coverage))) return false;
        pointTile=cell; pointDiameter=diameter; return true;
    }
    bool prepareHalos(float radius) {
        if(halos && radius==haloRadius) return true;
        const unsigned cell=static_cast<unsigned>(std::ceil(radius*2))+4,side=cell*16;
        ComPtr<ID3D11Texture2D> texture; ComPtr<ID2D1DeviceContext> target;
        if(!atlasSurface(side,side,texture,target)) return false;
        target->BeginDraw(); target->Clear(D2D1::ColorF(0,0,0,0));
        for(size_t i=0;i<256;++i) {
            ComPtr<ID2D1RadialGradientBrush> h;
            if(FAILED(ModernDrawing::createHalo(target.Get(),i,&h))) { target->EndDraw(); return false; }
            auto center=D2D1::Point2F(float(i%16*cell)+float(cell)/2,float(i/16*cell)+float(cell)/2);
            h->SetCenter(center); h->SetRadiusX(radius); h->SetRadiusY(radius); h->SetOpacity(1);
            target->FillEllipse(D2D1::Ellipse(center,radius,radius),h.Get());
        }
        if(FAILED(target->EndDraw())) return false;
        target->SetTarget(nullptr); halos.Reset();
        if(FAILED(device->CreateShaderResourceView(texture.Get(),nullptr,&halos))) return false;
        haloTile=cell; haloRadius=radius; return true;
    }
    bool pipeline() {
        if(pipelineReady) return true;
        if(device) return false; // A failed partial initialization must be discarded.
        const D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_0};
        if(FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            levels,1,D3D11_SDK_VERSION,&device,nullptr,&context))) return false;
        ComPtr<ID3DBlob> vs,psHalo,psPoint,error;
        const UINT flags=D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_OPTIMIZATION_LEVEL3;
        if(FAILED(D3DCompile(shader,std::strlen(shader),"ARose",nullptr,nullptr,"vertexMain","vs_5_0",flags,0,&vs,&error)) ||
           FAILED(D3DCompile(shader,std::strlen(shader),"ARose",nullptr,nullptr,"haloMain","ps_5_0",flags,0,&psHalo,&error)) ||
           FAILED(D3DCompile(shader,std::strlen(shader),"ARose",nullptr,nullptr,"pointMain","ps_5_0",flags,0,&psPoint,&error))) {
            if(error) OutputDebugStringA(static_cast<const char*>(error->GetBufferPointer()));
            return false;
        }
        if(FAILED(device->CreateVertexShader(vs->GetBufferPointer(),vs->GetBufferSize(),nullptr,&vertexShader)) ||
           FAILED(device->CreatePixelShader(psHalo->GetBufferPointer(),psHalo->GetBufferSize(),nullptr,&haloShader)) ||
           FAILED(device->CreatePixelShader(psPoint->GetBufferPointer(),psPoint->GetBufferSize(),nullptr,&pointShader))) return false;
        const D3D11_INPUT_ELEMENT_DESC elements[]={
            {"RECT",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,0,D3D11_INPUT_PER_INSTANCE_DATA,1},
            {"PARAMS",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,16,D3D11_INPUT_PER_INSTANCE_DATA,1},
            {"COLOR",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,32,D3D11_INPUT_PER_INSTANCE_DATA,1}};
        if(FAILED(device->CreateInputLayout(elements,3,vs->GetBufferPointer(),vs->GetBufferSize(),&layout))) return false;
        D3D11_BUFFER_DESC buffer{}; buffer.ByteWidth=static_cast<UINT>(sizeof sprites); buffer.Usage=D3D11_USAGE_DYNAMIC;
        buffer.BindFlags=D3D11_BIND_VERTEX_BUFFER; buffer.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;
        if(FAILED(device->CreateBuffer(&buffer,nullptr,&instances))) return false;
        buffer.ByteWidth=32; buffer.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        if(FAILED(device->CreateBuffer(&buffer,nullptr,&constants))) return false;
        D3D11_BLEND_DESC blending{}; auto& b=blending.RenderTarget[0]; b.BlendEnable=TRUE;
        b.SrcBlend=b.SrcBlendAlpha=D3D11_BLEND_ONE; b.DestBlend=b.DestBlendAlpha=D3D11_BLEND_INV_SRC_ALPHA;
        b.BlendOp=b.BlendOpAlpha=D3D11_BLEND_OP_ADD; b.RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
        if(FAILED(device->CreateBlendState(&blending,&blend))) return false;
        D3D11_RASTERIZER_DESC r{}; r.FillMode=D3D11_FILL_SOLID; r.CullMode=D3D11_CULL_NONE; r.DepthClipEnable=TRUE;
        if(FAILED(device->CreateRasterizerState(&r,&rasterizer))) return false;
        D3D11_SAMPLER_DESC sampler{}; sampler.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        sampler.AddressU=sampler.AddressV=sampler.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP; sampler.MaxLOD=D3D11_FLOAT32_MAX;
        pipelineReady=SUCCEEDED(device->CreateSamplerState(&sampler,&linear)); return pipelineReady;
    }
    void releaseOutput() {
        if(context) { context->OMSetRenderTargets(0,nullptr,nullptr); context->Flush(); }
        if(overlay) overlay->SetTarget(nullptr);
        overlayInk.Reset(); overlayBitmap.Reset(); view.Reset(); output.Reset();
    }
    bool bindOutput() {
        if(FAILED(device->CreateRenderTargetView(output.Get(),nullptr,&view))) return false;
        return true;
    }
    bool prepareOverlay() {
        if(overlayBitmap) return true;
        if(!overlay) {
            if(!ensureD2DDevice() || FAILED(overlayDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE,&overlay))) return false;
        }
        ComPtr<IDXGISurface> surface;
        if(FAILED(output.As(&surface))) return false;
        auto props=D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET|D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_IGNORE),96,96);
        if(FAILED(overlay->CreateBitmapFromDxgiSurface(surface.Get(),&props,&overlayBitmap))) return false;
        overlay->SetTarget(overlayBitmap.Get()); overlay->SetDpi(96,96);
        return SUCCEEDED(overlay->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White),&overlayInk));
    }
public:
    ~GpuDrawing() {
        releaseOutput(); overlay.Reset(); overlayDevice.Reset(); overlayFactory.Reset(); swap.Reset();
        if(context) { context->ClearState(); context->Flush(); }
    }
    GpuDrawing()=default;
    GpuDrawing(const GpuDrawing&)=delete;
    GpuDrawing& operator=(const GpuDrawing&)=delete;
    UINT pixelWidth() const { return width; }
    UINT pixelHeight() const { return height; }
    unsigned calls() const { return drawCalls; }
    bool prepare(HWND window,UINT w,UINT h,float diameter,float glow) {
        if(!pipeline()) return false;
        w=std::max(1u,w); h=std::max(1u,h);
        if(!output || width!=w || height!=h) {
            releaseOutput();
            if(window) {
                if(!swap) {
                    ComPtr<IDXGIDevice> dxgi; ComPtr<IDXGIAdapter> adapter; ComPtr<IDXGIFactory2> dxgiFactory;
                    if(FAILED(device.As(&dxgi)) || FAILED(dxgi->GetAdapter(&adapter)) || FAILED(adapter->GetParent(IID_PPV_ARGS(&dxgiFactory)))) return false;
                    DXGI_SWAP_CHAIN_DESC1 desc{}; desc.Width=w; desc.Height=h; desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
                    desc.SampleDesc.Count=1; desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; desc.BufferCount=2;
                    desc.SwapEffect=DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL; desc.AlphaMode=DXGI_ALPHA_MODE_IGNORE;
                    if(FAILED(dxgiFactory->CreateSwapChainForHwnd(device.Get(),window,&desc,nullptr,nullptr,&swap))) return false;
                    dxgiFactory->MakeWindowAssociation(window,DXGI_MWA_NO_ALT_ENTER);
                } else if(FAILED(swap->ResizeBuffers(2,w,h,DXGI_FORMAT_B8G8R8A8_UNORM,0))) return false;
                if(FAILED(swap->GetBuffer(0,IID_PPV_ARGS(&output)))) return false;
            } else {
                D3D11_TEXTURE2D_DESC desc{}; desc.Width=w; desc.Height=h; desc.MipLevels=desc.ArraySize=1;
                desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count=1; desc.BindFlags=D3D11_BIND_RENDER_TARGET;
                if(FAILED(device->CreateTexture2D(&desc,nullptr,&output))) return false;
            }
            if(!bindOutput()) return false;
            width=w; height=h;
        }
        return preparePoints(diameter) && (glow<=0 || prepareHalos(diameter*(4+12*glow)/2));
    }
    bool draw(const PreparedFrame& frame,float glow) {
        if(!view || frame.count>20*96) return false;
        size_t count=0;
        if(glow>0) for(size_t i=0;i<frame.count;++i) {
            const auto& p=frame.points[i]; auto& s=sprites[count++]; const float half=float(haloTile)/2;
            s={{p.x-half,p.y-half,float(haloTile),float(haloTile)},
                {float(p.halo),glow*p.strength*0.5f,0,0},{1,1,1,1}};
        }
        const UINT haloCount=static_cast<UINT>(count);
        for(size_t i=0;i<frame.count;++i) {
            const auto& p=frame.points[i];
            const float x=std::floor(p.x),y=std::floor(p.y),pad=float(pointTile/2);
            for(unsigned slice=0;slice<(glow>0?2u:1u);++slice) {
                const auto color=rainbow(p.hue,slice==0?0.9f:0.25f);
                const float opacity=p.strength*(slice==0?1:glow*0.8f);
                sprites[count++]={{x-pad,y-pad,float(pointTile),float(pointTile)},
                    {p.x-x,opacity,p.y-y,float(slice)},{color.r,color.g,color.b,1}};
            }
        }
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if(FAILED(context->Map(instances.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapped))) return false;
        std::memcpy(mapped.pData,sprites.data(),count*sizeof(Instance)); context->Unmap(instances.Get(),0);
        const float values[8]={float(width),float(height),float(pointTile),float(haloTile),float(haloTile*16),float(haloTile*16),float(phaseSteps),0};
        if(FAILED(context->Map(constants.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapped))) return false;
        std::memcpy(mapped.pData,values,sizeof values); context->Unmap(constants.Get(),0);
        auto rtv=view.Get(); context->OMSetRenderTargets(1,&rtv,nullptr);
        const float black[4]={0,0,0,1}; context->ClearRenderTargetView(rtv,black);
        context->OMSetBlendState(blend.Get(),nullptr,0xffffffff);
        context->RSSetState(rasterizer.Get()); D3D11_VIEWPORT viewport{0,0,float(width),float(height),0,1}; context->RSSetViewports(1,&viewport);
        context->IASetInputLayout(layout.Get()); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        const UINT stride=sizeof(Instance),offset=0; auto vb=instances.Get(); context->IASetVertexBuffers(0,1,&vb,&stride,&offset);
        context->VSSetShader(vertexShader.Get(),nullptr,0); auto cb=constants.Get(); context->VSSetConstantBuffers(0,1,&cb); context->PSSetConstantBuffers(0,1,&cb);
        context->GSSetShader(nullptr,nullptr,0); context->HSSetShader(nullptr,nullptr,0); context->DSSetShader(nullptr,nullptr,0);
        context->OMSetDepthStencilState(nullptr,0);
        drawCalls=0;
        if(haloCount) {
            context->PSSetShader(haloShader.Get(),nullptr,0); auto srv=halos.Get(); context->PSSetShaderResources(0,1,&srv);
            auto sampler=linear.Get(); context->PSSetSamplers(0,1,&sampler);
            context->DrawInstanced(6,haloCount,0,0); ++drawCalls;
        }
        if(count>haloCount) {
            context->PSSetShader(pointShader.Get(),nullptr,0); auto srv=coverage.Get(); context->PSSetShaderResources(0,1,&srv);
            context->DrawInstanced(6,static_cast<UINT>(count)-haloCount,0,haloCount); ++drawCalls;
        }
        ID3D11ShaderResourceView* empty=nullptr; context->PSSetShaderResources(0,1,&empty);
        return SUCCEEDED(device->GetDeviceRemovedReason());
    }
    ID2D1RenderTarget* beginOverlay() {
        if(!prepareOverlay()) return nullptr;
        context->OMSetRenderTargets(0,nullptr,nullptr); overlay->BeginDraw(); return overlay.Get();
    }
    ID2D1SolidColorBrush* overlayBrush() { return overlayInk.Get(); }
    bool endOverlay() { return overlay && SUCCEEDED(overlay->EndDraw()); }
    bool present() { return swap && SUCCEEDED(swap->Present(0,0)); }
    // Synchronous readback is confined to regression tests.
    bool readback(std::vector<BYTE>& pixels) {
        D3D11_TEXTURE2D_DESC desc{}; output->GetDesc(&desc); desc.Usage=D3D11_USAGE_STAGING;
        desc.BindFlags=0; desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ; desc.MiscFlags=0;
        ComPtr<ID3D11Texture2D> staging; if(FAILED(device->CreateTexture2D(&desc,nullptr,&staging))) return false;
        context->CopyResource(staging.Get(),output.Get()); D3D11_MAPPED_SUBRESOURCE mapped{};
        if(FAILED(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped))) return false;
        pixels.resize(size_t(width)*height*4);
        for(UINT y=0;y<height;++y) std::memcpy(pixels.data()+size_t(y)*width*4,static_cast<const BYTE*>(mapped.pData)+size_t(y)*mapped.RowPitch,size_t(width)*4);
        context->Unmap(staging.Get(),0); return true;
    }
private:
    static constexpr const char* shader=R"hlsl(
cbuffer Viewport : register(b0) { float4 viewport; float4 atlas; };
struct Input { float4 rect:RECT; float4 params:PARAMS; float4 color:COLOR; uint vertex:SV_VertexID; };
struct Output { float4 position:SV_Position; float2 uv:TEXCOORD0;
    nointerpolation float4 params:TEXCOORD1; nointerpolation float4 color:COLOR;
    nointerpolation float2 extent:TEXCOORD2; };
Output vertexMain(Input input) {
    static const float2 corners[6]={float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
    float2 uv=corners[input.vertex], p=input.rect.xy+uv*input.rect.zw;
    Output result; result.position=float4(p.x/viewport.x*2-1,1-p.y/viewport.y*2,0,1);
    result.uv=uv; result.params=input.params; result.color=input.color; result.extent=input.rect.zw; return result;
}
Texture2D<float4> haloImage:register(t0); SamplerState linearFilter:register(s0);
float4 haloMain(Output input):SV_Target {
    uint index=uint(input.params.x); float2 origin=float2(index%16,index/16)*viewport.w;
    return haloImage.Sample(linearFilter,(origin+input.uv*viewport.w)/atlas.xy)*input.params.y;
}
Texture2D<float4> pointImage:register(t0);
float4 pointMain(Output input):SV_Target {
    float2 phase=input.params.xz*atlas.z; uint2 base=uint2(floor(phase)); float2 blend=frac(phase);
    uint tile=uint(viewport.z),slice=uint(input.params.w);
    uint2 pixel=min(uint2(input.uv*input.extent),uint2(tile-1,tile-1))+uint2(0,slice*(uint(atlas.z)+1)*tile);
    float a=pointImage.Load(int3(base*tile+pixel,0)).a;
    float b=pointImage.Load(int3((base+uint2(1,0))*tile+pixel,0)).a;
    float c=pointImage.Load(int3((base+uint2(0,1))*tile+pixel,0)).a;
    float d=pointImage.Load(int3((base+uint2(1,1))*tile+pixel,0)).a;
    float alpha=lerp(lerp(a,b,blend.x),lerp(c,d,blend.x),blend.y)*input.params.y;
    return float4(input.color.rgb*alpha,alpha);
}
)hlsl";
};
}
