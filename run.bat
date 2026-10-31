@echo off
setlocal
chcp 65001 >nul
title BrainOut Launcher

set "ROOT=%~dp0"
set "SERVER=%ROOT%bin\server"
set "CLIENT=%ROOT%bin\client"
set "BIN=%ROOT%bin"

echo =====================
echo BRAIN / OUT LAUNCHER
echo =====================

if /i "%~1"=="freeplay" goto freeplay
if /i "%~1"=="match play" goto matchplay
goto lobby

:lobby
if not exist "%SERVER%\run.bat" goto error
if not exist "%SERVER%\server-lobby.json" goto error
if not exist "%CLIENT%\brainout-desktop.jar" goto error

start "BrainOut Main Menu Server" cmd /k "cd /d ""%SERVER%"" && run.bat --mode lobby --settings server-lobby.json --offline"
timeout /t 5 /nobreak >nul
start "BrainOut Client" cmd /k "cd /d ""%CLIENT%"" && java -jar brainout-desktop.jar --unsafe --offline"
goto end

:freeplay
if not exist "%SERVER%\run.bat" goto error
if not exist "%CLIENT%\brainout-desktop.jar" goto error

start "BrainOut Freeplay Server" cmd /k "cd /d ""%SERVER%"" && run.bat --settings server-free.json --map freeplay-maps.shuffle --mode free --offline"
timeout /t 5 /nobreak >nul
start "BrainOut Client" cmd /k "cd /d ""%CLIENT%"" && java -jar brainout-desktop.jar --unsafe --offline"
goto end

:matchplay
if not exist "%BIN%\Run Server Game Phase.bat" goto error
if not exist "%CLIENT%\brainout-desktop.jar" goto error

start "BrainOut Match Play Server" "%ComSpec%" /k ""%BIN%\Run Server Game Phase.bat""
timeout /t 5 /nobreak >nul
start "BrainOut Client" cmd /k "cd /d ""%CLIENT%"" && java -jar brainout-desktop.jar --unsafe --offline"
goto end

:error
echo.
echo ERROR: Required game files were not found.
pause
exit /b 1

:end
echo.
echo Game launched. Keep the server window open while playing.
pause