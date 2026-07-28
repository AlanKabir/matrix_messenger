@echo off
rem ===================================================================
rem  build_msi.bat - builds ABYROY Chat MSI package.
rem
rem  HOW TO USE
rem  1. Build the app first:  flutter build windows
rem  2. Keep this file and abyroy.wxs in folder:  <project>\installer\
rem  3. Increase VERSION below on every release (1.0.0 -> 1.1.0 -> ...)
rem  4. Run:  .\build_msi.bat
rem
rem  Result:  installer\ABYROY_Chat_<VERSION>.msi
rem
rem  NOTE: no parenthesis blocks here on purpose - WiX path contains
rem  "(x86)" and brackets break batch IF-blocks.
rem ===================================================================

set VERSION=1.0.1

rem Path to WiX Toolset v3 binaries (change if installed elsewhere)
set "WIX_BIN=C:\Program Files (x86)\WiX Toolset v3.14\bin"

rem Folder with the built application (Release folder from flutter build)
set "SRC=..\build\windows\x64\runner\Release"

if not exist "%WIX_BIN%\heat.exe" goto :no_wix
if not exist "%SRC%\matrix_messenger.exe" goto :no_app

echo [1/3] Harvesting files...
"%WIX_BIN%\heat.exe" dir "%SRC%" -cg AppFiles -gg -scom -sreg -sfrag -srd -dr INSTALLFOLDER -var var.SourceDir -out AppFiles.wxs
if errorlevel 1 goto :failed

rem NOTE about -arch: package must keep the SAME architecture as the
rem previously deployed version, otherwise Windows Installer does not see
rem the old product and installs a SECOND copy side by side.
rem Version 1.0.0 was built without -arch (x86), so we keep it that way.
rem To move to x64 later: uninstall the old version first, then add -arch x64.
echo [2/3] Compiling...
"%WIX_BIN%\candle.exe" -dVersion=%VERSION% -dSourceDir="%SRC%" abyroy.wxs AppFiles.wxs
if errorlevel 1 goto :failed

echo [3/3] Linking MSI...
"%WIX_BIN%\light.exe" -sval -out ABYROY_Chat_%VERSION%.msi abyroy.wixobj AppFiles.wixobj
if errorlevel 1 goto :failed

echo.
echo DONE: ABYROY_Chat_%VERSION%.msi
echo.
pause
exit /b 0

:no_wix
echo.
echo ERROR: WiX Toolset not found. Expected heat.exe in:
echo %WIX_BIN%
echo Install WiX v3.14 or fix WIX_BIN in this file.
echo.
pause
exit /b 1

:no_app
echo.
echo ERROR: application not found. Expected matrix_messenger.exe in:
echo %SRC%
echo Run "flutter build windows" first.
echo.
pause
exit /b 1

:failed
echo.
echo BUILD FAILED - see messages above.
echo.
pause
exit /b 1
