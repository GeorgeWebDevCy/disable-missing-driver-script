@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM  fix_missing_driver.bat
REM  Offline fix for "critical driver missing/corrupt" boot error
REM  Usage:
REM     fix_missing_driver.bat psinelam.sys
REM  If no argument is provided, defaults to psinelam.sys
REM ==========================================================

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=psinelam.sys"

set "LOG=%~dp0fix_missing_driver_%TARGET%.log"
echo ========================================================== > "%LOG%"
echo [%date% %time%] Starting offline driver fix for: %TARGET% >> "%LOG%"
echo ========================================================== >> "%LOG%"

echo.
echo Target driver: %TARGET%
echo Log file: %LOG%
echo.

REM --- Find Windows drive by looking for SYSTEM hive ---
set "WINDRV="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%D:\Windows\System32\Config\SYSTEM" (
    set "WINDRV=%%D:"
    goto :FOUNDWIN
  )
)

:FOUNDWIN
if "%WINDRV%"=="" (
  echo [ERROR] Could not find an offline Windows install (SYSTEM hive not found). >> "%LOG%"
  echo Could not find Windows install. Check drive letters in diskpart. 
  echo (See log: %LOG%)
  exit /b 1
)

echo [OK] Windows installation detected at %WINDRV% >> "%LOG%"
echo Windows detected at: %WINDRV%
echo.

REM --- Load offline SYSTEM hive ---
reg unload HKLM\OFFLINE >nul 2>&1
reg load HKLM\OFFLINE "%WINDRV%\Windows\System32\Config\SYSTEM" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to load offline SYSTEM hive. >> "%LOG%"
  echo Failed to load offline registry hive. (See log: %LOG%)
  exit /b 2
)

echo [OK] Loaded offline SYSTEM hive. >> "%LOG%"

REM --- Search for services referencing the target driver in ImagePath ---
echo.
echo Searching registry for references to: %TARGET%
echo This can take 10-60 seconds...
echo.

set "MATCHFILE=%TEMP%\driver_matches.txt"
del /f /q "%MATCHFILE%" >nul 2>&1

REM We query ALL services recursively and filter for ImagePath lines that contain TARGET.
REM Output format from reg query includes:
REM   HKEY_LOCAL_MACHINE\OFFLINE\ControlSet001\Services\SomeService
REM       ImagePath    REG_EXPAND_SZ    system32\drivers\xxx.sys

reg query HKLM\OFFLINE\ControlSet001\Services /s /v ImagePath 2>nul | findstr /i "%TARGET%" > "%MATCHFILE%"

if not exist "%MATCHFILE%" (
  echo [WARN] No matches file created; continuing... >> "%LOG%"
)

for %%A in ("%MATCHFILE%") do if %%~zA==0 (
  echo [WARN] No ImagePath references found for %TARGET% in ControlSet001. >> "%LOG%"
  echo No direct references found in ControlSet001.
  echo We'll also search CurrentControlSet mapping if present...
)

REM --- Identify which ControlSet is actually active (Select\Current) ---
set "CURSET="
for /f "tokens=3" %%i in ('reg query HKLM\OFFLINE\Select /v Current 2^>nul ^| findstr /i "Current"') do (
  set "CURSET=%%i"
)

if not "%CURSET%"=="" (
  set /a "CSNUM=%CURSET%"
  if %CSNUM% LSS 10 (set "CS=ControlSet00%CSNUM%") else set "CS=ControlSet0%CSNUM%"
  echo [OK] Active control set appears to be: %CS% (Select\Current=%CURSET%) >> "%LOG%"
) else (
  set "CS=ControlSet001"
  echo [WARN] Could not read Select\Current; defaulting to ControlSet001. >> "%LOG%"
)

REM --- Search the active ControlSet too (the one that matters) ---
set "MATCHFILE2=%TEMP%\driver_matches_active.txt"
del /f /q "%MATCHFILE2%" >nul 2>&1
reg query HKLM\OFFLINE\%CS%\Services /s /v ImagePath 2>nul | findstr /i "%TARGET%" > "%MATCHFILE2%"

REM --- Disable any matching services ---
set "CHANGED=0"
call :DISABLE_MATCHES "%MATCHFILE2%" "%CS%"
call :DISABLE_MATCHES "%MATCHFILE%" "ControlSet001"

REM --- If no registry matches found, we can still try a broader scan for *any* value referencing target ---
if "%CHANGED%"=="0" (
  echo.
  echo No ImagePath matches found. Trying broader scan (any value containing %TARGET%)...
  echo This can take longer...
  echo.
  echo [INFO] Broad scan started. >> "%LOG%"

  set "BROAD=%TEMP%\driver_matches_broad.txt"
  del /f /q "%BROAD%" >nul 2>&1

  reg query HKLM\OFFLINE\%CS%\Services /s 2>nul | findstr /i "%TARGET%" > "%BROAD%"
  call :DISABLE_MATCHES_ANY "%BROAD%" "%CS%"
)

REM --- Optional: rename the driver if it exists (prevents re-loading if restored) ---
echo.
if exist "%WINDRV%\Windows\System32\drivers\%TARGET%" (
  echo Driver file exists on disk. Renaming to disable load at filesystem level too...
  echo [INFO] Found file: %WINDRV%\Windows\System32\drivers\%TARGET% >> "%LOG%"
  ren "%WINDRV%\Windows\System32\drivers\%TARGET%" "%TARGET%.bak" >> "%LOG%" 2>&1
  if errorlevel 1 (
    echo [WARN] Could not rename driver file (permissions/BitLocker?). >> "%LOG%"
    echo Could not rename the driver file (still OK if registry was fixed).
  ) else (
    echo [OK] Renamed file to %TARGET%.bak >> "%LOG%"
    echo Renamed file to: %TARGET%.bak
  )
) else (
  echo Driver file not found on disk (that matches your situation). >> "%LOG%"
  echo Driver file not found on disk (that’s fine).
)

REM --- Unload hive ---
reg unload HKLM\OFFLINE >> "%LOG%" 2>&1

echo.
echo ==========================================================
echo Done.
echo Changes made: %CHANGED%
echo Log saved to: %LOG%
echo ==========================================================
echo.
echo Now reboot and test:
echo   wpeutil reboot
echo.

exit /b 0


:DISABLE_MATCHES
REM %1 = matchfile, %2 = controlset label
set "MF=%~1"
set "CSET=%~2"

if not exist "%MF%" (
  echo [INFO] No match file %MF% >> "%LOG%"
  goto :EOF
)

for /f "usebackq delims=" %%L in ("%MF%") do (
  set "LINE=%%L"

  REM The reg query output includes key lines + value lines.
  REM We only captured lines containing TARGET, but we need to locate the service key above it.
  REM So we re-run a targeted query per service by scanning for ImagePath matches from reg query.
)

REM Better approach: enumerate all services, query ImagePath, match, then disable.
for /f "tokens=*" %%K in ('reg query HKLM\OFFLINE\%CSET%\Services 2^>nul ^| findstr /i /r "HKEY_LOCAL_MACHINE\\OFFLINE\\%CSET%\\Services\\.*"') do (
  set "KEY=%%K"
  for /f "tokens=1,2,*" %%a in ('reg query "%%K" /v ImagePath 2^>nul ^| findstr /i "ImagePath"') do (
    set "IMG=%%c"
    echo !IMG! | findstr /i "%TARGET%" >nul
    if not errorlevel 1 (
      REM Extract service name from key
      for %%s in ("%%K") do set "SVC=%%~nxs"
      echo [MATCH] %CSET%\Services\!SVC! references %TARGET% >> "%LOG%"
      echo Disabling service: !SVC!  (%CSET%)
      reg add "%%K" /v Start /t REG_DWORD /d 4 /f >> "%LOG%" 2>&1
      if not errorlevel 1 (
        set /a CHANGED+=1
        echo [OK] Disabled !SVC! (Start=4) >> "%LOG%"
      ) else (
        echo [ERROR] Failed to disable !SVC! >> "%LOG%"
      )
    )
  )
)

goto :EOF


:DISABLE_MATCHES_ANY
REM Broad scan output doesn't preserve context; we still enumerate services and match any value quickly.
set "CSET=%~2"

for /f "tokens=*" %%K in ('reg query HKLM\OFFLINE\%CSET%\Services 2^>nul') do (
  set "KEY=%%K"
  REM query all values under this key and search for TARGET
  reg query "%%K" 2>nul | findstr /i "%TARGET%" >nul
  if not errorlevel 1 (
    for %%s in ("%%K") do set "SVC=%%~nxs"
    echo [MATCH-BROAD] %CSET%\Services\!SVC! references %TARGET% somewhere >> "%LOG%"
    echo Disabling service (broad match): !SVC!  (%CSET%)
    reg add "%%K" /v Start /t REG_DWORD /d 4 /f >> "%LOG%" 2>&1
    if not errorlevel 1 (
      set /a CHANGED+=1
      echo [OK] Disabled !SVC! (Start=4) >> "%LOG%"
    ) else (
      echo [ERROR] Failed to disable !SVC! >> "%LOG%"
    )
  )
)

goto :EOF
