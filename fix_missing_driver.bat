@echo off
setlocal EnableExtensions

REM ==========================================================
REM  fix_psinelam_winre.bat
REM  WinRE-safe offline registry fix for missing boot driver
REM  Uses FIND (not FINDSTR).
REM
REM  Usage:
REM    fix_psinelam_winre.bat psinelam.sys
REM  If no arg provided, defaults to psinelam.sys
REM ==========================================================

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=psinelam.sys"

set "LOG=%~dp0fix_driver_%TARGET%.log"
echo ==== [%date% %time%] Fix offline boot driver: %TARGET% ==== > "%LOG%"

echo.
echo Target: %TARGET%
echo Log: %LOG%
echo.

REM --- Detect Windows drive by presence of SYSTEM hive ---
set "WINDRV="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%D:\Windows\System32\Config\SYSTEM" set "WINDRV=%%D:"
)

if "%WINDRV%"=="" (
  echo [ERROR] Windows install not found (SYSTEM hive missing).>>"%LOG%"
  echo ERROR: Could not find Windows installation drive.
  exit /b 1
)

echo [OK] Windows found at %WINDRV%>>"%LOG%"
echo Windows detected at: %WINDRV%
echo.

REM --- Load offline SYSTEM hive ---
reg unload HKLM\OFFLINE >nul 2>&1
reg load HKLM\OFFLINE "%WINDRV%\Windows\System32\Config\SYSTEM" >>"%LOG%" 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to load offline SYSTEM hive.>>"%LOG%"
  echo ERROR: reg load failed.
  exit /b 2
)

REM --- Determine active ControlSet from Select\Current ---
set "CS=ControlSet001"
for /f "tokens=1,2,3" %%A in ('reg query HKLM\OFFLINE\Select /v Current 2^>nul') do (
  if /i "%%A"=="Current" (
    REM %%C looks like 0x1, 0x2, 0x3
    if /i "%%C"=="0x1" set "CS=ControlSet001"
    if /i "%%C"=="0x2" set "CS=ControlSet002"
    if /i "%%C"=="0x3" set "CS=ControlSet003"
  )
)

echo [OK] Active control set: %CS%>>"%LOG%"
echo Active ControlSet: %CS%
echo.

REM --- Enumerate all service keys and check ImagePath for TARGET using FIND ---
echo Searching registry for services referencing %TARGET%...
echo Searching registry for services referencing %TARGET%...>>"%LOG%"

set "CHANGED=0"

for /f "delims=" %%K in ('reg query HKLM\OFFLINE\%CS%\Services 2^>nul') do (
  call :CHECKKEY "%%K"
)

echo.
echo [DONE] Disabled services: %CHANGED%>>"%LOG%"
echo Done. Disabled services: %CHANGED%
echo Log saved to: %LOG%
echo.

REM --- Unload hive ---
reg unload HKLM\OFFLINE >>"%LOG%" 2>&1

echo Reboot now:
echo   wpeutil reboot
echo.
exit /b 0

:CHECKKEY
set "KEY=%~1"

REM Query ImagePath and search for TARGET (case-insensitive)
reg query "%KEY%" /v ImagePath 2>nul | find /i "%TARGET%" >nul
if errorlevel 1 goto :EOF

echo [MATCH] %KEY%>>"%LOG%"
echo MATCH: %KEY%

REM Disable by setting Start=4
reg add "%KEY%" /v Start /t REG_DWORD /d 4 /f >>"%LOG%" 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to disable %KEY%>>"%LOG%"
) else (
  set /a CHANGED=%CHANGED%+1
  echo [OK] Disabled (Start=4): %KEY%>>"%LOG%"
)

goto :EOF
