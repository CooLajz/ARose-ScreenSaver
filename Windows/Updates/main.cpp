#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <vector>
#include <string>
#include <ctime>
#include <filesystem>
#include "Schedule.h"
#include "UpdatePolicy.h"
#include "winsparkle.h"
#include "UpdateVersion.h"

namespace {
constexpr wchar_t key[]=L"Software\\CooLajz\\ARose\\Updates";
bool czech=false, background=false;
DWORD mainThread=0;
HWND window=nullptr;
const wchar_t* tr(const wchar_t* en,const wchar_t* cs){return czech?cs:en;}
uint64_t read(const wchar_t* name) {
    uint64_t value=0;DWORD size=sizeof value;
    RegGetValueW(HKEY_CURRENT_USER,key,name,RRF_RT_REG_QWORD,nullptr,&value,&size);return value;
}
bool write(const wchar_t* name,uint64_t value) {
    HKEY registry=nullptr;
    if(RegCreateKeyExW(HKEY_CURRENT_USER,key,0,nullptr,0,KEY_SET_VALUE,nullptr,&registry,nullptr)!=ERROR_SUCCESS)return false;
    auto result=RegSetValueExW(registry,name,0,REG_QWORD,reinterpret_cast<const BYTE*>(&value),sizeof value);
    RegCloseKey(registry);return result==ERROR_SUCCESS;
}
bool installed() {
    wchar_t path[32768]{}; DWORD size=sizeof path;
    if(RegGetValueW(HKEY_CURRENT_USER,L"Software\\CooLajz\\ARose",L"InstallPath",RRF_RT_REG_SZ,nullptr,path,&size)!=ERROR_SUCCESS)return false;
    auto current=std::filesystem::path(updates::executable()).parent_path().wstring();
    return _wcsicmp(current.c_str(),path)==0;
}
void requireInstall(HWND parent) {
    MessageBoxW(parent,tr(L"Install ARose using the full installer before enabling updates. The standalone preview and screen saver work without it.",L"Pro aktualizace nejprve nainstalujte ARose pomocí úplného instalátoru. Samostatný náhled i spořič fungují bez něj."),L"ARose",MB_OK|MB_ICONINFORMATION);
}
void finish(){PostThreadMessageW(mainThread,WM_APP+1,0,0);}
void finishedCheck(){if(background)finish();}
bool activeDesktop() {
    BOOL saver=FALSE;
    if(!SystemParametersInfoW(SPI_GETSCREENSAVERRUNNING,0,&saver,0)||saver)return false;
    HDESK desktop=OpenInputDesktop(0,FALSE,DESKTOP_READOBJECTS);
    if(!desktop)return false;
    wchar_t name[128]{};DWORD needed=0;
    bool active=GetUserObjectInformationW(desktop,UOI_NAME,name,sizeof name,&needed) && _wcsicmp(name,L"Default")==0;
    CloseDesktop(desktop);
    LASTINPUTINFO input{sizeof input,0};
    return active && GetLastInputInfo(&input) && static_cast<DWORD>(GetTickCount()-input.dwTime)<60000;
}
bool scheduledCheck() {
    auto now=static_cast<uint64_t>(std::time(nullptr));
    if(installed() && read(L"Weekly") && activeDesktop() && updates::due(read(L"LastAttempt"),now)) {
        write(L"LastAttempt",now); win_sparkle_check_update_without_ui(); return true;
    }
    return false;
}
void launchSaver(const wchar_t* argument) {
    auto path=std::filesystem::path(updates::executable()).parent_path()/L"ARose.scr";
    ShellExecuteW(window,L"open",path.c_str(),argument,nullptr,SW_SHOWNORMAL);
}
INT_PTR CALLBACK dialog(HWND h,UINT message,WPARAM wp,LPARAM) {
    if(message==WM_INITDIALOG) {
        window=h;
        SetWindowTextW(h,L"ARose ScreenSaver");
        SetDlgItemTextW(h,2001,tr(L"Check for Updates…",L"Zkontrolovat aktualizace…"));
        SetDlgItemTextW(h,2002,tr(L"Check automatically every week",L"Automaticky kontrolovat jednou týdně"));
        SetDlgItemTextW(h,2003,tr(L"Screen Saver Settings…",L"Nastavení spořiče…"));
        SetDlgItemTextW(h,2004,tr(L"Preview",L"Náhled"));
        SetDlgItemTextW(h,2005,tr(L"Updates are downloaded and installed after confirmation. Settings and saved figures are preserved.",L"Aktualizace se stáhnou a nainstalují po potvrzení. Nastavení a uložené obrazce zůstanou zachovány."));
        SetDlgItemTextW(h,2006,(std::wstring(L"ARose ")+AROSE_DISPLAY_VERSION).c_str());
        SetDlgItemTextW(h,IDCANCEL,tr(L"Close",L"Zavřít"));
        CheckDlgButton(h,2002,read(L"Weekly")?BST_CHECKED:BST_UNCHECKED); return TRUE;
    }
    if(message==WM_TIMER) { scheduledCheck(); return TRUE; }
    if(message==WM_COMMAND) {
        switch(LOWORD(wp)) {
        case 2001: if(!installed()){requireInstall(h);return TRUE;} write(L"LastAttempt",static_cast<uint64_t>(std::time(nullptr)));win_sparkle_check_update_with_ui();return TRUE;
        case 2002: {
            bool enable=IsDlgButtonChecked(h,2002)==BST_CHECKED;
            if(enable && !installed()){CheckDlgButton(h,2002,BST_UNCHECKED);requireInstall(h);return TRUE;}
            if(FAILED(updates::schedule(enable)) || !write(L"Weekly",enable?1:0)) {
                CheckDlgButton(h,2002,read(L"Weekly")?BST_CHECKED:BST_UNCHECKED);
                MessageBoxW(h,tr(L"Unable to change automatic update checks.",L"Automatickou kontrolu aktualizací se nepodařilo změnit."),L"ARose",MB_OK|MB_ICONERROR);
            } return TRUE;
        }
        case 2003:launchSaver(L"/c");return TRUE;
        case 2004:launchSaver(L"/w");return TRUE;
        case IDCANCEL:DestroyWindow(h);PostQuitMessage(0);return TRUE;
        }
    }
    if(message==WM_CLOSE){DestroyWindow(h);PostQuitMessage(0);return TRUE;}
    return FALSE;
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR arguments,int) {
    mainThread=GetCurrentThreadId();MSG msg;PeekMessageW(&msg,nullptr,0,0,PM_NOREMOVE);
    czech=PRIMARYLANGID(GetUserDefaultUILanguage())==LANG_CZECH;
    HRESULT apartment=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    if(FAILED(apartment))return 1;
    background=std::wstring(arguments)==L"/weekly";
    if(std::wstring(arguments)==L"/disable-weekly") {
        write(L"Weekly",0); auto hr=updates::schedule(false);CoUninitialize();return FAILED(hr)?1:0;
    }
    if(background) {
        auto now=static_cast<uint64_t>(std::time(nullptr)),last=read(L"LastAttempt");
        if(!installed() || !read(L"Weekly") || !activeDesktop() || !updates::due(last,now)){CoUninitialize();return 0;}
    }
    auto mutexName=L"Local\\ARoseUpdater-"+updates::userSid();
    HANDLE mutex=CreateMutexW(nullptr,FALSE,mutexName.c_str());
    if(!mutex || GetLastError()==ERROR_ALREADY_EXISTS){if(mutex)CloseHandle(mutex);CoUninitialize();return 0;}
    win_sparkle_set_app_details(L"CooLajz",L"ARose ScreenSaver",AROSE_DISPLAY_VERSION);
    win_sparkle_set_app_build_version(AROSE_BUILD_VERSION);
    win_sparkle_set_registry_path("Software\\CooLajz\\ARose\\WinSparkle");
    win_sparkle_set_appcast_url("https://github.com/CooLajz/ARose-ScreenSaver/releases/latest/download/appcast-windows.xml");
    if(!win_sparkle_set_eddsa_public_key("pSFLjqyn8G8zGioAiqcp+9+sEc1MUCMPw/+FSrohFjs=")){CloseHandle(mutex);CoUninitialize();return 1;}
    win_sparkle_set_lang(czech?"cs":"en");
    // Scheduling is opt-in and owned by our short-lived task, never the saver.
    win_sparkle_set_automatic_check_for_updates(0);
    win_sparkle_set_shutdown_request_callback(finish);
    win_sparkle_set_error_callback(finishedCheck);
    win_sparkle_set_did_not_find_update_callback(finishedCheck);
    win_sparkle_set_update_cancelled_callback(finishedCheck);
    win_sparkle_set_update_dismissed_callback(finishedCheck);
    win_sparkle_set_update_skipped_callback(finishedCheck);
    win_sparkle_set_update_postponed_callback(finishedCheck);
    win_sparkle_init();
    if(background && !scheduledCheck()){win_sparkle_cleanup();CloseHandle(mutex);CoUninitialize();return 0;}
    if(!background)window=CreateDialogParamW(instance,MAKEINTRESOURCEW(2000),nullptr,dialog,0);
    if(!background && !window){win_sparkle_cleanup();CloseHandle(mutex);CoUninitialize();return 1;}
    if(window){ShowWindow(window,SW_SHOWNORMAL);SetTimer(window,1,3600000,nullptr);scheduledCheck();}
    while(GetMessageW(&msg,nullptr,0,0)>0) {
        if(msg.message==WM_APP+1)break;
        if(!window || !IsDialogMessageW(window,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}
    }
    win_sparkle_cleanup();CloseHandle(mutex);CoUninitialize();return 0;
}
