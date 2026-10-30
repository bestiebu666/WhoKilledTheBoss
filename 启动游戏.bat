@echo off
rem Launch the "Who Killed The Boss" demo straight from the Godot source project.
rem Paths are RELATIVE: the project root is this script's own folder (%~dp0),
rem so the whole folder can be copied / shipped as-is.
setlocal
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
rem 1) Prefer a Godot exe placed next to this project folder (portable ship).
set "GODOT=%HERE%\Godot_v4.7.2-stable_win64.exe"
rem 2) Fall back to the current local install path.
if not exist "%GODOT%" set "GODOT=D:/godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
rem 3) Legacy path used by earlier copies of this project.
if not exist "%GODOT%" set "GODOT=D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo [ERROR] Godot 4.7.2 not found.
  echo         Put Godot_v4.7.2-stable_win64.exe next to this file,
  echo         or edit the GODOT line in this script.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%HERE%"
