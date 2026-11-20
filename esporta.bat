@echo off
rem Ricostruisce build\Medieval Quest.exe dal progetto, senza aprire l'editor.
rem Serve Godot 4.7.2 (percorso in godot_path.txt, lo scrive run_tests.bat) con i modelli di esportazione
rem installati una volta dall'editor: Editor ^> Gestisci modelli di esportazione ^> Scarica e installa.
setlocal
cd /d "%~dp0"
if not defined GODOT if exist "godot_path.txt" set /p GODOT=<"godot_path.txt"
if not defined GODOT (
  echo Godot non trovato: lancia prima run_tests.bat oppure scrivi il percorso di Godot in godot_path.txt
  pause
  exit /b 2
)
if not exist build mkdir build
echo Importo il progetto...
"%GODOT%" --headless --import > build\esporta.log 2>&1
echo Esporto build\Medieval Quest.exe ...
"%GODOT%" --headless --export-release "Windows" "build\Medieval Quest.exe" >> build\esporta.log 2>&1
set ESITO=%ERRORLEVEL%
if "%ESITO%"=="0" (echo Fatto: build\Medieval Quest.exe) else (echo Esportazione fallita, codice %ESITO%: vedi build\esporta.log)
pause
endlocal & exit /b %ESITO%
