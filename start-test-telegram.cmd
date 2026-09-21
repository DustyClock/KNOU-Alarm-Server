@echo off
setlocal
cd /d "%~dp0"
echo Sending a Telegram test message...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-telegram.ps1"
echo.
if errorlevel 1 (
  echo Test failed. Check the error shown above.
) else (
  echo Test completed successfully. Check the bot chat.
)
echo.
pause
endlocal
