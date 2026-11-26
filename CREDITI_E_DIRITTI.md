# Crediti e diritti

Medieval Quest è un progetto di fan **non ufficiale e senza scopo di lucro**. Non è affiliato, sponsorizzato né approvato da The Creative Assembly, SEGA, Activision o dagli autori della mod XL.

## Progetto aperto, senza supporto

- Il **codice** di Medieval Quest (cartelle `src`, `scenes`, `tests`, `tools`, file di progetto Godot) è distribuito con licenza **MIT**: vedi [LICENSE](LICENSE).
- Il progetto è fornito **così com'è**: nessuna garanzia, nessuna assistenza, nessun impegno di aggiornamento o di risposta a segnalazioni e richieste. Chi lo usa lo fa a proprio rischio.
- Si possono creare copie e versioni modificate del codice nel rispetto della licenza MIT, ma **non** dei contenuti di terzi elencati sotto, che seguono le loro regole.

## Gioco originale: Medieval: Total War

*Medieval: Total War* (2002) e l'espansione *Viking Invasion* sono stati sviluppati da **The Creative Assembly** e pubblicati da **Activision**; oggi la serie è di **SEGA** / The Creative Assembly. *Total War* e *Medieval: Total War* sono marchi dei rispettivi titolari. La colonna sonora originale è di Jeff van Dyck.

Medieval Quest ne riprende idee, regole e struttura della campagna. Il motore e il codice sono scritti da zero e dal 26/11/2026 il gioco **non contiene file del gioco originale** (immagini, musiche ed effetti sono nuovi o da librerie libere). Restano invece contenuti derivati:

- **nei dati** (`data/campagna`, `data/testi`, nomi di province, unità ed edifici): valori e testi ricavati dai file del gioco originale e della mod XL, in parte riscritti;
- **nelle immagini**: alcune icone di unità, edifici e mappa sono rielaborazioni, generate con l'IA, delle icone originali.

Su richiesta dei titolari dei diritti, i contenuti contestati verranno rimossi.

## Mod XL 3.0

La base della campagna (province, fazioni, unità, edifici, data di partenza) viene dalla **XL mod 3.0** per Medieval: Total War – Viking Invasion. Grazie ai suoi autori.

## Motore: Godot Engine

Il gioco usa [Godot Engine](https://godotengine.org), distribuito con licenza MIT:

> Copyright (c) 2014-present Godot Engine contributors.
> Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Godot include componenti di terzi con licenze proprie (per esempio FreeType: *Portions of this software are copyright © The FreeType Project, www.freetype.org. All rights reserved.*). Testi completi: <https://godotengine.org/license>. L'installer copia la licenza di Godot nel file `LICENZE_TERZE_PARTI.txt`.

## Caratteri

Con licenza [SIL Open Font License 1.1](https://openfontlicense.org) (testi completi in `assets/fonts`):

- **Alegreya**, © 2011 The Alegreya Project Authors (Juan Pablo del Peral, Huerta Tipográfica);
- **Fondamento**, © 2011 Brian J. Bonislawsky DBA Astigmatic. La versione ricavata per l'interfaccia (`Titoli-nitido.ttf`) si chiama «MQ Titoli Nitido», perché la licenza riserva il nome «Fondamento» all'originale.

## Immagini nuove

Ritratti, scene degli eventi, stemmi, cornici e gran parte delle icone sono stati generati in locale con **Intel AI Playground** (modelli di diffusione aperti, tra cui la famiglia Flux) e rifiniti con gli script in `tools/`.

## Audio nuovo

Tutto l'audio del gioco viene da librerie gratuite, con licenza [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (pubblico dominio). Gli autori sono citati per cortesia, la licenza non lo richiede.

- **Musiche** (tema gotico di menu e mappa), tutte da [OpenGameArt](https://opengameart.org), CC0: *Fantasy Choir 1, 2, 3* di **César da Rocha** (cesisco), *Laments of the War* di **Cethiel**, *Evil Approach* di **nene**, *Fantasy: Lament for a Warrior's Soul* di **RandomMind**, *Kokopelli's Graveyard Theme* di **Cleyton Kauffman**, *Cathedral* di **Umplix**, *Chant* (canto gregoriano) di **christislord**.
- **Vittoria e sconfitta**: *Victory Theme* e *Defeat Theme* di **RandomMind** su [OpenGameArt](https://opengameart.org/users/randommind), CC0.
- **Effetti brevi** (clic, pedine, pergamene, monete, costruzione, salvataggio): suoni dei pacchetti *RPG Audio*, *Impact Sounds* e *Casino Audio* di **Kenney** ([kenney.nl](https://kenney.nl)).
- **Fanfare e segnali** da [Freesound](https://freesound.org): *Trumpet Fanfare* (bevibeldesign), *FanFare.wav* (DylanTheFish), *Trumpet call* (Jorgemaca), *Success Fanfare Trumpets* (FunWithSound), *TollBell* (daytripper), *Battle_horn_1* (kirmm), *war horn* (adharca).

Tagli, volumi e conversioni con gli script in `tools/audio`.

## Autore

Federico Deserti — ideazione, direzione e progetto, con il supporto di assistenti IA per codice e documentazione.
