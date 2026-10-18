// Exercise the production window procedure and modal dialog with isolated HKCU data.
#define wWinMain aroseSaverEntryPoint
#include "../../Windows/main.cpp"
#undef wWinMain
#include <cstdlib>
#include <iostream>

namespace {
int dialogAction=IDCANCEL;
bool dialogSeen=false;
BOOL CALLBACK completeDialog(HWND w,LPARAM) {
    if(!GetDlgItem(w,IDC_STYLE)) return TRUE;
    dialogSeen=true;
    if(dialogAction==IDOK) SendDlgItemMessageW(w,IDC_GLOW,TBM_SETPOS,TRUE,0);
    PostMessageW(w,WM_COMMAND,dialogAction,0);
    return FALSE;
}
void CALLBACK dialogTimer(HWND,UINT,UINT_PTR,DWORD) {
    EnumThreadWindows(GetCurrentThreadId(),completeDialog,0);
}
void check(bool ok,const char* message) {
    if(!ok) { std::cerr << message << '\n'; std::exit(1); }
}
}

int main() {
    instance=GetModuleHandleW(nullptr);
    windowed=true;
    const auto testKey=L"Software\\CooLajz\\ARose-UI-Test-"+std::to_wstring(GetCurrentProcessId());
    settingsKey=testKey.c_str();
    struct Cleanup {
        std::wstring key;
        ~Cleanup() {
            for(HWND w:windows) if(IsWindow(w)) DestroyWindow(w);
            release(factory);
            RegDeleteTreeW(HKEY_CURRENT_USER,key.c_str());
        }
    } cleanup{testKey};
    INITCOMMONCONTROLSEX controls{sizeof controls,ICC_BAR_CLASSES};
    InitCommonControlsEx(&controls);
    check(SUCCEEDED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,&factory)),"D2D factory unavailable");
    WNDCLASSW cls{};
    cls.hInstance=instance; cls.lpfnWndProc=windowProc; cls.lpszClassName=L"ARoseScreenSaver";
    check(RegisterClassW(&cls)!=0,"Window class registration failed");
    resetEngine();
    check(addWindow(RECT{100,100,740,580}),"Preview window creation failed");
    HWND w=windows.front();
    const auto timer=SetTimer(nullptr,0,25,dialogTimer);
    check(timer!=0,"Dialog completion timer failed");
    for(int resume:{0,1}) for(bool initiallyPaused:{false,true}) for(int action:{IDCANCEL,IDOK}) {
        settings=Settings{}; settings.resumeFigure=resume;
        paused=initiallyPaused; resetEngine();
        for(int i=0;i<600;++i) engine->step();
        const auto before=engine->savedFigure();
        dialogAction=action; dialogSeen=false;
        SendMessageW(w,WM_KEYDOWN,VK_F1,0);
        check(dialogSeen,"F1 did not open the real configuration dialog");
        check(paused==initiallyPaused,"Configuration changed the previous pause state");
        if(action==IDCANCEL || resume) check(engine->savedFigure()==before,"Cancel/resume lost the current figure");
        else check(engine->frame==0,"Saved configuration did not restart the preview");
        if(action==IDCANCEL) check(settings.glow==80,"Cancel changed settings");
        else check(settings.glow==0,"Save did not apply dialog changes");
    }
    KillTimer(nullptr,timer);
    BYTE original[256]{}, keyboard[256]{};
    GetKeyboardState(original); std::memcpy(keyboard,original,sizeof keyboard);
    keyboard[VK_MENU]=0x80; SetKeyboardState(keyboard);
    SendMessageW(w,WM_SYSKEYDOWN,VK_F4,1LL<<29);
    SetKeyboardState(original);
    MSG quit{};
    check(PeekMessageW(&quit,nullptr,WM_QUIT,WM_QUIT,PM_REMOVE)!=0,"Alt+F4 did not close the preview");
    std::cout << "PASS: F1 cancel/save preserve pause and figure policy; Alt+F4 reaches the system handler.\n";
}
