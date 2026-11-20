# Fase 8: interfaccia

Obiettivo: un'interfaccia «abbastanza professionale» (Federico) con l'aspetto dell'originale. Ricerca e alternative in
`docs/ricerca_interfaccia.md`; decisione sugli asset in ADR-007 (PNG di `_ASSET_EXPORT`, versione `_HD` se c'è, niente
ingrandimento manuale).

## 8a, prototipo (fatto)

- `src/ui/asset_library.gd` (AssetLibrary): indice dal manifesto dell'esportazione, ricerca per percorso del gioco senza badare
  alle maiuscole, fotogrammi `__fNN`, versione HD con la precedenza, elenco delle immagini mancanti, avviso se l'esportazione
  non c'è (con il rimedio: rifare `export.py`). Carte e illustrazioni delle unità per nome (236 unità su 236, navi comprese);
  scudi delle fazioni da `SetShieldImage` dello startpos.
- `src/ui/ui_theme.gd` (UiTheme): tema costruito a codice e fuso nel tema predefinito (vale anche per i controlli sotto un
  CanvasLayer, i menu e i suggerimenti). Pergamena a nove parti dell'originale per i pannelli, striscia per la barra in alto,
  fregi tra le sezioni, inchiostri, Fondamento per titoli, sezioni e pulsanti, Alegreya per il testo (OFL, `assets/fonts`;
  scelti da Federico su un confronto di cinque coppie: Cinzel + EB Garamond erano «troppo spigolosi e posticci»). Senza immagini
  ripiega su stili disegnati con gli stessi colori.
- `src/ui/sharpen.gdshader`: nitidezza adattiva per le immagini piccole mostrate più grandi (carte 50x50 a 56).
- `src/ui/piece_art.gd` (PieceArt): pedine della mappa dell'originale per eserciti (comuni e con un capo o un erede), flotte,
  crociate, jihad e agenti; colori chiave sostituiti con quelli della fazione (stendardo e anello ciano: primario; anello
  magenta: secondario), scudo della fazione dipinto sulla figura. La posizione dello scudo è PROVVISORIA. Niente numero
  sotto le pedine, come nell'originale (scelta di Federico). Le carte delle unità hanno anche loro colori chiave (158 su 234,
  segnalati da Federico come «colori strani»): magenta -> primario, verde -> secondario della fazione dell'esercito.
- Mappa (`scenes/campaign_map.gd`, `scenes/army_layer.gd`): barra con lo scudo del giocatore, pannello della provincia con
  scudo e nome, pannello dell'esercito con le carte delle pile e le caselle per dividere e riaddestrare sotto le carte, pedine
  ordinate dall'alto in basso con il numero di pile, aiuto dei comandi con H (prima un'unica riga che si sovrapponeva).
- Verifica a occhio: catture dello schermo nella VM con Xvfb e OpenGL (`$HOME/godot/shot.sh`).

## Prossimi passi (proposta)

- 8b: finestre di corte, diplomazia ed eventi con ritratti, illustrazioni degli eventi e scudi; scheda dell'unità con
  l'illustrazione grande; elenco degli edifici con le immagini del review panel.
- 8c: menu iniziale e scelta della fazione (sfondo e pergamene del frontend), impostazioni (difficoltà, cartelle).
- 8d: rifiniture: titolo nel nastro delle pergamene, icone game-icons.net (CC BY) per le meccaniche nuove, suoni dei pulsanti.
