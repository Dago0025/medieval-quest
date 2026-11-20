@echo off
rem Avvia il remake dal progetto, senza esportare: utile per provare le modifiche appena fatte.
rem Prima aggiorna l'elenco delle classi del progetto (--import): senza, Godot non trova gli script nuovi
rem e mostra una schermata bianca.
setlocal
cd /d "%~dp0"
if not exist "godot_path.txt" (
  echo Manca godot_path.txt: esegui prima run_tests.bat, che trova Godot e ne ricorda il percorso.
  pause
  exit /b 1
)
set /p GODOT=<"godot_path.txt"
echo Aggiorno il progetto, attendi qualche secondo...
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1
start "" "%GODOT%" --path "%~dp0."
