@echo off
setlocal
chcp 65001 >nul

set "ROOT=%~dp0"
set "SERVER=%ROOT%bin\server"
set "CLIENT=%ROOT%bin\client"
set "TRACE=%ROOT%client-trace.log"

if not exist "%SERVER%\run.bat" (
    echo Server run.bat not found.
    pause
    exit /b 1
)

if not exist "%CLIENT%\brainout-desktop.jar" (
    echo Client JAR not found.
    pause
    exit /b 1
)

if exist "%TRACE%" del /q "%TRACE%"

start "BrainOut Freeplay Server" cmd /k "cd /d ""%SERVER%"" && run.bat --settings server-free.json --map freeplay-maps.shuffle --mode free --offline"

timeout /t 5 /nobreak >nul

start "BrainOut Client Trace" cmd /k "cd /d ""%CLIENT%"" && java -jar brainout-desktop.jar --unsafe --offline > ""%TRACE%"" 2>&1"

echo Client output will be saved to:
echo %TRACE%
pause