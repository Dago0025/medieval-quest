# Specifica della fase 5: agenti, diplomazia, religione, Papato

Obiettivo: il mondo politico e religioso di MTW. Le fazioni stringono alleanze e tregue tramite emissari e matrimoni; spie e assassini agiscono sulla mappa; ogni provincia ha una composizione religiosa che cambia nel tempo; il Papa ammonisce e scomunica; i cattolici bandiscono crociate e i musulmani jihad. Le regole vengono dal catalogo (§Agenti e diplomazia, §Religione e Papato); quelle senza formula sono `PROVVISORIA`, con i parametri in `data/regole/diplomazia.cfg`, `agenti.cfg`, `religione.cfg`, `papato.cfg`.

Vincoli: ADR-003, 004 (Auror integrata), 005, 008, 009, 010. Determinismo con `state.rng`. L'IA strategica è della fase 7: qui le fazioni IA **rispondono** alle proposte (accettazione PROVVISORIA) ma non prendono iniziative, salvo il Papato (avvertimenti e scomuniche, che sono regole) e i ribelli.

La fase si divide in tre blocchi in sequenza, perché toccano gli stessi file: **5a agenti e diplomazia**, **5b religione**, **5c Papato, crociate e jihad**. L'interfaccia segue ogni blocco.

## Ordine del fine anno (estende ADR-008)

1. movimento degli eserciti; **1b. agenti** (`AgentProcessor.process_year`: movimento degli agenti, missioni, cattura degli agenti nemici); 2. battaglie; 3. assedi; 4. conquiste; 5. fazioni distrutte; dinastia; province (4b); **religione** (`ReligionProcessor`, 5b); **Papato** (`PapacyProcessor`, 5c); poi reddito, costruzioni, reclutamento (gli agenti reclutati nascono qui), comandanti, calendario, **scadenza delle tregue**.

Le missioni si risolvono prima delle battaglie: un esercito corrotto o un generale assassinato cambiano lo scontro dello stesso anno.

## 5a. Diplomazia

### Stati (catalogo: alleanza, neutralità, guerra, tregua; niente vassallaggio)

`GameState` mantiene `wars` (com'è) e aggiunge `alliances` (chiave di coppia → true) e `truces` (chiave di coppia → anno di scadenza). Una coppia è in uno solo dei quattro stati; neutralità = nessuna voce. Accessi: `is_allied`, `truce_until`, `relation(a, b)` → `"guerra" | "alleanza" | "tregua" | "neutrale"`, `form_alliance`, `break_alliance`, `make_truce`, `end_war`. I ribelli restano in guerra con tutti e non entrano in trattati.

| Regola | Dettaglio |
|---|---|
| Attaccare | Come ora (ADR-009) dichiara guerra; se la coppia era alleata o in tregua il trattato si rompe e l'influenza del capo dell'attaccante scende di `malus_tradimento` (PROVVISORIA 1; catalogo: «tradire un alleato costa influenza»). Evento `EV_ALLIANCE_BROKEN` / `EV_TRUCE_BROKEN`. |
| Alleati | Le flotte alleate non bloccano le zone di mare (trasporto via mare, `sea_zone_status`); eserciti alleati nella stessa regione non combattono. Gli alleati non entrano in guerra automaticamente (scelta dell'IA, fase 7). |
| Tregua | Mette fine alla guerra per `durata_tregua` anni (PROVVISORIA 6; catalogo: durata ignota); alla scadenza la coppia torna neutrale (`EV_TRUCE_EXPIRED`). |
| Influenza | Del capo (fase 4a), entra nell'accettazione delle proposte. Auror fissa a 9. |

### Accettazione delle proposte (PROVVISORIA, catalogo: formula ignota, cala con la dimensione dell'impero)

`p = base + k_influenza·(influenza − 5) + k_valore·valore_agente + religione + dimensione + guerra`, limitata a [`p_min`, `p_max`]:
- `base`: `base_alleanza` 0,35, `base_tregua` 0,30, `base_matrimonio` 0,45;
- religione: `bonus_stessa_religione` +0,10, altrimenti `malus_religione_diversa` −0,15;
- dimensione: se le regioni di terra del proponente superano `soglia_dimensione` (0,25) del totale, `−k_dimensione·(quota − soglia)` con `k_dimensione` 2;
- guerra: per le alleanze, `−malus_guerra_alleati` 0,20 se il proponente è in guerra con un alleato del destinatario; per la tregua, `+k_forza·(Fp/(Fp+Fd) − 0,5)` con le forze totali delle due fazioni (uomini), `k_forza` 0,6.

Il giocatore che riceve proposte (dall'IA, fase 7) non è ancora previsto: le proposte al giocatore si scartano.

## 5a. Agenti

### Modello (`AgentState` esteso)

Aggiungere: `valour` (0–10, «valore»), `name`, `path` (regioni da attraversare, una per anno come gli eserciti), `sea_route`, `mission` (Dictionary vuoto o `{"tipo", "bersaglio"}`), `character_id` (solo principesse). Tipi da `UnitType.type_name`: EMISSARY, PRINCESS, SPY, ASSASSIN, BISHOP, CARDINAL, PRIEST, SHAMAN, ORTHODOX_BISHOP, MULLAH, ULAMA, INQUISITOR, GRAND_INQUISITOR (CRUSADE e JIHAD non sono agenti: 5c). Nessun mantenimento, nessuna morte per età (catalogo), salvo le principesse.

| Regola | Dettaglio |
|---|---|
| Reclutamento | `can_queue_unit` ammette i tipi agente (non PRINCESS, CRUSADE, JIHAD) con gli stessi controlli di requisiti, fazione, cultura e costo; alla fine della coda nasce un `AgentState` nella provincia. Valore iniziale `1 + (livello dell'edificio produttore − 1)` (PROVVISORIA). Nome dalla lista dei nomi della fazione. |
| Agenti iniziali | Gli emissari dello startpos hanno valore `valore_iniziale_startpos` (2, PROVVISORIA). Le principesse dello startpos diventano anche `Character` con ruolo `principessa` (anno di nascita dalla MakeUnit), collegati all'agente. |
| Principesse della dinastia | Alla maggiore età (fase 4a) una principessa riceve un agente PRINCESS nella capitale; al ritiro (32) o alla morte l'agente sparisce. Valore = acume del personaggio. |
| Movimento | Come gli eserciti: una regione di terra confinante all'anno, o via mare con la catena di zone sicure (stesse regole e funzioni del trasporto degli eserciti). Gli agenti possono entrare in territorio di altre fazioni senza dichiarare guerra e non combattono; una provincia conquistata non tocca gli agenti presenti. |
| Missioni | Ordinate su un agente con un bersaglio nella sua regione o in una confinante (l'agente ci va prima); si risolvono nel passo 1b dell'anno in cui l'agente è nella regione del bersaglio. Una missione per agente; si annulla se il bersaglio sparisce. |
| Crescita del valore | +1 (fino a 10) dopo una missione riuscita o la cattura di un agente nemico (catalogo: massimo e soglie non documentati, PROVVISORIA). |

### Missioni

| Agente | Missione | Bersaglio | Regola |
|---|---|---|---|
| Emissario | `alleanza` | fazione neutrale che possiede la regione | Accettazione come sopra; esito `EV_ALLIANCE_FORMED` o `EV_PROPOSAL_REFUSED`. |
| Emissario | `tregua` | fazione in guerra che possiede la regione o vi ha un esercito | Accettazione; se accetta: fine della guerra e tregua (`EV_TRUCE`). |
| Emissario | `corruzione` | esercito di un'altra fazione nella regione (mai quello del capo o dell'erede; catalogo) | Prezzo = Σ costo delle pile × uomini/uomini base × `k_prezzo` × (1 + lealtà comandante/10) × (1 + comando/10) (PROVVISORIA; campioni del catalogo 2.000–70.000 per tararlo). Il tesoro paga solo se l'esercito accetta: `p = 0,9 − 0,08·lealtà + 0,03·valore`, in [0,05; 0,95]. Se accetta, l'esercito e il comandante passano alla fazione dell'emissario; se era la guarnigione di un castello, passa anche la provincia. Tesoro insufficiente a fine anno = missione fallita. Esercito corrotto non dichiara guerra. |
| Principessa | `matrimonio` | fazione non in guerra che possiede la regione | Accettazione `base_matrimonio`; se accetta: alleanza (se non c'era) ed `EV_MARRIAGE`; la principessa lascia la partita. |
| Principessa | `sposa_generale` | generale della propria fazione nella regione (non capo né erede) | Lealtà del generale +`bonus_lealta_matrimonio` (2, fino a 10), il generale diventa di sangue reale (entra nella successione come principe); la principessa lascia la partita. |
| Assassino | `assassinio` | personaggio o agente di un'altra fazione nella regione | Tabella a 16 gradini del catalogo (0, 7, 10, 14, 17, 24, 34, 50, 66, 76, 83, 86, 90, 93, 95, 97%). Gradino di base: capo 4 (17%), erede/principe/generale 6 (34%), principessa 7 (50%), spia o assassino 8 (66%), religiosi 9 (76%), emissario 10 (83%). Il gradino sale di uno per ogni punto di valore dell'assassino oltre quello del bersaglio e scende per ogni punto sotto (valore del bersaglio: valore se agente, comando se personaggio); limitato a 0–15. Riuscita: il bersaglio muore (`EV_ASSASSINATION`, causa «assassinio»). Fallimento: l'assassino muore con probabilità `p_morte_fallimento` (0,5). |
| Spia | (nessun ordine) | — | Nella propria provincia: lealtà obiettivo +`bonus_lealta_spia` (5; una sola spia conta) e cattura degli agenti nemici. In una provincia altrui: lealtà obiettivo di quella provincia −`malus_lealta_spia` (5). In una provincia assediata dalla propria fazione: ogni anno probabilità `k_porte·valore` (0,05 a punto) di aprire le porte: l'assedio finisce con la conquista (`EV_GATES_OPENED`). |
| Religiosi, inquisitori | — | — | Conversione e processi nella 5b. |

### Cattura degli agenti (PROVVISORIA, catalogo: gerarchia forte di confine, spia, assassino, emissario)

Ogni anno, in ogni provincia, per ogni agente di un'altra fazione presente: il catturatore è il solo elemento di valore massimo tra il forte di confine del proprietario (`WATCH_TOWERS`, valore `2·livello`), le sue spie, i suoi assassini, i suoi emissari nella provincia. `p = clamp(base_cattura + k_cattura·(V − valore_agente), 0, p_max_cattura)` (0,10; 0,07; 0,8); spie e assassini nemici (invisibili) hanno `−malus_invisibile` 0,10. L'agente catturato muore (`EV_AGENT_CAPTURED`); il catturatore, se agente, guadagna valore. Alleati non si catturano.

### Comandi (`GameCommands`)

`order_agent_move(state, f, agent_id, path)`, `cancel_agent_move`, `order_mission(state, f, agent_id, tipo, bersaglio)`, `cancel_mission`, e le anteprime `mission_options(state, f, agent_id)` (missioni valide con bersagli, probabilità e prezzo, per l'interfaccia) e `bribe_price(state, army_id)`.

### Eventi

`EV_AGENT_RECRUITED`, `EV_AGENT_MOVED`, `EV_ALLIANCE_FORMED`, `EV_ALLIANCE_BROKEN`, `EV_TRUCE`, `EV_TRUCE_BROKEN`, `EV_TRUCE_EXPIRED`, `EV_PROPOSAL_REFUSED`, `EV_MARRIAGE`, `EV_BRIBE`, `EV_BRIBE_REFUSED`, `EV_ASSASSINATION`, `EV_ASSASSINATION_FAILED`, `EV_AGENT_CAPTURED`, `EV_GATES_OPENED`, `EV_MISSION_FAILED` (bersaglio sparito, tesoro insufficiente).

## 5b. Religione

| Regola | Dettaglio |
|---|---|
| Composizione | `ProvinceState.religions`: CATHOLIC, ORTHODOX, MUSLIM, PAGAN, HERETIC in percentuale (somma 100), più `zeal` 0–100 (zelo della religione del proprietario). Partita nuova (PROVVISORIA, i dati non hanno percentuali): 100% della religione della cultura della regione (`ProvinceRules.culture_religion`); se il proprietario ha un'altra religione, 75/25. Zelo iniziale 50. |
| Deriva | Ogni anno `deriva` punti (1) passano dalle altre religioni a quella del proprietario (catalogo: deriva lenta). |
| Edifici | Chiesa, moschea, monastero, santuario pagano: +`conv_edificio` (1); cattedrale, grande moschea: +`conv_edificio_grande` (1,5) punti all'anno alla religione dell'edificio (catalogo: 10% e 15%, interpretati come intensità; PROVVISORIA). |
| Religiosi | Ogni vescovo, sacerdote, mullah, sciamano nella provincia: +`conv_agente` (2) punti all'anno alla sua religione; cardinale, ulema, vescovo ortodosso: +`conv_agente_grande` (5) (catalogo, conflitto da verificare). Agiscono anche in province altrui. |
| Zelo | Sale con i religiosi e gli inquisitori (+2 / +5 da `unit_prod` col. 43–45 quando leggibile, altrimenti dai parametri), scende di `calo_zelo` (1) all'anno verso 50. |
| Lealtà | La penalità di religione della 4b diventa proporzionale: `penalita_religione × (100 − % religione del proprietario) / 100`. |
| Eresia | In una provincia cattolica con tassa alta (livello ≥ 3) o lealtà sotto 100, gli eretici crescono di `crescita_eresia` (1) all'anno (catalogo: eventi, tasse eccessive; PROVVISORIA); oltre `soglia_rivolta_eretica` (30%) la rivolta della 4b usa le truppe ribelli eretiche (etichetta «eretici») con probabilità doppia. |
| Inquisitori | Nella provincia: gli eretici calano di `conv_inquisitore` (3 / 6 il grande) all'anno, zelo +2 / +5. Missione `processo` su un generale, principe o agente cattolico (anche della propria fazione, anche il capo; catalogo): `p = base_processo + k_pieta·(5 − pietà)` (0,3; 0,08), in [0,05; 0,9]; riuscita: il bersaglio muore sul rogo (`EV_INQUISITION`). Un inquisitore senza eretici né processi abbassa la lealtà obiettivo della provincia di `malus_inquisitore_inattivo` (3; catalogo: «brucia la popolazione»). |

Eventi: `EV_HERETIC_REVOLT`, `EV_INQUISITION`, `EV_INQUISITION_FAILED`.

## 5c. Papato, scomunica, crociate e jihad

| Regola | Dettaglio |
|---|---|
| Papato | `FN_PAPIST`, fazione IA con capo (il Papa). La morte del Papa (dinastia 4a) revoca tutte le scomuniche (`EV_EXCOMMUNICATION_LIFTED`). Se il Papato è distrutto, riemerge negli Stati Pontifici ogni `anni_riemersione` (10) con un esercito più grande ogni volta (`k_crescita_esercito`), ignorando la soglia di lealtà (catalogo). |
| Avvertimento | Quando una fazione cattolica dichiara guerra a un'altra cattolica ed è la più grande delle due (province), il Papa la ammonisce (`EV_PAPAL_WARNING`): per `anni_avvertimento` (2) non deve attaccare quella fazione; se rispetta il termine, tra le due si impone una tregua di `durata_tregua_papale` (10) anni; se attacca, è scomunicata. Attaccare il Papato = scomunica immediata. |
| Scomunica | `FactionState.excommunicated` (e anno). Effetti: influenza −`malus_influenza` (2), lealtà obiettivo −`malus_lealta` (15) × % cattolici nelle province, alleanze con fazioni cattoliche rotte, bersaglio di crociate, nessuna crociata propria. Revoca alla morte del Papa o del capo scomunicato. |
| Crociata | Solo cattolici non scomunicati, una alla volta per fazione. Si recluta l'unità `Crusade` (requisiti e fazioni da `unit_prod`, costo 1.000, 4 anni); al termine nasce un esercito crociato (`Army.crusade`) con `pile_iniziali` (4) pile delle migliori unità cattoliche reclutabili nella provincia, senza bersaglio. Comando `set_crusade_target(state, f, army_id, region_id)`: bersaglio valido se di una fazione scomunicata, ribelle, non cattolica o a maggioranza eretica. L'esercito crociato attraversa le province altrui senza dichiarare guerra né conquistarle (catalogo), dichiara guerra solo al proprietario del bersaglio. |
| Zelo della crociata | Parte da `zelo_iniziale` (80), −`calo_zelo_anno` (5) ogni anno, −10 senza bersaglio; in una provincia cattolica attraversata recluta `pile_per_zelo` pile se lo zelo della provincia supera 60 (fino a `max_pile` 16, limite del motore). Soglie del catalogo: sotto 40 perde una pila all'anno, sotto 30 diserzioni (due pile), a 20 o meno si scioglie (`EV_CRUSADE_FAILED`). |
| Esito | Conquista del bersaglio: la provincia va alla fazione, l'esercito diventa normale, influenza +1, ricompensa di `pile_ordine` (2) pile di un ordine militare reclutabile dalla fazione (unità con requisito `CHAPTER_HOUSE`; catalogo). Distruzione o scioglimento: influenza −1. |
| Jihad | Solo musulmani (unità `Jihad`, `RIBAT`, 500, 2 anni); bersaglio solo province un tempo musulmane (`former_owner` musulmano o maggioranza musulmana); più jihad ammesse; stesse regole di zelo; riuscita +1 influenza, fallimento −2 (catalogo). |
| Doni papali | Una fazione cattolica non scomunicata con almeno `min_religiosi` (3) vescovi o sacerdoti riceve 1.000 fiorini con probabilità `p_dono` (0,05) all'anno (catalogo: trigger ignoto). |

Eventi: `EV_PAPAL_WARNING`, `EV_PAPAL_TRUCE`, `EV_EXCOMMUNICATION`, `EV_EXCOMMUNICATION_LIFTED`, `EV_CRUSADE_LAUNCHED`, `EV_CRUSADE_TARGET`, `EV_CRUSADE_RECRUITED`, `EV_CRUSADE_DESERTION`, `EV_CRUSADE_SUCCEEDED`, `EV_CRUSADE_FAILED`, `EV_JIHAD_*` (stessi), `EV_PAPAL_GIFT`, `EV_PAPACY_REEMERGED`.

## Salvataggi

Una versione per blocco (5a, 5b, 5c), con caricamento delle versioni precedenti: agenti senza valore → valore iniziale; province senza religioni → composizione della partita nuova; nessun trattato, nessuna scomunica.

## Interfaccia

- **Agenti sulla mappa**: segnalino tondo con l'iniziale del tipo (E emissario, P principessa, S spia, A assassino, V religiosi, I inquisitore) e il valore; selezione col clic; clic destro su una regione = movimento; clic destro su un bersaglio (esercito, regione di un'altra fazione, personaggio) con l'agente selezionato = menu delle missioni da `mission_options` con probabilità e prezzo.
- **Pannello della diplomazia** (tasto D): per ogni fazione viva relazione, scadenza della tregua, religione, scomunica, influenza del capo.
- **Province**: composizione religiosa, zelo ed eretici; agenti presenti; reclutamento degli agenti tra le unità.
- **Papato e crociate**: croce spezzata nella barra se scomunicati; avvertimento papale in evidenza; bersaglio della crociata o della jihad scelto col clic destro dall'esercito crociato.
- Resoconto di fine anno con gli eventi nuovi.

## Criteri d'uscita

- Test unitari di ogni regola e dei comandi.
- Simulazione di 200 anni sui dati reali con agenti e missioni casuali, deterministica e senza errori, con stato coerente: nessuna coppia alleata e in guerra, nessun trattato con i ribelli o con se stessi, agenti solo in regioni esistenti e di fazioni vive, principesse collegate a un personaggio vivo, scomunicati solo cattolici, al più una crociata per fazione, religioni di ogni provincia con somma 100.
