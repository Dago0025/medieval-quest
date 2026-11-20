# Specifica della fase 7: intelligenza artificiale

Obiettivo: le fazioni del computer giocano. Costruiscono, reclutano, difendono e attaccano, stringono e rompono trattati, mandano agenti, bandiscono crociate e jihad; l'Orda e i predoni razziano; il Papa si difende. L'IA è un **giocatore come gli altri**: legge lo stato e invia solo comandi (`GameCommands`), senza regole proprie né scorciatoie (ADR-003, ADR-008, ADR-012).

Fonti: catalogo §Intelligenza artificiale (poche osservazioni: rifiuta spesso tregue e nozze, offre principesse, attacca sentendo debolezza, lancia crociate; nessuna logica documentata). I dati del gioco danno però le **personalità** e i loro **pesi**:
- `SetBehaviour` dello startpos (già letto in `CampaignData.Faction.behaviour`): CATHOLIC_EXPANSIONIST_CRUSADER, CATHOLIC_EXPANSIONIST, CATHOLIC_NAVAL_EXPANSIONIST, CATHOLIC_ISOLATIONIST, CATHOLIC_TRADER, CATHOLIC_CRUSADER_TRADER, CATHOLIC_DEFENSIVE_CRUSADER, CATHOLIC_DEFENSIVE, ORTHODOX_EXPANSIONIST, ORTHODOX_STAGNANT, ORTHODOX_DEFENSIVE, MUSLIM_EXPANSIONIST, MUSLIM_PEACEFUL, MUSLIM_DEVOUT, POPE, BARBARIAN_RAIDER, REBELS; più tre profili di stato che «vari fattori di gioco» attivano (commento dello startpos): POVERTY_STRICKEN, DESPERATE_DEFENCE, CLOSE_TO_SUPPORT_LIMIT.
- `unit_prod` colonna 14 «Unit choices (AI)»: pesi `COMPORTAMENTO(peso)` per profilo per ogni unità.
- `build_prod` colonna 9 «Preferenze produzione AI» (`COMPORTAMENTO(peso)`) e colonna 10 «Influenze per combinazioni» (`{IMPROVED_FARMLAND(50)}`).

Tutto ciò che non sta nei dati (aggressività, soglie di forza, budget) è PROVVISORIO e in `data/regole/ia.cfg`, per profilo.

## Architettura

- `AiController.plan_year(state)`: per ogni fazione viva non del giocatore e non ribelle, in ordine di dichiarazione, `AiFaction.plan(state, faction_id)` impartisce gli ordini dell'anno con i comandi pubblici. **Non è dentro `TurnProcessor.end_year`**: la chiama chi fa avanzare la partita (`CampaignTurn.advance(state)` = IA poi fine anno, usata dall'interfaccia e dalle partite automatiche dei test). I test esistenti della simulazione non cambiano.
- Casualità dell'IA: un generatore proprio per fazione e anno, con seme derivato da seme della partita, anno e id della fazione; non consuma `state.rng` e non va salvato (stesso stato = stesse decisioni, anche dopo un caricamento).
- Profilo effettivo dell'anno: il comportamento dello startpos, sostituito da POVERTY_STRICKEN (tesoro sotto zero o reddito netto negativo), DESPERATE_DEFENCE (forze molto inferiori a un nemico confinante) o CLOSE_TO_SUPPORT_LIMIT (mantenimento oltre una quota del reddito), con soglie in `ia.cfg`.
- Prestazioni: pianificare l'anno di tutte le fazioni sui dati reali sotto `budget_ms` (200 ms; misurato in un test).

## 7a. Economia e guerra

| Modulo | Regola (PROVVISORIA salvo dove indicato) |
|---|---|
| Tasse | Normale; alta se la lealtà ha margine; bassa nelle province vicine alla rivolta. |
| Costruzioni | Coda vuota → l'edificio costruibile col punteggio più alto: peso della col. 9 per il profilo, più le influenze della col. 10 per gli edifici già presenti, più i bisogni (castello nelle province di frontiera minacciate, lealtà, reddito), diviso per costo e tempo. Mai sotto una riserva di tesoro per il reclutamento. |
| Reclutamento | Budget annuo = quota del reddito netto per profilo; mantenimento totale entro un tetto; unità scelte con i pesi della col. 14 per il profilo tra quelle reclutabili nella provincia; le province minacciate prima. |
| Mappa delle minacce | Per ogni provincia: forza propria (guarnigione ed eserciti) e forza nemica entro un passo (eserciti di fazioni in guerra, o non alleate per i profili espansionisti). |
| Difesa | Le province di frontiera minacciate ricevono rinforzi dagli eserciti interni; la capitale non resta mai sguarnita; un assedio subito richiama i soccorsi vicini. |
| Attacco | Bersagli confinanti (anche via mare con i trasporti per i profili navali): province ribelli, di fazioni in guerra, poi di neutrali deboli per i profili espansionisti. Si attacca se il rapporto di forza stimato (la stessa formula di `Combat`, senza casualità) supera la soglia del profilo; mai alleati né fazioni in tregua; un avvertimento papale si rispetta salvo profili aggressivi a scomunica già subita. Assalto ai castelli quando il rapporto lo consente, altrimenti assedio. |
| Flotte | Le fazioni con porti tengono flotte sulle zone di mare vicine per i trasporti e contro le flotte nemiche. |
| Comandanti e titoli | Il generale migliore comanda l'esercito più grande; titoli ai generali leali nelle province più ricche. |
| BARBARIAN_RAIDER | Attacca sempre la provincia confinante più ricca; per l'Orda d'Oro sostituisce la regola fissa della 6a quando l'IA è attiva. |
| POPE | Difende Roma e le sue province, non attacca (gli avvertimenti e le scomuniche restano regole della 5c). |
| REBELS | Nessun ordine (le rivolte sono regole della 4b). |

## 7b. Diplomazia, agenti, religione

| Modulo | Regola (PROVVISORIA) |
|---|---|
| Diplomazia | Emissari verso i vicini neutrali che hanno un nemico comune (alleanza), verso i nemici più forti quando si perde (tregua); principesse a nozze con fazioni con cui si vuole un'alleanza, o con i propri generali meno leali; rottura delle alleanze quando conviene attaccare l'alleato (solo profili espansionisti). |
| Proposte al giocatore | Le missioni dell'IA verso la fazione del giocatore (alleanza, tregua, matrimonio) creano una proposta in `GameState.pending_proposals` invece del rifiuto automatico; l'interfaccia la mostra a inizio turno; `GameCommands.answer_proposal(state, f, id, accetta)`; senza risposta scade a fine anno. Salvata. |
| Agenti | Spie nelle province di frontiera proprie e nemiche; assassini contro i generali nemici più forti e gli agenti nemici nelle proprie terre; corruzione di eserciti nemici deboli e ricchi; religiosi dove la religione del proprietario è minoritaria; inquisitori dove crescono gli eretici; un numero massimo di agenti per tipo in proporzione alle province. |
| Crociate e jihad | I profili crociati costruiscono la Chapter House e bandiscono crociate contro i bersagli validi più vicini; MUSLIM_DEVOUT ed espansionisti musulmani fanno jihad per riprendere province ex musulmane. |
| Difficoltà | `difficolta` in `ia.cfg` (facile, normale, difficile, molto difficile): scala aggressività, budget e soglie d'attacco; nessun bonus di risorse (catalogo: a difficoltà alte nemici più astuti, senza numeri). |

## Salvataggi

`pending_proposals` (7b) in una versione nuova; l'IA non ha altro stato.

## Interfaccia

- «Fine anno» chiama `CampaignTurn.advance` (IA, poi fine anno).
- Finestra delle proposte ricevute (accetta / rifiuta) a inizio turno.
- Nel resoconto: azioni rilevanti delle altre fazioni (guerre dichiarate, conquiste, alleanze, crociate), già coperte dagli eventi esistenti.
- Impostazione della difficoltà in `scenes/campaign_settings.gd` fino al menu della fase 8.

## Criteri d'uscita

- Test unitari di ogni modulo su mondi di prova (scelte attese in situazioni costruite: costruisce, recluta entro budget, difende la frontiera, attacca il più debole, non attacca alleati, rispetta le tregue, propone e risponde).
- Test sui dati reali: pianificazione di un anno entro il budget di tempo; partita IA contro IA dal 1000 al 1700 deterministica, senza errori e con stato coerente, che stampa le metriche per la taratura (province per fazione ogni 50 anni, guerre, alleanze, crociate, tesori, eserciti) e verifica che la mappa cambi (almeno N passaggi di provincia), che nessuna fazione accumuli un tesoro assurdo e che gli eserciti restino entro il mantenimento.
