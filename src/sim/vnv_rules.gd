class_name VnvRules
extends RefCounted
## Vizi e virtu' (VnV) del primo gruppo documentato, fase 4a (ADR-004): catene Leadership, Dread,
## Vacillator, Killer Instinct e Butcher, lette da data/regole/vizi_virtu.cfg.
##
## NOMI: gli id e i livelli vengono dai testi del gioco, Loc/Italian/Events.txt, sezione
## "Vice and virtue text" (voci <id><livello>title e <id><livello>desc, in inglese). Gli stessi id
## compaiono nei re famosi e negli eroi (campo `vnv` del file dei nomi). Una "catena" e' l'id senza
## il livello finale: `fearsome3` = catena `fearsome`, livello 3. Il prefisso `secret_` (vizio
## segreto, rivelato dalla spia) si riconosce ma non e' modellato.
##
## Tutte le catene dei file (defender3, educated1...) si conservano sul personaggio; hanno effetto
## solo quelle elencate in `chains`. I valori predefiniti qui sotto sono uguali a quelli del file
## (un test lo verifica). Effetti, contatori e soglie sono PROVVISORI (catalogo "Vizi, virtu' e titoli").

const DEFAULT_PATH := "res://data/regole/vizi_virtu.cfg"

## Attributi su cui una catena puo' avere effetto, con la chiave usata nel file.
const EFFECT_KEYS := {
	"command": "comando",
	"dread": "terrore",
	"piety": "pieta",
	"acumen": "acume",
	"loyalty": "lealta",
}

## Id delle catene attive, nell'ordine di valutazione.
var order := PackedStringArray(["fearsome", "tyrant", "vaccilator", "killer", "butcher"])
## Catena -> Dictionary {"nome", "contatore", "soglie" (Array di int), "scala", "solo_capo",
## "effetti": attributo -> Array di int (uno per livello)}.
var chains := {
	"fearsome": {
		"nome": "Leadership", "contatore": "vittorie", "soglie": [3, 7, 12, 20], "scala": 1, "solo_capo": false,
		"effetti": {"command": [1, 2, 3, 3], "loyalty": [1, 2, 3, 3]},
	},
	"tyrant": {
		"nome": "Dread", "contatore": "anni_tassa_alta", "soglie": [5, 10, 15, 20], "scala": 1, "solo_capo": true,
		"effetti": {"dread": [1, 2, 3, 4]},
	},
	"vaccilator": {
		"nome": "Vacillator", "contatore": "ritirate", "soglie": [3, 6, 10], "scala": 1, "solo_capo": false,
		"effetti": {"command": [0, -1, -2], "loyalty": [-1, -2, -3]},
	},
	"killer": {
		"nome": "Killer Instinct", "contatore": "uccisioni", "soglie": [40, 160], "scala": 10, "solo_capo": false,
		"effetti": {"dread": [1, 2]},
	},
	"butcher": {
		"nome": "Butcher", "contatore": "prigionieri", "soglie": [1000], "scala": 1, "solo_capo": false,
		"effetti": {"dread": [2]},
	},
}

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le catene mancanti nel file restano quelle predefinite. Se il file non
## c'e' o non si legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> VnvRules:
	var r := VnvRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Vizi e virtu' non letti da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	var listed: Variant = cfg.get_value("gruppo", "catene") if cfg.has_section_key("gruppo", "catene") else null
	if typeof(listed) != TYPE_ARRAY:
		return r
	var ids := PackedStringArray()
	var items: Array = listed
	for item in items:
		ids.append(str(item).strip_edges().to_lower())
	var loaded := {}
	for chain_id in ids:
		if not cfg.has_section(chain_id):
			r.errors.append("Catena %s elencata ma senza sezione in %s" % [chain_id, path])
			continue
		loaded[chain_id] = r._read_chain(cfg, chain_id)
	if not loaded.is_empty():
		r.order = PackedStringArray(loaded.keys())
		r.chains = loaded
	return r


## Spezza un id del gioco: "secret_tyrant3" -> {"catena": "tyrant", "livello": 3, "segreto": true};
## "pride" -> {"catena": "pride", "livello": 1, "segreto": false}. Id vuoto: catena "".
static func parse_id(vnv_id: String) -> Dictionary:
	var text := vnv_id.strip_edges().to_lower()
	var secret := false
	if text.begins_with("secret_"):
		secret = true
		text = text.substr(7)
	var end := text.length()
	while end > 0 and text.unicode_at(end - 1) >= 48 and text.unicode_at(end - 1) <= 57:
		end -= 1
	var chain := text.substr(0, end)
	var level := 1
	if end < text.length():
		level = text.substr(end).to_int()
	return {"catena": chain, "livello": maxi(level, 1), "segreto": secret}


func has_chain(chain: String) -> bool:
	return chains.has(chain)


## Numero di livelli con effetto di una catena (0 se la catena non e' tra quelle attive).
func level_count(chain: String) -> int:
	if not chains.has(chain):
		return 0
	var ch: Dictionary = chains[chain]
	var thresholds: Array = ch["soglie"]
	return thresholds.size()


## Nome del contatore che fa salire la catena ("" se la catena non e' attiva).
func counter_of(chain: String) -> String:
	if not chains.has(chain):
		return ""
	var ch: Dictionary = chains[chain]
	return str(ch["contatore"])


## Vero se la catena e' riservata al capo.
func leader_only(chain: String) -> bool:
	if not chains.has(chain):
		return false
	var ch: Dictionary = chains[chain]
	return bool(ch["solo_capo"])


## Valore del contatore (nell'unita' del contatore) da raggiungere per il livello (1..n); -1 se non esiste.
func threshold(chain: String, level: int) -> int:
	if not chains.has(chain):
		return -1
	var ch: Dictionary = chains[chain]
	var thresholds: Array = ch["soglie"]
	if level < 1 or level > thresholds.size():
		return -1
	return int(thresholds[level - 1]) * int(ch["scala"])


## Livello massimo raggiunto da un contatore (0 = nessuno).
func level_for_count(chain: String, count: int) -> int:
	var best := 0
	for level in range(1, level_count(chain) + 1):
		if count >= threshold(chain, level):
			best = level
	return best


## Variazione di un attributo dovuta alla catena al livello dato (livello oltre l'ultimo = ultimo).
func delta(chain: String, level: int, attr: String) -> int:
	if level < 1 or not chains.has(chain):
		return 0
	var ch: Dictionary = chains[chain]
	var effects: Dictionary = ch["effetti"]
	if not effects.has(attr):
		return 0
	var values: Array = effects[attr]
	if values.is_empty():
		return 0
	return int(values[mini(level, values.size()) - 1])


## Nome leggibile della catena (per i testi degli eventi).
func chain_name(chain: String) -> String:
	if not chains.has(chain):
		return chain
	var ch: Dictionary = chains[chain]
	return str(ch["nome"])


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {"order": Array(order), "chains": chains.duplicate(true)}


func _read_chain(cfg: ConfigFile, chain_id: String) -> Dictionary:
	var thresholds: Array = []
	var raw: Variant = cfg.get_value(chain_id, "soglie") if cfg.has_section_key(chain_id, "soglie") else null
	if typeof(raw) == TYPE_ARRAY:
		var raw_items: Array = raw
		for item in raw_items:
			thresholds.append(int(item))
	var effects := {}
	for attr in EFFECT_KEYS:
		var key: String = EFFECT_KEYS[attr]
		if not cfg.has_section_key(chain_id, key):
			continue
		var values: Variant = cfg.get_value(chain_id, key)
		if typeof(values) == TYPE_ARRAY:
			var list: Array = []
			var value_items: Array = values
			for item in value_items:
				list.append(int(item))
			effects[attr] = list
	return {
		"nome": str(cfg.get_value(chain_id, "nome", chain_id)),
		"contatore": str(cfg.get_value(chain_id, "contatore", "")),
		"soglie": thresholds,
		"scala": maxi(1, int(cfg.get_value(chain_id, "scala", 1))),
		"solo_capo": bool(cfg.get_value(chain_id, "solo_capo", false)),
		"effetti": effects,
	}
