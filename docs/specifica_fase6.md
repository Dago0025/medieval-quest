# Specifica della fase 6: eventi e vittoria

Obiettivo: la storia che scorre e una partita che finisce. Eventi storici con i loro testi originali, disastri, l'invasione dell'Orda d'Oro, le condizioni di vittoria e sconfitta (dominio) e la fine della campagna nel 1700. **Le imprese gloriose sono escluse dal remake per scelta di Federico (2026-11-08)**: non si implementano né la modalità né i punti. Le regole vengono dal catalogo (§Turni ed epoche, §Eventi e fazioni emergenti, §Condizioni di vittoria); i dati che i file non contengono (date ed effetti degli eventi) sono **ricostruiti da fonti esterne o dalla storia** e lo dichiarano nei file di dati, con la fonte per ogni voce.

Vincoli: ADR-003, 004, 005, 007 (i testi originali si leggono dall'installazione a ogni avvio e non entrano nel repository), 008, 011. Determinismo con `state.rng`.

Due blocchi in sequenza: **6a eventi** (storici, disastri, Orda d'Oro) e **6b vittoria** (dominio, sconfitta, fine partita). L'interfaccia segue.

## Ordine del fine anno (estende ADR-008)

Dopo il Papato (5c) e prima del reddito: **eventi** (`EventProcessor.process_year`: storici, disastri, Orda d'Oro). Dopo il calendario: **vittoria** (`VictoryProcessor.check`: dominio, sconfitta, fine della campagna).

## 6a. Eventi storici

| Regola | Dettaglio |
|---|---|
| Testi | I 71 titoli e testi di `Historical_event_titles` / `Historical_event_text` di `Loc/<lingua>/Events.txt`, letti con `LocLoader` per indice (ordine del file). Nessun testo nel repository: il file dei dati contiene solo indici, date ed effetti. |
| Date | `data/eventi/eventi_storici.cfg`: per ogni indice anno storico (o finestra di anni) con la fonte o la motivazione (catalogo: «circa come nella storia, ma non contarci»); un evento accade una sola volta, nell'anno indicato o in un anno estratto nella finestra (PROVVISORIA). Eventi legati a una fazione o a una regione (per esempio «Turbulent Priest Slain!» per gli Inglesi) si mostrano a tutti ma valgono per chi soddisfa la condizione. |
| Effetti | Dove il testo dichiara un effetto (per esempio «There are new goods for trade in Tripoli and Syria», reliquie, predicatori, eresie) lo si codifica con un vocabolario chiuso: `merci` (+commercio in regioni), `lealta`, `zelo`, `eretici`, `pieta_capo`, `tesoro`, `nessuno`. Effetti senza riscontro nel testo: nessuno. Tutto PROVVISORIO e nel file. |
| Invenzioni | Bussola (1169/1170) e polvere da sparo (1260) sono eventi senza effetto per gli Auror (armi da fuoco e caracche già disponibili, ADR-004); per le altre fazioni restano nominali finché le colonne delle invenzioni sono azzerate (dizionario). |

## 6a. Disastri (catalogo: esistono, frequenze ignote)

Messaggi da Events.txt (`floodregmes_xzy`, `famineregmes_xzy`, `plagueregmes_xzy`, `black_plagueregmes_xzy`, `quakeregmes_xzy`, `taifunregmes_xzy`). Parametri in `data/regole/eventi.cfg`, tutti PROVVISORI:

| Disastro | Regola |
|---|---|
| Inondazione | Probabilità annua per regione `p_inondazione`; non nelle regioni `SetRegionUnfloodable`; quell'anno l'agricoltura della regione è dimezzata. |
| Carestia | `p_carestia`; agricoltura a zero e lealtà −10 per un anno. |
| Terremoto | `p_terremoto`; non nelle `SetRegionUnquakeable`; un edificio casuale (non il castello) perde un livello. |
| Tempesta in mare | `p_tempesta` per flotta in mare; la flotta perde una pila. |
| Peste | `p_peste`; gli eserciti e le guarnigioni della regione perdono `perdite_peste` (10%) degli uomini; può propagarsi alle confinanti. |
| Peste Nera | Una sola volta, in un anno della finestra `peste_nera` (1346–1353, storica); per alcuni anni perdite più alte e reddito ridotto nelle regioni colpite, propagazione per confini. |

Il loader dello startpos legge `SetRegionUnfloodable` e `SetRegionUnquakeable`.

## 6a. Orda d'Oro

`FN_GOLDEN_HORDE` (o il nome dichiarato nello startpos: fazione inattiva pagana con comportamento `BARBARIAN_RAIDER`) compare nel `anno_orda` (1230, catalogo) in una regione di ingresso a est (`regioni_ingresso` in `eventi.cfg`, la prima libera o la più debole) con `pile_orda` pile delle migliori unità di cavalleria a cavallo reclutabili da quella cultura (PROVVISORIA). Finché non c'è l'IA (fase 7) segue una regola fissa: ogni anno attacca la regione confinante più ricca non sua; dopo `anni_orda` anni senza conquiste si scioglie. Le sue province diventano ribelli quando l'Orda sparisce. Eventi `EV_HORDE_ARRIVES`, `EV_HORDE_GONE`.

## 6b. Vittoria e sconfitta

| Regola | Dettaglio |
|---|---|
| Dominio | Vince la fazione del giocatore quando controlla la quota `soglia_dominio` delle province di terra: **85% per scelta di Federico** (manuale: due terzi; community: 60% o 100%; parametro in `data/regole/vittoria.cfg`). Evento `EV_VICTORY`; si può continuare a giocare. |
| Fine della campagna | Nell'anno finale (`final_year`, 1700) la partita finisce e vince chi controlla più province (a parità, reddito maggiore). Evento `EV_CAMPAIGN_END` con la classifica. |
| Sconfitta | La fazione del giocatore si estingue (nessun erede né generale di sangue reale, fase 4a) o perde tutte le province e gli eserciti: `EV_DEFEAT`, la partita finisce. |

`GameState.victory` (esito, anno, se il giocatore continua dopo la vittoria) va nei salvataggi (versione +1).

## Interfaccia

- Finestra dell'evento storico con titolo e testo originali (dall'installazione) e l'effetto in una riga; disastri, Orda e punti nel resoconto di fine anno.
- Avanzamento verso la soglia di dominio nella barra (province controllate / necessarie) e classifica delle fazioni per province (tasto G).
- Schermata di fine partita (vittoria, sconfitta, fine della campagna con la classifica); in dominio, «Continua a giocare».

## Criteri d'uscita

- Test unitari di ogni regola e del caricamento dei dati degli eventi (ogni regione citata esiste nello startpos; ogni indice di evento esiste in Events.txt sui dati reali).
- Simulazione dal 1000 al 1700 sui dati reali, deterministica, senza errori, con gli eventi storici accaduti una volta ciascuno, la Peste Nera una volta, l'Orda arrivata nel suo anno e la fine della campagna nel 1700.
