@echo off
setlocal
cd /d "%~dp0"
echo Starting KNOU notifier setup...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
if errorlevel 1 (
  echo Setup stopped because of the error shown above.
) else (
  echo Setup finished successfully.
)
echo.
pause
endlocal
