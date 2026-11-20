class_name AiRules
extends RefCounted
## Parametri dell'IA (fase 7, ADR-004, ADR-012), letti da data/regole/ia.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test lo
## verifica). L'IA e' un giocatore: non fa parte di `Rules` (la simulazione non la conosce), quindi la classe NON e'
## esposta come `rules.ai` ma la carica l'IA stessa: `AiRules.default_rules()` (letta una volta dal file, poi in memoria)
## oppure un'istanza passata a `AiController.plan_year` / `CampaignTurn.advance`.
##
## TUTTI i numeri sono PROVVISORI (il catalogo non documenta la logica dell'IA di MTW): vanno tarati con le partite IA contro
## IA di `tests/unit/test_ai_partita_lunga.gd`. Fanno eccezione i pesi dei profili, che stanno nei file del gioco
## (`UnitType.ai_weights`, `BuildingType.Level.ai_weights`).
##
## Dalla 7b: sezioni `[diplomazia]`, `[agenti]` e `[crociate]` (tregue, alleanze, nozze, tradimenti, tetto e budget degli agenti,
## crociate e jihad), tutte PROVVISORIE come il resto.
##
## Parametri per profilo (20 sezioni `[profilo_NOME]`, vedi `PROFILE_KEYS`): i 17 comportamenti di `SetBehaviour` piu' i tre
## profili di stato POVERTY_STRICKEN, DESPERATE_DEFENCE e CLOSE_TO_SUPPORT_LIMIT, che l'IA adotta per un anno quando valgono le
## condizioni di `[generale]` (vedi `AiProfiles.effective`). La difficolta' (`[difficolta_*]`) scala aggressivita', budget e
## soglie d'attacco; nessun bonus di risorse (catalogo: a difficolta' alte nemici piu' astuti, senza numeri).

const DEFAULT_PATH := "res://data/regole/ia.cfg"
const DIFFICULTIES := ["facile", "normale", "difficile", "molto_difficile"]
## Chiavi di ogni profilo.
const PROFILE_KEYS := ["bersagli", "soglia", "aggressione", "quota_truppe", "tetto_mantenimento", "margine_difesa", "quota_costruzioni", "tassa_max", "navale"]
## Bersagli ammessi, dal meno al piu' aggressivo: il livello e' la posizione nell'elenco.
const TARGET_MODES := ["nessuno", "ribelli", "guerra", "neutrali"]

static var _shared: AiRules = null

# --- [generale] ---
var difficulty := "normale"
var budget_ms := 200                ## tempo massimo per pianificare un anno di tutte le fazioni (misurato in un test)
var default_profile := "CATHOLIC_DEFENSIVE"   ## per le fazioni senza SetBehaviour noto
var poverty_treasury := 0           ## tesoro sotto questo valore (o reddito netto negativo con tesoro sotto la riserva): POVERTY_STRICKEN
var desperate_ratio := 2.0          ## forza nemica confinante / forza propria oltre cui: DESPERATE_DEFENCE
var support_limit := 0.7            ## mantenimento / reddito oltre cui: CLOSE_TO_SUPPORT_LIMIT
var reserve_fixed := 300            ## riserva minima di tesoro (fiorini)
var reserve_upkeep_years := 1.0     ## piu' tanti anni di mantenimento
var rich_years := 6.0               ## tesoro oltre riserva + tanti anni di reddito: la fazione e' "ricca"
var rich_spend := 0.25              ## quota dell'eccesso reinvestita ogni anno in truppe da una fazione ricca
var rich_upkeep_cap := 0.9          ## tetto di mantenimento (quota del reddito) di una fazione ricca
# --- [tasse] ---
var tax_margin_high := 25           ## lealta' sopra la soglia di rivolta richiesta per alzare le tasse
var tax_margin_low := 8             ## lealta' sotto soglia + margine: si abbassano le tasse
# --- [costruzioni] ---
var build_cost_scale := 600.0       ## divisore del punteggio: 1 + costo / scala_costo + anni / scala_tempo
var build_time_scale := 6.0
var build_noise := 0.1              ## rumore moltiplicativo sul punteggio (generatore dell'IA)
var build_min_score := 20.0
var build_max_per_year := 3         ## nuove costruzioni per fazione e anno
var need_castle := 300.0            ## bisogno: castello in una provincia minacciata
var need_loyalty := 40.0            ## bisogno: per punto di felicita' dell'edificio in una provincia vicina alla rivolta
var need_income := 2.0              ## bisogno: per punto di rendita dell'edificio
var need_trade := 150.0             ## bisogno: edificio commerciale in un porto
var need_port := 300.0              ## bisogno: porto e cantiere per i profili navali
var neutral_weight := 100.0         ## peso di un edificio o di un'unita' senza pesi nei file
# --- [reclutamento] ---
var recruit_noise := 0.15
var recruit_queue_max := 2          ## voci in coda di reclutamento per provincia
var recruit_per_province := 1       ## nuove reclute per provincia e anno
var stacks_per_province := 4.0      ## tetto delle pile di terra della fazione: base + questo per provincia
var stacks_base := 4
var retrain_threshold := 0.7        ## riaddestra le pile sotto questa quota dell'organico pieno (PROVVISORIA, [riaddestramento] soglia_ia)
var merc_per_year := 2              ## compagnie di mercenari assoldate al massimo in un anno (PROVVISORIA, [mercenari] max_per_anno)
var disband_per_year := 2           ## pile congedate al massimo in un anno da una fazione in debito e in perdita (PROVVISORIA, [congedo] max_per_anno)
# --- [guerra] ---
var capital_min_men := 40           ## uomini che la capitale tiene sempre in sede
var reinforce_radius := 3           ## passi entro cui un esercito interno soccorre una provincia minacciata
var attacks_per_year := 3           ## attacchi lanciati da una fazione in un anno
var assault_ratio := 1.5            ## rapporto di forza (assediante / guarnigione x castello) per ordinare l'assalto
var relief_ratio := 1.2             ## rapporto per attaccare gli assedianti di una provincia propria
var barricade_ratio := 1.5          ## minaccia oltre la difesa in campo (x bonus del difensore) per cui ci si barrica nel castello
var war_factor := 0.85              ## la soglia d'attacco contro chi e' gia' in guerra e' la soglia x questo fattore
var cautious_neutral_factor := 3.0  ## profili con bersagli «guerra»: contro un vicino neutrale la soglia e' la soglia x questo fattore
var overextension_share := 0.15     ## quota di regioni di terra oltre la quale la soglia contro neutrali e alleati cresce
var overextension_k := 3.0          ## ... di 1 + k x (quota - soglia_estensione)
var rebel_factor := 0.7             ## idem contro i ribelli
# --- [navi] ---
var naval_factor := 1.3             ## soglia d'attacco moltiplicata per questo fattore negli sbarchi
var fleets_per_port := 0.5          ## flotte desiderate per provincia con porto (profili navali)
var fleet_ratio := 1.5              ## rapporto di forza per attaccare una flotta nemica
# --- [personaggi] ---
var titles_per_year := 2
var title_min_loyalty := 4          ## lealta' minima di un generale per ricevere un titolo
var offices_per_year := 2           ## cariche di Stato vacanti assegnate al massimo in un anno
# --- [diplomazia] (fase 7b) ---
var truce_ratio := 1.0              ## forza nemica vicina / forza propria oltre cui una guerra «va male» e si cerca la tregua
var truce_losses := 1               ## province perse contro il nemico nell'ultimo anno oltre cui una guerra «va male»
var peace_prob := 0.12              ## probabilita' annua, per guerra, che una fazione non espansionista chieda tregua anche senza perdere
var alliance_prob := 0.35           ## probabilita' annua di cercare l'alleanza con un vicino neutrale che ha un nemico comune
var alliances_max := 2              ## alleanze contemporanee oltre le quali non se ne cercano altre
var alliance_min_p := 0.1           ## probabilita' di accettazione minima perche' valga la pena inviare l'emissario
var marriage_loyalty := 5           ## lealta' efficace sotto cui un generale e' un candidato alle nozze con una principessa
var marriage_prob := 0.5            ## probabilita' annua che una principessa libera sposi un generale poco leale
var betray_prob := 0.12             ## probabilita' annua che un profilo espansionista pensi di rompere un'alleanza
var betray_factor := 1.3            ## la soglia d'attacco contro un alleato e' la soglia del profilo x questo fattore
var betray_prob_other := 0.06       ## come betray_prob per i profili non espansionisti che attaccano almeno chi e' gia' in guerra
var stalemate_years := 8            ## anni di guerra senza svolte oltre cui ogni profilo puo' cercare la tregua
var stalemate_peace_prob := 0.35    ## probabilita' annua, per guerra in stallo, di cercare la tregua
var player_proposal_prob := 0.5     ## probabilita' annua che l'IA mandi davvero la proposta quando il destinatario e' un giocatore
var player_proposals_max := 3       ## proposte in attesa di risposta per giocatore oltre cui l'IA non ne manda altre
var agent_radius := 5               ## passi entro cui un agente cerca la sua destinazione
# --- [agenti] (fase 7b) ---
var cap_emissary := 0.15            ## agenti per tipo = arrotondamento per eccesso (tetto x province); principesse a parte
var cap_spy := 0.25
var cap_assassin := 0.1
var cap_religious := 0.2
var cap_inquisitor := 0.08
var agent_budget := 0.08            ## quota del reddito annuo spesa in nuovi agenti
var agents_per_year := 2            ## nuovi agenti per fazione e anno
var heresy_min := 5.0               ## % di eretici oltre cui una provincia chiama un inquisitore
var assassin_min_p := 0.35          ## probabilita' di riuscita minima di un assassinio
var bribe_min_p := 0.35             ## probabilita' di accettazione minima di una corruzione
var bribe_share := 0.3              ## quota del tesoro oltre la riserva spendibile per una corruzione
var bribe_min_men := 20             ## uomini minimi di un esercito nemico che vale la pena corrompere
# --- [crociate] (fase 7b) ---
var crusader_profiles := PackedStringArray(["CATHOLIC_EXPANSIONIST_CRUSADER", "CATHOLIC_CRUSADER_TRADER", "CATHOLIC_DEFENSIVE_CRUSADER"])
var jihad_profiles := PackedStringArray(["MUSLIM_DEVOUT", "MUSLIM_EXPANSIONIST"])
var crusade_prob := 0.3             ## probabilita' annua di bandire una crociata o un jihad quando c'e' un bersaglio valido
var crusade_radius := 6             ## passi di terra entro cui cercare un bersaglio
var crusade_treasury := 1.5         ## il tesoro oltre la riserva deve essere almeno tante volte il costo della crociata
# --- [viaggi_agenti] (ADR-053) ---
## Anni di viaggio massimi per gruppo di agente: emissario, principessa, assassino, spia, religioso, inquisitore.
var journey_years := {"emissario": 8, "principessa": 8, "assassino": 6, "spia": 5, "religioso": 4, "inquisitore": 6}
var journey_time_weight := 0.15     ## punteggio / (1 + peso x anni di viaggio)
var journey_hostile_risk := 0.05    ## punteggio x (1 - rischio x anni passati in terra di fazioni in guerra)
var journey_threshold := 10.0       ## punteggio minimo per assegnare un obiettivo
var journey_max_recalcs := 3        ## inseguimenti di un bersaglio mobile prima di rinunciare
var journey_expiry := 15            ## anni oltre cui un ordine scade
var journey_hysteresis := 1.5       ## un obiettivo nuovo sostituisce quello in corso solo se vale tante volte di piu'
var journey_max_per_target := 1     ## agenti dello stesso tipo sullo stesso bersaglio
var journey_threat_radius := 2      ## passi di terra entro cui un assassino nemico minaccia capo o erede
## Valore degli obiettivi per tipo.
var journey_values := {"assassinio_capo": 100.0, "assassinio_erede": 80.0, "assassinio_generale": 40.0, "assassinio_agente": 15.0,
		"alleanza": 50.0, "tregua": 60.0, "matrimonio": 45.0, "spionaggio": 20.0, "conversione": 25.0, "inquisizione": 30.0}
var journey_player_weight := 1.0    ## moltiplicatore degli obiettivi di una fazione del giocatore
## Tetto assoluto di agenti per fazione e gruppo di reclutamento (AiAgents.GROUP_*).
var journey_caps := {"assassini": 4, "emissari": 3, "spie": 3, "inquisitori": 2}
var aggressive_profiles := PackedStringArray(["CATHOLIC_EXPANSIONIST_CRUSADER", "CATHOLIC_EXPANSIONIST", "CATHOLIC_NAVAL_EXPANSIONIST", "ORTHODOX_EXPANSIONIST", "MUSLIM_EXPANSIONIST", "BARBARIAN_RAIDER"])
var trader_profiles := PackedStringArray(["CATHOLIC_TRADER", "CATHOLIC_CRUSADER_TRADER"])
## Classe di comportamento -> moltiplicatori dei valori (assassinio, diplomazia, commercio).
var behaviour := {
	"aggressiva": {"assassinio": 1.3, "diplomazia": 0.8, "commercio": 0.9},
	"commerciale": {"assassinio": 0.8, "diplomazia": 1.1, "commercio": 1.4},
	"difensiva": {"assassinio": 0.9, "diplomazia": 1.2, "commercio": 1.1},
}
# --- [commercio_navale] (ADR-053) ---
var trade_replan_years := 3         ## anni tra due pianificazioni delle zone
var trade_contested_cost := 4.0     ## costo in piu' di una zona con flotte nemiche
var trade_min_ratio := 1.2          ## guadagno / mantenimento minimo di una rotta
var trade_build_threshold := 150.0  ## fiorini l'anno di una rotta senza navi che fanno costruire una nave
var trade_reach_years := 3          ## anni massimi perche' una nave raggiunga la sua zona
var trade_peace_weight := 0.002     ## probabilita' di tregua in piu' per fiorino di commercio perso (al massimo 0,5)
var trade_building_priority := 1.5  ## bisogno di porto ed edificio commerciale nelle province costiere con merci
# --- [difficolta_*] ---
var difficulty_table := {
	"facile": {"aggressivita": 0.6, "budget": 0.8, "soglia": 1.25},
	"normale": {"aggressivita": 1.0, "budget": 1.0, "soglia": 1.0},
	"difficile": {"aggressivita": 1.2, "budget": 1.15, "soglia": 0.9},
	"molto_difficile": {"aggressivita": 1.4, "budget": 1.3, "soglia": 0.8},
}
## Profilo -> {chiave: valore}, vedi PROFILE_KEYS.
var profiles := {
		"CATHOLIC_EXPANSIONIST_CRUSADER": {"bersagli": "neutrali", "soglia": 1.4, "aggressione": 0.6, "quota_truppe": 0.45, "tetto_mantenimento": 0.65, "margine_difesa": 1.3, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": false},
		"CATHOLIC_EXPANSIONIST": {"bersagli": "neutrali", "soglia": 1.5, "aggressione": 0.55, "quota_truppe": 0.4, "tetto_mantenimento": 0.6, "margine_difesa": 1.3, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": false},
		"CATHOLIC_NAVAL_EXPANSIONIST": {"bersagli": "neutrali", "soglia": 1.5, "aggressione": 0.5, "quota_truppe": 0.35, "tetto_mantenimento": 0.6, "margine_difesa": 1.3, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": true},
		"CATHOLIC_ISOLATIONIST": {"bersagli": "ribelli", "soglia": 2.5, "aggressione": 0.2, "quota_truppe": 0.25, "tetto_mantenimento": 0.45, "margine_difesa": 1.8, "quota_costruzioni": 0.5, "tassa_max": 2, "navale": false},
		"CATHOLIC_TRADER": {"bersagli": "guerra", "soglia": 2.0, "aggressione": 0.3, "quota_truppe": 0.2, "tetto_mantenimento": 0.4, "margine_difesa": 1.6, "quota_costruzioni": 0.7, "tassa_max": 3, "navale": true},
		"CATHOLIC_CRUSADER_TRADER": {"bersagli": "guerra", "soglia": 1.8, "aggressione": 0.35, "quota_truppe": 0.25, "tetto_mantenimento": 0.45, "margine_difesa": 1.5, "quota_costruzioni": 0.6, "tassa_max": 3, "navale": true},
		"CATHOLIC_DEFENSIVE_CRUSADER": {"bersagli": "guerra", "soglia": 2.0, "aggressione": 0.3, "quota_truppe": 0.3, "tetto_mantenimento": 0.5, "margine_difesa": 1.8, "quota_costruzioni": 0.5, "tassa_max": 2, "navale": false},
		"CATHOLIC_DEFENSIVE": {"bersagli": "guerra", "soglia": 2.2, "aggressione": 0.25, "quota_truppe": 0.3, "tetto_mantenimento": 0.5, "margine_difesa": 1.8, "quota_costruzioni": 0.5, "tassa_max": 2, "navale": false},
		"ORTHODOX_EXPANSIONIST": {"bersagli": "neutrali", "soglia": 1.5, "aggressione": 0.55, "quota_truppe": 0.4, "tetto_mantenimento": 0.6, "margine_difesa": 1.3, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": false},
		"ORTHODOX_STAGNANT": {"bersagli": "guerra", "soglia": 2.5, "aggressione": 0.15, "quota_truppe": 0.2, "tetto_mantenimento": 0.4, "margine_difesa": 1.6, "quota_costruzioni": 0.6, "tassa_max": 2, "navale": false},
		"ORTHODOX_DEFENSIVE": {"bersagli": "guerra", "soglia": 2.2, "aggressione": 0.25, "quota_truppe": 0.3, "tetto_mantenimento": 0.5, "margine_difesa": 1.8, "quota_costruzioni": 0.5, "tassa_max": 2, "navale": false},
		"MUSLIM_EXPANSIONIST": {"bersagli": "neutrali", "soglia": 1.4, "aggressione": 0.6, "quota_truppe": 0.45, "tetto_mantenimento": 0.65, "margine_difesa": 1.3, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": false},
		"MUSLIM_PEACEFUL": {"bersagli": "ribelli", "soglia": 2.5, "aggressione": 0.2, "quota_truppe": 0.25, "tetto_mantenimento": 0.45, "margine_difesa": 1.8, "quota_costruzioni": 0.6, "tassa_max": 2, "navale": false},
		"MUSLIM_DEVOUT": {"bersagli": "guerra", "soglia": 1.8, "aggressione": 0.4, "quota_truppe": 0.35, "tetto_mantenimento": 0.55, "margine_difesa": 1.5, "quota_costruzioni": 0.5, "tassa_max": 3, "navale": false},
		"POPE": {"bersagli": "nessuno", "soglia": 99.0, "aggressione": 0.0, "quota_truppe": 0.35, "tetto_mantenimento": 0.5, "margine_difesa": 2.0, "quota_costruzioni": 0.6, "tassa_max": 2, "navale": false},
		"BARBARIAN_RAIDER": {"bersagli": "neutrali", "soglia": 0.8, "aggressione": 1.0, "quota_truppe": 0.5, "tetto_mantenimento": 0.7, "margine_difesa": 1.0, "quota_costruzioni": 0.3, "tassa_max": 4, "navale": false},
		"REBELS": {"bersagli": "nessuno", "soglia": 99.0, "aggressione": 0.0, "quota_truppe": 0.0, "tetto_mantenimento": 0.0, "margine_difesa": 0.0, "quota_costruzioni": 0.0, "tassa_max": 2, "navale": false},
		"POVERTY_STRICKEN": {"bersagli": "ribelli", "soglia": 3.0, "aggressione": 0.1, "quota_truppe": 0.0, "tetto_mantenimento": 0.3, "margine_difesa": 2.0, "quota_costruzioni": 0.9, "tassa_max": 4, "navale": false},
		"DESPERATE_DEFENCE": {"bersagli": "nessuno", "soglia": 99.0, "aggressione": 0.0, "quota_truppe": 0.6, "tetto_mantenimento": 0.7, "margine_difesa": 2.5, "quota_costruzioni": 0.1, "tassa_max": 1, "navale": false},
		"CLOSE_TO_SUPPORT_LIMIT": {"bersagli": "guerra", "soglia": 2.5, "aggressione": 0.1, "quota_truppe": 0.0, "tetto_mantenimento": 0.3, "margine_difesa": 1.8, "quota_costruzioni": 0.5, "tassa_max": 2, "navale": false},
}

## Errori di lettura del file (chiave con tipo sbagliato, valore fuori scala).
var errors := PackedStringArray()


## Regole condivise: lette una volta da `DEFAULT_PATH` (valori predefiniti se il file manca).
static func default_rules() -> AiRules:
	if _shared == null:
		_shared = load_file()
	return _shared


## Dimentica le regole condivise (i test che cambiano il file o vogliono ricaricarlo).
static func reset_shared() -> void:
	_shared = null


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si legge: valori
## predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> AiRules:
	var r := AiRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole dell'IA non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.difficulty = _text(cfg, "generale", "difficolta", r.difficulty)
	r.budget_ms = _int(cfg, "generale", "budget_ms", r.budget_ms)
	r.default_profile = _text(cfg, "generale", "profilo_predefinito", r.default_profile).to_upper()
	r.poverty_treasury = _int(cfg, "generale", "soglia_poverta", r.poverty_treasury)
	r.desperate_ratio = _num(cfg, "generale", "rapporto_disperato", r.desperate_ratio)
	r.support_limit = _num(cfg, "generale", "limite_mantenimento", r.support_limit)
	r.reserve_fixed = _int(cfg, "generale", "riserva_fissa", r.reserve_fixed)
	r.reserve_upkeep_years = _num(cfg, "generale", "riserva_anni_mantenimento", r.reserve_upkeep_years)
	r.rich_years = _num(cfg, "generale", "anni_tesoro_alto", r.rich_years)
	r.rich_spend = _num(cfg, "generale", "quota_eccesso", r.rich_spend)
	r.rich_upkeep_cap = _num(cfg, "generale", "tetto_ricco", r.rich_upkeep_cap)
	r.tax_margin_high = _int(cfg, "tasse", "margine_alta", r.tax_margin_high)
	r.tax_margin_low = _int(cfg, "tasse", "margine_bassa", r.tax_margin_low)
	r.build_cost_scale = _num(cfg, "costruzioni", "scala_costo", r.build_cost_scale)
	r.build_time_scale = _num(cfg, "costruzioni", "scala_tempo", r.build_time_scale)
	r.build_noise = _num(cfg, "costruzioni", "rumore", r.build_noise)
	r.build_min_score = _num(cfg, "costruzioni", "punteggio_min", r.build_min_score)
	r.build_max_per_year = _int(cfg, "costruzioni", "max_per_anno", r.build_max_per_year)
	r.need_castle = _num(cfg, "costruzioni", "bisogno_castello", r.need_castle)
	r.need_loyalty = _num(cfg, "costruzioni", "bisogno_lealta", r.need_loyalty)
	r.need_income = _num(cfg, "costruzioni", "bisogno_reddito", r.need_income)
	r.need_trade = _num(cfg, "costruzioni", "bisogno_commercio", r.need_trade)
	r.need_port = _num(cfg, "costruzioni", "bisogno_porto", r.need_port)
	r.neutral_weight = _num(cfg, "costruzioni", "peso_neutro", r.neutral_weight)
	r.recruit_noise = _num(cfg, "reclutamento", "rumore", r.recruit_noise)
	r.recruit_queue_max = _int(cfg, "reclutamento", "coda_max", r.recruit_queue_max)
	r.recruit_per_province = _int(cfg, "reclutamento", "per_provincia", r.recruit_per_province)
	r.stacks_per_province = _num(cfg, "reclutamento", "pile_per_provincia", r.stacks_per_province)
	r.stacks_base = _int(cfg, "reclutamento", "pile_base", r.stacks_base)
	r.retrain_threshold = _num(cfg, "riaddestramento", "soglia_ia", r.retrain_threshold)
	r.merc_per_year = _int(cfg, "mercenari", "max_per_anno", r.merc_per_year)
	r.disband_per_year = _int(cfg, "congedo", "max_per_anno", r.disband_per_year)
	r.capital_min_men = _int(cfg, "guerra", "uomini_min_capitale", r.capital_min_men)
	r.reinforce_radius = _int(cfg, "guerra", "raggio_rinforzi", r.reinforce_radius)
	r.attacks_per_year = _int(cfg, "guerra", "attacchi_max", r.attacks_per_year)
	r.assault_ratio = _num(cfg, "guerra", "soglia_assalto", r.assault_ratio)
	r.relief_ratio = _num(cfg, "guerra", "soglia_soccorso", r.relief_ratio)
	r.barricade_ratio = _num(cfg, "guerra", "soglia_barricata", r.barricade_ratio)
	r.war_factor = _num(cfg, "guerra", "fattore_guerra", r.war_factor)
	r.cautious_neutral_factor = _num(cfg, "guerra", "fattore_neutrali_prudenti", r.cautious_neutral_factor)
	r.overextension_share = _num(cfg, "guerra", "soglia_estensione", r.overextension_share)
	r.overextension_k = _num(cfg, "guerra", "k_estensione", r.overextension_k)
	r.rebel_factor = _num(cfg, "guerra", "fattore_ribelli", r.rebel_factor)
	r.naval_factor = _num(cfg, "navi", "fattore_soglia", r.naval_factor)
	r.fleets_per_port = _num(cfg, "navi", "flotte_per_porto", r.fleets_per_port)
	r.fleet_ratio = _num(cfg, "navi", "soglia_flotte", r.fleet_ratio)
	r.titles_per_year = _int(cfg, "personaggi", "titoli_per_anno", r.titles_per_year)
	r.title_min_loyalty = _int(cfg, "personaggi", "lealta_min_titolo", r.title_min_loyalty)
	r.offices_per_year = _int(cfg, "personaggi", "cariche_per_anno", r.offices_per_year)
	r.truce_ratio = _num(cfg, "diplomazia", "rapporto_tregua", r.truce_ratio)
	r.truce_losses = _int(cfg, "diplomazia", "perdite_tregua", r.truce_losses)
	r.peace_prob = _num(cfg, "diplomazia", "prob_pace", r.peace_prob)
	r.alliance_prob = _num(cfg, "diplomazia", "prob_alleanza", r.alliance_prob)
	r.alliances_max = _int(cfg, "diplomazia", "alleanze_max", r.alliances_max)
	r.alliance_min_p = _num(cfg, "diplomazia", "p_min_alleanza", r.alliance_min_p)
	r.marriage_loyalty = _int(cfg, "diplomazia", "lealta_nozze", r.marriage_loyalty)
	r.marriage_prob = _num(cfg, "diplomazia", "prob_nozze", r.marriage_prob)
	r.betray_prob = _num(cfg, "diplomazia", "prob_tradimento", r.betray_prob)
	r.betray_factor = _num(cfg, "diplomazia", "fattore_tradimento", r.betray_factor)
	r.betray_prob_other = _num(cfg, "diplomazia", "prob_tradimento_altri", r.betray_prob_other)
	r.stalemate_years = _int(cfg, "diplomazia", "anni_stallo", r.stalemate_years)
	r.stalemate_peace_prob = _num(cfg, "diplomazia", "prob_pace_stallo", r.stalemate_peace_prob)
	r.player_proposal_prob = _num(cfg, "diplomazia", "prob_proposta_giocatore", r.player_proposal_prob)
	r.player_proposals_max = _int(cfg, "diplomazia", "proposte_giocatore_max", r.player_proposals_max)
	r.agent_radius = _int(cfg, "diplomazia", "raggio_agenti", r.agent_radius)
	r.cap_emissary = _num(cfg, "agenti", "tetto_emissari", r.cap_emissary)
	r.cap_spy = _num(cfg, "agenti", "tetto_spie", r.cap_spy)
	r.cap_assassin = _num(cfg, "agenti", "tetto_assassini", r.cap_assassin)
	r.cap_religious = _num(cfg, "agenti", "tetto_religiosi", r.cap_religious)
	r.cap_inquisitor = _num(cfg, "agenti", "tetto_inquisitori", r.cap_inquisitor)
	r.agent_budget = _num(cfg, "agenti", "quota_reddito", r.agent_budget)
	r.agents_per_year = _int(cfg, "agenti", "nuovi_per_anno", r.agents_per_year)
	r.heresy_min = _num(cfg, "agenti", "eretici_min", r.heresy_min)
	r.assassin_min_p = _num(cfg, "agenti", "p_min_assassinio", r.assassin_min_p)
	r.bribe_min_p = _num(cfg, "agenti", "p_min_corruzione", r.bribe_min_p)
	r.bribe_share = _num(cfg, "agenti", "quota_corruzione", r.bribe_share)
	r.bribe_min_men = _int(cfg, "agenti", "uomini_min_corruzione", r.bribe_min_men)
	r.crusader_profiles = _strings(cfg, "crociate", "profili_crociati", r.crusader_profiles)
	r.jihad_profiles = _strings(cfg, "crociate", "profili_jihad", r.jihad_profiles)
	r.crusade_prob = _num(cfg, "crociate", "prob_crociata", r.crusade_prob)
	r.crusade_radius = _int(cfg, "crociate", "raggio_crociata", r.crusade_radius)
	r.crusade_treasury = _num(cfg, "crociate", "tesoro_crociata", r.crusade_treasury)
	for key in r.journey_years.keys():
		r.journey_years[key] = _int(cfg, "viaggi_agenti", "anni_" + str(key), int(r.journey_years[key]))
	r.journey_time_weight = _num(cfg, "viaggi_agenti", "peso_tempo", r.journey_time_weight)
	r.journey_hostile_risk = _num(cfg, "viaggi_agenti", "rischio_per_anno_ostile", r.journey_hostile_risk)
	r.journey_threshold = _num(cfg, "viaggi_agenti", "soglia_assegnazione", r.journey_threshold)
	r.journey_max_recalcs = _int(cfg, "viaggi_agenti", "max_ricalcoli", r.journey_max_recalcs)
	r.journey_expiry = _int(cfg, "viaggi_agenti", "scadenza_ordine", r.journey_expiry)
	r.journey_hysteresis = _num(cfg, "viaggi_agenti", "isteresi", r.journey_hysteresis)
	r.journey_max_per_target = _int(cfg, "viaggi_agenti", "max_agenti_per_bersaglio", r.journey_max_per_target)
	r.journey_threat_radius = _int(cfg, "viaggi_agenti", "raggio_minaccia", r.journey_threat_radius)
	for key in r.journey_values.keys():
		r.journey_values[key] = _num(cfg, "viaggi_agenti", "valore_" + str(key), float(r.journey_values[key]))
	r.journey_player_weight = _num(cfg, "viaggi_agenti", "peso_contro_giocatore", r.journey_player_weight)
	for key in r.journey_caps.keys():
		r.journey_caps[key] = _int(cfg, "viaggi_agenti", "tetto_" + str(key), int(r.journey_caps[key]))
	r.aggressive_profiles = _strings(cfg, "viaggi_agenti", "profili_aggressivi", r.aggressive_profiles)
	r.trader_profiles = _strings(cfg, "viaggi_agenti", "profili_commerciali", r.trader_profiles)
	for cls in r.behaviour.keys():
		var row: Dictionary = r.behaviour[cls]
		for key in row.keys():
			row[key] = _num(cfg, "viaggi_agenti", "%s_%s" % [cls, key], float(row[key]))
	r.trade_replan_years = _int(cfg, "commercio_navale", "anni_ripianificazione", r.trade_replan_years)
	r.trade_contested_cost = _num(cfg, "commercio_navale", "costo_zona_contesa", r.trade_contested_cost)
	r.trade_min_ratio = _num(cfg, "commercio_navale", "soglia_convenienza", r.trade_min_ratio)
	r.trade_build_threshold = _num(cfg, "commercio_navale", "soglia_costruzione_nave", r.trade_build_threshold)
	r.trade_reach_years = _int(cfg, "commercio_navale", "anni_max_raggiungimento", r.trade_reach_years)
	r.trade_peace_weight = _num(cfg, "commercio_navale", "peso_pace_per_rendita_persa", r.trade_peace_weight)
	r.trade_building_priority = _num(cfg, "commercio_navale", "priorita_porto_mercante_con_merci", r.trade_building_priority)
	for name in DIFFICULTIES:
		var section := "difficolta_%s" % name
		var row: Dictionary = (r.difficulty_table[name] as Dictionary).duplicate()
		for key in ["aggressivita", "budget", "soglia"]:
			row[key] = _num(cfg, section, key, float(row[key]))
		r.difficulty_table[name] = row
	for section in cfg.get_sections():
		if not section.begins_with("profilo_"):
			continue
		var profile_name := section.substr(8).to_upper()
		var row: Dictionary = {}
		if r.profiles.has(profile_name):
			row = (r.profiles[profile_name] as Dictionary).duplicate()
		else:
			row = (r.profiles[r.default_profile] as Dictionary).duplicate() if r.profiles.has(r.default_profile) else {}
		row["bersagli"] = _text(cfg, section, "bersagli", str(row.get("bersagli", "guerra")))
		for key in ["soglia", "aggressione", "quota_truppe", "tetto_mantenimento", "margine_difesa", "quota_costruzioni"]:
			row[key] = _num(cfg, section, key, float(row.get(key, 0.0)))
		row["tassa_max"] = _int(cfg, section, "tassa_max", int(row.get("tassa_max", 2)))
		row["navale"] = _bool(cfg, section, "navale", bool(row.get("navale", false)))
		r.profiles[profile_name] = row
	r.errors.append_array(r._check_consistency())
	return r


## Parametri del profilo (quelli del profilo predefinito se il nome non e' noto). Non va modificato.
func profile(profile_name: String) -> Dictionary:
	var key := profile_name.strip_edges().to_upper()
	if profiles.has(key):
		return profiles[key]
	if profiles.has(default_profile):
		return profiles[default_profile]
	return {}


## Vero se il profilo e' dichiarato (non un ripiego).
func has_profile(profile_name: String) -> bool:
	return profiles.has(profile_name.strip_edges().to_upper())


## Parametri della difficolta' scelta (`difficulty`, oppure `override_name` se non vuoto): aggressivita', budget, soglia.
func difficulty_params(override_name: String = "") -> Dictionary:
	var name := override_name if override_name != "" else difficulty
	if difficulty_table.has(name):
		return difficulty_table[name]
	return difficulty_table["normale"]


## Livello dei bersagli ammessi dal profilo: 0 nessuno, 1 ribelli, 2 ribelli e guerre in corso, 3 anche i neutrali.
func target_level(profile_name: String) -> int:
	var p := profile(profile_name)
	return maxi(0, TARGET_MODES.find(str(p.get("bersagli", "nessuno"))))


## Tutti i parametri in un Dictionary (per confronti nei test).
func to_dict() -> Dictionary:
	return {
		"difficulty": difficulty, "budget_ms": budget_ms, "default_profile": default_profile,
		"poverty_treasury": poverty_treasury, "desperate_ratio": desperate_ratio, "support_limit": support_limit,
		"reserve_fixed": reserve_fixed, "reserve_upkeep_years": reserve_upkeep_years, "rich_years": rich_years,
		"rich_spend": rich_spend, "rich_upkeep_cap": rich_upkeep_cap,
		"tax_margin_high": tax_margin_high, "tax_margin_low": tax_margin_low,
		"build_cost_scale": build_cost_scale, "build_time_scale": build_time_scale, "build_noise": build_noise,
		"build_min_score": build_min_score, "build_max_per_year": build_max_per_year, "need_castle": need_castle,
		"need_loyalty": need_loyalty, "need_income": need_income, "need_trade": need_trade, "need_port": need_port,
		"neutral_weight": neutral_weight, "recruit_noise": recruit_noise, "recruit_queue_max": recruit_queue_max,
		"recruit_per_province": recruit_per_province, "stacks_per_province": stacks_per_province, "stacks_base": stacks_base,
		"retrain_threshold": retrain_threshold, "merc_per_year": merc_per_year, "disband_per_year": disband_per_year, "capital_min_men": capital_min_men,
		"reinforce_radius": reinforce_radius, "attacks_per_year": attacks_per_year, "assault_ratio": assault_ratio,
		"relief_ratio": relief_ratio, "barricade_ratio": barricade_ratio, "war_factor": war_factor, "rebel_factor": rebel_factor,
		"cautious_neutral_factor": cautious_neutral_factor, "overextension_share": overextension_share,
		"overextension_k": overextension_k,
		"naval_factor": naval_factor, "fleets_per_port": fleets_per_port, "fleet_ratio": fleet_ratio,
		"titles_per_year": titles_per_year, "title_min_loyalty": title_min_loyalty, "offices_per_year": offices_per_year,
		"truce_ratio": truce_ratio, "truce_losses": truce_losses, "peace_prob": peace_prob, "alliance_prob": alliance_prob,
		"alliances_max": alliances_max, "alliance_min_p": alliance_min_p, "marriage_loyalty": marriage_loyalty,
		"marriage_prob": marriage_prob, "betray_prob": betray_prob, "betray_factor": betray_factor,
		"betray_prob_other": betray_prob_other, "stalemate_years": stalemate_years, "stalemate_peace_prob": stalemate_peace_prob,
		"player_proposal_prob": player_proposal_prob, "player_proposals_max": player_proposals_max, "agent_radius": agent_radius,
		"cap_emissary": cap_emissary, "cap_spy": cap_spy, "cap_assassin": cap_assassin, "cap_religious": cap_religious,
		"cap_inquisitor": cap_inquisitor, "agent_budget": agent_budget, "agents_per_year": agents_per_year,
		"heresy_min": heresy_min, "assassin_min_p": assassin_min_p, "bribe_min_p": bribe_min_p, "bribe_share": bribe_share,
		"bribe_min_men": bribe_min_men, "crusader_profiles": Array(crusader_profiles), "jihad_profiles": Array(jihad_profiles),
		"crusade_prob": crusade_prob, "crusade_radius": crusade_radius, "crusade_treasury": crusade_treasury,
		"journey_years": journey_years.duplicate(), "journey_time_weight": journey_time_weight,
		"journey_hostile_risk": journey_hostile_risk, "journey_threshold": journey_threshold,
		"journey_max_recalcs": journey_max_recalcs, "journey_expiry": journey_expiry, "journey_hysteresis": journey_hysteresis,
		"journey_max_per_target": journey_max_per_target, "journey_threat_radius": journey_threat_radius,
		"journey_values": journey_values.duplicate(), "journey_player_weight": journey_player_weight,
		"journey_caps": journey_caps.duplicate(), "aggressive_profiles": Array(aggressive_profiles),
		"trader_profiles": Array(trader_profiles), "behaviour": behaviour.duplicate(true),
		"trade_replan_years": trade_replan_years, "trade_contested_cost": trade_contested_cost,
		"trade_min_ratio": trade_min_ratio,
		"trade_build_threshold": trade_build_threshold, "trade_reach_years": trade_reach_years,
		"trade_peace_weight": trade_peace_weight, "trade_building_priority": trade_building_priority,
		"difficulty_table": difficulty_table.duplicate(true), "profiles": profiles.duplicate(true),
	}


func _check_consistency() -> PackedStringArray:
	var out := PackedStringArray()
	if not DIFFICULTIES.has(difficulty):
		out.append("generale/difficolta '%s' sconosciuta: uso normale" % difficulty)
		difficulty = "normale"
	if not profiles.has(default_profile):
		out.append("generale/profilo_predefinito '%s' non dichiarato: uso CATHOLIC_DEFENSIVE" % default_profile)
		default_profile = "CATHOLIC_DEFENSIVE"
	for profile_name in profiles:
		var row: Dictionary = profiles[profile_name]
		if not TARGET_MODES.has(str(row.get("bersagli", ""))):
			out.append("profilo_%s/bersagli '%s' non valido: uso nessuno" % [profile_name, str(row.get("bersagli", ""))])
			row["bersagli"] = "nessuno"
		row["tassa_max"] = clampi(int(row.get("tassa_max", 2)), 0, 4)
	return out


static func _num(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback


static func _int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


static func _text(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges()
	return fallback


static func _strings(cfg: ConfigFile, section: String, key: String, fallback: PackedStringArray) -> PackedStringArray:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var items: Array = v
	var out := PackedStringArray()
	for item in items:
		out.append(str(item).strip_edges().to_upper())
	return out


## Vero se il profilo bandisce le crociate (profili di `profili_crociati`).
func is_crusader(profile_name: String) -> bool:
	return crusader_profiles.has(profile_name.strip_edges().to_upper())


## Vero se il profilo bandisce il jihad (profili di `profili_jihad`).
func is_jihadi(profile_name: String) -> bool:
	return jihad_profiles.has(profile_name.strip_edges().to_upper())


static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_BOOL:
		return bool(v)
	return fallback


## Classe di comportamento del profilo per i viaggi degli agenti e il commercio navale: aggressiva, commerciale o difensiva.
func behaviour_class(profile_name: String) -> String:
	var key := profile_name.strip_edges().to_upper()
	if aggressive_profiles.has(key):
		return "aggressiva"
	if trader_profiles.has(key):
		return "commerciale"
	return "difensiva"


## Moltiplicatore del comportamento del profilo per la voce `kind` (assassinio, diplomazia, commercio).
func behaviour_weight(profile_name: String, kind: String) -> float:
	var row: Dictionary = behaviour.get(behaviour_class(profile_name), {})
	return float(row.get(kind, 1.0))
