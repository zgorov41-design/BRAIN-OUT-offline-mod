
@echo off
setlocal
chcp 65001 >nul
title BrainOut Offline Freeplay

rem Путь определяется относительно расположения этого BAT
set "ROOT=%~dp0"
set "SERVER=%ROOT%bin\server"
set "CLIENT=%ROOT%bin\client"

echo =====================================
echo       BrainOut Offline Freeplay
echo =====================================
echo.

if not exist "%SERVER%\run.bat" (
    echo Ошибка: не найден сервер.
    echo Положи BAT в корневую папку игры.
    pause
    exit /b 1
)

if not exist "%CLIENT%\brainout-desktop.jar" (
    echo Ошибка: не найден клиент brainout-desktop.jar.
    pause
    exit /b 1
)


echo.
echo Запуск сервера...

start "BrainOut Server" cmd /k "cd /d ""%SERVER%"" && run.bat --settings server-free.json --map freeplay-maps.shuffle --mode free --offline"

timeout /t 5 /nobreak >nul

echo Запуск клиента...
cd /d "%CLIENT%"
java -jar brainout-desktop.jar --unsafe --offline

echo.
echo Игра закрыта.
pause
