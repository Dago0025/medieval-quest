# Pubblica su GitHub la release di Medieval Quest con l'installer allegato (ADR-144).
# Gira sul PC di sviluppo con GitHub CLI autenticato (gh auth login, token limitato al repo con Contents in scrittura).
#
#   powershell -ExecutionPolicy Bypass -File installer\pubblica_release.ps1 -Versione 2026.12.03 -Note note.md
#
# Controlla che config/version di project.godot sia uguale alla versione, che l'installer esista
# (build\MedievalQuest-Setup-<versione>.exe, creato da prepara_installer.py) e che il tag non esista gia';
# crea la release v<versione> su main, la segna come ultima e verifica che l'allegato sia arrivato intero.
# Il codice va spinto su main PRIMA di lanciarlo: il tag nasce dall'ultimo commit di main su GitHub.
param(
  [Parameter(Mandatory = $true)][string]$Versione,
  [Parameter(Mandatory = $true)][string]$Note,
  [string]$Repo = 'Dago0025/medieval-quest',
  [switch]$Bozza
)
$ErrorActionPreference = 'Stop'
$progetto = Split-Path $PSScriptRoot -Parent
function Esci($msg) { Write-Output "ERRORE: $msg"; exit 1 }

$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { foreach ($c in @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe")) { if (Test-Path $c) { $gh = $c; break } } }
if (-not $gh) { Esci "GitHub CLI non trovato (winget install GitHub.cli)" }

$cfg = Get-Content "$progetto\project.godot" -Raw
if ($cfg -notmatch '(?m)^config/version="([^"]*)"') { Esci "config/version mancante in project.godot" }
if ($Matches[1] -ne $Versione) { Esci "project.godot ha config/version=$($Matches[1]), non $Versione" }

$setup = "$progetto\build\MedievalQuest-Setup-$Versione.exe"
if (-not (Test-Path $setup)) { $setup = "$progetto\installer\build\MedievalQuest-Setup-$Versione.exe" }
if (-not (Test-Path $setup)) { Esci "installer non trovato: lancia prima installer\prepara_installer.py --versione $Versione" }
if (-not (Test-Path $Note)) { Esci "note non trovate: $Note" }

$ErrorActionPreference = 'Continue'
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Esci "GitHub CLI non autenticato: gh auth login" }
& $gh release view "v$Versione" --repo $Repo *> $null
if ($LASTEXITCODE -eq 0) { Esci "la release v$Versione esiste gia'" }

$argomenti = @('release', 'create', "v$Versione", $setup, '--repo', $Repo, '--target', 'main',
  '--title', "Medieval Quest $Versione", '--notes-file', $Note)
if ($Bozza) { $argomenti += '--draft' } else { $argomenti += '--latest' }
Write-Output "Carico $(Split-Path $setup -Leaf) ($([math]::Round((Get-Item $setup).Length / 1MB)) MB)..."
& $gh @argomenti
if ($LASTEXITCODE -ne 0) { Esci "gh release create non riuscito ($LASTEXITCODE)" }

$attesa = (Get-Item $setup).Length
$caricato = & $gh release view "v$Versione" --repo $Repo --json assets --jq '.assets[0].size'
if ([int64]$caricato -ne $attesa) { Esci "allegato di $caricato byte invece di $attesa" }
Write-Output "Pubblicata: https://github.com/$Repo/releases/tag/v$Versione (installer $attesa byte)"
