class_name GameState
extends RefCounted
## Stato di una partita: tutto cio' che cambia da un anno all'altro, piu' i riferimenti
## ai dati statici (campagna, tabelle unita' ed edifici, regole), che non si salvano.
##
## Il generatore casuale (`rng`) e' conservato nello stato e nei salvataggi; dalla fase 3 lo
## usano gli scontri (`Combat`), in un ordine fisso: l'ordine dei sorteggi fa parte delle regole.

## Tipi di evento nel registro dell'anno (`events`, voci Dictionary con "tipo" e "anno"):
const EV_BUILT := "costruzione_completata"
const EV_RECRUITED := "reclutamento_completato"
## Coda di reclutamento ripetuta: in pausa per mancanza di fondi, ripresa, unita' tolta perche' non piu' reclutabile.
const EV_QUEUE_PAUSED := "coda_in_pausa"
const EV_QUEUE_RESUMED := "coda_ripresa"
const EV_QUEUE_DROPPED := "coda_unita_tolta"
## Unione di eserciti ordinata trascinandoli uno sull'altro: riuscita all'arrivo, o mancata (bersaglio partito, troppe pile).
const EV_ARMIES_MERGED := "eserciti_uniti"
const EV_MERGE_FAILED := "unione_mancata"
## Esercito trascinato su un proprio castello confinante: all'arrivo si barrica con le unita' che ci stanno, o non ci riesce.
const EV_ARMY_GARRISONED := "barricato_all_arrivo"
const EV_GARRISON_FAILED := "barricata_mancata"
const EV_NEGATIVE_TREASURY := "tesoro_negativo"
const EV_MOVED := "movimento"
## Obsoleto dalla fase 3: non viene piu' prodotto (gli attacchi ora si risolvono). La costante
## resta perche' l'interfaccia la conosce ancora.
const EV_PENDING_CONFLICT := "conflitto_in_sospeso"
## Eventi della fase 3 (spec. fase 3 §5). Ognuno ha almeno "tipo", "anno", "fazione",
## "regione" e "testo" (italiano, leggibile), piu' i dettagli propri.
const EV_WAR_DECLARED := "guerra_dichiarata"
const EV_BATTLE := "battaglia"
## ADR-056: un ammiraglio sale di stella dopo una vittoria navale: "esercito", "regione", "nome", "stelle".
const EV_ADMIRAL_PROMOTED := "ammiraglio_promosso"
const EV_RETREAT := "ritirata"
const EV_CAPTURED_UNITS := "unita_catturate"
## ADR-073: prigionieri presi, riscatto chiesto, liberati, riscattati, riscatto rifiutato, giustiziati (campo «esito»).
const EV_PRISONERS := "prigionieri"
const EV_SIEGE_STARTED := "assedio_iniziato"
const EV_SIEGE_ENDED := "assedio_terminato"
const EV_ASSAULT := "assalto"
const EV_SALLY := "sortita"
const EV_STARVED := "resa_per_fame"
const EV_PROVINCE_CAPTURED := "provincia_conquistata"
const EV_FACTION_DESTROYED := "fazione_distrutta"
## Trasporto via mare interrotto al momento del movimento (spec. fase 3 §9): l'esercito resta dov'e'.
const EV_TRANSPORT_BLOCKED := "trasporto_interrotto"

## Eventi della fase 4a (spec. fase 4 §4a). Ognuno ha almeno "tipo", "anno", "fazione", "regione" e
## "testo" (italiano, leggibile), piu' i dettagli propri ("personaggio" = id, "nome", "ruolo"...).
## "anno" e' l'anno in cui si chiama il fine anno; le eta' si contano all'anno dopo.
const EV_BIRTH := "nascita"
const EV_COMING_OF_AGE := "maggiore_eta"
const EV_DEATH := "morte"
const EV_SUCCESSION := "successione"
const EV_FACTION_EXTINCT := "fazione_estinta"
const EV_HERO_APPEARS := "eroe_compare"
const EV_VNV_GAINED := "vnv_acquisito"
const EV_TITLE_CHANGED := "titolo_cambiato"
const EV_STAR_CHANGED := "stella_cambiata"
const EV_OFFICE_CHANGED := "carica_cambiata"   ## carica di Stato: "azione" (assegnato, revocato, ceduto, perso), "edificio", "carica"

## Eventi della fase 4b (spec. fase 4 §4b). Hanno "tipo", "anno", "fazione", "regione" e "testo" (italiano, leggibile),
## piu' i dettagli propri. Quelli che creano uomini (rivolta, propagazione, riemersione) li dichiarano in "uomini".
## EV_LOYALTY_LOW: "provincia", "lealta", "obiettivo", "soglia"; EV_REBELLION e EV_REBELLION_SPREAD: "provincia",
## "lealta", "tipo_ribelli" (contadini, banditi, musulmani...), "esercito", "uomini" (spread: anche "origine");
## EV_FACTION_REEMERGED: "provincia", "capo", "eserciti", "uomini" (creati, 0 se ha preso eserciti ribelli);
## EV_CIVIL_WAR: "motivo", "promotore", "generali", "eserciti", "province", "uomini" (passati ai ribelli).
## EV_LOYALISTS_RETURN (ADR-070): "provincia", "eserciti", "uomini" (0: gli eserciti c'erano gia'), "precedente" (ribelli).
const EV_LOYALTY_LOW := "lealta_bassa"
const EV_REBELLION := "rivolta"
const EV_REBELLION_SPREAD := "rivolta_propagata"
const EV_FACTION_REEMERGED := "fazione_riemersa"
const EV_CIVIL_WAR := "guerra_civile"
const EV_LOYALISTS_RETURN := "lealisti_consegnano"

## Eventi della fase 5a (spec. fase 5 §5a). Hanno "tipo", "anno", "fazione", "regione" ("" se non c'e') e "testo"
## (italiano, leggibile), piu' i dettagli propri. Gli eventi sugli agenti portano "agente" (id) e "tipo_agente".
## EV_AGENT_RECRUITED: "provincia", "agente", "valore" (e "origine": "coda" o "principessa");
## EV_AGENT_MOVED: "da", "a" (e "via_mare", "catena"); EV_ALLIANCE_FORMED / EV_TRUCE / EV_PROPOSAL_REFUSED:
## "con" (l'altra fazione), "agente", "probabilita" (EV_TRUCE: "fino_al" = anno di scadenza); EV_ALLIANCE_BROKEN /
## EV_TRUCE_BROKEN: "con", "influenza_persa"; EV_TRUCE_EXPIRED: "con"; EV_MARRIAGE: "con" (fazione sposata, "" per
## la sposa generale), "personaggio" (generale o principessa), "nuova_alleanza"; EV_BRIBE / EV_BRIBE_REFUSED:
## "esercito", "con" (fazione dell'esercito), "prezzo", "provincia" (solo se passa anche la provincia);
## EV_ASSASSINATION / EV_ASSASSINATION_FAILED: "bersaglio_tipo" ("personaggio" o "agente"), "bersaglio", "nome",
## "probabilita" (e "assassino_morto" nel fallimento); EV_AGENT_CAPTURED: "fazione" (chi cattura), "con" (fazione
## dell'agente), "agente" (il catturato), "catturatore" (testo), "catturatore_agente" (id, 0 = forte di confine);
## EV_GATES_OPENED: "assediata"; EV_MISSION_FAILED: "missione", "motivo".
const EV_AGENT_RECRUITED := "agente_reclutato"

## Eventi della fase 7b (proposte dell'IA al giocatore). Hanno "tipo", "anno", "fazione" (chi propone), "con" (il destinatario),
## "regione", "testo" (italiano). EV_PROPOSAL_RECEIVED: "id" della proposta, "missione" ("alleanza", "tregua", "matrimonio"),
## "agente", "tipo_agente", "scadenza" (ultimo anno per rispondere); EV_PROPOSAL_EXPIRED: "id", "missione", "motivo"
## ("scaduta", "agente", "proponente"). Rispondere (`GameCommands.answer_proposal`) produce gli eventi di sempre
## (EV_ALLIANCE_FORMED, EV_TRUCE, EV_MARRIAGE o EV_PROPOSAL_REFUSED).
const EV_PROPOSAL_RECEIVED := "proposta_ricevuta"
const EV_PROPOSAL_EXPIRED := "proposta_scaduta"
const EV_AGENT_MOVED := "agente_mosso"
## Viaggio di un agente verso una provincia lontana interrotto (2026-11-13): "verso", "testo"; l'agente resta dov'e'.
const EV_AGENT_JOURNEY_STOPPED := "viaggio_interrotto"
const EV_ALLIANCE_FORMED := "alleanza_stipulata"
const EV_ALLIANCE_BROKEN := "alleanza_rotta"
const EV_TRUCE := "tregua"
const EV_TRUCE_BROKEN := "tregua_rotta"
const EV_TRUCE_EXPIRED := "tregua_scaduta"
const EV_PROPOSAL_REFUSED := "proposta_rifiutata"
const EV_MARRIAGE := "matrimonio"
const EV_BRIBE := "corruzione"
const EV_BRIBE_REFUSED := "corruzione_rifiutata"
const EV_ASSASSINATION := "assassinio"
const EV_ASSASSINATION_FAILED := "assassinio_fallito"
const EV_AGENT_CAPTURED := "agente_catturato"
const EV_GATES_OPENED := "porte_aperte"
const EV_MISSION_FAILED := "missione_fallita"
## Missioni delle spie (18/11/2026): EV_SPY_REPORT "bersaglio_tipo" ("provincia"/"esercito"), "bersaglio", "fino_al";
## EV_UNREST "provincia", "lealta", "fino_al"; EV_SABOTAGE "provincia", "edificio", "livello" (nuovo livello).
const EV_SPY_REPORT := "spionaggio"
const EV_UNREST := "malcontento"
const EV_SABOTAGE := "sabotaggio"

## Eventi della fase 5b (spec. fase 5 §5b). Hanno "tipo", "anno", "fazione", "regione" e "testo" (italiano, leggibile).
## EV_HERETIC_REVOLT (si aggiunge a EV_REBELLION nello stesso anno): "provincia", "eretici" (% nella provincia), "esercito",
## "uomini"; EV_INQUISITION / EV_INQUISITION_FAILED (processo dell'inquisitore): "agente", "tipo_agente", "bersaglio_tipo"
## ("personaggio" o "agente"), "bersaglio" (id), "nome", "con" (fazione del bersaglio), "pieta", "probabilita"; in
## EV_INQUISITION la causa di morte del bersaglio e' "rogo".
const EV_HERETIC_REVOLT := "rivolta_eretica"
const EV_INQUISITION := "inquisizione"
const EV_INQUISITION_FAILED := "inquisizione_fallita"

## Eventi della fase 5c (spec. fase 5 §5c). Hanno "tipo", "anno", "fazione", "regione" ("" se non c'e') e "testo"
## (italiano, leggibile), piu' i dettagli propri. Crociate e jihad usano gli stessi eventi, distinti dal campo "genere"
## ("crociata" o "jihad"); gli eventi dell'esercito crociato portano anche "esercito" (id).
## EV_PAPAL_WARNING: "contro" (la fazione che non va attaccata), "fino_al" (ultimo anno dell'avvertimento);
## EV_PAPAL_TRUCE: "con", "fino_al" (anno di scadenza della tregua); EV_EXCOMMUNICATION: "motivo"
## ("attacco_al_papato" o "attacco_durante_avvertimento"), "influenza_persa", "alleanze_rotte" (fazioni);
## EV_EXCOMMUNICATION_LIFTED: "motivo" ("morte_del_papa", "morte_del_capo", "papato_distrutto", "fazione_distrutta");
## EV_CRUSADE_LAUNCHED: "genere", "provincia", "esercito", "pile", "zelo";
## EV_CRUSADE_TARGET: "genere", "esercito", "bersaglio" ("" = tolto), "proprietario", "motivo" (se il bersaglio cade);
## EV_CRUSADE_RECRUITED: "genere", "esercito", "provincia", "pile", "zelo_provincia";
## EV_CRUSADE_DESERTION: "genere", "esercito", "pile" (perse), "zelo", "motivo" ("perdite" o "diserzione");
## EV_CRUSADE_SUCCEEDED: "genere", "esercito", "bersaglio", "influenza", "pile_ordine", "unita_ordine";
## EV_CRUSADE_FAILED: "genere", "esercito", "motivo" ("scioglimento", "distrutto", "senza_pile", "perso", "scomunica"),
## "influenza" (variazione, <= 0); EV_PAPAL_GIFT: "importo", "religiosi";
## EV_PAPACY_REEMERGED: "provincia", "capo", "esercito", "pile", "riemersioni".
const EV_PAPAL_WARNING := "avvertimento_papale"
const EV_PAPAL_TRUCE := "tregua_papale"
const EV_EXCOMMUNICATION := "scomunica"
const EV_EXCOMMUNICATION_LIFTED := "scomunica_revocata"
const EV_CRUSADE_LAUNCHED := "crociata_bandita"
const EV_CRUSADE_TARGET := "crociata_bersaglio"
const EV_CRUSADE_RECRUITED := "crociata_reclutamento"
const EV_CRUSADE_DESERTION := "crociata_diserzione"
const EV_CRUSADE_SUCCEEDED := "crociata_riuscita"
const EV_CRUSADE_FAILED := "crociata_fallita"
const EV_PAPAL_GIFT := "dono_papale"
const EV_PAPACY_REEMERGED := "papato_riemerso"
## ADR-114: primo approdo di una fazione straniera nelle Americhe ("fazione", "regione", "provincia").
const EV_AMERICAS_CONTACT := "contatto_americhe"
## ADR-114: il capo riceve la guardia ("fazione", "regione", "personaggio", "unita", "esercito", "uomini" creati).
const EV_ROYAL_GUARD := "guardia_del_capo"

## Eventi della fase 6a (spec. fase 6 §6a). Hanno "tipo", "anno", "fazione", "regione" ("" se non c'e') e "testo" (italiano,
## leggibile), piu' i dettagli propri. Testo e titolo originali di un evento storico si leggono da Events.txt con `EventTexts`.
## EV_HISTORICAL: "indice" (0-70, ordine di Events.txt), "chiave", "effetto" (merci, lealta, zelo, eretici, pieta_capo, tesoro,
## nessuno), "valore", "regioni" (colpite), "fazioni" (colpite), "provvisoria";
## EV_FLOOD / EV_FAMINE: "provincia", "proprietario" (EV_FAMINE anche "lealta_persa"); EV_QUAKE: "provincia", "proprietario",
## "edificio" ("" se non ce n'era uno da colpire), "livello" (dopo il danno); EV_STORM: "esercito", "uomini" (persi), "pile" (1);
## EV_PLAGUE: "provincia", "proprietario", "uomini" (persi), "eserciti" (toccati), "origine" ("" o la provincia da cui si e'
## propagata), "peste_nera" (vero se e' un'ondata della Peste Nera); EV_BLACK_DEATH (una sola volta): "regioni" (iniziali),
## "anno_inizio"; EV_HORDE_ARRIVES: "provincia", "eserciti" (id), "pile", "uomini" (creati); EV_HORDE_GONE: "motivo"
## ("senza_conquiste" o "distrutta"), "province" (passate ai ribelli), "eserciti" (sciolti), "uomini" (persi).
const EV_HISTORICAL := "evento_storico"
const EV_FLOOD := "inondazione"
const EV_FAMINE := "carestia"
const EV_QUAKE := "terremoto"
const EV_STORM := "tempesta"
const EV_PLAGUE := "peste"
const EV_BLACK_DEATH := "peste_nera"
const EV_HORDE_ARRIVES := "orda_arrivata"
const EV_HORDE_GONE := "orda_sciolta"

## Eventi della fase 6b (spec. fase 6 §6b). Hanno "tipo", "anno" (l'anno raggiunto dopo il fine anno), "fazione", "regione" ("" )
## e "testo" (italiano, leggibile). EV_VICTORY (dominio, una volta): "province", "necessarie", "totale", "quota", "soglia";
## EV_DEFEAT: "motivo" ("estinta" o "senza_province"); EV_CAMPAIGN_END: "fazione" e "vincitore" (prima in classifica),
## "giocatore" (id della fazione del giocatore, "" se non c'e'), "posizione_giocatore" (0 se fuori classifica), "classifica"
## (righe di `VictoryProcessor.standings`).
const EV_VICTORY := "vittoria"
const EV_DEFEAT := "sconfitta"
const EV_CAMPAIGN_END := "fine_campagna"

## Riaddestramento delle unita' (vedi `RetrainProcessor`). EV_RETRAINED (fine anno): "fazione", "provincia", "regione" (= la
## provincia), "esercito", "pile" (numero), "unita" (id, una per pila), "uomini" (aggiunti: il conto degli uomini dei test lo
## usa), "costo" (pagato); EV_RETRAIN_CANCELLED (ordini che a fine anno non si applicano, rimborsati): gli stessi campi piu'
## "rimborso" e "motivo" ("esercito_perso", "esercito_mosso", "provincia_persa", "pila_cambiata"). Annullare con un comando
## (cancel_retrain, muovere, dividere o unire) non genera eventi: il registro dell'anno si svuota all'inizio del fine anno.
const EV_RETRAINED := "riaddestramento"
const EV_RETRAIN_CANCELLED := "riaddestramento_annullato"
## Fase 8d: mercenari assoldati ("fazione", "provincia", "unita", "uomini", "costo", "esercito").
const EV_MERCENARY_HIRED := "mercenari_assoldati"
## Luoghi leggendari (26/11/2026): "luogo" (id), "regione"; EV_SITE_EVENT anche "evento", "titolo", "esito" (righe dei
## risultati), "scelta" (id della scelta in attesa del giocatore, 0 = nessuna), "opzione" (scelta fatta, -1 = nessuna).
const EV_SITE_DISCOVERED := "luogo_conquistato"
const EV_SITE_EVENT := "luogo_evento"
const EV_SITE_TRANSIT := "luogo_transito"

## Fazione dei ribelli: in guerra con tutti.
const REBEL := "FN_REBEL"
## Fazione del Papato (fase 5c): il suo capo e' il Papa.
const PAPAL := "FN_PAPIST"

## Stati diplomatici di una coppia (`relation`): una coppia e' in uno solo.
const REL_WAR := "guerra"
const REL_ALLIANCE := "alleanza"
const REL_TRUCE := "tregua"
const REL_NEUTRAL := "neutrale"

# --- dati statici (non salvati) ---------------------------------------------
var campaign: CampaignData
var units: UnitProdLoader.UnitTable
var buildings: BuildingProdLoader.BuildingTable
var rules: Rules
## Nomi, re ed eroi famosi (file dei nomi); null = nomi di riserva e nessun re o eroe famoso.
var heroes: HeroesData

# --- stato dinamico ---------------------------------------------------------
var year := 1000
var final_year := 1700
var era := "EARLY"
var seed_value := 0
## Scenario della partita (ADR-068): "auror" (modalita' Auror) o "storico"; "" = non indicato (partite dei test, salvataggi
## di prima: Auror). Lo legge il menu per caricare i dati giusti prima del salvataggio.
var scenario := ""
var rng := RandomNumberGenerator.new()
var factions: Array[FactionState] = []      ## ordine di dichiarazione
var provinces: Array[ProvinceState] = []    ## regioni di terra, ordine di dichiarazione
var armies: Array[Army] = []                ## eserciti e flotte, in ordine di id
var agents: Array[AgentState] = []
## Fase 4a: personaggi (vivi e morti), in ordine di id. Un mondo senza dati dei capi non ne ha.
var characters: Array[Character] = []
var events: Array[Dictionary] = []          ## registro dell'ultimo fine anno
## Guerre in corso: chiave "A|B" (A < B, vedi `war_key`) -> anno dell'ultima svolta (dichiarazione o ultima provincia passata
## di mano tra i due: `mark_war_turn`), che misura la stanchezza della guerra. I ribelli sono in guerra con tutti senza comparire qui.
var wars := {}
## Fase 5a: alleanze (stessa chiave delle guerre -> true) e tregue (chiave -> anno di scadenza: scade nel fine
## anno in cui l'anno nuovo la raggiunge). Una coppia e' in uno solo degli stati guerra, alleanza, tregua;
## neutralita' = nessuna voce. I ribelli non entrano in trattati.
var alliances := {}
var truces := {}
## Fase 7b: proposte dell'IA alla fazione di un giocatore in attesa di risposta (emissari e principesse arrivati a destinazione).
## Ogni voce: {"id", "da" (chi propone), "a" (il giocatore), "tipo" ("alleanza", "tregua", "matrimonio"), "agente" (id dell'agente che
## aspetta), "regione" (dove), "anno" (di nascita), "scadenza" (ultimo anno in cui si puo' rispondere)}, in ordine di id. Salvate.
var pending_proposals: Array[Dictionary] = []
var next_proposal_id := 1
## ADR-073: prigionieri in attesa di una decisione (vedi PrisonerProcessor), in ordine di id. Salvati.
var prisoners: Array[Dictionary] = []
var next_prisoner_id := 1
## Luoghi leggendari (LegendarySiteProcessor): stato per luogo, scelte del giocatore in attesa, luoghi scoperti sulla
## mappa per fazione (id -> PackedStringArray). Salvati.
var sites_state := {}
var site_choices: Array[Dictionary] = []
var next_site_choice_id := 1
var sites_discovered := {}
## Fase 5c: avvertimenti papali in corso. Chiave "CHI>CONTRO" (la fazione ammonita e quella che non deve attaccare)
## -> {"anno": anno dell'avvertimento, "scadenza": ultimo anno in cui un attacco porta alla scomunica}.
var papal_warnings := {}
## Fase 5c: id del Papa (capo di `PAPAL`) all'ultimo controllo, 0 = nessuno; se cambia le scomuniche cadono.
var papal_leader := 0
## Fase 5c: anni consecutivi in cui il Papato e' distrutto e riemersioni gia' avvenute (esercito piu' grande a ogni volta).
var papacy_dead_years := 0
## ADR-114: anno dell'arrivo degli europei nelle Americhe (0 = non ancora; da allora Aztechi, Inca e Cahokia hanno i cavalli).
var americas_contact_year := 0
var papacy_reemergences := 0
## Fase 5c (non salvato): esercito crociato -> {"fazione", "tipo"} all'inizio del fine anno, per riconoscere quelli distrutti.
var crusade_roster := {}
## Fase 6a: eventi storici gia' accaduti (indice -> anno in cui sono accaduti) e anno estratto per ciascuno (indice -> anno,
## deciso la prima volta che il fine anno li guarda: per le finestre con `state.rng`). Un evento accade una volta sola,
## nell'anno estratto.
var historical_done := {}
var historical_years := {}
## Fase 6a: Peste Nera. {} = mai cominciata; altrimenti "anno" (di inizio), "colpite" (regione -> anni di contagio che restano),
## "guarite" (regioni gia' passate: non si ripetono), "anni" (anni trascorsi dall'inizio), "finita" (bool).
var black_death := {}
## Fase 6a: Orda d'Oro. {} = non ancora arrivata; altrimenti "stato" ("attiva" o "sciolta"), "arrivo" (anno), "ingresso"
## (regione), "senza_conquiste" (anni di fila), "conquiste" (province prese in tutto).
var horde := {}
## Fase 6b: esito della partita (vittoria per dominio, sconfitta, fine della campagna), anno, classifica e scelta di continuare.
var victory := VictoryState.new()
## Riaddestramento: ordini in attesa del fine anno, in ordine di emissione. Ogni voce: {"esercito" (id), "fazione", "provincia",
## "pila" (indice nell'esercito alla data dell'ordine), "unita" (id), "uomini" (della pila alla data dell'ordine), "costo" (pagato),
## "anno" (dell'ordine)}. Salvati (versione 11).
var retrain_orders: Array[Dictionary] = []
## Fase 8d: compagnie di mercenari in attesa d'ingaggio, per provincia: id -> Array di {"unita", "uomini", "valore", "anni"}
## ("anni" = da quanto tempo la compagnia e' in giro). Salvate (versione 13).
var mercenaries := {}
## Assedi in corso: id della regione assediata -> SiegeState. Per scorrerli in ordine fisso
## usare `sieges_in_order()`.
var sieges := {}
var next_army_id := 1
var next_agent_id := 1
var next_character_id := 1
## Fase 4a: numerali dei re. Fazione -> Array di int: per ogni nome reale (indice) i re gia'
## incoronati con quel nome, compreso il re in carica ("Darkos I" = 1).
var royal_counters := {}
## Fase 4a: eroi famosi gia' comparsi o scartati (chiave di `GameSetup.hero_key`) -> true.
var heroes_done := {}
## Anomalie dei dati trovate all'avvio (token sconosciuti e simili).
var setup_errors := PackedStringArray()
## Fase 7 (non salvato): vero quando l'IA ha dato gli ordini dell'anno (`AiController.plan_year`): l'Orda d'Oro non segue piu' la
## regola fissa della 6a (`EventProcessor._horde_orders`) perche' la guida l'IA (profilo BARBARIAN_RAIDER). `CampaignTurn.advance`
## lo rimette a falso dopo il fine anno; un fine anno chiamato da solo (test della 6a) lo trova falso.
var ai_orders_horde := false

var _faction_by_id := {}
var _province_by_id := {}
var _character_by_id := {}
var _leader_cache := {}
var _commander_cache := {}


func _init(campaign_data: CampaignData = null, unit_table: UnitProdLoader.UnitTable = null, building_table: BuildingProdLoader.BuildingTable = null, rule_set: Rules = null) -> void:
	campaign = campaign_data
	units = unit_table
	buildings = building_table
	rules = rule_set if rule_set != null else Rules.new()


func add_faction(f: FactionState) -> void:
	factions.append(f)
	_faction_by_id[f.id] = f


func add_province(p: ProvinceState) -> void:
	provinces.append(p)
	_province_by_id[p.id] = p


func faction(faction_id: String) -> FactionState:
	return _faction_by_id.get(SimUtil.norm(faction_id))


func province(region_id: String) -> ProvinceState:
	return _province_by_id.get(SimUtil.norm(region_id))


func army(army_id: int) -> Army:
	for a in armies:
		if a.id == army_id:
			return a
	return null


## Eserciti e flotte presenti in una regione.
func armies_in(region_id: String) -> Array[Army]:
	var key := SimUtil.norm(region_id)
	var out: Array[Army] = []
	for a in armies:
		if a.region == key:
			out.append(a)
	return out


func armies_of(faction_id: String) -> Array[Army]:
	var key := SimUtil.norm(faction_id)
	var out: Array[Army] = []
	for a in armies:
		if a.faction == key:
			out.append(a)
	return out


func provinces_of(faction_id: String) -> Array[ProvinceState]:
	var key := SimUtil.norm(faction_id)
	var out: Array[ProvinceState] = []
	for p in provinces:
		if p.owner == key:
			out.append(p)
	return out


## Nuovo esercito (o flotta) registrato nello stato, con id progressivo.
func create_army(faction_id: String, region_id: String, fleet: bool) -> Army:
	var a := Army.new(next_army_id, SimUtil.norm(faction_id), SimUtil.norm(region_id), fleet)
	next_army_id += 1
	armies.append(a)
	if fleet and (rules == null or rules.combat.admirals_on):
		a.admiral = Admirals.new_admiral(self, a)   # ogni flotta nasce con il suo ammiraglio (ADR-056)
	return a


## Una pila nuova della fazione: nasce almeno con il valore iniziale della fazione (auror.cfg `valore_iniziale`,
## nell'originale la patch del valore in CreateUnit), senza superare il valore massimo.
func new_stack(faction_id: String, unit_id: String, men: int, valour: int = 0) -> UnitStack:
	var start := rules.combat.start_valour_of(faction_id) if rules != null else 0
	var v := maxi(valour, start)
	if rules != null:
		v = mini(v, maxi(valour, rules.combat.valour_max))
	var st := UnitStack.new(unit_id, men, v)
	TroopUpgrades.apply_start(self, st, faction_id)   # armi e armatura della fazione (auror.cfg `armi_armatura_iniziali`)
	return st


func create_agent(faction_id: String, region_id: String, unit_id: String, type_name: String, birth_year: int) -> AgentState:
	var a := AgentState.new(next_agent_id, SimUtil.norm(faction_id), SimUtil.norm(region_id), unit_id, type_name, birth_year)
	next_agent_id += 1
	agents.append(a)
	return a


## Agente per id, null se non esiste.
func agent(agent_id: int) -> AgentState:
	for a in agents:
		if a.id == agent_id:
			return a
	return null


## Agenti presenti in una regione, in ordine di id.
func agents_in(region_id: String) -> Array[AgentState]:
	var key := SimUtil.norm(region_id)
	var out: Array[AgentState] = []
	for a in agents:
		if a.region == key:
			out.append(a)
	return out


## Agenti di una fazione, in ordine di id.
func agents_of(faction_id: String) -> Array[AgentState]:
	var key := SimUtil.norm(faction_id)
	var out: Array[AgentState] = []
	for a in agents:
		if a.faction == key:
			out.append(a)
	return out


## Toglie un agente dallo stato (catturato, morto, sposato, fazione estinta).
func remove_agent(a: AgentState) -> void:
	agents.erase(a)


# --- proposte in attesa (fase 7b) ----------------------------------------------------


## La proposta in attesa con quell'id ({} se non c'e').
func proposal(proposal_id: int) -> Dictionary:
	for p in pending_proposals:
		if int(p.get("id", 0)) == proposal_id:
			return p
	return {}


## La proposta in attesa il cui agente e' `agent_id` ({} se l'agente non aspetta nessuna risposta).
func proposal_of_agent(agent_id: int) -> Dictionary:
	for p in pending_proposals:
		if int(p.get("agente", 0)) == agent_id:
			return p
	return {}


## Proposte in attesa di risposta della fazione destinataria, in ordine di id.
func proposals_for(faction_id: String) -> Array[Dictionary]:
	var key := SimUtil.norm(faction_id)
	var out: Array[Dictionary] = []
	for p in pending_proposals:
		if str(p.get("a", "")) == key:
			out.append(p)
	return out


## Vero se esiste gia' una proposta in attesa dello stesso tipo tra le due fazioni (da -> a).
func has_proposal(from_id: String, to_id: String, kind: String) -> bool:
	var from_key := SimUtil.norm(from_id)
	var to_key := SimUtil.norm(to_id)
	for p in pending_proposals:
		if str(p.get("da", "")) == from_key and str(p.get("a", "")) == to_key and str(p.get("tipo", "")) == kind:
			return true
	return false


## Toglie una proposta dall'elenco (risposta, scadenza, agente scomparso).
func remove_proposal(proposal_id: int) -> void:
	for i in pending_proposals.size():
		if int(pending_proposals[i].get("id", 0)) == proposal_id:
			pending_proposals.remove_at(i)
			return


# --- personaggi (fase 4a) -----------------------------------------------------------


## Registra un personaggio gia' costruito (l'id arriva da `next_character_id`).
func add_character(c: Character) -> void:
	characters.append(c)
	_character_by_id[c.id] = c
	next_character_id = maxi(next_character_id, c.id + 1)


## Nuovo personaggio registrato nello stato, con id progressivo.
func create_character(faction_id: String) -> Character:
	var c := Character.new(next_character_id)
	c.faction = SimUtil.norm(faction_id)
	add_character(c)
	return c


func character(character_id: int) -> Character:
	return _character_by_id.get(character_id)


## Personaggi di una fazione in ordine di id (""= tutte); i morti solo se richiesto.
func characters_of(faction_id: String, include_dead: bool = false) -> Array[Character]:
	var key := SimUtil.norm(faction_id)
	var out: Array[Character] = []
	for c in characters:
		if faction_id != "" and c.faction != key:
			continue
		if c.alive or include_dead:
			out.append(c)
	return out


## Capo vivo della fazione, null se non ce n'e' (fazione senza dati o in attesa di successione).
## Usa una cache di ricerca, controllata a ogni lettura: se i personaggi cambiano il risultato resta giusto.
func leader_of(faction_id: String) -> Character:
	var key := SimUtil.norm(faction_id)
	var cached: Variant = _leader_cache.get(key)
	if cached != null:
		var hit: Character = cached
		if hit.alive and hit.faction == key and hit.role == Character.ROLE_LEADER:
			return hit
	for c in characters:
		if c.alive and c.faction == key and c.role == Character.ROLE_LEADER:
			_leader_cache[key] = c
			return c
	return null


## Erede designato: il maschio vivo piu' anziano con ruolo `erede` (a parita' l'id minore); null se non c'e'.
func heir_of(faction_id: String) -> Character:
	var key := SimUtil.norm(faction_id)
	var best: Character = null
	for c in characters:
		if not c.alive or c.faction != key or c.role != Character.ROLE_HEIR:
			continue
		if best == null or c.birth_year < best.birth_year:
			best = c
	return best


## Comandante vivo dell'esercito o della flotta, null se non ne ha (con cache controllata come `leader_of`).
func commander_of(army_id: int) -> Character:
	if army_id <= 0:
		return null
	var cached: Variant = _commander_cache.get(army_id)
	if cached != null:
		var hit: Character = cached
		if hit.alive and hit.army == army_id:
			return hit
	for c in characters:
		if c.alive and c.army == army_id:
			_commander_cache[army_id] = c
			return c
	return null


## Governatore della provincia (chi ne detiene il titolo), null se non ce n'e'.
func governor_of(region_id: String) -> Character:
	var key := SimUtil.norm(region_id)
	for c in characters:
		if c.alive and c.title == key:
			return c
	return null


## Dove si trova il personaggio: la regione dell'esercito che comanda, altrimenti l'ultima nota.
func character_region(c: Character) -> String:
	if c.army > 0:
		var a := army(c.army)
		if a != null:
			return a.region
	return c.region


## Vero se la fazione ha (o ha avuto) un capo nella simulazione: i mondi senza dati dei capi non hanno dinastie.
func has_dynasty(faction_id: String) -> bool:
	var key := SimUtil.norm(faction_id)
	for c in characters:
		if c.faction == key and c.role == Character.ROLE_LEADER:
			return true
	return false


## Re gia' incoronati con il nome reale di indice `name_index` (0 se la fazione non ha contatori).
func royal_counter(faction_id: String, name_index: int) -> int:
	var list: Array = royal_counters.get(SimUtil.norm(faction_id), [])
	if name_index < 0 or name_index >= list.size():
		return 0
	return int(list[name_index])


func set_royal_counter(faction_id: String, name_index: int, value: int) -> void:
	if name_index < 0:
		return
	var key := SimUtil.norm(faction_id)
	var list: Array = royal_counters.get(key, [])
	while list.size() <= name_index:
		list.append(0)
	list[name_index] = value
	royal_counters[key] = list


## Numerale del prossimo re con quel nome: incrementa il contatore e lo restituisce.
func next_numeral(faction_id: String, name_index: int) -> int:
	var value := royal_counter(faction_id, name_index) + 1
	set_royal_counter(faction_id, name_index, value)
	return value


## Toglie un esercito dallo stato (distrutto, catturato o senza pile).
func remove_army(a: Army) -> void:
	armies.erase(a)


# --- guerre ----------------------------------------------------------------------


## Chiave di una guerra: i due id in maiuscolo, il minore per primo, separati da "|".
static func war_key(faction_a: String, faction_b: String) -> String:
	var a := SimUtil.norm(faction_a)
	var b := SimUtil.norm(faction_b)
	if a > b:
		return "%s|%s" % [b, a]
	return "%s|%s" % [a, b]


## Vero se le due fazioni sono in guerra. I ribelli sono in guerra con tutti; nessuno con se stesso.
func at_war(faction_a: String, faction_b: String) -> bool:
	var a := SimUtil.norm(faction_a)
	var b := SimUtil.norm(faction_b)
	if a == b:
		return false
	if a == REBEL or b == REBEL:
		return true
	return wars.has(war_key(a, b))


## Dichiara guerra. Vero se la guerra e' nuova (false se gia' in corso, se i ribelli sono coinvolti
## o se le due fazioni coincidono). Un'alleanza o una tregua della coppia cade (una coppia e' in uno stato solo):
## la perdita di influenza e gli eventi sono di `DiplomacyProcessor.break_for_attack`.
func declare_war(faction_a: String, faction_b: String) -> bool:
	if at_war(faction_a, faction_b):
		return false
	var key := war_key(faction_a, faction_b)
	alliances.erase(key)
	truces.erase(key)
	wars[key] = year
	return true


## Anno dell'ultima svolta della guerra tra le due fazioni (vedi `wars`), 0 se non sono in guerra (o se una e' dei ribelli).
func war_turn_year(faction_a: String, faction_b: String) -> int:
	return int(wars.get(war_key(faction_a, faction_b), 0))


## Una provincia e' passata di mano tra le due fazioni: se sono in guerra la svolta e' quest'anno.
func mark_war_turn(faction_a: String, faction_b: String) -> void:
	var key := war_key(faction_a, faction_b)
	if wars.has(key):
		wars[key] = year


## Chiude la guerra (senza tregua: la coppia torna neutrale). Vero se c'era.
func end_war(faction_a: String, faction_b: String) -> bool:
	if SimUtil.norm(faction_a) == REBEL or SimUtil.norm(faction_b) == REBEL:
		return false
	return wars.erase(war_key(faction_a, faction_b))


## Fazioni in guerra con `faction_id`, nell'ordine di dichiarazione delle fazioni (esclusi i ribelli,
## che sono in guerra con tutti).
func enemies_of(faction_id: String) -> Array[String]:
	var key := SimUtil.norm(faction_id)
	var out: Array[String] = []
	for f in factions:
		if f.id != key and f.id != REBEL and wars.has(war_key(key, f.id)):
			out.append(f.id)
	return out


# --- alleanze e tregue (fase 5a) -------------------------------------------------------


## Vero se le due fazioni sono alleate.
func is_allied(faction_a: String, faction_b: String) -> bool:
	return alliances.has(war_key(faction_a, faction_b))


## Anno di scadenza della tregua della coppia, 0 se non c'e'.
func truce_until(faction_a: String, faction_b: String) -> int:
	return int(truces.get(war_key(faction_a, faction_b), 0))


## Stato della coppia: REL_WAR ("guerra", i ribelli con tutti), REL_ALLIANCE, REL_TRUCE o REL_NEUTRAL ("neutrale";
## anche per una fazione con se stessa).
func relation(faction_a: String, faction_b: String) -> String:
	if SimUtil.norm(faction_a) == SimUtil.norm(faction_b):
		return REL_NEUTRAL
	if at_war(faction_a, faction_b):
		return REL_WAR
	var key := war_key(faction_a, faction_b)
	if alliances.has(key):
		return REL_ALLIANCE
	if truces.has(key):
		return REL_TRUCE
	return REL_NEUTRAL


## Stringe un'alleanza. Falso (nessun cambiamento) se una fazione e' dei ribelli, se coincidono, se sono in guerra
## o se sono gia' alleate. Una tregua della coppia cade.
func form_alliance(faction_a: String, faction_b: String) -> bool:
	var a := SimUtil.norm(faction_a)
	var b := SimUtil.norm(faction_b)
	if a == b or a == REBEL or b == REBEL or at_war(a, b):
		return false
	var key := war_key(a, b)
	if alliances.has(key):
		return false
	truces.erase(key)
	alliances[key] = true
	return true


## Rompe un'alleanza (la coppia torna neutrale). Vero se c'era.
func break_alliance(faction_a: String, faction_b: String) -> bool:
	return alliances.erase(war_key(faction_a, faction_b))


## Firma una tregua fino all'anno `until_year` (compreso nella scadenza di fine anno: vedi `truces`). Mette fine
## alla guerra e all'alleanza della coppia. Falso se una fazione e' dei ribelli o se coincidono.
func make_truce(faction_a: String, faction_b: String, until_year: int) -> bool:
	var a := SimUtil.norm(faction_a)
	var b := SimUtil.norm(faction_b)
	if a == b or a == REBEL or b == REBEL:
		return false
	var key := war_key(a, b)
	wars.erase(key)
	alliances.erase(key)
	truces[key] = until_year
	return true


## Rompe una tregua (la coppia torna neutrale). Vero se c'era.
func break_truce(faction_a: String, faction_b: String) -> bool:
	return truces.erase(war_key(faction_a, faction_b))


## Le due fazioni di una chiave di coppia, nell'ordine della chiave.
static func pair_of(key: String) -> PackedStringArray:
	return PackedStringArray(key.split("|"))


# --- avvertimenti papali (fase 5c) -------------------------------------------------------


## Chiave di un avvertimento: la fazione ammonita e quella che non deve attaccare (ordinate: A>B e B>A sono diversi).
static func warning_key(offender: String, protected_faction: String) -> String:
	return "%s>%s" % [SimUtil.norm(offender), SimUtil.norm(protected_faction)]


## Avvertimento in corso ({"anno", "scadenza"}), vuoto se non c'e'.
func papal_warning(offender: String, protected_faction: String) -> Dictionary:
	var w: Variant = papal_warnings.get(warning_key(offender, protected_faction), {})
	if typeof(w) != TYPE_DICTIONARY:
		return {}
	var warning: Dictionary = w
	return warning


# --- assedi ----------------------------------------------------------------------


func siege_in(region_id: String) -> SiegeState:
	return sieges.get(SimUtil.norm(region_id))


## Assedi in ordine fisso (ordine di dichiarazione delle regioni), indipendente dall'ordine di
## inserimento: cosi' un salvataggio ricaricato si comporta come l'originale.
func sieges_in_order() -> Array[SiegeState]:
	var out: Array[SiegeState] = []
	if campaign == null:
		return out
	for r in campaign.regions:
		var s: SiegeState = sieges.get(r.id)
		if s != null:
			out.append(s)
	return out


func is_besieged(region_id: String) -> bool:
	return sieges.has(SimUtil.norm(region_id))


func is_finished() -> bool:
	return year >= final_year


## Vero se la partita non puo' andare avanti: anno finale raggiunto, sconfitta del giocatore, fine della campagna, oppure
## vittoria per dominio in attesa della scelta di continuare (`GameCommands.continue_after_victory`).
func is_game_over() -> bool:
	return is_finished() or victory.is_final() or victory.awaits_choice()


## Epoca (EARLY/HIGH/LATE) di un anno secondo le date della campagna.
func era_for_year(at_year: int) -> String:
	var result := "EARLY"
	if campaign == null:
		return result
	var starts := campaign.period_starts
	var high: int = int(starts.get("HIGH", 99999))
	var late: int = int(starts.get("LATE", 99999))
	if at_year >= late:
		result = "LATE"
	elif at_year >= high:
		result = "HIGH"
	return result


## Aggiunge una voce al registro dell'anno; `data` e' unita al tipo e all'anno.
func add_event(event_type: String, data: Dictionary = {}) -> void:
	var e := {"tipo": event_type, "anno": year}
	e.merge(data)
	events.append(e)


## Quante pile ha una fazione (""= tutte) del tipo indicato (id unita'; ""= qualsiasi).
func count_stacks(faction_id: String = "", unit_id: String = "") -> int:
	var key := SimUtil.norm(faction_id)
	var total := 0
	for a in armies:
		if faction_id != "" and a.faction != key:
			continue
		for s in a.stacks:
			if unit_id == "" or s.unit_id == unit_id:
				total += 1
	return total
