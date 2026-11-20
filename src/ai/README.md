# Intelligenza artificiale (fase 7a: economia e guerra; fase 7b: diplomazia, agenti, crociate)

L'IA e' un giocatore come gli altri (ADR-003, ADR-008, ADR-012): legge lo stato (`GameState`) e manda solo i comandi pubblici di
`GameCommands`, controllandone l'esito. Non ha scorciatoie e non fa parte di `TurnProcessor.end_year`: la chiama chi fa avanzare
la partita.

```
CampaignTurn.advance(state)  =  AiController.plan_year(state)  +  TurnProcessor.end_year(state)
```

`advance` restituisce lo stesso dizionario di `end_year`. L'interfaccia (`scenes/campaign_map.gd`: pulsante Fine anno e Invio) lo
chiama con la difficolta' `Settings.AI_DIFFICULTY` (`scenes/campaign_settings.gd`). La fazione del giocatore (`is_player`) non
riceve ordini; i ribelli (`FN_REBEL`) nemmeno.

## File

| File | Compito |
|---|---|
| `ai_controller.gd` | `plan_year(state, difficulty, ai_rules, keep_log)`: contesto, poi ogni fazione viva, non del giocatore, non ribelle, nell'ordine di dichiarazione. Rapporto: anno, fazioni, ordini, rifiutati, rifiuti, ms, registro. |
| `campaign_turn.gd` | `advance`: IA e fine anno; rimette a falso `ai_orders_horde`. |
| `ai_rules.gd` | Parametri letti da `data/regole/ia.cfg` (valori predefiniti identici, un test lo verifica). Non e' `rules.ai`: la carica l'IA. |
| `ai_context.gd` | Fotografia dell'anno costruita una volta: eserciti per regione, forze, mantenimento, redditi, governatori, vicini, generatore casuale (`rng_for`). |
| `ai_profiles.gd` | Profilo di base (`SetBehaviour`) e profilo effettivo dell'anno (DESPERATE_DEFENCE, POVERTY_STRICKEN, CLOSE_TO_SUPPORT_LIMIT), riserva di tesoro. |
| `ai_plan.gd` | Dati di lavoro di una fazione e di un anno; `record` conta ordini e rifiuti. |
| `ai_threat.gd` | Mappa delle minacce per provincia (forza propria, nemica, fronte, assedio, capitale). |
| `ai_force.gd` | Stima della forza con la formula di `Combat` senza casualita'. |
| `ai_policy.gd` | Chi si puo' attaccare: mai alleati, tregue, avvertimenti papali rispettati, Papato intoccabile. |
| `ai_economy.gd` | Tasse, costruzioni, riaddestramento delle pile decimate e reclutamento. |
| `ai_war.gd` | Assedi e assalti, difesa, attacco, concentrazione. |
| `ai_navy.gd` | Flotte, attacchi in mare, sbarchi. |
| `ai_staff.gd` | Comandanti e titoli di governatore. |
| `ai_diplomacy.gd` | (7b) Tregue, alleanze, nozze con emissari e principesse; tradimento degli alleati per i soli profili espansionisti. |
| `ai_agents.gd` | (7b) Reclutamento di agenti con un tetto per tipo; spie, assassini, corruzione, religiosi e inquisitori; utilita' di percorso condivise. |
| `ai_crusades.gd` | (7b) Crociate e jihad: bandire (Casa del Capitolo se manca) e scegliere il bersaglio dell'esercito crociato. |
| `ai_journeys.gd` | (ADR-053) Viaggi lunghi degli agenti: ordini di lungo periodo (`AgentState.ai_order`), obiettivi anche lontani con `AgentTravel`. |
| `ai_trade.gd` | (ADR-053) Commercio navale: zone di mare da presidiare con la formula del giocatore in ipotesi, una flotta per zona. |
| `ai_faction.gd` | L'ordine dei moduli per una fazione. |

Ordine per fazione: profilo effettivo, minacce, tasse, reclutamento, costruzioni, tradimento (`AiDiplomacy.plan_betrayal`),
ordini di viaggio in corso (`AiJourneys.continue_orders`), diplomazia (`AiDiplomacy.plan`), guerra, flotte, commercio navale
(`AiTrade.plan`), concentrazione, crociate (`AiCrusades.plan`), agenti (`AiAgents.plan`), viaggi nuovi (`AiJourneys.plan`),
comandanti e titoli (`AiStaff.consolidate` per ultimo: la fotografia dell'anno non vede i cambi fatti durante l'anno).

## Fase 7b: diplomazia, agenti, crociate

Tutto con i comandi pubblici (`order_mission`, `order_agent_move`, `queue_unit`, `queue_building`, `set_crusade_target`); i parametri
(PROVVISORI) sono nelle sezioni `[diplomazia]`, `[agenti]`, `[crociate]` di `ia.cfg`, con gli stessi valori predefiniti in `AiRules`.

- **Tregue**: una guerra «va male» se si e' persa almeno `perdite_tregua` provincia nell'ultimo anno, se il nemico assedia una
  provincia propria o se ha entro un passo una forza oltre `rapporto_tregua` volte quella propria: parte un emissario dal nemico. I
  profili non espansionisti la cercano anche senza perdere, con probabilita' annua `prob_pace`.
- **Alleanze**: con un vicino neutrale in guerra con un nostro nemico (non il Papato), probabilita' `prob_alleanza`, al massimo
  `alleanze_max` alleati, solo se la probabilita' d'accettazione stimata e' almeno `p_min_alleanza`.
- **Nozze**: la principessa libera sposa un vicino da allearsi, altrimenti (probabilita' `prob_nozze`) il generale con la lealta'
  piu' bassa (non oltre `lealta_nozze`).
- **Tradimento**: solo i profili espansionisti (non i predoni), con probabilita' `prob_tradimento`: se conviene attaccare un alleato
  senza nemici in comune (rapporto di forza sopra la soglia del profilo per `fattore_tradimento`) l'alleato va in `AiPlan.betray` e
  `AiWar` lo attacca; l'alleanza si rompe da sola attaccando (`DiplomacyProcessor.break_for_attack`). Chi si corteggia quest'anno
  (`AiPlan.courting`) non si attacca.
- **Agenti**: tetto per tipo = tetto x province (per eccesso); spie alla frontiera propria e nemica e dove si assedia, assassini
  contro i generali nemici (probabilita' almeno `p_min_assassinio`) e gli agenti stranieri nelle proprie terre, corruzione di eserciti
  deboli con una quota del tesoro oltre la riserva, religiosi dove la religione del proprietario e' minoranza, inquisitori dove gli
  eretici sono almeno `eretici_min`. Gli indici per regione stanno in `AiContext` (`characters_in`, `agents_in`).
- **Crociate e jihad**: i profili di `profili_crociati` (cattolici non scomunicati) e `profili_jihad` bandiscono con probabilita'
  `prob_crociata` se entro `raggio_crociata` passi c'e' un bersaglio valido e il tesoro oltre la riserva copre `tesoro_crociata` volte
  il costo; se manca la Casa del Capitolo (o il Ribat) la costruiscono. L'esercito crociato riceve il bersaglio con
  `set_crusade_target` (rendita, castello e rapporto di forza, divisi per la distanza).
- **Proposte al giocatore**: un'IA che manda un emissario o una principessa a un giocatore crea una proposta in attesa
  (`GameState.pending_proposals`, ADR-012) con probabilita' `prob_proposta_giocatore` e non oltre `proposte_giocatore_max` in attesa;
  il giocatore risponde con `GameCommands.answer_proposal` (finestra a inizio turno); scade a fine dell'anno dopo.


## Riaddestramento

Dentro `AiEconomy.plan_recruitment`, prima delle reclute nuove, `AiEconomy.plan_retraining(plan, budget)` riporta all'organico pieno
(`GameCommands.order_retrain`, regole in `data/regole/riaddestramento.cfg`) le pile con meno di `soglia_ia` (0,7, PROVVISORIA,
sezione `[riaddestramento]` di `ia.cfg`, `AiRules.retrain_threshold`) dell'organico degli eserciti di terra fermi nelle sue province
(`GameCommands.retrain_options`: niente mercenari, ordini militari, province assediate, eserciti in marcia). Ordine: priorita' della
provincia come per il reclutamento (minacciate prima), poi la pila piu' decimata; una pila che non ci sta nel budget si salta e si
continua con le meno costose. Il costo rientra nel budget annuo del reclutamento (`quota_truppe`) e nella spesa restituita; il limite
per provincia (`max_per_provincia`) si controlla prima, quindi nessun rifiuto. Se piu' tardi nell'anno `AiWar` muove l'esercito,
`order_move` rimborsa l'ordine. Le pile decimate restano contate in parte nel tetto delle pile (`_land_stacks`). Con
`max_per_provincia` a 0 nello stato (`rules.retrain`) il riaddestramento e' spento: e' cosi' nei mondi di prova di `ai_world.gd`
(`quiet_rules`), per non alterare i test del reclutamento; `ai_world.allow_retraining` lo riaccende (`test_ai_riaddestramento.gd`).

## Pesi dai file del gioco

I pesi dei profili non stanno in `ia.cfg` ma nei file prod: `UnitType.ai_weight(profilo)` (unit_prod colonna 14),
`BuildingType.Level.ai_weight(profilo)` (build_prod colonna 9, un gruppo per livello) e `Level.ai_influences` (colonna 10:
`{FAMIGLIA_LIVELLO(bonus)}` per livello). Un peso zero vuol dire «mai». Interpretazione PROVVISORIA delle influenze: la voce vale
se la provincia ha la famiglia indicata almeno a quel livello.

## Casualita' e determinismo

Generatore per fazione e anno: `seme_partita * 1000003 + anno * 7919 + indice_fazione * 104729 + 31337`. Non si usa `state.rng`
e non si salva: stesso stato = stessi ordini, anche dopo un caricamento. Fazioni nell'ordine di dichiarazione, province in quello
del file, eserciti per id.

## Orda e Papato

- BARBARIAN_RAIDER (compresa l'Orda d'Oro con l'IA attiva) attacca i vicini neutrali con soglia bassa, scegliendo la provincia piu' ricca.
  `AiController.plan_year` imposta `state.ai_orders_horde`: la regola fissa della 6a (`EventProcessor._horde_orders`) tace;
  senza IA vale come prima.
- POPE non attacca; REBELS non riceve ordini. Le fazioni cattoliche non attaccano il Papato e rispettano gli avvertimenti
  (`PapacyProcessor`), salvo i profili aggressivi gia' scomunicati.

## Tempo

`budget_ms` (ia.cfg) e' il tempo massimo per pianificare un anno di tutte le fazioni sui dati reali (`test_ai_reale.gd` lo
stampa e lo controlla). Cache: `AiEconomy._option_cache` (unita' reclutabili) e le liste per fazione di `UnitTable`.

## Taratura

Tutti i numeri di `ia.cfg` sono PROVVISORI (il catalogo non descrive la logica dell'IA). `test_ai_partita_lunga.gd` gioca 1000-1700
con tutte le fazioni e stampa ogni 50 anni province, guerre, conquiste, tesori, eserciti e uomini. Dalla 7b la stessa partita stampa anche alleanze,
tregue, nozze, corruzioni, assassinii, crociate e jihad (in vigore e cumulati). Fuori dalla 7b: ricerca del giocatore da parte dell'IA.

- 2026-11-09: guarnigione volontaria in `AiWar._barricade` (dopo i rinforzi di `_defence`), soglia `[guerra] soglia_barricata` in `data/regole/ia.cfg`.
