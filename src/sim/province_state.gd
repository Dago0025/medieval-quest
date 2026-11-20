class_name ProvinceState
extends RefCounted
## Stato dinamico di una provincia di terra.
##
## Fase 5b: composizione religiosa (`religions`) e zelo (`zeal`). Le percentuali sommano sempre a 100 e sono multipli di
## `RELIGION_UNIT` (0,25), numeri esatti in binario: le somme in virgola mobile non perdono mai un decimale. Tutte le
## modifiche passano da `ReligionProcessor.shift`; `normalize_religions` riporta a 100 qualunque insieme di valori.

const CATHOLIC := "CATHOLIC"
const ORTHODOX := "ORTHODOX"
const MUSLIM := "MUSLIM"
const PAGAN := "PAGAN"
const HERETIC := "HERETIC"
## Culto Imperiale degli Auror (richiesta di Federico del 16/11/2026): religione propria, per ora con edifici e agenti dei
## cattolici (`GameCommands.religion_base`). In coda all'ordine: le parita' e i salvataggi precedenti non cambiano.
const IMPERIAL := "IMPERIAL"
## Ordine fisso delle religioni (salvataggi, ripartizioni, parita').
const RELIGIONS := ["CATHOLIC", "ORTHODOX", "MUSLIM", "PAGAN", "HERETIC", "IMPERIAL"]
## Passo delle percentuali (in punti): 400 passi fanno 100.
const RELIGION_UNIT := 0.25
const UNITS_TOTAL := 400

var id := ""                 ## id della regione (maiuscolo)
var owner := ""              ## id della fazione proprietaria
## Edifici costruiti: famiglia (maiuscolo) -> livello (da 1). Assente = non costruito.
var buildings := {}
var building_queue: Array[QueueItem] = []
var unit_queue: Array[QueueItem] = []
var tax_level := 2           ## 0-4, 2 = normale
## Ultimo reddito con il dettaglio: agricoltura, miniere, commercio, totale, conteso.
var last_income := {}
## Fase 4b: lealta' corrente in percentuale (0..lealta massima); sotto 100 puo' scoppiare una rivolta.
var loyalty := 100
## Fase 4b: proprietario al momento dell'ultimo calcolo della lealta' (serve a riconoscere un cambio di proprietario).
var loyalty_owner := ""
## Fase 4b: ultima fazione che possedeva la provincia prima che passasse ai ribelli ("" se mai); una fazione estinta
## puo' riemergere solo in una provincia ribelle che possedeva.
var former_owner := ""
## Fase 4b: contatori: "anni_sotto_soglia" (anni consecutivi con lealta' sotto la soglia di rivolta), "rivolte".
var counters := {}
## Fase 4b: dettaglio dell'ultimo calcolo della lealta' (vedi `ProvinceProcessor.loyalty_terms`) con l'obiettivo e
## la lealta' corrente; vuoto prima del primo calcolo.
var last_loyalty := {}
## Fase 5b: religione -> percentuale (somma 100, multipli di `RELIGION_UNIT`). Predefinito: tutta pagana; la partita nuova
## e i salvataggi precedenti la impostano con `ReligionProcessor.init_religions`.
var religions := {"CATHOLIC": 0.0, "ORTHODOX": 0.0, "MUSLIM": 0.0, "PAGAN": 100.0, "HERETIC": 0.0, "IMPERIAL": 0.0}
## Fase 5b: zelo (0-100) della religione del proprietario.
var zeal := 50
## Fase 6a: effetti di durata un anno (disastri, Peste Nera), letti dal reddito (`Economy.province_income`) e azzerati a fine
## anno dopo il calcolo del reddito (`EventProcessor.clear_temporary`). Chiavi: `TEMP_FARM` (moltiplicatore dell'agricoltura,
## 0..1) e `TEMP_INCOME` (moltiplicatore di tutto il reddito); una chiave assente vale 1,0.
var temp_effects := {}
## Fase 6a: merci aggiunte da eventi storici (`merci`), in maiuscolo, che si sommano a quelle della regione nel commercio.
var extra_goods := PackedStringArray()
## Coda di reclutamento ripetuta (richiesta di Federico, solo il giocatore la imposta dall'interfaccia): fazione che l'ha
## attivata ("" = spenta). Vale solo finche' e' il proprietario: se la provincia cambia mano si spegne da sola. Ogni unita'
## completata torna in fondo alla coda, pagata di nuovo (`TurnProcessor._advance_recruitment`).
var repeat_faction := ""
## Unita' della coda ripetuta in attesa di fondi, in ordine: la coda e' in pausa finche' il tesoro non basta per la prima.
var repeat_pending := PackedStringArray()

const TEMP_FARM := "agricoltura"
const TEMP_INCOME := "reddito"


func _init(region_id: String = "", owner_id: String = "") -> void:
	id = region_id
	owner = owner_id
	loyalty_owner = owner_id


func level_of(family: String) -> int:
	return int(buildings.get(family.strip_edges().to_upper(), 0))


## Livello 0 o meno = edificio tolto (demolizione, danni della conquista): la voce sparisce.
func set_level(family: String, level: int) -> void:
	var key := family.strip_edges().to_upper()
	if level <= 0:
		buildings.erase(key)
	else:
		buildings[key] = level


## Moltiplicatore temporaneo (1,0 se non c'e' l'effetto).
func temp_factor(key: String) -> float:
	var v: Variant = temp_effects.get(key, 1.0)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return 1.0


## Imposta un effetto temporaneo; se ce n'e' gia' uno sulla stessa chiave si tiene il piu' severo (il valore minore).
func add_temp_factor(key: String, factor: float) -> void:
	temp_effects[key] = minf(temp_factor(key), clampf(factor, 0.0, 1.0))


## Percentuale della religione (0 se non e' una delle cinque).
func religion_pct(religion: String) -> float:
	return float(religions.get(religion, 0.0))


## Passi (multipli di `RELIGION_UNIT`) della religione: la quantita' intera su cui lavorano le ripartizioni.
func religion_units(religion: String) -> int:
	return roundi(religion_pct(religion) / RELIGION_UNIT)


## Somma delle percentuali (100 in uno stato coerente).
func religions_sum() -> float:
	var total := 0.0
	for k in RELIGIONS:
		total += religion_pct(k)
	return total


## Religione con la quota maggiore (a parita' la prima nell'ordine di `RELIGIONS`).
func majority_religion() -> String:
	var best := RELIGIONS[0] as String
	for k in RELIGIONS:
		if religion_pct(k) > religion_pct(best):
			best = k
	return best


## Imposta la composizione dai passi `units` (religione -> passi interi, somma `UNITS_TOTAL`).
func set_religion_units(units: Dictionary) -> void:
	var d := {}
	for k in RELIGIONS:
		d[k] = float(int(units.get(k, 0))) * RELIGION_UNIT
	religions = d


## Normalizza valori qualunque (religione -> numero, anche non intero o con somma diversa da 100) in una composizione
## valida: i valori negativi o illeggibili valgono 0, si scalano a 100 e si arrotondano ai passi con il metodo del
## maggior resto (i passi avanzati vanno ai resti piu' grandi, a parita' alla prima religione dell'ordine). Se la somma
## e' zero: tutta pagana. Restituisce un Dictionary religione -> float.
static func normalize_religions(values: Dictionary) -> Dictionary:
	var raw: Array[float] = []
	var total := 0.0
	for k in RELIGIONS:
		var v: Variant = values.get(k, 0.0)
		var f := 0.0
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			f = maxf(0.0, float(v))
		if is_nan(f) or is_inf(f):
			f = 0.0
		raw.append(f)
		total += f
	var out := {}
	if total <= 0.0:
		for k in RELIGIONS:
			out[k] = 100.0 if k == PAGAN else 0.0
		return out
	var steps: Array[int] = []
	var rests: Array[float] = []
	var given := 0
	for i in RELIGIONS.size():
		var exact := raw[i] / total * float(UNITS_TOTAL)
		var whole := int(floorf(exact))
		steps.append(whole)
		rests.append(exact - float(whole))
		given += whole
	var left := UNITS_TOTAL - given
	while left > 0:
		var best := 0
		for i in RELIGIONS.size():
			if rests[i] > rests[best]:
				best = i
		steps[best] += 1
		rests[best] = -1.0
		left -= 1
	for i in RELIGIONS.size():
		out[RELIGIONS[i]] = float(steps[i]) * RELIGION_UNIT
	return out


func to_dict() -> Dictionary:
	var bq: Array = []
	for q in building_queue:
		bq.append(q.to_dict())
	var uq: Array = []
	for q in unit_queue:
		uq.append(q.to_dict())
	var d := {
		"id": id,
		"proprietario": owner,
		"edifici": buildings.duplicate(),
		"coda_costruzione": bq,
		"coda_reclutamento": uq,
		"tassa": tax_level,
		"ultimo_reddito": last_income.duplicate(),
		"lealta": loyalty,
		"lealta_proprietario": loyalty_owner,
		"ex_proprietario": former_owner,
		"contatori": counters.duplicate(),
		"ultima_lealta": last_loyalty.duplicate(),
		"religioni": religions.duplicate(),
		"zelo": zeal,
	}
	# fase 6a: compaiono solo se ci sono (i salvataggi precedenti non li hanno)
	if not temp_effects.is_empty():
		d["effetti_temporanei"] = temp_effects.duplicate()
	if not extra_goods.is_empty():
		d["merci_extra"] = Array(extra_goods)
	if repeat_faction != "":
		d["coda_ripetuta"] = repeat_faction
	if not repeat_pending.is_empty():
		d["ripeti_in_attesa"] = Array(repeat_pending)
	return d


static func from_dict(d: Dictionary) -> ProvinceState:
	var p := ProvinceState.new(str(d.get("id", "")), str(d.get("proprietario", "")))
	var b: Dictionary = d.get("edifici", {})
	for key in b:
		p.buildings[str(key)] = int(b[key])
	var bq: Array = d.get("coda_costruzione", [])
	for item in bq:
		var qd: Dictionary = item
		p.building_queue.append(QueueItem.from_dict(qd))
	var uq: Array = d.get("coda_reclutamento", [])
	for item in uq:
		var ud: Dictionary = item
		p.unit_queue.append(QueueItem.from_dict(ud))
	p.tax_level = int(d.get("tassa", 2))
	var li: Dictionary = d.get("ultimo_reddito", {})
	p.last_income = li.duplicate()
	# fase 4b: nei salvataggi vecchi mancano; la lealta' si ricalcola al caricamento (SaveGame)
	p.loyalty = int(d.get("lealta", 100))
	p.loyalty_owner = str(d.get("lealta_proprietario", p.owner))
	p.former_owner = str(d.get("ex_proprietario", ""))
	var counter_data: Dictionary = d.get("contatori", {})
	p.counters = counter_data.duplicate()
	var terms: Dictionary = d.get("ultima_lealta", {})
	p.last_loyalty = terms.duplicate()
	# fase 5b: nei salvataggi precedenti mancano (SaveGame li imposta con ReligionProcessor.init_religions)
	var religion_data: Variant = d.get("religioni", null)
	if religion_data is Dictionary:
		var rd: Dictionary = religion_data
		p.religions = normalize_religions(rd)
	p.zeal = clampi(int(d.get("zelo", p.zeal)), 0, 100)
	var temp_data: Variant = d.get("effetti_temporanei", {})
	if typeof(temp_data) == TYPE_DICTIONARY:
		var td: Dictionary = temp_data
		for key in td:
			p.temp_effects[str(key)] = float(td[key])
	p.extra_goods = SimUtil.strings_from(d.get("merci_extra", []))
	p.repeat_faction = str(d.get("coda_ripetuta", ""))
	p.repeat_pending = SimUtil.strings_from(d.get("ripeti_in_attesa", []))
	return p


## Vero se la coda di reclutamento si ripete per il proprietario attuale.
func repeats_units() -> bool:
	return repeat_faction != "" and repeat_faction == owner


## Voci della coda di reclutamento contando quelle in attesa di fondi della coda ripetuta.
func unit_queue_load() -> int:
	return unit_queue.size() + (repeat_pending.size() if repeats_units() else 0)
