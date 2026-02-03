@echo off
setlocal EnableExtensions

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=psinelam.sys"

set "LOG=%~dp0fix_driver_ref_%TARGET%.log"
echo ==== [%date% %time%] Fix for %TARGET% ==== > "%LOG%"

REM 1) Find Windows drive
set "WINDRV="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist "%%D:\Windows\System32\Config\SYSTEM" set "WINDRV=%%D:"
)
if "%WINDRV%"=="" (
  echo ERROR: Windows SYSTEM hive not found. >> "%LOG%"
  echo Windows install not found. Check drive letters in diskpart.
  exit /b 1
)

echo Windows found at %WINDRV% >> "%LOG%"
echo Windows found at %WINDRV%

REM 2) Load offline SYSTEM hive
reg unload HKLM\OFFLINE >nul 2>&1
reg load HKLM\OFFLINE "%WINDRV%\Windows\System32\Config\SYSTEM" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo ERROR: reg load failed >> "%LOG%"
  echo Failed to load offline registry hive.
  exit /b 2
)

REM 3) Determine active ControlSet
set "CUR="
for /f "tokens=3" %%i in ('reg query HKLM\OFFLINE\Select /v Current 2^>nul ^| findstr /i "Current"') do set "CUR=%%i"

set "CS=ControlSet001"
if not "%CUR%"=="" (
  if "%CUR%"=="1" set "CS=ControlSet001"
  if "%CUR%"=="2" set "CS=ControlSet002"
  if "%CUR%"=="3" set "CS=ControlSet003"
)

echo Active control set: %CS% >> "%LOG%"
echo Active control set: %CS%

REM 4) Find matching services by enumerating services list and checking ImagePath
echo Searching for services referencing %TARGET% ...
echo Searching for services referencing %TARGET% ... >> "%LOG%"

for /f "delims=" %%K in ('reg query HKLM\OFFLINE\%CS%\Services 2^>nul') do (
  REM Query ImagePath for this service key and check if it contains TARGET
  reg query "%%K" /v ImagePath 2>nul | findstr /i "%TARGET%" >nul
  if not errorlevel 1 (
    echo MATCH: %%K >> "%LOG%"
    echo Disabling: %%K
    reg add "%%K" /v Start /t REG_DWORD /d 4 /f >> "%LOG%" 2>&1
  )
)

REM 5) Unload hive
reg unload HKLM\OFFLINE >> "%LOG%" 2>&1

echo Done. Log: %LOG%
echo Now reboot: wpeutil reboot
exit /b 0
