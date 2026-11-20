# Cerca l'eseguibile di Godot 4 (versione standard, non .NET) nelle cartelle piu' comuni.
# Stampa il percorso trovato, oppure niente. Preferisce la versione "console",
# che mostra l'output dei test nel terminale.
$ErrorActionPreference = 'SilentlyContinue'
$roots = @(
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents",
    "$env:LOCALAPPDATA",
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}\Steam\steamapps\common",
    "C:\Godot",
    "C:\Tools"
) | Where-Object { $_ -and (Test-Path $_) }

$found = foreach ($r in $roots) {
    Get-ChildItem -Path $r -Recurse -Depth 4 -File -Include 'Godot*.exe', 'godot*.exe'
}
$found = $found | Where-Object { $_.Name -notmatch 'uninstall|mono|dotnet' }
$best = $found |
    Sort-Object @{ Expression = { if ($_.Name -match 'console') { 0 } else { 1 } } },
                @{ Expression = { $_.LastWriteTime }; Descending = $true } |
    Select-Object -First 1
if ($best) { $best.FullName }
