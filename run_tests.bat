@echo off
rem Esegue i test del remake con Godot 4 senza finestra di gioco.
rem Cerca Godot da solo (PATH, poi cartelle comuni) e ricorda il percorso in godot_path.txt.
rem Per indicarlo a mano: scrivi il percorso completo dell'eseguibile in godot_path.txt.
rem L'esito completo viene salvato in tests\esito_test.txt.
setlocal
cd /d "%~dp0"
set "LOG=%~dp0tests\esito_test.txt"

if not defined GODOT if exist "godot_path.txt" set /p GODOT=<"godot_path.txt"
if defined GODOT if not exist "%GODOT%" set "GODOT="
if not defined GODOT for /f "delims=" %%P in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%P"
if not defined GODOT (
  echo Cerco Godot nelle cartelle comuni, attendi...
  for /f "delims=" %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\trova_godot.ps1"') do set "GODOT=%%P"
)
if not defined GODOT (
  echo Godot non trovato.> "%LOG%"
  echo.
  echo Godot non trovato. Scrivi il percorso completo dell'eseguibile di Godot
  echo per esempio C:\Godot\Godot_v4.7.1-stable_win64_console.exe, nel file
  echo godot_path.txt in questa cartella e rilancia.
  pause
  exit /b 2
)
> "godot_path.txt" echo %GODOT%

echo Godot: %GODOT%
> "%LOG%" echo Godot: %GODOT%
>> "%LOG%" echo Data: %DATE% %TIME%

rem L'importazione aggiorna l'elenco delle classi: serve ogni volta che si aggiungono script.
echo Importo il progetto...
>> "%LOG%" echo === Importazione ===
"%GODOT%" --headless --import >> "%LOG%" 2>&1

echo Eseguo i test...
>> "%LOG%" echo === Test ===
"%GODOT%" --headless --script res://tests/run_tests.gd >> "%LOG%" 2>&1
set ESITO=%ERRORLEVEL%
>> "%LOG%" echo === Codice di uscita: %ESITO% ===

echo.
type "%LOG%"
echo.
if "%ESITO%"=="0" (echo TUTTI I TEST PASSATI) else (echo ATTENZIONE: test falliti o errore, codice %ESITO%)
echo L'esito e' salvato in tests\esito_test.txt
pause
endlocal & exit /b %ESITO%
