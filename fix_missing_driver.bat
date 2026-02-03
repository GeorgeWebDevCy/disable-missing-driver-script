@echo off
setlocal EnableExtensions

REM WinRE Offline Driver Disable Script
REM Usage: fix_driver_boot.bat psinelam.sys
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=psinelam.sys"

set "LOG=%~dp0fix_driver_boot_%TARGET%.log"
set "TMP=%TEMP%\fix_driver_boot_matches.txt"
set "TMPKEYS=%TEMP%\fix_driver_boot_keys.txt"

echo ========================================================== > "%LOG%"
echo [%date% %time%] WinRE offline fix for: %TARGET% >> "%LOG%"
echo ========================================================== >> "%LOG%"

REM --- Find Windows drive by SYSTEM hive ---
set "WINDRV="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%D:\Windows\System32\Config\SYSTEM" (
    set "WINDRV=%%D:"
    goto :FOUNDWIN
  )
)

:FOUNDWIN
if "%WINDRV%"=="" (
  echo [ERROR] Windows not found (no SYSTEM hive). >> "%LOG%"
  echo Windows not found. Use DISKPART to check letters.
  echo Log: %LOG%
  exit /b 1
)

echo [OK] Windows detected at %WINDRV% >> "%LOG%"
echo Windows detected at: %WINDRV%

REM --- Load offline SYSTEM hive ---
reg unload HKLM\OFFLINE >nul 2>&1
reg load HKLM\OFFLINE "%WINDRV%\Windows\System32\Config\SYSTEM" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo [ERROR] reg load failed. >> "%LOG%"
  echo Failed to load offline SYSTEM hive.
  echo Log: %LOG%
  exit /b 2
)

REM --- Determine Active ControlSet ---
set "CUR="
for /f "tokens=3" %%i in ('reg query HKLM\OFFLINE\Select /v Current 2^>nul ^| findstr /i "Current"') do set "CUR=%%i"

set "CS=ControlSet001"
if "%CUR%"=="2" set "CS=ControlSet002"
if "%CUR%"=="3" set "CS=ControlSet003"
if "%CUR%"=="4" set "CS=ControlSet004"

echo [OK] Using %CS% (Select\Current=%CUR%) >> "%LOG%"
echo Active control set: %CS%

REM --- Search for ImagePath referencing TARGET ---
del /f /q "%TMP%" "%TMPKEYS%" >nul 2>&1

reg query "HKLM\OFFLINE\%CS%\Services" /s /v ImagePath 2>nul | findstr /i "%TARGET%" > "%TMP%"

REM If no matches in active control set, try ControlSet001
for %%A in ("%TMP%") do if %%~zA==0 (
  echo [WARN] No matches in %CS%. Trying ControlSet001... >> "%LOG%"
  reg query "HKLM\OFFLINE\ControlSet001\Services" /s /v ImagePath 2>nul | findstr /i "%TARGET%" > "%TMP%"
  set "CS=ControlSet001"
)

for %%A in ("%TMP%") do if %%~zA==0 (
  echo [WARN] No registry ImagePath reference found for %TARGET%. >> "%LOG%"
  echo No registry ImagePath reference found for %TARGET%.
  goto :UNLOAD
)

REM --- Extract only registry key lines and disable them ---
for /f "delims=" %%L in ('type "%TMP%" ^| findstr /i /r "^HKEY_LOCAL_MACHINE\\OFFLINE\\.*\\Services\\.*"') do (
  echo %%L>>"%TMPKEYS%"
)

set "CHANGED=0"
for /f "delims=" %%K in ('type "%TMPKEYS%"') do (
  echo [MATCH] %%K >> "%LOG%"
  reg add "%%K" /v Start /t REG_DWORD /d 4 /f >> "%LOG%" 2>&1
  if not errorlevel 1 set /a CHANGED+=1
)

echo [OK] Disabled %CHANGED% service(s). >> "%LOG%"
echo Disabled %CHANGED% service(s).

REM --- Optional: rename file if it exists on the real Windows volume ---
if exist "%WINDRV%\Windows\System32\drivers\%TARGET%" (
  ren "%WINDRV%\Windows\System32\drivers\%TARGET%" "%TARGET%.bak" >> "%LOG%" 2>&1
)

:UNLOAD
reg unload HKLM\OFFLINE >> "%LOG%" 2>&1

echo.
echo Done. Log:
echo   %LOG%
echo Reboot:
echo   wpeutil reboot
echo.
exit /b 0
