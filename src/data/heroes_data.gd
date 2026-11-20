class_name HeroesData
extends RefCounted
## Modello del file dei nomi, dei re famosi e degli eroi famosi
## (campmap/names/MTW_XL_EARLY_HEROES.TXT e simili), riempito da HeroesLoader.
##
## Le liste di nomi (ADD_FORENAMES, ADD_SURNAMES, ADD_PRINCESS) sono numerate da 1
## nell'ordine di creazione, separatamente per i tre tipi; SET_* le associa alle
## fazioni. Il nome di un re famoso è un indice (da 0) nella lista dei nomi di
## battesimo della sua fazione. Ogni voce conserva i campi grezzi del file.

## Regione degli eroi che compaiono ovunque.
const ANY_REGION := "ID_LIMBO"
## Fazione dei ribelli (eroi famosi dei ribelli).
const REBEL_FACTION := "FN_REBEL"


## Liste di nomi associate a una fazione (SET_FORENAMES, SET_SURNAMES, SET_PRINCESS).
## Il numero di lista è 0 se la fazione non ha quell'associazione.
class FactionNames:
	var faction: String
	var forename_list := 0
	var royal_count := 0     ## i primi n nomi di battesimo sono "reali" (come dichiarato)
	var surname_list := 0
	var princess_list := 0

	func _init(faction_id: String) -> void:
		faction = faction_id


## Nomi dei ribelli di una regione (SET_REBELS).
class RebelNames:
	var region: String
	var forename_list := 0
	var surname_list := 0

	func _init(region_id: String, forename_list_number: int, surname_list_number: int) -> void:
		region = region_id
		forename_list = forename_list_number
		surname_list = surname_list_number


## Un re famoso: riga `nome, numero, c, d, p, a, ritratto, vnv`.
class FamousKing:
	var faction: String
	var name_index := 0      ## indice (da 0) nella lista dei nomi di battesimo della fazione
	var number := 0          ## numerale del re (2 = "II")
	var command := 0
	var dread := 0
	var piety := 0
	var acumen := 0
	var portrait := -1       ## -1 = ritratto casuale
	var vnv := ""            ## vizio o virtù (`tyrant2`, `educated1`...)
	var raw := PackedStringArray()
	var line := 0

	func _init(faction_id: String) -> void:
		faction = faction_id


## Un eroe famoso: riga `"nome", "cognome", anno, c, d, p, a, l, vnv, TIPO, REGIONE, ritratto`.
class FamousHero:
	var faction: String
	var forename := ""
	var surname := ""
	var year := 0            ## anno da cui il personaggio diventa disponibile
	var command := 0
	var dread := 0
	var piety := 0
	var acumen := 0
	var loyalty := 0
	var vnv := ""
	var type_name := ""      ## GENERAL, EMISSARY, BISHOP, INQUISITOR...
	var region := ""         ## token ID_*; ID_LIMBO = ovunque
	var portrait := -1
	var raw := PackedStringArray()
	var line := 0

	func _init(faction_id: String) -> void:
		faction = faction_id

	func full_name() -> String:
		return ("%s %s" % [forename, surname]).strip_edges()

	func is_anywhere() -> bool:
		return region == HeroesData.ANY_REGION


## Liste di nomi, nell'ordine del file (la lista numero n sta all'indice n - 1).
var forename_lists: Array[PackedStringArray] = []
var surname_lists: Array[PackedStringArray] = []
var princess_lists: Array[PackedStringArray] = []
## Re e eroi, nell'ordine del file.
var kings: Array[FamousKing] = []
var heroes: Array[FamousHero] = []
## Numero di voci dichiarato nell'intestazione, per fazione (per controllo).
var declared_kings := {}
var declared_heroes := {}
## Fazioni con associazioni SET_*, nell'ordine di prima comparsa.
var faction_order := PackedStringArray()
var errors := PackedStringArray()

var _names_by_faction := {}
var _rebels := {}
var _rebel_order := PackedStringArray()


static func norm(id: String) -> String:
	return id.strip_edges().to_upper()


## Associazioni di una fazione; la crea se non esiste (usato dal lettore).
func names_for(faction: String) -> FactionNames:
	var key := norm(faction)
	if _names_by_faction.has(key):
		return _names_by_faction[key]
	var n := FactionNames.new(key)
	_names_by_faction[key] = n
	faction_order.append(key)
	return n


## Associazioni di una fazione, o null.
func faction_names(faction: String) -> FactionNames:
	return _names_by_faction.get(norm(faction))


func add_rebels(region: String, forename_list_number: int, surname_list_number: int) -> void:
	var key := norm(region)
	if not _rebels.has(key):
		_rebel_order.append(key)
	_rebels[key] = RebelNames.new(key, forename_list_number, surname_list_number)


func rebel_names(region: String) -> RebelNames:
	return _rebels.get(norm(region))


func rebel_regions() -> PackedStringArray:
	return _rebel_order


# --- liste di nomi ------------------------------------------------------------


## Lista di nomi di battesimo (numero da 1); vuota se non esiste.
func forenames(list_number: int) -> PackedStringArray:
	return _list(forename_lists, list_number)


func surnames(list_number: int) -> PackedStringArray:
	return _list(surname_lists, list_number)


func princess_names(list_number: int) -> PackedStringArray:
	return _list(princess_lists, list_number)


func _list(lists: Array[PackedStringArray], list_number: int) -> PackedStringArray:
	if list_number < 1 or list_number > lists.size():
		return PackedStringArray()
	return lists[list_number - 1]


## Nomi di battesimo della fazione (vuota se non ha lista).
func forenames_of(faction: String) -> PackedStringArray:
	var n := faction_names(faction)
	return forenames(n.forename_list) if n != null else PackedStringArray()


func surnames_of(faction: String) -> PackedStringArray:
	var n := faction_names(faction)
	return surnames(n.surname_list) if n != null else PackedStringArray()


func princess_names_of(faction: String) -> PackedStringArray:
	var n := faction_names(faction)
	return princess_names(n.princess_list) if n != null else PackedStringArray()


## Nomi "reali" della fazione: i primi n della lista (n limitato alla lunghezza della lista).
func royal_names_of(faction: String) -> PackedStringArray:
	var n := faction_names(faction)
	if n == null:
		return PackedStringArray()
	var names := forenames(n.forename_list)
	return names.slice(0, mini(n.royal_count, names.size()))


# --- re ed eroi famosi ---------------------------------------------------------


func kings_of(faction: String) -> Array[FamousKing]:
	var key := norm(faction)
	var out: Array[FamousKing] = []
	for k in kings:
		if k.faction == key:
			out.append(k)
	return out


func heroes_of(faction: String) -> Array[FamousHero]:
	var key := norm(faction)
	var out: Array[FamousHero] = []
	for h in heroes:
		if h.faction == key:
			out.append(h)
	return out


func heroes_of_type(type_name: String) -> Array[FamousHero]:
	var key := norm(type_name)
	var out: Array[FamousHero] = []
	for h in heroes:
		if h.type_name == key:
			out.append(h)
	return out


## Fazioni con re famosi, nell'ordine del file.
func king_factions() -> PackedStringArray:
	return _distinct_factions(true)


func hero_factions() -> PackedStringArray:
	return _distinct_factions(false)


func _distinct_factions(for_kings: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if for_kings:
		for k in kings:
			if not out.has(k.faction):
				out.append(k.faction)
	else:
		for h in heroes:
			if not out.has(h.faction):
				out.append(h.faction)
	return out


## Nome di battesimo di un re famoso ("" se l'indice non è nella lista della fazione).
func king_forename(k: FamousKing) -> String:
	var names := forenames_of(k.faction)
	if k.name_index < 0 or k.name_index >= names.size():
		return ""
	return names[k.name_index]


## Nome con numerale: "William II".
func king_label(k: FamousKing) -> String:
	var base := king_forename(k)
	if base.is_empty():
		return ""
	return "%s %s" % [base, roman(k.number)]


## Numero romano per i re (1-3999); oltre, il numero in cifre.
static func roman(value: int) -> String:
	if value < 1 or value > 3999:
		return str(value)
	var symbols := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var values := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var rest := value
	var out := ""
	for i in symbols.size():
		var step: int = values[i]
		while rest >= step:
			out += String(symbols[i])
			rest -= step
	return out
