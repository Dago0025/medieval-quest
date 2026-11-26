# Sviluppo

Note per chi vuole aprire, modificare o ricompilare Medieval Quest. Il progetto non prevede supporto: questo file e i commenti nel codice sono tutta la documentazione tecnica disponibile.

## Requisiti

- **Godot 4.7** (versione standard, non .NET): <https://godotengine.org/download>.
- Il gioco non usa file del gioco originale: immagini e audio sono tutti in `assets/`. Una cartella `originale/` accanto a `project.godot` (fuori dal repository, creata con `python tools/copia_originale.py "<cartella di Medieval: Total War Gold>"`) serve solo ad alcuni test e strumenti di confronto, che senza di essa vengono saltati.
- Python 3 solo per gli script di `tools/` e per l'installer.

## Avvio

- **Editor**: apri `project.godot` con Godot e premi F5. In alternativa `avvia.bat`, che usa il Godot indicato in `godot_path.txt`.
- **Test**: `run_tests.bat` trova Godot (o legge `godot_path.txt`), importa il progetto, esegue i test di `tests/unit` e scrive l'esito in `tests/esito_test.txt`.
- **Eseguibile**: `esporta.bat` ricostruisce `build/Medieval Quest.exe` (pck incorporato) con il preset «Windows» di `export_presets.cfg`. Servono i modelli di esportazione 4.7.2, da installare una volta dall'editor: Editor → Gestisci modelli di esportazione → Scarica e installa.
- **Installer**: vedi [installer/LEGGIMI.md](../installer/LEGGIMI.md).

Salvataggi e impostazioni: `%APPDATA%/Godot/app_userdata/MTW Remake` (il nome interno del progetto resta «MTW Remake» per non perdere i salvataggi esistenti).

## Struttura

| Cartella | Contenuto |
|---|---|
| `src/core` | Accesso ai file e utilità (testo cp1252, percorsi) |
| `src/data` | Lettori di startpos, tabelle di unità ed edifici, testi; modello dei dati |
| `src/map` | Mappa delle regioni, proiezione, confini, shader |
| `src/sim` | Regole della simulazione: turno, economia, scontri, agenti, dinastie, religione, eventi, vittoria |
| `src/ai` | Intelligenza artificiale delle fazioni del computer (usa gli stessi comandi del giocatore) |
| `src/ui` | Componenti dell'interfaccia |
| `scenes` | Scene principali: menu, plancia della campagna |
| `data` | Dati della campagna, regole (`data/regole/*.cfg`), testi italiano/inglese, mappa del mondo |
| `assets` | Immagini, caratteri, icone, audio proprio |
| `tests` | Esecutore dei test e test unitari |
| `tools` | Script Python per preparare dati e immagini |
| `docs` | Decisioni architetturali, catalogo delle meccaniche, dizionario dei dati, specifiche per fase |

## Principi

- La simulazione (`src/sim`) è separata dalla grafica: GDScript puro, deterministica con seme casuale, coperta dai test.
- Ogni azione, del giocatore o dell'IA, passa da `GameCommands`; il fine anno (`TurnProcessor.end_year`) segue un ordine fisso.
- Parametri e contenuti stanno nei file di dati, non nel codice. Le regole senza una formula nota dell'originale sono marcate `PROVVISORIA` nel catalogo (`docs/catalogo_meccaniche.md`) e nel codice.
- I file di dati di origine MTW sono in cp1252 con fine riga CRLF.
