class_name BuildingType
extends RefCounted
## Una famiglia di edifici del file prod (MTW_XL_*_BUILD_PROD13.TXT) con i suoi livelli.
##
## Nel file ogni riga è una famiglia e i valori per livello sono liste separate
## da virgola. Il livello n si cita con il token `NOME` (n = 1), `NOME2`, ...
## Gli ID e i token sono salvati in MAIUSCOLO. Le colonne non interpretate
## restano in `raw` (campi originali, indice = colonna).


## Un livello di una famiglia.
class Level:
	var family := ""                 ## id della famiglia
	var level := 1                   ## da 1
	var token := ""                  ## CASTLE, CASTLE2...
	var label := ""                  ## col. 2: nome mostrato (come nel file)
	var cost := 0                    ## col. 4, denari
	var build_time := 0              ## col. 5, stagioni
	## col. 6: requisiti. Alternative (OR) di gruppi di token (AND); vuota = nessuno.
	var requires: Array[PackedStringArray] = []
	var upgrades := PackedStringArray()      ## col. 16: UPGRADE_ARMOUR(1)...
	var tech_level := 0              ## col. 17
	var resources := PackedStringArray()     ## col. 18: risorse richieste nella regione
	var factions := PackedStringArray()      ## col. 19: vuoto = tutte le fazioni
	var glory_goals := PackedStringArray()   ## col. 20
	var faith := 0.0                 ## col. 21: propagazione della fede
	var income := 0                  ## col. 22: rendita generata (0 = nessuna)
	var happiness := 0               ## col. 23
	var mercenary_magnetism := 0     ## col. 24
	var inventions := PackedStringArray()    ## col. 26 (senza NONE)
	var capacity := 0                ## col. 27: guarnigione (solo castelli)
	## col. 9 «AI characters building production preferences» (fase 7): profilo IA -> peso (float) di questo livello;
	## vuoto se il file non ha la colonna. Un solo gruppo nel file vale per tutti i livelli.
	var ai_weights := {}
	## col. 10 «AI building influences for building combos» (fase 7): per questo livello, gli edifici che lo rendono piu'
	## desiderabile se gia' costruiti. Voci {"token": "IMPROVED_FARMLAND3", "family": "IMPROVED_FARMLAND", "level": 3,
	## "bonus": 50.0}. PROVVISORIA l'interpretazione: la voce vale se la provincia ha la famiglia almeno a quel livello.
	var ai_influences: Array[Dictionary] = []

	## Peso del livello per il profilo dell'IA; `fallback` se manca la colonna o il profilo.
	func ai_weight(profile: String, fallback: float = 0.0) -> float:
		return float(ai_weights.get(profile.strip_edges().to_upper(), fallback))

	func has_ai_weights() -> bool:
		return not ai_weights.is_empty()

	func has_income() -> bool:
		return income != 0

	## Prima risorsa richiesta, "" se nessuna.
	func resource() -> String:
		return resources[0] if not resources.is_empty() else ""

	## Fazioni vuote = aperto a tutte.
	func allows_faction(faction_id: String) -> bool:
		return factions.is_empty() or factions.has(faction_id.strip_edges().to_upper())


var id: String                           ## col. 1
var index := 0                           ## posizione nel file
var types := PackedStringArray()         ## col. 3: TROOP_PRODUCER, UNIQUE...
var levels: Array[Level] = []
var frontier := false                    ## col. 11
var religions := PackedStringArray()     ## col. 14 (vuoto = tutte)
var mercenary_hub := false               ## col. 25
var raw := PackedStringArray()


func _init(family_id: String) -> void:
	id = family_id


func level_count() -> int:
	return levels.size()


## Livello `n` (da 1), oppure null.
func get_level(n: int) -> Level:
	if n < 1 or n > levels.size():
		return null
	return levels[n - 1]


## Token del livello n: `NOME` per 1, `NOME2`... poi.
func token(n: int) -> String:
	return id if n == 1 else "%s%d" % [id, n]


func has_type(type_name: String) -> bool:
	return types.has(type_name.strip_edges().to_upper())


func is_unique() -> bool:
	return has_type("UNIQUE")
