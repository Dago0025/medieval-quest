# Caratteri dell'interfaccia

Scelti da Federico il 2026-11-08 (confronto in docs/specifica_fase8.md). Licenza SIL Open Font License 1.1 (testi completi
accanto a ciascun file), dal repository google/fonts:

- `Fondamento-Regular.ttf`: Fondamento di Astigmatic, a penna larga, per titoli, sezioni e pulsanti (`ofl/fondamento`).
- `Alegreya-VF.ttf`: Alegreya di Juan Pablo del Peral (Huerta Tipográfica), umanistico, per il testo (`ofl/alegreya`); è un
  carattere variabile, il peso si sceglie con `FontVariation` (asse `wght`) in `src/ui/ui_theme.gd`.

Versioni «nitide» per le parti scalate dell'interfaccia (barra in basso), usate come caratteri a campo di distanza (MSDF)
da `UiTheme.crisp_font` (2026-11-11): i contorni sovrapposti degli originali lasciavano puntini e macchie.

- `Alegreya-500-nitido.ttf`, `Alegreya-760-nitido.ttf`: pesi fissi ricavati da `Alegreya-VF.ttf` con fontTools
  (`varLib.instancer`, `OverlapMode.REMOVE`).
- `Titoli-nitido.ttf`: Fondamento con i contorni uniti (`fontTools.ttLib.removeOverlaps`); nome interno «MQ Titoli Nitido»
  perché la licenza riserva il nome «Fondamento» all'originale.
