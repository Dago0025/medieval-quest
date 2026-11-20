class_name FactionState
extends RefCounted
## Stato dinamico di una fazione.

const SPEND_BUILDINGS := "costruzioni"
const SPEND_RECRUITS := "arruolamenti"
const SPEND_RETRAIN := "riaddestramento"
const SPEND_MERCENARIES := "mercenari"
const SPEND_BRIBES := "corruzione"

var id := ""
var treasury := 0
var alive := true
var is_player := false
## Dettaglio dell'ultimo fine anno: agricoltura, miniere, commercio, mantenimento, netto.
var last_income := {}
## Spese dell'anno in corso per voce, in fiorini (i rimborsi tolgono): "costruzioni", "arruolamenti", "riaddestramento",
## "mercenari", "corruzione" (segnalazione di Federico, 2026-11-13: il tesoro scendeva con il reddito netto in attivo, perche'
## il reddito non conta le spese, per esempio le code ripetute). A fine anno vanno in `last_income["spese"]`.
var spent := {}
## Tesoro alla chiusura dell'ultimo fine anno (-1 = non noto, salvataggi precedenti): la differenza con il tesoro alla chiusura
## seguente e' il saldo reale dell'anno (`last_income["saldo"]`).
var treasury_mark := -1
## Fase 5c: scomunica papale (`PapacyProcessor`). Solo una fazione cattolica puo' essere scomunicata; l'anno e' quello
## dell'evento (0 = mai) e `excommunication_leader` l'id del capo al momento (0 = nessuno): la scomunica cade alla morte
## del capo scomunicato o del Papa.
var excommunicated := false
var excommunication_year := 0
var excommunication_leader := 0
## Piano del commercio navale dell'IA (ADR-053, `AiTrade`): zone di mare da presidiare con una nave ciascuna e anno in cui
## e' stato fatto (-1 = mai). La simulazione non lo legge; si salva perche' l'IA ripianifica solo ogni qualche anno.
var ai_trade_zones := PackedStringArray()
var ai_trade_year := -1
## Informazioni delle spie (missione «spiare», 18/11/2026): "P:<provincia>" o "A:<id esercito>" -> ultimo anno valido.
var intel := {}


func _init(faction_id: String = "", start_treasury: int = 0, is_alive: bool = true) -> void:
	id = faction_id
	treasury = start_treasury
	treasury_mark = start_treasury   # partita nuova: il primo saldo parte dal tesoro iniziale (from_dict lo sovrascrive)
	alive = is_alive


## Spesa: toglie dal tesoro e la registra sotto `category` (vedi `spent`).
func spend(amount: int, category: String) -> void:
	treasury -= amount
	spent[category] = int(spent.get(category, 0)) + amount


## Rimborso di una spesa: torna nel tesoro e si toglie dalla voce `category`.
func refund(amount: int, category: String) -> void:
	treasury += amount
	spent[category] = int(spent.get(category, 0)) - amount


## Chiude l'anno: saldo reale (variazione del tesoro dall'ultima chiusura, se nota) e spese per voce in `last_income`.
func close_year() -> void:
	if treasury_mark >= 0:
		last_income["saldo"] = treasury - treasury_mark
	var closed := {}
	for key in spent:
		if int(spent[key]) != 0:
			closed[key] = int(spent[key])
	last_income["spese"] = closed
	spent = {}
	treasury_mark = treasury


func to_dict() -> Dictionary:
	var d := {"id": id, "tesoro": treasury, "viva": alive, "giocatore": is_player, "ultimo_reddito": last_income.duplicate(true)}
	if not spent.is_empty():
		d["spese_anno"] = spent.duplicate()
	if treasury_mark >= 0:
		d["tesoro_chiusura"] = treasury_mark
	# fase 5c: compare solo per le fazioni scomunicate (i salvataggi precedenti non l'hanno)
	if excommunicated:
		d["scomunicata"] = true
		d["anno_scomunica"] = excommunication_year
		d["capo_scomunica"] = excommunication_leader
	if ai_trade_year >= 0:
		d["rotte_ia"] = {"anno": ai_trade_year, "zone": Array(ai_trade_zones)}
	if not intel.is_empty():
		d["spionaggio"] = intel.duplicate()
	return d


static func from_dict(d: Dictionary) -> FactionState:
	var f := FactionState.new(str(d.get("id", "")), int(d.get("tesoro", 0)), bool(d.get("viva", true)))
	f.is_player = bool(d.get("giocatore", false))
	var li: Dictionary = d.get("ultimo_reddito", {})
	f.last_income = li.duplicate(true)
	var sp: Variant = d.get("spese_anno", {})
	if typeof(sp) == TYPE_DICTIONARY:
		for key in sp:
			f.spent[str(key)] = int(sp[key])
	# salvataggi precedenti: il primo saldo parte dal tesoro al caricamento (le spese da li' in poi sono registrate)
	f.treasury_mark = int(d.get("tesoro_chiusura", f.treasury))
	f.excommunicated = bool(d.get("scomunicata", false))
	if f.excommunicated:
		f.excommunication_year = int(d.get("anno_scomunica", 0))
		f.excommunication_leader = int(d.get("capo_scomunica", 0))
	var routes: Variant = d.get("rotte_ia", null)
	if typeof(routes) == TYPE_DICTIONARY:
		var rd: Dictionary = routes
		f.ai_trade_year = int(rd.get("anno", -1))
		f.ai_trade_zones = SimUtil.strings_from(rd.get("zone", []))
	var intel_data: Variant = d.get("spionaggio", {})
	if typeof(intel_data) == TYPE_DICTIONARY:
		for key in intel_data:
			f.intel[str(key)] = int(intel_data[key])
	return f
