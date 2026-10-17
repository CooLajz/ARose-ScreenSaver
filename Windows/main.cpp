#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <d2d1.h>
#include <dwmapi.h>
#include <dwrite.h>
#include <chrono>
#include <cwchar>
#include <cwctype>
#include <memory>
#include <string>
#include "RoseEngine.h"
#include "FrameTiming.h"
#include "PreparedFrame.h"
#include "resource.h"

namespace {
using namespace arose;
HINSTANCE instance;
bool czech = false, preview = false, windowed = false, paused = false, smoke = false;
Settings settings;
std::unique_ptr<Engine> engine;
ID2D1Factory* factory = nullptr;
std::vector<HWND> windows;
POINT initialMouse{};
ULONGLONG started = 0;
using AnimationClock = std::chrono::steady_clock;
auto lastStep = AnimationClock::now();
FrameTiming frameTiming;
bool animationReady = false;
std::deque<std::array<ModernPoint, 96>> previousHistory;
unsigned renderedFrames = 0;
constexpr wchar_t settingsKey[] = L"Software\\CooLajz\\ARose";
const wchar_t* tr(const wchar_t* en, const wchar_t* cs) { return czech ? cs : en; }
template<class T> void release(T*& p) { if (p) { p->Release(); p = nullptr; } }
void chooseLanguage() {
    ULONG count = 0, size = 0;
    GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &count, nullptr, &size);
    if (!size) return;
    std::vector<wchar_t> languages(size);
    if (!GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &count, languages.data(), &size)) return;
    for (const wchar_t* p = languages.data(); *p; p += wcslen(p) + 1) {
        if (_wcsnicmp(p, L"cs", 2) == 0 && (p[2] == 0 || p[2] == L'-')) { czech = true; return; }
        if (_wcsnicmp(p, L"en", 2) == 0 && (p[2] == 0 || p[2] == L'-')) return;
    }
}
void loadSettings() {
    const wchar_t* names[] = {L"Appearance", L"Speed", L"Trail", L"Palette", L"Glow", L"DebugCPU", L"ResumeFigure"};
    int* values[] = {&settings.appearance, &settings.speed, &settings.tail, &settings.palette, &settings.glow, &settings.debugCPU, &settings.resumeFigure};
    for (int i = 0; i < 7; ++i) {
        DWORD value = 0, bytes = sizeof value;
        if (RegGetValueW(HKEY_CURRENT_USER, settingsKey, names[i], RRF_RT_REG_DWORD, nullptr, &value, &bytes) == ERROR_SUCCESS && value <= INT_MAX)
            *values[i] = static_cast<int>(value);
    }
    settings.validate();
}
bool saveSettings(const Settings& s) {
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, settingsKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
    const wchar_t* names[] = {L"Appearance", L"Speed", L"Trail", L"Palette", L"Glow", L"DebugCPU", L"ResumeFigure"};
    const int values[] = {s.appearance, s.speed, s.tail, s.palette, s.glow, s.debugCPU, s.resumeFigure};
    bool success = true;
    for (int i = 0; i < 7; ++i) {
        DWORD v = static_cast<DWORD>(values[i]);
        success = (RegSetValueExW(key, names[i], 0, REG_DWORD, reinterpret_cast<const BYTE*>(&v), sizeof v) == ERROR_SUCCESS) && success;
    }
    RegCloseKey(key); return success;
}
uint64_t lastFigureSave = 0;
const wchar_t* figureValue() { return windowed ? L"PreviewFigureV1" : L"FigureV1"; }
void loadFigure() {
    if(preview || smoke || !settings.resumeFigure) return;
    Engine::FigureState state{};
    DWORD bytes=sizeof state;
    if(RegGetValueW(HKEY_CURRENT_USER,settingsKey,figureValue(),RRF_RT_REG_BINARY,nullptr,state.data(),&bytes)==ERROR_SUCCESS && bytes==sizeof state)
        engine->restoreFigure(state);
    lastFigureSave=engine->frame;
}
void saveFigure() {
    if(preview || smoke || !settings.resumeFigure || !engine || !engine->frame) return;
    HKEY key=nullptr;
    if(RegCreateKeyExW(HKEY_CURRENT_USER,settingsKey,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)!=ERROR_SUCCESS) return;
    auto state=engine->savedFigure();
    RegSetValueExW(key,figureValue(),0,REG_BINARY,reinterpret_cast<const BYTE*>(state.data()),sizeof state);
    RegCloseKey(key); lastFigureSave=engine->frame;
}
struct CPUMeter {
    ULONGLONG wall = 0, cpu = 0;
    double percent = -1, singleCorePercent = -1;
    void sample() {
        ULONGLONG now = GetTickCount64();
        if(wall && now-wall<1000) return;
        FILETIME creation, exit, kernel, user;
        if(!GetProcessTimes(GetCurrentProcess(),&creation,&exit,&kernel,&user)) { wall=0; percent=-1; singleCorePercent=-1; return; }
        auto ticks=[](FILETIME t) { return (static_cast<ULONGLONG>(t.dwHighDateTime)<<32)|t.dwLowDateTime; };
        ULONGLONG total=ticks(kernel)+ticks(user);
        // FILETIME is in 100 ns units; wall time is in milliseconds.
        if(wall && now>wall && total>=cpu) {
            singleCorePercent=double(total-cpu)/double(now-wall)/100;
            percent=std::clamp(singleCorePercent / std::max<DWORD>(1,GetActiveProcessorCount(ALL_PROCESSOR_GROUPS)),0.0,100.0);
        }
        wall=now; cpu=total;
    }
} cpuMeter;
void resetEngine() { lastFigureSave = 0; animationReady = false; cpuMeter = {}; engine = std::make_unique<Engine>(); engine->settings = settings; lastStep = AnimationClock::now(); frameTiming = {}; previousHistory.clear(); }
int selection(HWND d, int id) { return static_cast<int>(SendDlgItemMessageW(d, id, CB_GETCURSEL, 0, 0)); }
void updateDialog(HWND d) {
    bool modern = selection(d, IDC_STYLE) == 1;
    EnableWindow(GetDlgItem(d, IDC_PALETTE), !modern);
    EnableWindow(GetDlgItem(d, IDC_GLOW), modern);
    EnableWindow(GetDlgItem(d, IDC_PERCENT), modern);
    auto value = SendDlgItemMessageW(d, IDC_GLOW, TBM_GETPOS, 0, 0);
    SetDlgItemTextW(d, IDC_PERCENT, (std::to_wstring(value) + L" %").c_str());
}
INT_PTR CALLBACK settingsProc(HWND d, UINT msg, WPARAM wp, LPARAM) {
    constexpr int lengths[] = {1, 4, 8, 12, 16, 20};
    if (msg == WM_INITDIALOG) {
        SetWindowTextW(d, tr(L"ARose Settings", L"Nastavení ARose"));
        const int ids[] = {IDC_STYLE_LABEL,IDC_SPEED_LABEL,IDC_TRAIL_LABEL,IDC_PALETTE_LABEL,IDC_GLOW_LABEL,IDC_NOTE,IDOK,IDCANCEL};
        const wchar_t* en[] = {L"Style",L"Speed",L"Trail",L"Colors",L"Glow",L"Glow is available in Modern mode. Modern colors use a smooth rainbow.",L"Save",L"Cancel"};
        const wchar_t* cs[] = {L"Podoba",L"Rychlost",L"Stopa",L"Barvy",L"Záře",L"Záře je dostupná v moderním režimu. Moderní barvy používají plynulou duhu.",L"Uložit",L"Zrušit"};
        for (int i=0;i<8;++i) SetDlgItemTextW(d,ids[i],tr(en[i],cs[i]));
        auto add = [d](int id, const wchar_t* e, const wchar_t* c) { SendDlgItemMessageW(d,id,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(tr(e,c))); };
        add(IDC_STYLE,L"Original Amiga",L"Originální Amiga"); add(IDC_STYLE,L"Modern",L"Moderní");
        const wchar_t* speedsEN[] = {L"Very slow",L"Slow",L"Normal",L"Fast",L"Very fast"};
        const wchar_t* speedsCS[] = {L"Velmi pomalu",L"Pomalu",L"Normálně",L"Rychle",L"Velmi rychle"};
        for(int i=0;i<5;++i) add(IDC_SPEED,speedsEN[i],speedsCS[i]);
        const wchar_t* trailsEN[] = {L"No trail",L"Short",L"Medium short",L"Medium",L"Long",L"Longest"};
        const wchar_t* trailsCS[] = {L"Bez stopy",L"Krátká",L"Středně krátká",L"Střední",L"Dlouhá",L"Nejdelší"};
        int trailIndex = 4;
        for(int i=0;i<6;++i) { add(IDC_TRAIL,trailsEN[i],trailsCS[i]); if(lengths[i]==settings.tail) trailIndex=i; }
        add(IDC_PALETTE,L"Black and white",L"Černobílá"); add(IDC_PALETTE,L"Amiga ECS · 16 colors",L"Amiga ECS · 16 barev"); add(IDC_PALETTE,L"Amiga AGA · 256 colors",L"Amiga AGA · 256 barev");
        SendDlgItemMessageW(d,IDC_STYLE,CB_SETCURSEL,settings.appearance,0);
        SendDlgItemMessageW(d,IDC_SPEED,CB_SETCURSEL,settings.speed-1,0);
        SendDlgItemMessageW(d,IDC_TRAIL,CB_SETCURSEL,trailIndex,0);
        SendDlgItemMessageW(d,IDC_PALETTE,CB_SETCURSEL,settings.palette,0);
        SendDlgItemMessageW(d,IDC_GLOW,TBM_SETRANGE,TRUE,MAKELPARAM(0,100));
        SendDlgItemMessageW(d,IDC_GLOW,TBM_SETPOS,TRUE,settings.glow);
        SetDlgItemTextW(d,IDC_DEBUG_CPU,tr(L"Debug: show process CPU usage",L"Debug: zobrazovat vytížení procesu"));
        CheckDlgButton(d,IDC_DEBUG_CPU,settings.debugCPU?BST_CHECKED:BST_UNCHECKED);
        SetDlgItemTextW(d,IDC_RESUME_FIGURE,tr(L"Resume from last figure",L"Pokračovat od posledního obrazce"));
        CheckDlgButton(d,IDC_RESUME_FIGURE,settings.resumeFigure?BST_CHECKED:BST_UNCHECKED);
        updateDialog(d); return TRUE;
    }
    if(msg==WM_HSCROLL) { updateDialog(d); return TRUE; }
    if(msg==WM_COMMAND) {
        if(LOWORD(wp)==IDC_STYLE && HIWORD(wp)==CBN_SELCHANGE) { updateDialog(d); return TRUE; }
        if(LOWORD(wp)==IDCANCEL) { EndDialog(d,IDCANCEL); return TRUE; }
        if(LOWORD(wp)==IDOK) {
            Settings s = settings;
            s.resumeFigure=IsDlgButtonChecked(d,IDC_RESUME_FIGURE)==BST_CHECKED?1:0;
            s.debugCPU=IsDlgButtonChecked(d,IDC_DEBUG_CPU)==BST_CHECKED?1:0;
            s.appearance=selection(d,IDC_STYLE); s.speed=selection(d,IDC_SPEED)+1;
            int index=selection(d,IDC_TRAIL); s.tail=lengths[std::clamp(index,0,5)];
            s.palette=selection(d,IDC_PALETTE); s.glow=static_cast<int>(SendDlgItemMessageW(d,IDC_GLOW,TBM_GETPOS,0,0)); s.validate();
            if(!saveSettings(s)) { MessageBoxW(d,tr(L"Settings could not be saved. Please check your user profile permissions.",L"Nastavení se nepodařilo uložit. Zkontrolujte oprávnění svého uživatelského profilu."),L"ARose",MB_OK|MB_ICONERROR); return TRUE; }
            settings=s; EndDialog(d,IDOK); return TRUE;
        }
    }
    return FALSE;
}
void showSettings(HWND parent) {
    if(DialogBoxParamW(instance,MAKEINTRESOURCEW(IDD_SETTINGS),parent,settingsProc,0)==-1)
        MessageBoxW(parent,tr(L"Unable to open ARose settings.",L"Nastavení ARose se nepodařilo otevřít."),L"ARose",MB_OK|MB_ICONERROR);
}
D2D1_COLOR_F rainbow(double hue, float saturation, float alpha = 1) {
    double h = hue * 6; int sector = static_cast<int>(h) % 6; float f=static_cast<float>(h-std::floor(h));
    float p=1-saturation,q=1-f*saturation,t=1-(1-f)*saturation;
    const float c[6][3]={{1,t,p},{q,1,p},{p,1,t},{p,q,1},{t,p,1},{1,p,q}};
    return D2D1::ColorF(c[sector][0],c[sector][1],c[sector][2],alpha);
}
struct Renderer {
    ID2D1HwndRenderTarget* target=nullptr;
    ID2D1SolidColorBrush* brush=nullptr;
    ID2D1Bitmap* bitmap=nullptr;
    IDWriteFactory* textFactory=nullptr;
    IDWriteTextFormat* textFormat=nullptr;
    std::array<ID2D1RadialGradientBrush*,256> halos{};
    bool halosReady = false;
    PreparedFrame prepared;
    int cachedPalette = -1;
    std::array<uint32_t, 256> paletteColors{};
    std::vector<uint32_t> rgba = std::vector<uint32_t>(800*600);
    ~Renderer(){ discard(); release(textFormat); release(textFactory); }
    void discard() { halosReady=false; for(auto& h:halos) release(h); release(bitmap); release(brush); release(target); }
    bool create(HWND w) {
        if(target) return true;
        RECT r; GetClientRect(w,&r);
        auto properties=D2D1::RenderTargetProperties(); properties.dpiX=properties.dpiY=96;
        HRESULT hr=factory->CreateHwndRenderTarget(properties,D2D1::HwndRenderTargetProperties(w,D2D1::SizeU(std::max(1L,r.right),std::max(1L,r.bottom)),D2D1_PRESENT_OPTIONS_IMMEDIATELY),&target);
        if(SUCCEEDED(hr)) hr=target->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White),&brush);
        if(SUCCEEDED(hr)) hr=target->CreateBitmap(D2D1::SizeU(800,600),nullptr,0,D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_IGNORE)),&bitmap);
        if(FAILED(hr)) { discard(); return false; }
        return true;
    }
    ID2D1RadialGradientBrush* halo(size_t index) {
        if(halos[index]) return halos[index];
        auto color=rainbow(double(index)/256,0.9f);
        D2D1_GRADIENT_STOP stops[4]={{0,color},{0.2f,color},{0.55f,color},{1,color}};
        stops[0].color.a=0.85f; stops[1].color.a=0.48f; stops[2].color.a=0.12f; stops[3].color.a=0;
        ID2D1GradientStopCollection* collection=nullptr;
        HRESULT hr=target->CreateGradientStopCollection(stops,4,&collection);
        if(SUCCEEDED(hr)) hr=target->CreateRadialGradientBrush(D2D1::RadialGradientBrushProperties(D2D1::Point2F(),D2D1::Point2F(),1,1),collection,&halos[index]);
        release(collection); return SUCCEEDED(hr)?halos[index]:nullptr;
    }
    bool prepareResources(HWND w) {
        if(!create(w)) return false;
        if(settings.appearance==1 && settings.glow>0 && !halosReady) {
            for(size_t i=0; i<halos.size(); ++i) if(!halo(i)) return false;
            halosReady=true;
        }
        return true;
    }
    void drawCPU(HWND w) {
        cpuMeter.sample();
        if(!textFactory && FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),reinterpret_cast<IUnknown**>(&textFactory)))) return;
        if(!textFormat && FAILED(textFactory->CreateTextFormat(L"Consolas",nullptr,DWRITE_FONT_WEIGHT_NORMAL,DWRITE_FONT_STYLE_NORMAL,DWRITE_FONT_STRETCH_NORMAL,12,L"en-us",&textFormat))) return;
        wchar_t value[160];
        if(cpuMeter.percent>=0) swprintf(value,160,L"%ls: %.1f %%  |  %ls: %.1f %%",
            tr(L"1 core",L"1 jádro"),cpuMeter.singleCorePercent,tr(L"All cores",L"Všechna jádra"),cpuMeter.percent);
        else swprintf(value,160,L"%ls: —  |  %ls: —",tr(L"1 core",L"1 jádro"),tr(L"All cores",L"Všechna jádra"));
        std::wstring text=std::wstring(tr(L"Process CPU",L"CPU procesu"))+L"\n"+value;
        float dpi=static_cast<float>(GetDpiForWindow(w))/96;
        auto size=target->GetSize();
        target->SetTransform(D2D1::Matrix3x2F::Scale(dpi,dpi));
        float right=size.width/dpi-10, bottom=size.height/dpi-10;
        auto box=D2D1::RectF(std::max(0.0f,right-390),std::max(0.0f,bottom-42),right,bottom);
        brush->SetColor(D2D1::ColorF(0,0,0,0.8f)); target->FillRectangle(box,brush);
        box.left+=7; box.top+=5; box.right-=7;
        brush->SetColor(D2D1::ColorF(D2D1::ColorF::White));
        target->DrawText(text.c_str(),static_cast<UINT32>(text.size()),textFormat,box,brush,D2D1_DRAW_TEXT_OPTIONS_CLIP);
        target->SetTransform(D2D1::Matrix3x2F::Identity());
    }
    void draw(HWND w) {
        if(!prepareResources(w)) { if(smoke) PostQuitMessage(1); return; }
        const auto size=target->GetSize();
        target->BeginDraw(); target->Clear(D2D1::ColorF(D2D1::ColorF::Black));
        if(settings.appearance==0) {
            if(cachedPalette!=settings.palette) {
                paletteColors=Engine::palette(settings.palette); cachedPalette=settings.palette;
            }
            for(size_t i=0;i<rgba.size();++i) rgba[i]=paletteColors[engine->pixels[i]];
            bitmap->CopyFromMemory(nullptr,rgba.data(),800*4);
            float scale=std::min(size.width/800,size.height/600),width=800*scale,height=600*scale;
            target->DrawBitmap(bitmap,D2D1::RectF((size.width-width)/2,(size.height-height)/2,(size.width+width)/2,(size.height+height)/2),1,D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
        } else {
            float smaller=std::min(size.width,size.height);
            // Keep the original physical-pixel size and Direct2D rasterization.
            float dpi=static_cast<float>(GetDpiForWindow(w))/96;
            float diameter=std::max(1.0f,std::min(1.8f*dpi,smaller/600));
            float glow=static_cast<float>(settings.glow)/100;
            prepared.prepare(engine->modernHistory, previousHistory, frameTiming.alpha(), size.width, size.height);
            if(glow>0) {
                const float radius=diameter*(4+12*glow)/2;
                for(size_t i=0; i<prepared.count; ++i) {
                    const auto& p=prepared.points[i];
                    auto center=D2D1::Point2F(p.x,p.y);
                    auto h=halos[p.halo];
                    h->SetCenter(center); h->SetRadiusX(radius); h->SetRadiusY(radius);
                    h->SetOpacity(glow*p.strength*0.5f);
                    target->FillEllipse(D2D1::Ellipse(center,radius,radius),h);
                }
            }
            for(size_t i=0; i<prepared.count; ++i) {
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
        if(settings.debugCPU) drawCPU(w);
        if(FAILED(target->EndDraw())) { discard(); if(smoke) PostQuitMessage(1); }
        else ++renderedFrames;
    }
};
LRESULT CALLBACK windowProc(HWND w,UINT msg,WPARAM wp,LPARAM lp) {
    auto renderer=reinterpret_cast<Renderer*>(GetWindowLongPtrW(w,GWLP_USERDATA));
    switch(msg) {
    case WM_CREATE: SetWindowLongPtrW(w,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(new Renderer)); return 0;
    case WM_NCDESTROY: delete renderer; SetWindowLongPtrW(w,GWLP_USERDATA,0); return DefWindowProcW(w,msg,wp,lp);
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: { PAINTSTRUCT ps; BeginPaint(w,&ps); if(renderer) renderer->draw(w); EndPaint(w,&ps); return 0; }
    case WM_SIZE: if(renderer && renderer->target && LOWORD(lp) && HIWORD(lp)) renderer->target->Resize(D2D1::SizeU(LOWORD(lp),HIWORD(lp))); InvalidateRect(w,nullptr,FALSE); return 0;
    case WM_DPICHANGED: if(!preview) { auto r=reinterpret_cast<RECT*>(lp); SetWindowPos(w,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE); } return 0;
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
        if(preview) return 0;
        if(windowed) {
            if(wp==VK_F1) { paused=true; auto state=engine->savedFigure(); showSettings(w); resetEngine(); if(settings.resumeFigure) engine->restoreFigure(state); paused=false; }
            if(wp==VK_SPACE) { paused=!paused; lastStep=AnimationClock::now(); }
            if(wp=='R') resetEngine();
            if(wp==VK_ESCAPE) PostQuitMessage(0);
        } else PostQuitMessage(0);
        return 0;
    case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN: case WM_MOUSEWHEEL:
        if(!preview && !windowed) PostQuitMessage(0); return 0;
    case WM_MOUSEMOVE:
        if(!preview && !windowed) { POINT p; GetCursorPos(&p); if(GetTickCount64()-started<1000) initialMouse=p; else if(std::abs(p.x-initialMouse.x)>6 || std::abs(p.y-initialMouse.y)>6) PostQuitMessage(0); } return 0;
    case WM_SETCURSOR: if(!preview && !windowed) { SetCursor(nullptr); return TRUE; } break;
    case WM_ACTIVATEAPP: if(!wp && !preview && !windowed && GetTickCount64()-started>1000) PostQuitMessage(0); break;
    case WM_DISPLAYCHANGE: if(!preview && !windowed) PostQuitMessage(0); break;
    case WM_CLOSE: PostQuitMessage(0); return 0;
    case WM_DESTROY: if(preview) PostQuitMessage(0); return 0;
    case WM_SYSCOMMAND: if((wp&0xfff0)==SC_SCREENSAVE) return 0; break;
    }
    return DefWindowProcW(w,msg,wp,lp);
}
bool addWindow(RECT r, HWND parent=nullptr) {
    DWORD style=preview?WS_CHILD|WS_VISIBLE:windowed?WS_OVERLAPPEDWINDOW|WS_VISIBLE:WS_POPUP|WS_VISIBLE;
    HWND w=CreateWindowExW(!preview && !windowed?WS_EX_TOPMOST:0,L"ARoseScreenSaver",tr(L"ARose Preview — F1: Settings · Space: Pause · R: Restart",L"Náhled ARose — F1: Nastavení · Mezerník: Pauza · R: Znovu"),style,r.left,r.top,r.right-r.left,r.bottom-r.top,parent,nullptr,instance,nullptr);
    if(w) windows.push_back(w);
    return w!=nullptr;
}
BOOL CALLBACK monitorProc(HMONITOR, HDC, LPRECT rect, LPARAM) { return addWindow(*rect)?TRUE:FALSE; }
}
int WINAPI wWinMain(HINSTANCE h,HINSTANCE,PWSTR,int) {
    instance=h; chooseLanguage(); loadSettings();
    INITCOMMONCONTROLSEX controls{sizeof controls,ICC_BAR_CLASSES}; InitCommonControlsEx(&controls);
    int argc=0; LPWSTR* argv=CommandLineToArgvW(GetCommandLineW(),&argc);
    if(!argv) return 1;
    std::wstring arg=argc>1?argv[1]:L"/c";
    for(auto& c:arg) c=static_cast<wchar_t>(std::towlower(c));
    wchar_t mode=arg.size()>=2 && (arg[0]==L'/' || arg[0]==L'-')?arg[1]:0;
    HWND parent=nullptr;
    bool valid = arg.size()==2 || (arg.size()>3 && arg[2]==L':' && (mode==L'p'||mode==L'c'));
    if(mode==L'p'||mode==L'c') {
        std::wstring handle=arg.size()>3 && arg[2]==L':'?arg.substr(3):(argc>2?argv[2]:L"");
        if(!handle.empty()) { wchar_t* end=nullptr; auto n=wcstoull(handle.c_str(),&end,0); if(*end || handle[0]==L'-') valid=false; else parent=reinterpret_cast<HWND>(static_cast<UINT_PTR>(n)); }
    }
    LocalFree(argv);
    if(!valid) return 2;
    if(mode==L'c') { showSettings(IsWindow(parent)?parent:nullptr); return 0; }
    preview=mode==L'p'; windowed=mode==L'w'||mode==L't'; smoke=mode==L't';
    if(mode!=L's' && !preview && !windowed) return 2;
    if(preview && !IsWindow(parent)) return 2;
    if(FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,&factory))) return 1;
    resetEngine(); loadFigure(); started=GetTickCount64(); GetCursorPos(&initialMouse);
    WNDCLASSW cls{}; cls.hInstance=instance; cls.lpfnWndProc=windowProc; cls.lpszClassName=L"ARoseScreenSaver";
    cls.hCursor=LoadCursorW(nullptr,IDC_ARROW); cls.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(IDI_AROSE));
    if(!RegisterClassW(&cls)) { release(factory); return 1; }
    if(preview) { RECT r; GetClientRect(parent,&r); addWindow(r,parent); }
    else if(windowed) { RECT r{100,100,1000,800}; addWindow(r); }
    else EnumDisplayMonitors(nullptr,nullptr,monitorProc,0);
    if(windows.empty()) { release(factory); return 1; }
    MSG msg{};
    bool running = true;
    int exitCode = 0;
    while(running) {
        while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)) {
            if(msg.message==WM_QUIT) { exitCode=static_cast<int>(msg.wParam); running=false; break; }
            TranslateMessage(&msg); DispatchMessageW(&msg);
        }
        if(!running) break;
        if(smoke && GetTickCount64()-started>1500) { exitCode=renderedFrames>0?0:1; break; }
        if(preview) {
            HWND parent=GetParent(windows.front());
            if(!IsWindow(parent)) break;
            RECT r, current; GetClientRect(parent,&r); GetClientRect(windows.front(),&current);
            if(r.right!=current.right || r.bottom!=current.bottom)
                SetWindowPos(windows.front(),nullptr,0,0,r.right,r.bottom,SWP_NOZORDER|SWP_NOACTIVATE);
        }
        if(!animationReady) {
            // Prepare every monitor before starting the shared simulation clock.
            // WM_PAINT may already have initialized a target; preparation is idempotent.
            bool ready=true;
            for(HWND w:windows) {
                auto renderer=reinterpret_cast<Renderer*>(GetWindowLongPtrW(w,GWLP_USERDATA));
                if(!renderer || !renderer->prepareResources(w)) ready=false;
            }
            lastStep=AnimationClock::now();
            if(!ready) {
                if(smoke) { exitCode=1; break; }
                MsgWaitForMultipleObjectsEx(0,nullptr,100,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
                continue;
            }
            animationReady=true;
        }
        auto now=AnimationClock::now();
        double elapsed=std::chrono::duration<double>(now-lastStep).count(); lastStep=now;
        if(!paused) {
            int steps=frameTiming.advance(elapsed);
            for(int i=0;i<steps;++i) {
                previousHistory=engine->modernHistory;
                engine->step();
            }
        }
        if(engine->frame >= lastFigureSave && engine->frame-lastFigureSave>=1500) saveFigure();
        bool visible=false;
        for(HWND w:windows) {
            if(IsWindowVisible(w) && !IsIconic(w)) {
                visible=true;
                InvalidateRect(w,nullptr,FALSE); UpdateWindow(w);
            }
        }
        // Submit all monitors before waiting once for the compositor. Separate
        // v-sync waits per window would reduce frame rate on multi-monitor PCs.
        const auto beforeFlush=AnimationClock::now();
        const HRESULT flushed=visible?DwmFlush():E_FAIL;
        if(FAILED(flushed) || AnimationClock::now()-beforeFlush<std::chrono::milliseconds(1))
            MsgWaitForMultipleObjectsEx(0,nullptr,visible?8:100,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
    }
    saveFigure();
    for(HWND w:windows) if(IsWindow(w)) DestroyWindow(w);
    release(factory);
    return exitCode;
}
