# Ricerca: grafica dell'interfaccia (fase 8)

Data: 2026-11-08. Domanda di Federico: un'interfaccia «abbastanza professionale», sapendo che Claude non disegna immagini raster.

## Cosa c'è già

L'esportazione degli asset dell'installazione (`<gioco>/_ASSET_EXPORT`, 6.552 immagini, `_manifest.csv`) copre quasi tutta
l'interfaccia della campagna originale:

| Gruppo | Quantità | Dimensioni | Uso nel remake |
|---|---|---|---|
| Ritratti (re, eredi, principesse, generali, agenti per religione) | ~4.200 | 96x142 | pannello personaggi, corte, agenti |
| Illustrazioni info di unità, edifici, navi, agenti | ~590 | 366x448 | schede di unità ed edifici |
| Carte delle unità (review panel) | ~600 | 150x150 e 68x50 | pannello esercito, reclutamento |
| Pedine della mappa (unità, agenti, navi) | ~270 | ~105x226 | segnalini sulla mappa |
| Scudi delle fazioni e colori | ~230 | 34x40 | stemmi, liste, classifiche |
| Pergamene, cornici, divisori, icone, pulsanti | ~250 | fino a 800x600 | pannelli e controlli |
| Menu iniziale, selezione fazione, caricamento | ~70 | fino a 1280x1024 | schermate iniziali |
| Schermate di fine partita per fazione | ~40 | 640x480 | vittoria e sconfitta |

Lo stile è unitario (pergamena chiara, inchiostro seppia, metallo brunito) e di buona fattura. Il limite è la risoluzione,
pensata per 1024x768. Il remake legge già dalla cartella `_HD` le versioni ingrandite (oggi la mappa).

## Soluzioni trovate

1. **Asset originali letti dall'installazione** (ADR-007, da confermare). Decodifica a runtime: i TGA con
   `Image.load_tga_from_buffer` di Godot, i BIF con un decodificatore GDScript ricavato da `_strumenti/bif.py` (formato già
   documentato in `_ASSET_EXPORT/LEGGIMI.txt`). Nessuna immagine entra nel repository; resta l'override da `_HD`.
2. **Ingrandimento con IA in locale**: Upscayl (gratuito, Real-ESRGAN su GPU Vulkan), già usato per la mappa. Modelli da
   provare: «Digital Art» per illustrazioni e pergamene, «Remacri» per i ritratti (pelle meno plastica); due passaggi 2x
   danno spesso meno artefatti di un 4x. Lavoro in blocco su cartelle, risultati in `_HD` con lo stesso percorso.
3. **Tema Godot costruito a codice**: StyleBoxTexture a nove parti ricavate dalle pergamene originali (bordi che non si
   deformano a nessuna dimensione), un unico costruttore del tema in GDScript (sul modello di ThemeGen, licenza MIT) per
   colori, margini e stati dei controlli. Effetti a shader (grana della carta, ombre, bagliore della selezione) senza immagini.
4. **Caratteri liberi (OFL)**, che possono stare nel repository: IM Fell English (tipi del Seicento) o Cinzel per i titoli,
   EB Garamond o Alegreya per il testo, entrambi leggibili a corpo piccolo.
5. **Icone per le meccaniche nuove** che l'originale non ha (riaddestramento, dividere e unire, proposte, zelo, vittoria):
   game-icons.net, oltre 4.000 SVG in licenza CC BY 3.0 (basta citare gli autori), da ricolorare in seppia per stare sulla
   pergamena. Godot carica gli SVG senza conversioni. In riserva Kenney «Fantasy UI Borders» (CC0, cornici a nove parti).
6. **Stemmi mancanti** (solo se qualche fazione Auror non ha lo scudo): Armoria di Azgaar genera stemmi araldici in SVG
   (codice MIT, figure semplici CC0).
7. **Illustrazioni nuove con IA generativa**, facoltativo: Recraft genera SVG con stile bloccato, adatto a icone coerenti;
   per immagini raster servirebbe un generatore usato da Federico, con il remake che le carica da `_HD`.

## Cosa può fare Claude e cosa no

Claude scrive il decodificatore, il tema, gli shader, le scene e gli script Python che ritagliano, ricolorano e preparano le
immagini sulla macchina di Federico. Non dipinge illustrazioni nuove e non lancia Upscayl, che gira sulla GPU del PC.

## Proposta

Base: punti 1, 2, 3 e 4, cioè l'aspetto dell'originale ripulito e ad alta risoluzione. Punto 5 per le lacune, 6 e 7 solo se
servono. Primo passo: un prototipo di una schermata (pannello provincia ed esercito) vestita con gli asset originali, da
valutare prima di estendere lo stile a tutta l'interfaccia.

## Fonti

- [game-icons.net, licenza](https://game-icons.net/about.html)
- [Kenney, Fantasy UI Borders (CC0)](https://opengameart.org/content/fantasy-ui-borders)
- [ThemeGen per Godot (MIT)](https://godotengine.org/asset-library/asset/3299)
- [Armoria, licenza](https://github.com/azgaar/armoria-api)
- [Godot, caricamento di file a runtime](https://docs.godotengine.org/en/4.4/tutorials/io/runtime_file_loading_and_saving.html)
- [Upscayl, modelli](https://www.aiarty.com/ai-image-enhancer/upscayl-vs-topaz.htm)
- [IM Fell English (OFL)](https://online-fonts.com/fonts/im-fell-english)
- [Recraft, SVG con stile coerente](https://www.recraft.ai/docs/recraft-models/recraft-V2)
