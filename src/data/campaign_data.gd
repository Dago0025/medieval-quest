class_name CampaignData
extends RefCounted
## Stato iniziale di una campagna, letto da un file startpos.
##
## Gli ID (fazioni, regioni) sono salvati in MAIUSCOLO: i file originali non
## sono coerenti (per esempio `ID_Tripoli` contro `ID_TRIPOLI`) e il gioco li
## tratta come uguali.
##
## FORMATO DEDOTTO dei comandi sui personaggi (fase 4a). Fonti: i commenti `//` di EARLY_XL.TXT,
## _MOD_DANESI_LEGGIMI.txt (punti 12, 13, 17), lo script _MOD_BACKUP_ORIG/auror_apply.py e il
## confronto con MTW_XL_EARLY_HEROES.TXT (verificato sulle 29 fazioni attive):
## - `SetStartLeader:: FN flag n c0 c1 ... c(n-1)`: `flag` e' sempre 0 (significato ignoto);
##   `n` e' il numero di nomi reali della fazione coperti (<= il secondo numero di SET_FORENAMES);
##   `ci` e' il contatore del numerale del nome reale di indice i: quanti re con quel nome sono
##   gia' saliti al trono, compreso il re in carica. Prova: Auror `0 1 1` = «Darkos I» (LEGGIMI
##   punto 17), Early XL Inghilterra `0 7  0 2 0 0 2 1 2` con primo re famoso «William II» (nome 4,
##   contatore 2). Il capo iniziale e' il primo dei FAMOUS_KINGS della fazione il cui numerale e'
##   uguale al contatore del suo nome (Francia: Philippe I; Bisanzio: Alexius I); senza corrispondenza
##   il primo nome reale con contatore > 0. Eta' e attributi non sono nel file.
## - `PlaceLeader:: ID_REGIONE FN`: regione del capo (e quindi dell'esercito che comanda).
## - `AddHeir:: FN sesso eta'`: un membro della famiglia reale; sesso 1 = maschio (57 su 76 righe,
##   il LEGGIMI punto 12-13 dice «erede maschio» per le righe `1 eta'` aggiunte agli Auror), 0 =
##   femmina (diventera' principessa); eta' in anni all'inizio della campagna (da 2 a 24).
## - `AddTitle:: ID_REGIONE "nome" lealta acume terrore guerra pieta vizio virtu' ["descrizione"]`:
##   titolo di governatore della provincia (una per regione); le colonne dopo il nome sono i
##   bonus all'attributo del titolare (guerra = comando); nome vuoto = titolo senza nome.
##   Le ultime due colonne (indice di vizio e di virtu') sono 0 in tutte le righe attive.
## - `AddOffice:: FN edificio "nome" lealta acume terrore guerra pieta vizio virtu'`: carica di
##   Stato, come i titoli ma legata a un edificio (royal_palace, constables_palace, marshals_palace,
##   chancellery, admiralty, cathedral, grand_mosque, pagan_monument) che la sblocca.
## - `SetNameData:: "percorso"`: file dei nomi, dei re e degli eroi famosi (HeroesLoader).


class Faction:
	var id: String
	var index: int
	var active_type := ""        ## FT_MAJOR ecc.; vuoto = fazione non attiva
	var religion := ""
	var culture := ""
	var behaviour := ""          ## comportamento dell'IA (SetBehaviour)
	var treasury := PackedInt32Array()   ## un valore per livello di difficoltà
	var color_primary := Color.WHITE
	var color_secondary := Color.BLACK
	var shield_large := ""       ## immagine dello scudo grande (SetShieldImage, per esempio "Denmark_lge" in campmap/shields)
	var shield_small := ""       ## immagine dello scudo piccolo ("Denmark_sml")
	var shield_piece := ""       ## scudo dipinto sulle pedine della mappa ("F1003" in campmap/pieces/Units/Christian/Shields)
	var leader_region := ""      ## regione in cui si trova il capo (PlaceLeader)
	var start_leader := PackedStringArray()  ## argomenti grezzi di SetStartLeader
	var heirs: Array[PackedStringArray] = [] ## argomenti grezzi di AddHeir

	func _init(faction_id: String, faction_index: int) -> void:
		id = faction_id
		index = faction_index

	func is_active() -> bool:
		return active_type != ""

	## Contatori dei numerali dei nomi reali di `SetStartLeader` (vedi il formato in testa al file):
	## uno per nome reale, al massimo `n` valori; vuoto se la riga manca o e' troncata.
	func leader_counters() -> PackedInt32Array:
		var out := PackedInt32Array()
		if start_leader.size() < 2:
			return out
		var count := start_leader[1].to_int()
		for i in range(count):
			if 2 + i >= start_leader.size():
				break
			out.append(start_leader[2 + i].to_int())
		return out

	## Membri della famiglia reale di `AddHeir`, nell'ordine del file: Dictionary {"male": bool, "age": int}.
	func heir_entries() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for h in heirs:
			if h.size() >= 2:
				out.append({"male": h[0] == "1", "age": h[1].to_int()})
		return out

	## Vero se la fazione ha i dati del capo (`SetStartLeader`).
	func has_leader_data() -> bool:
		return not start_leader.is_empty()


class Region:
	var id: String
	var index: int               ## posizione nell'ordine di dichiarazione (terra e mare separati)
	var is_sea := false
	var display_name := ""
	var culture := ""
	var climate := ""
	var architecture := ""
	var income := 0              ## rendita base di SetAttributes
	var castle_name := ""
	var owner := "FN_REBEL"
	var rebels := 0
	var castle_pos := Vector2i.ZERO
	var has_port := false
	var port_pos := Vector2i.ZERO
	var port_dir := 0            ## orientamento del molo (SetPort, quarto campo, 0-7): fotogramma di campmap/ships/port.BIF
	var trade_goods := PackedStringArray()
	var resources := PackedStringArray()
	var buildings := PackedStringArray()
	var neighbours := PackedStringArray()

	func _init(region_id: String, region_index: int, sea: bool) -> void:
		id = region_id
		index = region_index
		is_sea = sea


## Bonus agli attributi di chi detiene un titolo o una carica (`AddTitle`, `AddOffice`).
class BonusDef:
	var display_name := ""       ## nome del titolo o della carica ("" = senza nome)
	var loyalty := 0
	var acumen := 0
	var dread := 0
	var warcraft := 0            ## bonus al comando
	var piety := 0
	var vice_index := 0          ## sempre 0 nei file reali
	var virtue_index := 0
	var line := 0

	## Bonus per l'attributo indicato ("command", "dread", "piety", "acumen", "loyalty").
	func bonus(attr: String) -> int:
		match attr:
			"command":
				return warcraft
			"dread":
				return dread
			"piety":
				return piety
			"acumen":
				return acumen
			"loyalty":
				return loyalty
		return 0


## Titolo di governatore di una provincia (`AddTitle`).
class TitleDef extends BonusDef:
	var region := ""


## Carica di Stato di una fazione (`AddOffice`), sbloccata dall'edificio `building`.
class OfficeDef extends BonusDef:
	var faction := ""
	var building := ""           ## in minuscolo, come nel file (royal_palace...)


class StartUnit:
	var region: String
	var unit_type: String
	var amount: int              ## uomini; per emissari e principesse è l'anno di nascita
	var culture := ""
	var line: int

	func _init(region_id: String, type_name: String, value: int, line_number: int) -> void:
		region = region_id
		unit_type = type_name
		amount = value
		line = line_number


var start_year := 0
var period := ""
var period_starts := {}          ## "EARLY"/"HIGH"/"LATE" -> anno di inizio
var unit_prod_file := ""
var building_prod_file := ""
var factions: Array[Faction] = []
var regions: Array[Region] = []
var start_units: Array[StartUnit] = []
var trade_goods := {}            ## nome merce -> valore
var name_data_file := ""         ## SetNameData: percorso del file dei nomi (con i separatori del file)
var titles: Array[TitleDef] = [] ## AddTitle, nell'ordine del file
var offices: Array[OfficeDef] = [] ## AddOffice, nell'ordine del file
## Fase 6a: regioni immuni a inondazioni (`SetRegionUnfloodable`) e a terremoti (`SetRegionUnquakeable`), in maiuscolo,
## nell'ordine del file. Un mondo che non ne dichiara nessuna non ha disastri (`has_disaster_data`).
var unfloodable := PackedStringArray()
var unquakeable := PackedStringArray()
var errors := PackedStringArray()   ## riferimenti a ID non dichiarati e simili
var ignored_commands := {}       ## comandi non ancora interpretati -> conteggio

var _faction_by_id := {}
var _region_by_id := {}
var _land_count := 0
var _sea_count := 0


static func norm(id: String) -> String:
	return id.strip_edges().to_upper()


func add_faction(id: String) -> Faction:
	var key := norm(id)
	if _faction_by_id.has(key):
		errors.append("Fazione dichiarata due volte: %s" % key)
		return _faction_by_id[key]
	var f := Faction.new(key, factions.size())
	factions.append(f)
	_faction_by_id[key] = f
	return f


func add_region(id: String, sea: bool) -> Region:
	var key := norm(id)
	if _region_by_id.has(key):
		errors.append("Regione dichiarata due volte: %s" % key)
		return _region_by_id[key]
	var idx := _sea_count if sea else _land_count
	if sea:
		_sea_count += 1
	else:
		_land_count += 1
	var r := Region.new(key, idx, sea)
	regions.append(r)
	_region_by_id[key] = r
	return r


func faction(id: String) -> Faction:
	return _faction_by_id.get(norm(id))


func region(id: String) -> Region:
	return _region_by_id.get(norm(id))


func land_regions() -> Array[Region]:
	var out: Array[Region] = []
	for r in regions:
		if not r.is_sea:
			out.append(r)
	return out


func sea_regions() -> Array[Region]:
	var out: Array[Region] = []
	for r in regions:
		if r.is_sea:
			out.append(r)
	return out


func active_factions() -> Array[Faction]:
	var out: Array[Faction] = []
	for f in factions:
		if f.is_active():
			out.append(f)
	return out


## Coppie di regioni confinanti senza ripetizioni, ciascuna come "A|B" con A < B.
func adjacency_pairs() -> PackedStringArray:
	var seen := {}
	for r in regions:
		for n in r.neighbours:
			var a: String = r.id
			var b: String = n
			if b < a:
				var tmp: String = a
				a = b
				b = tmp
			seen[a + "|" + b] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## Coppie in cui A elenca B tra i vicini ma B non elenca A.
func asymmetric_neighbours() -> PackedStringArray:
	var out := PackedStringArray()
	for r in regions:
		for n in r.neighbours:
			var other: Region = region(n)
			if other != null and not other.neighbours.has(r.id):
				out.append("%s -> %s" % [r.id, n])
	return out


## Vero se la regione e' immune alle inondazioni (`SetRegionUnfloodable`).
func is_unfloodable(region_id: String) -> bool:
	return unfloodable.has(norm(region_id))


## Vero se la regione e' immune ai terremoti (`SetRegionUnquakeable`).
func is_unquakeable(region_id: String) -> bool:
	return unquakeable.has(norm(region_id))


## Vero se lo startpos dichiara almeno una regione immune a inondazioni o terremoti: e' il segno che il mondo ha i
## disastri (nei mondi di prova senza queste righe il fine anno non li estrae e non consuma numeri casuali).
func has_disaster_data() -> bool:
	return not unfloodable.is_empty() or not unquakeable.is_empty()


## Titolo di governatore della regione, null se non ce n'e'.
func title_for(region_id: String) -> TitleDef:
	var key := norm(region_id)
	for t in titles:
		if t.region == key:
			return t
	return null


## Carica di Stato della fazione legata all'edificio (in minuscolo), null se non esiste.
func office_for(faction_id: String, building: String) -> OfficeDef:
	var f := norm(faction_id)
	var b := building.strip_edges().to_lower()
	for o in offices:
		if o.faction == f and o.building == b:
			return o
	return null


## Cariche di Stato di una fazione, nell'ordine del file.
func offices_of(faction_id: String) -> Array[OfficeDef]:
	var f := norm(faction_id)
	var out: Array[OfficeDef] = []
	for o in offices:
		if o.faction == f:
			out.append(o)
	return out


## Nome del file dei nomi senza cartelle (SetNameData usa `campmap\names\FILE.TXT`).
func name_data_basename() -> String:
	return name_data_file.replace("\\", "/").get_file()


func regions_owned_by(faction_id: String) -> Array[Region]:
	var key := norm(faction_id)
	var out: Array[Region] = []
	for r in regions:
		if r.owner == key:
			out.append(r)
	return out
