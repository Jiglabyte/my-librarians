@echo off
rem PerfectScreen — Windows install script.
rem Copies the extension into the user CEP folder and enables debug mode
rem (required to load unsigned extensions).

set SRC=%~dp0
set DEST=%APPDATA%\Adobe\CEP\extensions\perfectscreen-ae

if exist "%DEST%" rmdir /s /q "%DEST%"
xcopy /e /i /q "%SRC%" "%DEST%"
echo Copied extension to: %DEST%

rem Enable unsigned extensions for every CEP runtime AE 2020+ might use.
for %%v in (9 10 11 12) do (
  reg add "HKCU\Software\Adobe\CSXS.%%v" /v PlayerDebugMode /t REG_SZ /d 1 /f >nul
)

echo PlayerDebugMode enabled for CSXS 9-12.
echo Restart After Effects, then open: Window ^> Extensions ^> PerfectScreen
pause
