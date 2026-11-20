class_name UnitType
extends RefCounted
## Una voce del file prod delle unità (MTW_XL_*_UNIT_PROD11.TXT).
##
## Il file elenca insieme truppe, navi, cavalcature e agenti (spie, vescovi,
## crociate...): `type_name` li distingue. Le colonne non ancora interpretate
## restano in `raw` (campi originali, senza virgolette, indice = colonna).
## Gli ID di fazioni, regioni, culture ed edifici sono salvati in MAIUSCOLO.

const INFANTRY := "INFANTRY"
const CAVALRY := "CAVALRY"
const ARTILLERY := "ARTILLERY"
const SHIP := "SHIP"
const MOUNT := "MOUNT"
const ALL_PERIODS := "ALL_PERIODS"

var id: String                          ## col. 0, univoco (maiuscole come nel file)
var index := 0                          ## posizione nel file (da 0)
var type_name := ""                     ## col. 1: INFANTRY, CAVALRY, SPY, BISHOP...
var cost := 0                           ## col. 2, fiorini
var support_cost := 0                   ## col. 3, per stagione
var build_time := 0                     ## col. 4, stagioni
var honour_handicap := 0                ## col. 5
var base_strength := 0                  ## col. 6 (uso nel gioco non chiaro)
var men := 0                            ## col. 7, uomini base prima dello scaling
var honour_step := 0                    ## col. 8, uccisioni per salire di livello
var general_candidate := ""             ## col. 9: PREFERRED / OK / DISCOURAGED
var ruler_advantage := ""               ## col. 11, FN_*
var region_advantage := ""              ## col. 12, ID_*
## col. 16: edifici necessari. Lista di alternative (OR); ogni alternativa è un
## insieme di token (AND). Vuota = nessun requisito.
## `{ A, B }` -> [[A, B]];  `{ {A},{B} }` -> [[A], [B]].
var requires: Array[PackedStringArray] = []
var unit_classes := PackedStringArray()  ## col. 17: ATTACKER, MISSILE...
var moral_bonus := 0                    ## col. 18 (0 se vuota)
var has_moral_bonus := false
var periods := PackedStringArray()      ## col. 19: ALL_PERIODS oppure EARLY/HIGH/LATE
var scalable := false                   ## col. 20
var stats := {}                         ## col. 21: CHIAVE -> int / float / String
var charge_bonus := 0                   ## carica (CHARGE_BONUS)
var melee_bonus := 0                    ## mischia (MELEE_BONUS)
var defence_bonus := 0                  ## difesa (DEFENCE_BONUS)
var armour_level := 0                   ## armatura (ARMOUR_LEVEL)
var honour_level := 0                   ## onore (HONOUR_LEVEL)
var ammo := 0                           ## munizioni (AMMO)
var projectile := ""                    ## PROJECTILE_TYPE (NONE se non tira)
var invisible := false                  ## col. 22: invisibile in mappa strategica
var mount_type := ""                    ## col. 25: HORSE / CAMEL / vuoto
var leader_of := PackedStringArray()    ## col. 27: fazioni di cui è l'unità del capo
var all_factions := false               ## col. 28 contiene ALL_FACTIONS
var factions := PackedStringArray()     ## col. 28: FN_* (senza ALL_FACTIONS)
var regions := PackedStringArray()      ## col. 29: ID_* (condizione OR)
var cultures := PackedStringArray()     ## col. 32: culture ammesse (vuota = tutte)
var is_ship_data := false               ## col. 33 letta correttamente
var ship_range := 0
var ship_attack := 0
var ship_defence := 0
var ship_speed := 0
var ship_strength := 0
var ship_sunk_label := ""
var ai_weights := {}                    ## col. 14: profilo IA -> peso (float); vuoto se la colonna manca (fase 7)
var weapon_type := ""                   ## col. 48
var mercenary := false                  ## col. 49
var elite := false                      ## unita' esclusiva degli Auror (AurorUnits, ADR-074): limiti di fazione e regione sempre validi
var strength_multiplier := 1.0          ## moltiplica la forza nella risoluzione automatica (AurorUnits `moltiplicatore_forza`)
var raw := PackedStringArray()          ## tutti i campi originali


func _init(unit_id: String) -> void:
	id = unit_id


## Peso dell'unita' per il profilo dell'IA (col. 14 «Unit choices (AI)»); `fallback` se il file non ha la colonna o il
## profilo. Piu' alto = piu' desiderata.
func ai_weight(profile: String, fallback: float = 0.0) -> float:
	return float(ai_weights.get(profile.strip_edges().to_upper(), fallback))


func has_ai_weights() -> bool:
	return not ai_weights.is_empty()


func is_infantry() -> bool:
	return type_name == INFANTRY


func is_cavalry() -> bool:
	return type_name == CAVALRY


func is_artillery() -> bool:
	return type_name == ARTILLERY


func is_ship() -> bool:
	return type_name == SHIP


func is_mount() -> bool:
	return type_name == MOUNT


## Truppe e navi (nel dizionario dati: 236 = 127 + 83 + 13 + 13).
func is_military() -> bool:
	return type_name == INFANTRY or type_name == CAVALRY or type_name == ARTILLERY or type_name == SHIP


## Agenti e azioni strategiche (spie, vescovi, crociata...).
func is_agent() -> bool:
	return not is_military() and type_name != MOUNT


func stat_int(key: String, fallback: int = 0) -> int:
	var v: Variant = stats.get(key, fallback)
	return int(v)


## Vero se la fazione è nell'elenco (o l'elenco è ALL_FACTIONS). Un elenco vuoto
## senza ALL_FACTIONS NON ammette nessuno: il significato nel gioco è incerto.
func allows_faction(faction_id: String) -> bool:
	if all_factions or factions.has(faction_id.strip_edges().to_upper()):
		return true
	# Crusade e Jihad hanno la colonna 28 vuota nei dati: le decide la cultura (col. 32: CATHOLIC, MUSLIM) e l'edificio
	# (Chapter House, Ribat), come nell'originale, dove le bandiscono tutte le fazioni della religione giusta.
	return factions.is_empty() and (type_name == "CRUSADE" or type_name == "JIHAD")


## Chi puo' reclutarla: le fazioni dell'elenco, e in piu' chiunque per le **unita' regionali**, cioe' le truppe con la
## colonna delle fazioni vuota ma con un elenco di regioni e degli edifici richiesti (uscarli, karl, landsmenn, servi e
## predoni vichinghi in Scandinavia, fyrd, guardaboschi di Sherwood, guerrieri e giavellottieri slavi, spadaccini
## variaghi): nell'originale le arruola chi possiede quelle regioni, in ogni campagna. Prima restavano fuori da ogni
## elenco (segnalazione di Federico dell'11/11). Restano escluse quelle senza regioni o senza edifici (vichinghi di
## Jomsborg, banditi gallesi, prima guardia variaga), che compaiono solo come ribelli o mercenari.
func recruitable_by(faction_id: String) -> bool:
	if allows_faction(faction_id):
		return true
	return is_regional()


func is_regional() -> bool:
	return is_military() and not all_factions and factions.is_empty() and not regions.is_empty() and not requires.is_empty()


## Elenco regioni vuoto = nessun vincolo regionale.
func allows_region(region_id: String) -> bool:
	return regions.is_empty() or regions.has(region_id.strip_edges().to_upper())


## Elenco culture vuoto = tutte le culture.
func allows_culture(culture: String) -> bool:
	return cultures.is_empty() or cultures.has(culture.strip_edges().to_upper())


## `period` è EARLY, HIGH o LATE. Elenco vuoto o ALL_PERIODS = sempre.
func available_in_period(period: String) -> bool:
	return periods.is_empty() or periods.has(ALL_PERIODS) or periods.has(period.strip_edges().to_upper())


## Tutti i token edificio citati nei requisiti, senza ripetizioni.
func required_tokens() -> PackedStringArray:
	var out := PackedStringArray()
	for group in requires:
		for token in group:
			if not out.has(token):
				out.append(token)
	return out
