extends RefCounted
## Valori predefiniti della partita quando la mappa si avvia da sola (senza il menu iniziale della fase 8c, che sceglie
## fazione, difficolta' e seme con GameLaunch; difficolta' e inclinazione dell'utente stanno in UserSettings).

## Fazione del giocatore: gli Auror (la fazione della mod integrata, ADR-004; nei dati FN_DANISH). Nome, colori e stemma in
## data/fazioni.cfg.
const PLAYER_FACTION := "FN_DANISH"
## Nome del salvataggio rapido (F5 salva, F9 carica) in user://salvataggi/.
const QUICK_SAVE := "rapido"
## Difficolta' dell'IA (fase 7): "facile", "normale", "difficile" o "molto_difficile"; "" = quella di data/regole/ia.cfg.
## Scala aggressivita', budget e soglie d'attacco delle fazioni del computer, senza bonus di risorse. Fino al menu della fase 8.
const AI_DIFFICULTY := "normale"
## Seme del generatore casuale della partita nuova.
const NEW_GAME_SEED := 20261108
## Inclinazione della plancia (MapProjection.tilt): rapporto tra la larghezza della mappa
## visibile in alto e in basso. 1 = vista dall'alto; P alterna, Pagina su/giù regolano.
const PERSPECTIVE_TILT := 1.6
