@echo off
chcp 65001 >nul
rem Двойной клик: запускает Rojo и раз в 30 секунд забирает изменения с GitHub.
rem Изменения кода Rojo сразу переносит в Studio. Остановить — закрыть оба окна.
cd /d "%~dp0"

if not exist rojo.exe (
  echo Нет rojo.exe в папке проекта. Положи его рядом с этим файлом.
  pause
  exit /b
)

rem git: установленный отдельно или встроенный в GitHub Desktop.
set "GIT=git"
where git >nul 2>nul
if errorlevel 1 (
  for /d %%D in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do set "GIT=%%D\resources\app\git\cmd\git.exe"
)

"%GIT%" pull --ff-only -q
call :project
set "RUNNING=%PROJ%"
start "Rojo" rojo.exe serve
echo Rojo запущен. Изменения с GitHub подтягиваются каждые 30 секунд.
echo В Studio нажми Connect в Rojo. Остановить - закрыть это окно и окно Rojo.

:loop
timeout /t 30 /nobreak >nul
"%GIT%" pull --ff-only -q
if errorlevel 1 echo [%time%] Не удалось забрать изменения - открой GitHub Desktop и посмотри, что мешает.
call :project
if not "%PROJ%"=="%RUNNING%" (
  echo [%time%] Изменился default.project.json - перезапускаю Rojo, в Studio нажми Connect ещё раз.
  taskkill /im rojo.exe /f >nul 2>nul
  start "Rojo" rojo.exe serve
)
set "RUNNING=%PROJ%"
goto loop

:project
set "PROJ="
for /f "usebackq" %%H in (`"%GIT%" rev-parse HEAD:default.project.json`) do set "PROJ=%%H"
exit /b
