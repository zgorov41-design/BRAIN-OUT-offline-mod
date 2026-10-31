
@echo off
setlocal
cd /d "%~dp0server"

if not exist "brainout-server.jar" (
    echo ERROR: brainout-server.jar not found in "%CD%"
    pause
    exit /b 1
)

set server_settings={"bots":8}
java -jar brainout-server.jar no 36555,36556,36557 --settings server-settings.json --maps maps-set.json --offline
pause
