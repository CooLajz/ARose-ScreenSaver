#pragma once
#include <windows.h>
#include <taskschd.h>
#include <sddl.h>
#include <wrl/client.h>
#include <string>
#include <vector>

namespace updates {
inline std::wstring executable() {
    std::wstring path(32768,L'\0');
    DWORD length=GetModuleFileNameW(nullptr,path.data(),static_cast<DWORD>(path.size()));
    if(!length || length>=path.size()) return {};
    path.resize(length); return path;
}
struct Bstr {
    BSTR value;
    explicit Bstr(const wchar_t* s):value(SysAllocString(s)) {}
    ~Bstr(){SysFreeString(value);}
    operator BSTR() const{return value;}
};
inline std::wstring userSid() {
    HANDLE token=nullptr;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) return {};
    DWORD size=0; GetTokenInformation(token,TokenUser,nullptr,0,&size);
    std::vector<BYTE> data(size);
    bool ok=GetTokenInformation(token,TokenUser,data.data(),size,&size)!=FALSE;
    CloseHandle(token);
    LPWSTR sid=nullptr;
    if(!ok || !ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid,&sid)) return {};
    std::wstring result=sid; LocalFree(sid); return result;
}
inline HRESULT schedule(bool enable) {
    using Microsoft::WRL::ComPtr;
    auto sid=userSid(); if(sid.empty()) return E_FAIL;
    std::wstring name=L"ARose Update Check-"+sid;
    ComPtr<ITaskService> service;
    HRESULT hr=CoCreateInstance(CLSID_TaskScheduler,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&service));
    if(FAILED(hr)) return hr;
    VARIANT empty; VariantInit(&empty);
    if(FAILED(hr=service->Connect(empty,empty,empty,empty))) return hr;
    ComPtr<ITaskFolder> folder;
    if(FAILED(hr=service->GetFolder(Bstr(L"\\"),&folder))) return hr;
    if(!enable) {
        hr=folder->DeleteTask(Bstr(name.c_str()),0);
        return hr==HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)?S_OK:hr;
    }
    ComPtr<ITaskDefinition> task;
    if(FAILED(hr=service->NewTask(0,&task))) return hr;
    ComPtr<IPrincipal> principal;
    if(FAILED(hr=task->get_Principal(&principal))) return hr;
    if(FAILED(hr=principal->put_UserId(Bstr(sid.c_str())))) return hr;
    if(FAILED(hr=principal->put_LogonType(TASK_LOGON_INTERACTIVE_TOKEN))) return hr;
    if(FAILED(hr=principal->put_RunLevel(TASK_RUNLEVEL_LUA))) return hr;
    ComPtr<ITaskSettings> settings;
    if(FAILED(hr=task->get_Settings(&settings))) return hr;
    settings->put_DisallowStartIfOnBatteries(VARIANT_FALSE);
    settings->put_StopIfGoingOnBatteries(VARIANT_FALSE);
    settings->put_StartWhenAvailable(VARIANT_TRUE);
    settings->put_WakeToRun(VARIANT_FALSE);
    settings->put_MultipleInstances(TASK_INSTANCES_IGNORE_NEW);
    settings->put_ExecutionTimeLimit(Bstr(L"PT1H"));
    ComPtr<ITriggerCollection> triggers; ComPtr<ITrigger> trigger; ComPtr<ITimeTrigger> time;
    if(FAILED(hr=task->get_Triggers(&triggers))) return hr;
    if(FAILED(hr=triggers->Create(TASK_TRIGGER_TIME,&trigger))) return hr;
    if(FAILED(hr=trigger.As(&time))) return hr;
    SYSTEMTIME now; GetLocalTime(&now); wchar_t boundary[32];
    swprintf_s(boundary,L"%04u-%02u-%02uT%02u:%02u:%02u",now.wYear,now.wMonth,now.wDay,now.wHour,now.wMinute,now.wSecond);
    time->put_StartBoundary(Bstr(boundary));
    ComPtr<IRepetitionPattern> repetition;
    if(FAILED(hr=time->get_Repetition(&repetition))) return hr;
    if(FAILED(hr=repetition->put_Interval(Bstr(L"PT1H")))) return hr;
    ComPtr<IActionCollection> actions; ComPtr<IAction> action; ComPtr<IExecAction> exec;
    if(FAILED(hr=task->get_Actions(&actions))) return hr;
    if(FAILED(hr=actions->Create(TASK_ACTION_EXEC,&action))) return hr;
    if(FAILED(hr=action.As(&exec))) return hr;
    if(FAILED(hr=exec->put_Path(Bstr(executable().c_str())))) return hr;
    if(FAILED(hr=exec->put_Arguments(Bstr(L"/weekly")))) return hr;
    ComPtr<IRegisteredTask> registered;
    return folder->RegisterTaskDefinition(Bstr(name.c_str()),task.Get(),TASK_CREATE_OR_UPDATE,empty,empty,TASK_LOGON_INTERACTIVE_TOKEN,empty,&registered);
}
// Administrative uninstall removes only tasks that launch this installed binary.
inline HRESULT removeInstalledTasks() {
    using Microsoft::WRL::ComPtr;
    ComPtr<ITaskService> service;
    HRESULT hr=CoCreateInstance(CLSID_TaskScheduler,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&service));
    if(FAILED(hr)) return hr;
    VARIANT empty; VariantInit(&empty);
    if(FAILED(hr=service->Connect(empty,empty,empty,empty))) return hr;
    ComPtr<ITaskFolder> folder;
    if(FAILED(hr=service->GetFolder(Bstr(L"\\"),&folder))) return hr;
    ComPtr<IRegisteredTaskCollection> tasks;
    if(FAILED(hr=folder->GetTasks(TASK_ENUM_HIDDEN,&tasks))) return hr;
    LONG count=0; if(FAILED(hr=tasks->get_Count(&count))) return hr;
    const auto path=executable();
    HRESULT result=S_OK;
    for(LONG i=count;i>=1;--i) {
        VARIANT index; VariantInit(&index); index.vt=VT_I4; index.lVal=i;
        ComPtr<IRegisteredTask> task; Bstr name(L"");
        if(FAILED(tasks->get_Item(index,&task))) continue;
        SysFreeString(name.value); name.value=nullptr;
        if(FAILED(task->get_Name(&name.value)) || !name.value ||
           std::wstring(name.value).rfind(L"ARose Update Check-",0)!=0) continue;
        ComPtr<ITaskDefinition> definition; ComPtr<IActionCollection> actions;
        ComPtr<IAction> action; ComPtr<IExecAction> exec;
        if(FAILED(task->get_Definition(&definition)) || FAILED(definition->get_Actions(&actions)) ||
           FAILED(actions->get_Item(1,&action)) || FAILED(action.As(&exec))) continue;
        Bstr taskPath(L""); SysFreeString(taskPath.value); taskPath.value=nullptr;
        if(FAILED(exec->get_Path(&taskPath.value)) || !taskPath.value ||
           _wcsicmp(taskPath.value,path.c_str())!=0) continue;
        hr=folder->DeleteTask(name,0);
        if(FAILED(hr)) result=hr;
    }
    return result;
}

}
