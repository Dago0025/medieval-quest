class_name CampaignUiText
extends RefCounted
## Testi dell'interfaccia della campagna (in italiano) costruiti dallo stato di gioco.
## Funzioni pure: leggono lo stato e producono stringhe, non lo modificano.

const TAX_NAMES := ["Molto bassa", "Bassa", "Normale", "Alta", "Molto alta"]


## Nome del livello di tassa (0-4); oltre i cinque livelli noti "Livello N".
static func tax_name(level: int) -> String:
	if level >= 0 and level < TAX_NAMES.size():
		var label: String = TAX_NAMES[level]
		return Lang.t(label)
	return Lang.t("Livello %d") % level


static func era_name(era: String) -> String:
	match era.strip_edges().to_upper():
		"EARLY":
			return Lang.t("Primo Medioevo")
		"HIGH":
			return Lang.t("Pieno Medioevo")
		"LATE":
			return Lang.t("Tardo Medioevo")
	return era


## Intero con segno esplicito: +12, -5, 0.
static func signed(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return "%d" % value


## Nome mostrato di una regione: il nome italiano (data/province.cfg) se c'è, poi quello dei dati, altrimenti l'ID.
static func region_name(state: GameState, region_id: String) -> String:
	var italian := RegionNames.italian(region_id)
	if italian != "":
		return italian
	var r: CampaignData.Region = state.campaign.region(region_id)
	if r == null:
		return region_id
	if r.display_name != "":
		return r.display_name
	return r.id


## "FEUDAL_KNIGHTS" -> "Feudal Knights".
static func unit_name(unit_id: String) -> String:
	# nome dell'originale (names.txt dell'installazione, «Feudal Knights»); senza installazione l'id leggibile
	var original := UnitTexts.plural_name(unit_id)
	return original if original != "" else unit_id.capitalize()


## Nome al singolare (agenti, crociate: «Emissary», «Crusade»), dall'installazione; altrimenti l'id leggibile.
static func agent_unit_name(unit_id: String) -> String:
	var original := UnitTexts.singular_name(unit_id)
	return original if original != "" else unit_id.capitalize()


## Pila in cui combatte il comandante dell'esercito (la sua guardia), -1 se non ha comandante o pile. L'originale lega il
## generale a un'unita' precisa; qui la si ricava dai dati: la prima pila la cui unita' e' indicata come adatta a un
## generale (colonna 9: PREFERRED, poi OK, poi le altre), a parita' la piu' costosa, poi la prima. Le unita' a cavallo vengono
## prima di tutte (ADR-114: il capo combatte con la guardia a cavallo).
static func commander_stack(state: GameState, army: Army) -> int:
	if army == null or army.stacks.is_empty() or army.is_fleet or state.commander_of(army.id) == null:
		return -1
	var best := -1
	var best_score := -1
	for i in army.stacks.size():
		var unit := state.units.get_unit(army.stacks[i].unit_id) if state.units != null else null
		var rank := 1
		var cost := 0
		if unit != null:
			cost = unit.cost
			match unit.general_candidate:
				"PREFERRED":
					rank = 3
				"OK":
					rank = 2
				"DISCOURAGED":
					rank = 0
		if unit != null and HistoricalLimits.is_mounted(unit):
			rank += 10
		if unit != null and unit.unique:
			rank += 100   # Ankalagon: la carta di Darkos e' il suo drago
		var score := rank * 1000000 + mini(cost, 999999)
		if score > best_score:
			best_score = score
			best = i
	return best


## Pennacchio dell'originale sulla carta della pila del comandante: corona del re, insegna dell'erede e dei principi, del
## generale per gli altri ("" se l'esercito non ha comandante).
static func commander_pennant(state: GameState, army: Army) -> String:
	var c := state.commander_of(army.id) if army != null else null
	if c == null:
		return ""
	match c.role:
		Character.ROLE_LEADER:
			return "campmap/is_king_mon.BIF"
		Character.ROLE_HEIR, Character.ROLE_PRINCE:
			return "campmap/is_heir_mon.BIF"
	return "campmap/is_noble_mon.BIF"


## Pennacchio dell'ammiraglio: l'originale non ne ha uno, il percorso serve solo a OriginalHud.pennant_texture per trovare
## il dipinto assets/ui/veste/pennacchio_admiral.png (ADR-062).
const ADMIRAL_PENNANT := "campmap/is_admiral_mon.BIF"


## Distintivo per la carta `index` dell'esercito nella barra in basso (richiesta di Federico dell'11/11/2026: re e principi
## si riconoscono dalle carte, senza aprire la pergamena): {"immagine" (pennacchio dell'originale), "nota"} per la pila del
## comandante, {} per le altre.
static func commander_badge(state: GameState, army: Army, index: int) -> Dictionary:
	if army != null and army.is_fleet:
		# ADR-062: la nave dell'ammiraglio ha il suo pennacchio (l'ancora), come la pila del comandante negli eserciti
		if index < 0 or index != Admirals.flagship(state, army):
			return {}
		var caption := admiral_caption(state, army)
		return {"immagine": ADMIRAL_PENNANT, "nota": Lang.t("Nave dell'%s") % caption}
	if army == null or index < 0 or index != commander_stack(state, army):
		return {}
	return {"immagine": commander_pennant(state, army), "nota": commander_stack_note(state, army)}


## Personaggio legato alla carta `index` dell'esercito (il comandante sulla sua pila), 0 per le altre: il clic destro su
## quella carta apre la sua scheda con il ritratto invece della scheda dell'unita' (richiesta di Federico dell'11/11/2026).
## Unita' guidata da un personaggio (richiesta di Federico del 27/11/2026: dalla scheda del re o del generale si apre la
## scheda della sua unita'): {"esercito", "pila"} della pila del comandante; vuoto se non comanda un esercito di terra
## (gli ammiragli non sono personaggi: la loro nave apre gia' la scheda dell'ammiraglio).
static func led_unit(state: GameState, c: Character) -> Dictionary:
	if state == null or c == null or not c.alive or c.army <= 0:
		return {}
	var army := state.army(c.army)
	if army == null or army.stacks.is_empty():
		return {}
	var index := commander_stack(state, army) if state.commander_of(army.id) == c else -1
	if index < 0 or index >= army.stacks.size():
		return {}
	return {"esercito": army.id, "pila": index}


static func card_character(state: GameState, army: Army, index: int) -> int:
	if army == null or index < 0 or index != commander_stack(state, army):
		return 0
	var c := state.commander_of(army.id)
	return c.id if c != null else 0


## Sala dei regnanti (richiesta di Federico dell'11/11/2026): i capi in carica di tutte le fazioni vive, il giocatore per
## primo e poi per numero di province. Ogni voce: {"personaggio", "nome", "fazione", "nome_fazione", "eta", "province",
## "rapporto" («La tua fazione», «In guerra», «Alleato», «In pace»), "tono" ("proprio", "guerra", "alleato", "pace")}.
static func rulers(state: GameState, player_id: String) -> Array[Dictionary]:
	var me := SimUtil.norm(player_id)
	var out: Array[Dictionary] = []
	for f in state.factions:
		if not f.alive:
			continue
		var c := state.leader_of(f.id)
		if c == null or not c.alive:
			continue
		var tone := "pace"
		var relation := Lang.t("In pace")
		if f.id == me:
			tone = "proprio"
			relation = Lang.t("La tua fazione")
		elif state.at_war(me, f.id):
			tone = "guerra"
			relation = Lang.t("In guerra con te")
		elif state.is_allied(me, f.id):
			tone = "alleato"
			relation = Lang.t("Tuo alleato")
		var title := state.rules.dynasty.leader_title(f.id)
		out.append({"personaggio": c.id, "nome": ("%s %s" % [Lang.t(title), c.full_name()]) if title != "" else c.full_name(), "fazione": f.id, "nome_fazione": faction_name(f.id), "eta": c.age(state.year),
			"province": state.provinces_of(f.id).size(), "rapporto": relation, "tono": tone})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (str(a["tono"]) == "proprio") != (str(b["tono"]) == "proprio"):
			return str(a["tono"]) == "proprio"
		if int(a["province"]) != int(b["province"]):
			return int(a["province"]) > int(b["province"])
		return str(a["fazione"]) < str(b["fazione"]))
	return out


## Chi comanda l'esercito, per il titolo della barra: «re Darkos I», «erede …», «principe …», «generale …» ("" se nessuno).
static func commander_caption(state: GameState, army: Army) -> String:
	if army != null and army.is_fleet:
		return admiral_caption(state, army)
	var c := state.commander_of(army.id) if army != null else null
	if c == null:
		return ""
	var rank := Lang.t("generale")
	match c.role:
		Character.ROLE_LEADER:
			rank = leader_rank(state, c.faction)
		Character.ROLE_HEIR:
			rank = Lang.t("erede")
		Character.ROLE_PRINCE:
			rank = Lang.t("principe")
	return "%s %s" % [rank, c.full_name()]


## Chi guida la pila del comandante, per il suggerimento della carta: «Unità del re Knud II».
static func commander_stack_note(state: GameState, army: Army) -> String:
	var c := state.commander_of(army.id) if army != null else null
	if c == null:
		return ""
	var who := Lang.t("del generale")
	match c.role:
		Character.ROLE_LEADER:
			var title := state.rules.dynasty.leader_title(c.faction)
			who = Lang.t("dell'%s") % Lang.t(title) if title != "" else Lang.t("del re")
		Character.ROLE_HEIR:
			who = Lang.t("dell'erede")
		Character.ROLE_PRINCE:
			who = Lang.t("del principe")
	var note := Lang.t("Unità %s %s") % [who, c.full_name()]
	var office := office_name(state, c)
	if office != "":
		note += " · %s" % office
	return note


## Nome di un edificio al livello dato: "Castle (livello 3)".
static func building_name(state: GameState, family_id: String, level: int) -> String:
	# nomi italiani (data/nomi_edifici.cfg): «Castello (livello 7)»
	var italian := building_label(family_id, level)
	if italian != "":
		return Lang.t("%s (livello %d)") % [italian, level]
	var fam: BuildingType = state.buildings.get_family(family_id) if state.buildings != null else null
	if fam == null:
		return Lang.t("%s (livello %d)") % [family_id.capitalize(), level]
	var base := fam.id
	var lv: BuildingType.Level = fam.get_level(maxi(1, level))
	if lv != null and lv.label != "":
		base = lv.label
	return Lang.t("%s (livello %d)") % [base.replace("_", " ").capitalize(), level]


static var _building_cfg: ConfigFile = null


## Azzera le tabelle dei nomi gia' lette (cambio di lingua, Lang.set_language).
static func reset_tables() -> void:
	_building_cfg = null
	_vnv_cfg = null

## Nome italiano dell'edificio al livello (oltre l'ultimo: l'ultimo), "" se la famiglia non e' nella tabella.
static func building_label(family_id: String, level: int) -> String:
	if _building_cfg == null:
		_building_cfg = ConfigFile.new()
		_building_cfg.load(Lang.data_path("res://data/nomi_edifici.cfg"))   # in inglese data/lingue/en/nomi_edifici.cfg
	var names: Array = _building_cfg.get_value("livelli", family_id.to_upper(), [])
	if names.is_empty():
		return ""
	return str(names[clampi(level, 1, names.size()) - 1])


## Nome di una fazione per il pannello, da data/fazioni.cfg: "FN_DANISH" -> "Auror", "FN_ENGLISH" -> "Inglesi"; i ribelli
## "ribelli"; senza voce nella tabella dall'id ("FN_ALPHA" -> "Alpha").
static func faction_name(faction_id: String) -> String:
	return FactionStyle.name_of(faction_id)


# --- nomi delle fazioni nelle frasi (fase 8d): articolo, preposizioni articolate e accordo del verbo -------------------

const _PREP := {
	"di": {"il": "del", "lo": "dello", "l'": "dell'", "la": "della", "i": "dei", "gli": "degli", "le": "delle"},
	"a": {"il": "al", "lo": "allo", "l'": "all'", "la": "alla", "i": "ai", "gli": "agli", "le": "alle"},
	"da": {"il": "dal", "lo": "dallo", "l'": "dall'", "la": "dalla", "i": "dai", "gli": "dagli", "le": "dalle"},
	"in": {"il": "nel", "lo": "nello", "l'": "nell'", "la": "nella", "i": "nei", "gli": "negli", "le": "nelle"},
	"su": {"il": "sul", "lo": "sullo", "l'": "sull'", "la": "sulla", "i": "sui", "gli": "sugli", "le": "sulle"},
}


## Fazione come soggetto a inizio frase: «Gli Inglesi», «Il Sacro Romano Impero», «Alpha» (senza articolo).
static func fsubj(faction_id: String) -> String:
	var t := FactionStyle.with_article(faction_id)
	return t.left(1).to_upper() + t.substr(1)


## Fazione con l'articolo dentro la frase: «gli Inglesi».
static func fart(faction_id: String) -> String:
	return FactionStyle.with_article(faction_id)


## Preposizioni italiane -> inglesi per fprep in inglese (ADR-066); «da» vale «from» salvo `english` esplicito («by»).
const _PREP_EN := {"di": "of", "a": "to", "da": "from", "in": "in", "su": "on", "contro": "against", "tra": "among",
	"fra": "among", "con": "with", "per": "for", "verso": "towards"}


## Preposizione articolata: fprep("di", "FN_ENGLISH") -> «degli Inglesi»; preposizioni senza forma articolata
## (contro, tra, con, per) restano staccate: «contro gli Inglesi». In inglese «of the English»; `english` sceglie la
## preposizione inglese quando quella della tabella non va bene (fprep("da", id, "by") -> «by the English»).
static func fprep(prep: String, faction_id: String, english: String = "") -> String:
	if Lang.is_english():
		var en := english if english != "" else str(_PREP_EN.get(prep, prep))
		return "%s %s" % [en, fart(faction_id)] if en != "" else fart(faction_id)
	var a := FactionStyle.article(faction_id)
	var n := FactionStyle.name_of(faction_id)
	if a == "":
		return "%s %s" % [prep, n]
	var first := a.get_slice(" ", 0) if not a.ends_with("'") else "l'"
	var rest := a.substr(first.length()).strip_edges() if not a.ends_with("'") else ""
	var table: Dictionary = _PREP.get(prep, {})
	if table.has(first):
		var joined := str(table[first])
		var tail := ("%s %s" % [rest, n]).strip_edges() if rest != "" else n
		return joined + tail if joined.ends_with("'") else "%s %s" % [joined, tail]
	return "%s %s" % [prep, fart(faction_id)]


## Verbo accordato alla fazione: fverb("FN_ENGLISH", "dichiara", "dichiarano") -> «dichiarano».
static func fverb(faction_id: String, singular: String, plural: String) -> String:
	return plural if FactionStyle.is_plural(faction_id) else singular


## Piu' fazioni con l'articolo: «gli Inglesi e i Francesi»; con `prep` ogni nome prende la preposizione.
static func fnames(ids: PackedStringArray, prep: String = "", english: String = "") -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(fprep(prep, id, english) if prep != "" else fart(id))
	if parts.size() <= 1:
		return "".join(parts)
	return Lang.t("%s e %s") % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


## Verbo per un gruppo di fazioni: plurale se sono piu' d'una o se l'unica e' plurale.
static func fverbs(ids: PackedStringArray, singular: String, plural: String) -> String:
	if ids.size() > 1:
		return plural
	return fverb(ids[0], singular, plural) if ids.size() == 1 else singular


## Condizione sugli edifici in parole: gruppi alternativi separati da " oppure ", token di un
## gruppo da " + ". I token noti sono mostrati con il nome dell'edificio.
static func requires_text(state: GameState, condition: Array[PackedStringArray]) -> String:
	var groups := PackedStringArray()
	for group in condition:
		var parts := PackedStringArray()
		for token in group:
			var lv: BuildingType.Level = state.buildings.resolve(token)
			if lv != null:
				var base := lv.label if lv.label != "" else lv.family
				parts.append("%s %d" % [base.replace("_", " ").capitalize(), lv.level])
			else:
				parts.append(token.capitalize())
		groups.append(" + ".join(parts))
	return Lang.t(" oppure ").join(groups)


## Nomi delle voci di spesa di FactionState.spent, nell'ordine in cui si mostrano.
const SPEND_NAMES := [["arruolamenti", "Arruolamenti"], ["costruzioni", "Costruzioni"], ["riaddestramento", "Riaddestramento"],
	["mercenari", "Mercenari"], ["corruzione", "Corruzione"]]


## Spese per voce in una riga: «Arruolamenti -14200 · Costruzioni -1280»; vuota se non ce ne sono.
static func spending_line(spent: Dictionary) -> String:
	var parts := PackedStringArray()
	for pair in SPEND_NAMES:
		var v := int(spent.get(pair[0], 0))
		if v != 0:
			parts.append("%s %s" % [Lang.t(str(pair[1])), signed(-v)])
	return " · ".join(parts)


## Righe del bilancio della fazione (segnalazione di Federico, 2026-11-13: il tesoro scendeva con il reddito netto in attivo).
## Saldo reale dell'ultimo anno (variazione del tesoro), reddito netto (rendite meno mantenimento), spese per voce e il resto
## (eventi, doni, riscatti); poi le spese gia' fatte quest'anno. Vuoto prima del primo fine anno.
static func balance_lines(f: FactionState) -> PackedStringArray:
	var out := PackedStringArray()
	if f == null:
		return out
	var li := f.last_income
	if not li.is_empty():
		var net := int(li.get("netto", 0))
		var spent: Dictionary = li.get("spese", {})
		var total_spent := 0
		for key in spent:
			total_spent += int(spent[key])
		if li.has("saldo"):
			out.append(Lang.t("Saldo dell'ultimo anno: %s denari") % signed(int(li["saldo"])))
		out.append(Lang.t("Reddito netto (rendite meno mantenimento): %s") % signed(net))
		var line := spending_line(spent)
		if line != "":
			out.append(Lang.t("Spese: %s") % line)
		if li.has("saldo"):
			var other := int(li["saldo"]) - net + total_spent
			if other != 0:
				out.append(Lang.t("Altro (eventi, doni, rimborsi): %s") % signed(other))
	var now := spending_line(f.spent)
	if now != "":
		out.append(Lang.t("Spese di quest'anno finora: %s") % now)
	return out


## Righe del reddito di una provincia (risultato di Economy.province_income).
static func income_lines(income: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if bool(income.get("conteso", false)):
		out.append(Lang.t("Provincia contesa: reddito zero"))
		return out
	out.append(Lang.t("Agricoltura: %d") % int(income.get("agricoltura", 0)))
	out.append(Lang.t("Miniere: %d") % int(income.get("miniere", 0)))
	out.append(Lang.t("Commercio: %d") % int(income.get("commercio", 0)))
	var sea := int(income.get("commercio_marittimo", 0))
	var imports := int(income.get("importazioni", 0))
	if sea > 0 or imports > 0:
		out.append(Lang.t("   locale %d · via mare %d · importazioni %d") % [int(income.get("commercio_locale", 0)), sea, imports])
	var routes: Array = income.get("rotte", [])
	if not routes.is_empty():
		out.append(Lang.t("   rotte commerciali: %d porti stranieri") % routes.size())
	out.append(Lang.t("Totale annuo: %d") % int(income.get("totale", 0)))
	return out


## Una riga per un evento del registro dell'anno, senza id grezzi di regioni o fazioni (`humanize_ids`).
static func format_event(state: GameState, e: Dictionary) -> String:
	return humanize_ids(state, _format_event_raw(state, e))


static func _format_event_raw(state: GameState, e: Dictionary) -> String:
	var kind := str(e.get("tipo", ""))
	if kind == GameState.EV_PRISONERS:
		return str(e.get("testo", ""))   # ADR-073: testo gia' composto da PrisonerProcessor
	if kind == GameState.EV_AMERICAS_CONTACT:
		# ADR-114: arrivo degli europei nelle Americhe
		return Lang.t("Primo approdo straniero nelle Americhe: %s a %s. Da ora i popoli del Nuovo Mondo conoscono il cavallo.") % [
			FactionStyle.with_article(str(e.get("fazione", ""))), region_name(state, str(e.get("regione", "")))]
	if kind == GameState.EV_ROYAL_GUARD:
		# ADR-114: guardia del capo (testo con il nome del personaggio gia' composto dalla simulazione)
		return str(e.get("testo", ""))
	if kind == GameState.EV_BUILT:
		return Lang.t("Costruzione completata a %s: %s.") % [
			region_name(state, str(e.get("provincia", ""))),
			building_name(state, str(e.get("edificio", "")), int(e.get("livello", 1)))]
	if kind == GameState.EV_RECRUITED:
		return Lang.t("Reclutata a %s l'unità %s (esercito %d).") % [
			region_name(state, str(e.get("provincia", ""))),
			unit_name(str(e.get("unita", ""))),
			int(e.get("esercito", 0))]
	if kind == GameState.EV_QUEUE_PAUSED:
		return Lang.t("Coda ripetuta di %s in pausa: per %s servono %d denari. Riprende quando il tesoro basta.") % [
			region_name(state, str(e.get("provincia", ""))),
			unit_name(str(e.get("unita", ""))),
			int(e.get("costo", 0))]
	if kind == GameState.EV_QUEUE_RESUMED:
		return Lang.t("Coda ripetuta di %s ripresa: il tesoro basta di nuovo.") % region_name(state, str(e.get("provincia", "")))
	if kind == GameState.EV_QUEUE_DROPPED:
		return Lang.t("%s esce dalla coda ripetuta di %s: %s.") % [
			unit_name(str(e.get("unita", ""))),
			region_name(state, str(e.get("provincia", ""))),
			humanize_ids(state, str(e.get("motivo", ""))).trim_suffix(".")]
	if kind == GameState.EV_ARMIES_MERGED:
		return Lang.t("L'esercito %d si unisce all'esercito %d a %s (%d pile).") % [
			int(e.get("esercito", 0)), int(e.get("bersaglio", 0)),
			region_name(state, str(e.get("regione", ""))), int(e.get("pile", 0))]
	if kind == GameState.EV_MERGE_FAILED:
		return Lang.t("L'esercito %d non si unisce all'esercito %d a %s: %s.") % [
			int(e.get("esercito", 0)), int(e.get("bersaglio", 0)),
			region_name(state, str(e.get("regione", ""))), str(e.get("motivo", ""))]
	if kind == GameState.EV_ARMY_GARRISONED:
		var outside := int(e.get("fuori", 0))
		return Lang.t("L'esercito %d arriva a %s e si barrica nel castello (%d pile)%s.") % [
			int(e.get("esercito", 0)), region_name(state, str(e.get("regione", ""))), int(e.get("dentro", 0)),
			Lang.t("; %d restano fuori per mancanza di posto") % outside if outside > 0 else ""]
	if kind == GameState.EV_GARRISON_FAILED:
		return Lang.t("L'esercito %d non si barrica nel castello di %s: %s.") % [
			int(e.get("esercito", 0)), region_name(state, str(e.get("regione", ""))),
			humanize_ids(state, str(e.get("motivo", ""))).trim_suffix(".")]
	if kind == GameState.EV_MOVED:
		if bool(e.get("via_mare", false)):
			return Lang.t("Esercito %d: da %s a %s via mare (%s).") % [
				int(e.get("esercito", 0)),
				region_name(state, str(e.get("da", ""))),
				region_name(state, str(e.get("a", ""))),
				chain_names(state, e.get("catena", []))]
		return Lang.t("Esercito %d: da %s a %s.") % [
			int(e.get("esercito", 0)),
			region_name(state, str(e.get("da", ""))),
			region_name(state, str(e.get("a", "")))]
	if kind == GameState.EV_TRANSPORT_BLOCKED:
		return Lang.t("Trasporto via mare interrotto: l'esercito %d resta a %s (destinazione %s): %s.") % [
			int(e.get("esercito", 0)),
			region_name(state, str(e.get("regione", ""))),
			region_name(state, str(e.get("verso", ""))),
			humanize_ids(state, str(e.get("motivo", Lang.t("catena non più valida"))))]
	if kind == GameState.EV_PENDING_CONFLICT:
		return Lang.t("Esercito %d fermo a %s: %s è di un'altra fazione, conflitto in sospeso.") % [
			int(e.get("esercito", 0)),
			region_name(state, str(e.get("da", ""))),
			region_name(state, str(e.get("verso", "")))]
	if kind == GameState.EV_NEGATIVE_TREASURY:
		return Lang.t("Tesoro negativo: %d denari.") % int(e.get("tesoro", 0))
	var phase3 := _format_phase3(state, kind, e)
	if phase3 != "":
		return phase3
	var phase4 := _format_phase4(state, kind, e)
	if phase4 != "":
		return phase4
	var phase5a := _format_phase5a(state, kind, e)
	if phase5a != "":
		return phase5a
	var phase5b := _format_phase5b(state, kind, e)
	if phase5b != "":
		return phase5b
	var phase5c := CampaignUiPapacy.format_event(state, kind, e)
	if phase5c != "":
		return phase5c
	var phase6 := CampaignUiEvents.format_event(state, kind, e)
	if phase6 != "":
		return phase6
	var phase7 := CampaignUiProposals.format_event(state, kind, e)
	if phase7 != "":
		return phase7
	var retrain := CampaignUiRetrain.format_event(state, kind, e)
	if retrain != "":
		return retrain
	if kind == GameState.EV_ADMIRAL_PROMOTED:
		return Lang.t("L'ammiraglio %s (%s) sale a %s dopo la vittoria in %s.") % [text_of(e.get("nome", "")), faction_name(_actor_id(e)),
			admiral_stars_text(int_of(e.get("stelle"))), region_name(state, text_of(e.get("regione", "")))]
	if kind == GameState.EV_MERCENARY_HIRED:
		var fid := _actor_id(e)
		return Lang.t("%s %s %s (%d uomini) a %s per %d denari.") % [fsubj(fid), fverb(fid, Lang.t("assolda"), Lang.t("assoldano")),
			unit_name(text_of(e.get("unita", ""))), int_of(e.get("uomini")), region_name(state, text_of(e.get("provincia", ""))), int_of(e.get("costo"))]
	return kind


## Righe del resoconto di fine anno per una fazione, in testo semplice (la finestra usa year_report_sections, impaginato da
## CampaignUiReport). Prima le sezioni della fase 3 (battaglie, conquiste, assedi, ritirate e catture, fazioni distrutte,
## guerre) e della fase 4 («Corte» e «Province») con gli eventi che riguardano la fazione; poi i suoi altri eventi; infine gli
## avvisi e gli errori del risultato di TurnProcessor.end_year. Senza eventi di queste sezioni il resoconto non ha
## intestazioni. Fazioni distrutte, estinte e riemerse si riportano sempre. Gli avvisi di tesoro negativo non si ripetono
## (c'è già l'evento, e quelli di altre fazioni non riguardano il giocatore).
static func year_report(state: GameState, faction_id: String, result: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for sec in year_report_sections(state, faction_id, result):
		var kind := str(sec["tipo"])
		var title := str(sec["titolo"])
		var lines: PackedStringArray = sec["righe"]
		if title != "":
			out.append("— %s —" % title)
		for line in lines:
			match kind:
				REPORT_SECTION:
					out.append("  " + line)
				REPORT_WARNINGS:
					out.append(Lang.t("Avviso: %s") % line)
				REPORT_ERRORS:
					out.append(Lang.t("Errore nei dati: %s") % line)
				_:
					out.append(line)
	return out


const REPORT_SECTION := "sezione"     ## sezione con intestazione (Battaglie, Corte, ...)
const REPORT_OTHERS := "altri"        ## altri eventi della fazione (con intestazione solo se ci sono sezioni)
const REPORT_WARNINGS := "avvisi"     ## avvisi del fine anno
const REPORT_ERRORS := "errori"       ## errori nei dati


## Il resoconto di fine anno diviso in blocchi, nell'ordine di visualizzazione: [{"tipo": REPORT_*, "titolo": testo ("" =
## senza intestazione), "righe": PackedStringArray}]. I blocchi vuoti non ci sono. Stesse regole di year_report.
static func year_report_sections(state: GameState, faction_id: String, result: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := SimUtil.norm(faction_id)
	var sections := all_report_sections()
	var section_of := {}
	var section_lines: Array = []
	for i in range(sections.size()):
		var kinds: PackedStringArray = sections[i]["tipi"]
		for k in kinds:
			section_of[k] = i
		section_lines.append(PackedStringArray())
	var others := PackedStringArray()
	var news := PackedStringArray()
	var always := always_reported_kinds()
	var world := world_news_kinds()
	for e in state.events:
		var kind := str(e.get("tipo", ""))
		if section_of.has(kind):
			if always.has(kind) or event_mentions(e, key) or _agent_move_relevant(state, kind, e, key):
				var index: int = section_of[kind]
				var lines: PackedStringArray = section_lines[index]
				lines.append(format_event(state, e))
				section_lines[index] = lines
			elif world.has(kind):
				news.append(format_event(state, e))   # notizia dalle altre fazioni (richiesta di Federico del 2026-11-13)
		elif str(e.get("fazione", "")) == key and not hidden_report_kinds().has(kind):
			others.append(format_event(state, e))
	var any_section := false
	for i in range(sections.size()):
		var lines: PackedStringArray = section_lines[i]
		if lines.is_empty():
			continue
		any_section = true
		out.append({"tipo": REPORT_SECTION, "titolo": str(sections[i]["titolo"]), "righe": lines})
	if not news.is_empty():
		any_section = true
		out.append({"tipo": REPORT_SECTION, "titolo": Lang.t(NEWS_TITLE), "righe": news})
	if not others.is_empty():
		out.append({"tipo": REPORT_OTHERS, "titolo": Lang.t("Altri eventi") if any_section else "", "righe": others})
	var warnings := PackedStringArray()
	for w in result.get("avvisi", []):
		var text := str(w)
		if not text.contains("tesoro negativo"):
			warnings.append(text)
	if not warnings.is_empty():
		out.append({"tipo": REPORT_WARNINGS, "titolo": "", "righe": warnings})
	var errors := PackedStringArray()
	for er in result.get("errori", []):
		errors.append(str(er))
	if not errors.is_empty():
		out.append({"tipo": REPORT_ERRORS, "titolo": "", "righe": errors})
	return out


## «ammiraglio Erik Haraldsson ★★★»: nome e stelle dell'ammiraglio della flotta (ADR-056), "" se non ne ha.
static func admiral_caption(state: GameState, army: Army) -> String:
	var stars := Admirals.stars(state, army)
	if stars < 0:
		return ""
	return Lang.t("ammiraglio %s %s") % [str(army.admiral.get("nome", "")), "★".repeat(stars) if stars > 0 else Lang.t("(nessuna stella)")]


## Righe dell'ammiraglio per la descrizione della flotta: nome, stelle, battaglie navali vinte e perse (come la scheda
## dell'originale) e l'effetto delle stelle.
static func admiral_lines(state: GameState, army: Army) -> PackedStringArray:
	var out := PackedStringArray()
	var stars := Admirals.stars(state, army)
	if stars < 0:
		return out
	out.append(Lang.t("Ammiraglio %s con %d %s") % [str(army.admiral.get("nome", "")), army.stack_count(), Lang.t("nave") if army.stack_count() == 1 else Lang.t("navi")])
	out.append(Lang.t("Stelle: %s · battaglie navali vinte %d, perse %d") % [admiral_stars_text(stars), int(army.admiral.get("vinte", 0)), int(army.admiral.get("perse", 0))])
	return out


## «3 stelle», «1 stella», «nessuna stella».
static func admiral_stars_text(stars: int) -> String:
	if stars <= 0:
		return Lang.t("nessuna stella")
	return "%d %s" % [stars, Lang.t("stella") if stars == 1 else Lang.t("stelle")]


static func army_title(army: Army) -> String:
	if army.is_fleet:
		return Lang.t("Flotta %d") % army.id
	return Lang.t("Esercito %d") % army.id


## Descrizione di un esercito o di una flotta: posizione, uomini, unità, percorso.
static func describe_army(state: GameState, army: Army) -> String:
	var lines := PackedStringArray()
	lines.append("%s (%s)" % [army_title(army), faction_name(army.faction)])
	if army.loyal_to != "" and army.faction == GameState.REBEL:
		lines.append(Lang.t("Ribelli lealisti %s: se prendono la provincia la consegnano a loro") % fprep("di", army.loyal_to, "to"))
	if army.is_fleet:
		lines.append_array(admiral_lines(state, army))
	lines.append(Lang.t("Posizione: %s") % region_name(state, army.region))
	var status := army_status(state, army)
	if status != "":
		lines.append(status)
	lines.append(Lang.t("Unità: %d · uomini: %d") % [army.stack_count(), army.men_total()])
	for s in army.stacks:
		lines.append("  %s × %d" % [unit_name(s.unit_id), s.men])
	if not army.path.is_empty():
		var names := PackedStringArray()
		for step in army.path:
			names.append(region_name(state, step))
		lines.append(Lang.t("Movimento: %s") % " > ".join(names))
		if not army.sea_route.is_empty():
			lines.append(Lang.t("Trasporto via mare, attraverso: %s") % chain_names(state, Array(army.sea_route)))
		var last: String = army.path[army.path.size() - 1]
		if attack_target(state, army, last):
			lines.append(Lang.t("Attacco a %s: la guerra si dichiara a fine anno") % region_name(state, last))
	if army.pending_conflict != "":
		lines.append(Lang.t("Conflitto in sospeso con %s") % region_name(state, army.pending_conflict))
	var aim := CampaignUiAttack.target_line(state, army)
	if aim != "":
		lines.append(aim)
	return "\n".join(lines)


# --- Trasporto via mare (spec. fase 3 §9) -------------------------------------------

## Nomi delle zone di una catena ("Mare del Nord > Canale"); `chain` e' un Array di id (anche da JSON).
static func chain_names(state: GameState, chain: Variant) -> String:
	var names := PackedStringArray()
	for id in list_of(chain):
		names.append(region_name(state, str(id)))
	return " > ".join(names)


## Sostituisce gli id di regione ("ID_NORTH_SEA") di un testo con i loro nomi mostrati.
## Anche gli id delle fazioni (FN_...) diventano il loro nome (richiesta di Federico del 27/11/2026: «FN_DANISH» compariva
## nei messaggi degli Auror, per esempio negli spostamenti via mare non possibili).
static func humanize_ids(state: GameState, text: String) -> String:
	if not (text.contains("ID_") or text.contains("FN_")):
		return text
	var pattern := RegEx.new()
	pattern.compile("(ID|FN)_[A-Z0-9_]+")
	var out := text
	var found := pattern.search_all(text)
	var i := found.size() - 1
	while i >= 0:
		var m: RegExMatch = found[i]
		var token := m.get_string()
		var shown := region_name(state, token) if token.begins_with("ID_") else faction_id_label(state, token)
		out = out.substr(0, m.get_start()) + shown + out.substr(m.get_end())
		i -= 1
	return out


## Nome di una fazione da mostrare al posto del suo id (anche ribelli e Papato); l'id com'e' se non e' una fazione.
static func faction_id_label(state: GameState, token: String) -> String:
	var key := token.strip_edges().to_upper()
	if state != null and state.faction(key) == null and state.campaign != null and state.campaign.faction(key) == null \
			and key != GameState.REBEL and key != GameState.PAPAL:
		return token
	return SimUtil.faction_label(key)


## Province da evidenziare quando e' selezionato `army`: se e' un esercito di terra del giocatore,
## quelle raggiungibili via mare (GameCommands.sea_destinations); altrimenti nessuna.
static func sea_reachable(state: GameState, army: Army, player_id: String) -> PackedStringArray:
	if army == null or army.is_fleet or army.faction != SimUtil.norm(player_id):
		return PackedStringArray()
	return GameCommands.sea_destinations(state, player_id, army.id)


## Id delle regioni lungo cui si disegna la freccia di un trasporto: partenza, zone della catena,
## destinazione. Vuoto se l'esercito non ha un trasporto ordinato.
static func transport_region_ids(army: Army) -> PackedStringArray:
	var out := PackedStringArray()
	if army.sea_route.is_empty() or army.path.is_empty():
		return out
	out.append(army.region)
	out.append_array(army.sea_route)
	out.append(army.path[army.path.size() - 1])
	return out


## Testo dell'errore di un ordine di movimento rifiutato, con i nomi delle regioni al posto degli id.
static func order_error_text(state: GameState, error: String) -> String:
	return humanize_ids(state, error)


# --- Fase 3: guerre, assedi, battaglie ---------------------------------------------
# La simulazione della fase 3 espone i dati con nomi che qui sono dati per scontati ma letti
# in modo difensivo (prop, event_kind): se un nome manca, il testo si accorcia ma non si rompe.

const REBEL_ID := "FN_REBEL"
## Motivi di fine assedio (codici della simulazione) in inglese; in italiano si mostra il codice com'e'.
const SIEGE_END_EN := {"conquista": "conquered", "tolto": "lifted", "guarnigione_assente": "empty castle"}
## Fazioni nominate al massimo nella barra in alto; le altre diventano "+N".
const BAR_MAX_ENEMIES := 3

const SIEGE_FACTION_KEYS := ["faction", "fazione", "besieger", "assediante", "attacker"]
const SIEGE_YEARS_KEYS := ["years", "anni", "anni_assedio", "years_besieged"]
const SIEGE_LEFT_KEYS := ["years_left", "years_to_starve", "anni_alla_resa", "anni_alla_fame", "starve_in"]
const SIEGE_ARMIES_KEYS := ["army_ids", "armies", "eserciti", "assedianti", "besiegers"]
const ASSAULT_KEYS := ["assault", "assault_ordered", "assault_armies", "assalto", "assalto_ordinato"]

static var _kind_cache := {}


## Valore della costante di evento di GameState con quel nome ("EV_BATTLE"). Se la simulazione
## non la definisce (ancora), il nome in minuscolo: i confronti restano coerenti e non si rompe nulla.
static func event_kind(const_name: String) -> String:
	if _kind_cache.has(const_name):
		var cached: String = _kind_cache[const_name]
		return cached
	var script: GDScript = GameState
	var constants: Dictionary = script.get_script_constant_map()
	var value := const_name.to_lower()
	if constants.has(const_name):
		value = str(constants[const_name])
	_kind_cache[const_name] = value
	return value


## Sezioni del resoconto di fine anno per gli eventi della fase 3, nell'ordine di visualizzazione:
## [{"titolo": testo, "tipi": PackedStringArray dei tipi di evento}].
static func phase3_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Battaglie"), ["EV_BATTLE", "EV_ADMIRAL_PROMOTED"]],
		[Lang.t("Conquiste"), ["EV_PROVINCE_CAPTURED"]],
		[Lang.t("Assedi"), ["EV_SIEGE_STARTED", "EV_ASSAULT", "EV_SALLY", "EV_STARVED", "EV_SIEGE_ENDED"]],
		[Lang.t("Ritirate e catture"), ["EV_RETREAT", "EV_CAPTURED_UNITS", "EV_PRISONERS"]],
		[Lang.t("Fazioni distrutte"), ["EV_FACTION_DESTROYED"]],
		[Lang.t("Guerre dichiarate"), ["EV_WAR_DECLARED"]],
	]
	return _sections_from(defs)


## Sezioni della fase 4: «Corte» (4a: personaggi) e «Province» (4b: lealtà, rivolte, guerre civili).
## I tipi della 4b si leggono da GameState con event_kind: se la costante non c'è ancora, il tipo
## non corrisponde a nessun evento e la sezione resta semplicemente vuota.
static func phase4_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Corte"), ["EV_BIRTH", "EV_COMING_OF_AGE", "EV_DEATH", "EV_SUCCESSION", "EV_HERO_APPEARS", "EV_VNV_GAINED", "EV_TITLE_CHANGED", "EV_OFFICE_CHANGED", "EV_STAR_CHANGED", "EV_ROYAL_GUARD"]],
		[Lang.t("Province"), ["EV_LOYALTY_LOW", "EV_REBELLION", "EV_REBELLION_SPREAD", "EV_LOYALISTS_RETURN", "EV_FACTION_REEMERGED", "EV_CIVIL_WAR", "EV_FACTION_EXTINCT"]],
	]
	return _sections_from(defs)


## Tutte le sezioni del resoconto, nell'ordine: fase 3 poi fase 4.
static func report_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(phase3_sections())
	out.append_array(phase4_sections())
	return out


## Sezioni della fase 5a: «Agenti» (reclutamento, movimenti, catture, missioni fallite), «Intrighe» (corruzioni,
## assassinii, porte aperte dalle spie) e «Diplomazia» (alleanze, tregue, proposte rifiutate, matrimoni).
static func phase5a_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Agenti"), ["EV_AGENT_RECRUITED", "EV_AGENT_MOVED", "EV_AGENT_JOURNEY_STOPPED", "EV_AGENT_CAPTURED", "EV_MISSION_FAILED"]],
		[Lang.t("Intrighe"), ["EV_BRIBE", "EV_BRIBE_REFUSED", "EV_ASSASSINATION", "EV_ASSASSINATION_FAILED", "EV_GATES_OPENED", "EV_SPY_REPORT", "EV_UNREST", "EV_SABOTAGE"]],
		[Lang.t("Diplomazia"), ["EV_ALLIANCE_FORMED", "EV_ALLIANCE_BROKEN", "EV_TRUCE", "EV_TRUCE_BROKEN", "EV_TRUCE_EXPIRED", "EV_PROPOSAL_REFUSED", "EV_PROPOSAL_RECEIVED", "EV_PROPOSAL_EXPIRED", "EV_MARRIAGE"]],
	]
	return _sections_from(defs)


## Sezione della fase 5b: «Religione» (rivolte degli eretici, processi dell'Inquisizione). Le morti sul rogo stanno
## in «Corte» (EV_DEATH, causa «rogo»).
static func phase5b_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Religione"), ["EV_HERETIC_REVOLT", "EV_INQUISITION", "EV_INQUISITION_FAILED"]],
	]
	return _sections_from(defs)


## Sezione della fase 5c: «Papato e crociate» (avvertimenti, tregue e scomuniche del Papa, doni, riemersione del
## Papato, crociate e jihad: bando, bersaglio, reclutamento, diserzioni, esito).
static func phase5c_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Papato e crociate"), [
			"EV_PAPAL_WARNING", "EV_PAPAL_TRUCE", "EV_EXCOMMUNICATION", "EV_EXCOMMUNICATION_LIFTED", "EV_PAPAL_GIFT", "EV_PAPACY_REEMERGED",
			"EV_CRUSADE_LAUNCHED", "EV_CRUSADE_TARGET", "EV_CRUSADE_RECRUITED", "EV_CRUSADE_DESERTION", "EV_CRUSADE_SUCCEEDED", "EV_CRUSADE_FAILED"]],
	]
	return _sections_from(defs)


## Sezione della fase 6: «Eventi e storia» (6a: eventi storici, disastri, Peste Nera, Orda d'Oro; 6b: vittoria, sconfitta, fine
## della campagna).
static func phase6_sections() -> Array[Dictionary]:
	var defs := [
		[Lang.t("Eventi e storia"), [
			"EV_HISTORICAL", "EV_AMERICAS_CONTACT", "EV_FLOOD", "EV_FAMINE", "EV_QUAKE", "EV_STORM", "EV_PLAGUE", "EV_BLACK_DEATH", "EV_HORDE_ARRIVES",
			"EV_HORDE_GONE", "EV_VICTORY", "EV_DEFEAT", "EV_CAMPAIGN_END"]],
	]
	return _sections_from(defs)


## Tutte le sezioni del resoconto di fine anno: fase 3, fase 4, fase 5a, fase 5b, fase 5c, poi fase 6.
static func all_report_sections() -> Array[Dictionary]:
	var out := report_sections()
	out.append_array(phase5a_sections())
	out.append_array(phase5b_sections())
	out.append_array(phase5c_sections())
	out.append_array(phase6_sections())
	return out


## Un agente straniero che entra in una provincia del giocatore e' rilevante anche se non nomina la sua fazione.
static func _agent_move_relevant(state: GameState, kind: String, e: Dictionary, faction_key: String) -> bool:
	if kind != event_kind("EV_AGENT_MOVED"):
		return false
	var province := state.province(text_of(e.get("a")))
	return province != null and province.owner == faction_key


## Tipi di evento che non compaiono nel resoconto di fine anno: le unita' arruolate ogni anno dalle code (richiesta di Federico
## del 2026-11-13: «non ha senso averle»). Restano nel registro degli eventi e nella cronologia della provincia.
static func hidden_report_kinds() -> PackedStringArray:
	return PackedStringArray([event_kind("EV_RECRUITED")])


## Titolo della sezione del resoconto con le notizie dalle altre fazioni.
const NEWS_TITLE := "Notizie dalle altre fazioni"


## Tipi di evento delle altre fazioni che arrivano al giocatore nella sezione `NEWS_TITLE` del resoconto (richiesta di Federico
## del 2026-11-13: guerre, diplomazia, crociate e jihad, scomuniche, successioni ai troni).
static func world_news_kinds() -> PackedStringArray:
	return PackedStringArray([
		event_kind("EV_WAR_DECLARED"), event_kind("EV_ALLIANCE_FORMED"), event_kind("EV_ALLIANCE_BROKEN"), event_kind("EV_TRUCE"),
		event_kind("EV_TRUCE_BROKEN"), event_kind("EV_MARRIAGE"), event_kind("EV_CRUSADE_LAUNCHED"), event_kind("EV_CRUSADE_TARGET"),
		event_kind("EV_CRUSADE_SUCCEEDED"), event_kind("EV_CRUSADE_FAILED"), event_kind("EV_EXCOMMUNICATION"),
		event_kind("EV_EXCOMMUNICATION_LIFTED"), event_kind("EV_SUCCESSION")])


## Tipi di evento riportati a ogni giocatore anche se non nominano la sua fazione.
static func always_reported_kinds() -> PackedStringArray:
	return PackedStringArray([
		event_kind("EV_FACTION_DESTROYED"), event_kind("EV_FACTION_EXTINCT"), event_kind("EV_FACTION_REEMERGED"), event_kind("EV_PAPACY_REEMERGED"),
		event_kind("EV_HISTORICAL"), event_kind("EV_AMERICAS_CONTACT"), event_kind("EV_BLACK_DEATH"), event_kind("EV_HORDE_ARRIVES"), event_kind("EV_HORDE_GONE"),
		event_kind("EV_VICTORY"), event_kind("EV_DEFEAT"), event_kind("EV_CAMPAIGN_END")])


static func _sections_from(defs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in defs:
		var names: Array = d[1]
		var kinds := PackedStringArray()
		for n in names:
			kinds.append(event_kind(str(n)))
		out.append({"titolo": str(d[0]), "tipi": kinds})
	return out


# --- accesso difensivo ---

## Primo campo presente tra `names` di un Dictionary o di un oggetto (proprietà); null se nessuno.
static func prop(obj: Variant, names: Array) -> Variant:
	if obj is Dictionary:
		var d: Dictionary = obj
		for n in names:
			if d.has(n):
				return d[n]
		return null
	if obj is Object:
		var o: Object = obj
		for n in names:
			var field := str(n)
			if field in o:
				return o.get(field)
	return null


static func text_of(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


static func int_of(v: Variant, fallback: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return roundi(float(v))
		TYPE_BOOL:
			return 1 if bool(v) else 0
		TYPE_STRING:
			var s: String = v
			if s.is_valid_int():
				return s.to_int()
	return fallback


## Qualunque valore come Array di voci: null = vuoto; array = le sue voci; Dictionary = le chiavi;
## un valore singolo = una voce.
static func list_of(v: Variant) -> Array:
	var out: Array = []
	match typeof(v):
		TYPE_NIL:
			pass
		TYPE_ARRAY:
			var a: Array = v
			out.append_array(a)
		TYPE_PACKED_STRING_ARRAY:
			var ps: PackedStringArray = v
			for s in ps:
				out.append(s)
		TYPE_PACKED_INT32_ARRAY:
			var p32: PackedInt32Array = v
			for n in p32:
				out.append(n)
		TYPE_PACKED_INT64_ARRAY:
			var p64: PackedInt64Array = v
			for n in p64:
				out.append(n)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			out.append_array(d.keys())
		_:
			out.append(v)
	return out


## Id di eserciti da un valore (interi, oggetti con `id`, Dictionary con "id").
static func army_ids_of(v: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	for item in list_of(v):
		if item is Object or item is Dictionary:
			out.append(int_of(prop(item, ["id"])))
		else:
			out.append(int_of(item))
	return out


## Id (maiuscoli) di fazioni da un valore: stringhe, id di eserciti (si risale alla fazione),
## Dictionary con "fazione" o oggetti con `faction`. Senza doppioni, nell'ordine.
static func faction_ids_of(state: GameState, v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for item in list_of(v):
		var id := ""
		if item is Dictionary or item is Object:
			id = text_of(prop(item, ["fazione", "faction"]))
		elif typeof(item) == TYPE_INT or typeof(item) == TYPE_FLOAT:
			var a: Army = state.army(int(item))
			if a != null:
				id = a.faction
		else:
			id = str(item)
		id = SimUtil.norm(id)
		if id != "" and not out.has(id):
			out.append(id)
	return out


## Nomi di fazioni separati da virgole.
static func faction_names(ids: PackedStringArray) -> String:
	var names := PackedStringArray()
	for id in ids:
		names.append(faction_name(SimUtil.norm(id)))
	return ", ".join(names)


# --- guerre ---

## Chiave di una guerra: "A|B" con A < B (maiuscole).
static func war_key(a: String, b: String) -> String:
	var x := SimUtil.norm(a)
	var y := SimUtil.norm(b)
	if x > y:
		return "%s|%s" % [y, x]
	return "%s|%s" % [x, y]


## Chiavi delle guerre da GameState.wars (Dictionary con le chiavi "A|B", oppure elenco di chiavi
## o di coppie). Vuoto se la simulazione non le ha.
static func war_keys(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for item in list_of(raw):
		if item is Array:
			var pair: Array = item
			if pair.size() == 2:
				out.append(war_key(str(pair[0]), str(pair[1])))
		else:
			out.append(str(item).to_upper())
	return out


## Fazioni in guerra con `faction_id` (senza i ribelli, sempre ostili a tutti), in ordine alfabetico.
static func enemies_from(raw: Variant, faction_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var me := SimUtil.norm(faction_id)
	for key in war_keys(raw):
		var parts := key.split("|")
		if parts.size() != 2:
			continue
		var other := ""
		if parts[0] == me:
			other = parts[1]
		elif parts[1] == me:
			other = parts[0]
		if other != "" and other != REBEL_ID and not out.has(other):
			out.append(other)
	out.sort()
	return out


## Fazioni vive in guerra con `faction_id` nello stato.
static func enemies_of(state: GameState, faction_id: String) -> PackedStringArray:
	var all := enemies_from(state.get("wars"), faction_id)
	var out := PackedStringArray()
	for id in all:
		var f := state.faction(id)
		if f == null or f.alive:
			out.append(id)
	return out


## Testo compatto per la barra in alto: "In pace" oppure "In guerra: A, B, C +2".
static func war_bar_text(enemies: PackedStringArray) -> String:
	if enemies.is_empty():
		return Lang.t("In pace")
	var shown := PackedStringArray()
	for i in range(mini(enemies.size(), BAR_MAX_ENEMIES)):
		shown.append(faction_name(enemies[i]))
	var text := Lang.t("In guerra: %s") % ", ".join(shown)
	if enemies.size() > BAR_MAX_ENEMIES:
		text += " +%d" % (enemies.size() - BAR_MAX_ENEMIES)
	return text


## Tooltip della barra: tutti i nomi, uno per riga.
static func war_tooltip(enemies: PackedStringArray) -> String:
	var lines := PackedStringArray()
	if enemies.is_empty():
		lines.append(Lang.t("Non sei in guerra con nessuna fazione."))
	else:
		lines.append(Lang.t("In guerra con:"))
		for id in enemies:
			lines.append("  %s" % faction_name(id))
	lines.append(Lang.t("I ribelli sono ostili a tutti."))
	return "\n".join(lines)


## Vero se muovere `army` verso `region_id` è un attacco: la regione è di un'altra fazione
## o contiene eserciti di altre fazioni.
static func attack_target(state: GameState, army: Army, region_id: String) -> bool:
	var region := state.campaign.region(region_id)
	if region != null and region.is_sea:
		# in mare si combatte solo con le flotte delle fazioni in guerra (le neutrali convivono): come la simulazione
		return not WarProcessor.hostile_factions(state, army.faction, army.is_fleet, region_id).is_empty()
	var owner_id := ""
	var p := state.province(region_id)
	if p != null:
		owner_id = p.owner
	var present := PackedStringArray()
	for a in state.armies_in(region_id):
		if a.id != army.id and not a.stacks.is_empty():
			present.append(a.faction)
	return MarkerLayout.is_attack_target(army.faction, owner_id, present)


# --- assedi ---

## Dati di un assedio per l'interfaccia, da GameState.sieges (`raw`: regione -> SiegeState o Dictionary).
## {"assediata": bool, "assediante": id, "anni": int, "anni_alla_resa": int (-1 = non noto),
##  "eserciti": PackedInt32Array, "assalto": int (1 = ordinato per tutti, 0 = no, -1 = non noto),
##  "assalto_ids": PackedInt32Array degli eserciti con assalto ordinato}.
static func siege_info_from(raw: Variant, region_id: String) -> Dictionary:
	var out := {"assediata": false, "assediante": "", "anni": 0, "anni_alla_resa": -1,
			"eserciti": PackedInt32Array(), "assalto": -1, "assalto_ids": PackedInt32Array()}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var sieges: Dictionary = raw
	var key := SimUtil.norm(region_id)
	if not sieges.has(key):
		return out
	var siege: Variant = sieges[key]
	out["assediata"] = true
	out["assediante"] = SimUtil.norm(text_of(prop(siege, SIEGE_FACTION_KEYS)))
	out["anni"] = int_of(prop(siege, SIEGE_YEARS_KEYS))
	var left: Variant = prop(siege, SIEGE_LEFT_KEYS)
	if left != null:
		out["anni_alla_resa"] = int_of(left, -1)
	out["eserciti"] = army_ids_of(prop(siege, SIEGE_ARMIES_KEYS))
	var assault: Variant = prop(siege, ASSAULT_KEYS)
	if typeof(assault) == TYPE_BOOL:
		out["assalto"] = 1 if bool(assault) else 0
	elif assault != null:
		out["assalto_ids"] = army_ids_of(assault)
		out["assalto"] = 0
	return out


static func siege_info(state: GameState, region_id: String) -> Dictionary:
	return siege_info_from(state.get("sieges"), region_id)


## Regioni (maiuscole) con un assedio in corso.
static func sieged_regions(state: GameState) -> PackedStringArray:
	var out := PackedStringArray()
	for item in list_of(state.get("sieges")):
		out.append(SimUtil.norm(str(item)))
	return out


## Righe del pannello della provincia sull'assedio; vuote se non è assediata.
static func siege_lines_from(info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not bool(info.get("assediata", false)):
		return out
	var besieger := str(info.get("assediante", ""))
	if besieger == "":
		out.append(Lang.t("Provincia assediata"))
	else:
		out.append(Lang.t("Assediata da %s") % faction_name(besieger))
	out.append(Lang.t("Anni di assedio: %d") % int(info.get("anni", 0)))
	var left := int(info.get("anni_alla_resa", -1))
	if left == 0:
		out.append(Lang.t("Resa per fame: alla fine di quest'anno"))
	elif left > 0:
		out.append(Lang.t("Resa per fame tra %d anni") % left)
	return out


static func siege_lines(state: GameState, region_id: String) -> PackedStringArray:
	return siege_lines_from(siege_info(state, region_id))


## Vero se l'esercito è dentro il castello (Army.in_castle, se la simulazione lo ha).
static func is_in_castle(army: Army) -> bool:
	var v: Variant = prop(army, ["in_castle"])
	return v != null and bool(v)


## Vero se l'esercito assedia la sua regione.
static func is_besieging(state: GameState, army: Army) -> bool:
	if is_in_castle(army):
		return false
	var info := siege_info(state, army.region)
	return is_besieging_from(info, army.id, army.faction)


static func is_besieging_from(info: Dictionary, army_id: int, faction_id: String) -> bool:
	if not bool(info.get("assediata", false)):
		return false
	if str(info.get("assediante", "")) != SimUtil.norm(faction_id):
		return false
	var ids: PackedInt32Array = info.get("eserciti", PackedInt32Array())
	return ids.is_empty() or ids.has(army_id)


## Assalto ordinato dall'esercito: 1 sì, 0 no, -1 non noto.
static func assault_state(state: GameState, army: Army) -> int:
	var own: Variant = prop(army, ["assault", "assault_ordered", "assalto"])
	if typeof(own) == TYPE_BOOL:
		return 1 if bool(own) else 0
	var info := siege_info(state, army.region)
	var flag := int(info.get("assalto", -1))
	if flag == -1:
		return -1
	if flag == 1:
		return 1
	var ids: PackedInt32Array = info.get("assalto_ids", PackedInt32Array())
	return 1 if ids.has(army.id) else 0


## Riga di stato di un esercito per il pannello; vuota se è un esercito qualunque.
static func army_status_text(in_castle: bool, besieging: bool, besieged_by_enemy: bool, years: int, assault: int) -> String:
	if in_castle:
		if besieged_by_enemy:
			return Lang.t("Stato: in guarnigione, assediato (anni di assedio: %d)") % years
		return Lang.t("Stato: in guarnigione nel castello")
	if besieging:
		var text := Lang.t("Stato: assedia il castello (anni di assedio: %d)") % years
		if assault == 1:
			text += Lang.t("\nAssalto ordinato: a fine anno attacca il castello")
		return text
	return ""


static func army_status(state: GameState, army: Army) -> String:
	var info := siege_info(state, army.region)
	var sieged := bool(info.get("assediata", false))
	var enemy := sieged and str(info.get("assediante", "")) != army.faction
	var in_castle := is_in_castle(army)
	var besieging := (not in_castle) and is_besieging_from(info, army.id, army.faction)
	var assault := -1
	if besieging:
		assault = assault_state(state, army)
	return army_status_text(in_castle, besieging, enemy, int(info.get("anni", 0)), assault)


# --- testi degli eventi della fase 3 ---

## Vero se l'evento nomina la fazione in un suo campo (fazione, attaccanti, perdite...).
static func event_mentions(e: Dictionary, faction_id: String) -> bool:
	var key := SimUtil.norm(faction_id)
	for k in e:
		if str(k) == "testo":
			continue
		if _value_has(e[k], key, 3):
			return true
	return false


static func _value_has(v: Variant, key: String, depth: int) -> bool:
	if depth <= 0:
		return false
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return SimUtil.norm(str(v)) == key
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for item in list_of(v):
				if _value_has(item, key, depth - 1):
					return true
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k in d:
				if _value_has(k, key, depth - 1) or _value_has(d[k], key, depth - 1):
					return true
	return false


static func battle_label(battle_type: String, fallback: String = "Battaglia") -> String:
	match battle_type.strip_edges().to_lower():
		"campo":
			return Lang.t("Battaglia in campo")
		"assalto":
			return Lang.t("Assalto al castello")
		"sortita":
			return Lang.t("Sortita della guarnigione")
		"navale":
			return Lang.t("Scontro navale")
	return Lang.t(fallback)


static func _place(state: GameState, e: Dictionary, keys: Array = ["regione"]) -> String:
	var id := text_of(prop(e, keys))
	if id == "":
		return ""
	return region_name(state, id)


static func _actor(e: Dictionary) -> String:
	return faction_name(_actor_id(e))


static func _actor_id(e: Dictionary) -> String:
	return SimUtil.norm(str(e.get("fazione", "")))


## Forze (attaccanti, difensori) di un evento di battaglia: da "forze" (Dictionary
## attaccanti/difensori o coppia) o da forza_attaccanti/forza_difensori. -1 se non note.
static func battle_forces(e: Dictionary) -> Vector2i:
	var fa := -1
	var fd := -1
	var forces: Variant = prop(e, ["forze"])
	if typeof(forces) == TYPE_DICTIONARY:
		var a: Variant = prop(forces, ["attaccanti", "attaccante"])
		var d: Variant = prop(forces, ["difensori", "difensore"])
		if a != null:
			fa = int_of(a, -1)
		if d != null:
			fd = int_of(d, -1)
	elif typeof(forces) == TYPE_ARRAY:
		var pair: Array = forces
		if pair.size() >= 2:
			fa = int_of(pair[0], -1)
			fd = int_of(pair[1], -1)
	var sa: Variant = prop(e, ["forza_attaccanti", "forza_attaccante"])
	var sd: Variant = prop(e, ["forza_difensori", "forza_difensore"])
	if sa != null:
		fa = int_of(sa, -1)
	if sd != null:
		fd = int_of(sd, -1)
	return Vector2i(fa, fd)


## Vincitore in parole ("Danish", "gli attaccanti"); vuoto se non noto o pareggio.
static func battle_winner(state: GameState, e: Dictionary, attackers: PackedStringArray, defenders: PackedStringArray) -> String:
	return faction_names(battle_winner_ids(state, e, attackers, defenders))


## Fazioni vincitrici di una battaglia (vuoto se pareggio o non note).
static func battle_winner_ids(state: GameState, e: Dictionary, attackers: PackedStringArray, defenders: PackedStringArray) -> PackedStringArray:
	var v: Variant = prop(e, ["vincitore", "vincitori"])
	if v == null:
		var av: Variant = prop(e, ["attaccante_vince", "vince_attaccante"])
		if av == null:
			return PackedStringArray()
		return attackers if bool(av) else defenders
	if typeof(v) == TYPE_STRING:
		var word: String = v
		match word.strip_edges().to_lower():
			"", "nessuno", "pareggio":
				return PackedStringArray()
			"attaccante", "attaccanti":
				return attackers
			"difensore", "difensori":
				return defenders
	return faction_ids_of(state, v)


## "Perdite: Danish 120 uomini, Norman 340 uomini"; vuoto se non note.
static func battle_losses(e: Dictionary) -> String:
	var losses: Variant = prop(e, ["perdite"])
	if typeof(losses) != TYPE_DICTIONARY and e.has("perdite_attaccante"):
		# Formato della simulazione (BattleResult.to_dict): perdite per lato.
		var by_side := {}
		by_side[str(e.get("attaccante", "attaccante"))] = int_of(e.get("perdite_attaccante"))
		by_side[str(e.get("difensore", "difensore"))] = int_of(e.get("perdite_difensore"))
		losses = by_side
	if typeof(losses) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = losses
	var parts := PackedStringArray()
	for k in d:
		var raw: Variant = d[k]
		var men := 0
		if typeof(raw) == TYPE_DICTIONARY:
			men = int_of(prop(raw, ["uomini", "men"]))
		else:
			men = int_of(raw)
		parts.append(Lang.t("%s %d uomini") % [faction_name(SimUtil.norm(str(k))), men])
	if parts.is_empty():
		return ""
	return Lang.t("Perdite: %s.") % ", ".join(parts)


## Frase di una battaglia (campo, assalto, sortita, navale).
static func battle_text(state: GameState, e: Dictionary, default_label: String = "Battaglia") -> String:
	var label := battle_label(text_of(prop(e, ["scontro", "tipo_battaglia", "battaglia"])), default_label)
	var where := _place(state, e)
	var attackers := faction_ids_of(state, prop(e, ["attaccanti", "attaccante"]))
	var defenders := faction_ids_of(state, prop(e, ["difensori", "difensore"]))
	if attackers.is_empty() and defenders.is_empty() and str(e.get("testo", "")) != "":
		return str(e.get("testo", ""))
	var text := label
	if where != "":
		text += Lang.t(" a %s") % where
	if not attackers.is_empty() or not defenders.is_empty():
		text += Lang.t(": %s contro %s") % [fnames(attackers) if not attackers.is_empty() else fart(_actor_id(e)), fnames(defenders) if not defenders.is_empty() else Lang.t("i difensori")]
	var forces := battle_forces(e)
	if forces.x >= 0 and forces.y >= 0:
		text += Lang.t(" (forze %d contro %d)") % [forces.x, forces.y]
	text += "."
	var winner_ids := battle_winner_ids(state, e, attackers, defenders)
	if not winner_ids.is_empty():
		text += " %s %s." % [fverbs(winner_ids, Lang.t("Vince"), Lang.t("Vincono")), fnames(winner_ids)]
	var losses := battle_losses(e)
	if losses != "":
		text += " " + losses
	return text


## Testo di un evento della fase 3; vuoto se `kind` non è uno dei loro tipi.
static func _format_phase3(state: GameState, kind: String, e: Dictionary) -> String:
	var actor_id := _actor_id(e)
	var actor := fsubj(actor_id)
	var where := _place(state, e)
	if kind == event_kind("EV_WAR_DECLARED"):
		var declares := fverb(actor_id, Lang.t("dichiara"), Lang.t("dichiarano"))
		var targets := faction_ids_of(state, prop(e, ["contro", "bersaglio", "nemico", "avversario"]))
		if not targets.is_empty():
			return Lang.t("%s %s guerra %s.") % [actor, declares, fnames(targets, "a", "on")]
		if where != "":
			return Lang.t("%s %s guerra (attacco a %s).") % [actor, declares, where]
		return Lang.t("%s %s guerra.") % [actor, declares]
	if kind == event_kind("EV_BATTLE"):
		return battle_text(state, e)
	if kind == event_kind("EV_ASSAULT"):
		var assault := battle_text(state, e, "Assalto al castello")
		if prop(e, ["attaccanti", "attaccante", "vincitore", "forze"]) == null:
			var storms := fverb(actor_id, Lang.t("assalta"), Lang.t("assaltano"))
			return Lang.t("%s %s il castello di %s.") % [actor, storms, where] if where != "" else Lang.t("%s %s il castello.") % [actor, storms]
		return assault
	if kind == event_kind("EV_SALLY"):
		var sally := battle_text(state, e, "Sortita della guarnigione")
		if prop(e, ["attaccanti", "attaccante", "vincitore", "forze"]) == null:
			return Lang.t("La guarnigione di %s fa una sortita.") % where if where != "" else Lang.t("La guarnigione fa una sortita.")
		return sally
	if kind == event_kind("EV_RETREAT"):
		var army_id := int_of(prop(e, ["esercito"]))
		var who := Lang.t("Esercito %d") % army_id if army_id > 0 else Lang.t("Una forza %s") % fprep("di", actor_id)
		var from_id := text_of(prop(e, ["da", "regione"]))
		var to_id := text_of(prop(e, ["a", "verso", "destinazione"]))
		var text := Lang.t("%s si ritira") % who
		if from_id != "":
			text += Lang.t(" da %s") % region_name(state, from_id)
		if to_id != "":
			text += " " + Lang.t("a %s") % region_name(state, to_id)
		elif prop(e, ["castello", "nel_castello"]) == true:
			text += Lang.t(" nel castello")
		return text + "."
	if kind == event_kind("EV_CAPTURED_UNITS"):
		var men := int_of(prop(e, ["uomini", "unita", "numero", "catturati"]))
		var base := Lang.t("Unità %s catturate") % fprep("di", actor_id)
		if men > 0:
			base = Lang.t("%d uomini %s catturati") % [men, fprep("di", actor_id)]
		if where != "":
			base += Lang.t(" a %s") % where
		return base + "."
	if kind == event_kind("EV_SIEGE_STARTED"):
		var besieger_ids := faction_ids_of(state, prop(e, ["assediante", "assedianti"]))
		if besieger_ids.is_empty():
			besieger_ids = PackedStringArray([actor_id])
		var besieger := fnames(besieger_ids)
		besieger = besieger.left(1).to_upper() + besieger.substr(1)
		var starts := fverbs(besieger_ids, Lang.t("inizia"), Lang.t("iniziano"))
		return Lang.t("%s %s l'assedio del castello di %s.") % [besieger, starts, where] if where != "" else Lang.t("%s %s un assedio.") % [besieger, starts]
	if kind == event_kind("EV_SIEGE_ENDED"):
		var ended := Lang.t("L'assedio di %s è terminato") % where if where != "" else Lang.t("Un assedio è terminato")
		var years := int_of(prop(e, ["anni", "anni_assedio"]))
		if years > 0:
			ended += Lang.t(" dopo %d anni") % years
		var reason := text_of(prop(e, ["motivo"]))
		if reason != "":
			ended += " (%s)" % Lang.pick(reason, str(SIEGE_END_EN.get(reason, reason)))   # codice del motivo
		return ended + "."
	if kind == event_kind("EV_STARVED"):
		var starved := Lang.t("La guarnigione di %s si arrende per fame") % where if where != "" else Lang.t("Una guarnigione si arrende per fame")
		var starved_years := int_of(prop(e, ["anni", "anni_assedio"]))
		if starved_years > 0:
			starved += Lang.t(" dopo %d anni di assedio") % starved_years
		return starved + "."
	if kind == event_kind("EV_PROVINCE_CAPTURED"):
		var conquers := fverb(actor_id, Lang.t("conquista"), Lang.t("conquistano"))
		var captured := "%s %s %s" % [actor, conquers, where] if where != "" else Lang.t("%s %s una provincia") % [actor, conquers]
		var previous := faction_names(faction_ids_of(state, prop(e, ["precedente", "ex_proprietario", "perdente", "da_fazione"])))
		if previous != "":
			captured += Lang.t(" (era di %s)") % previous
		return captured + "."
	if kind == event_kind("EV_FACTION_DESTROYED"):
		return "%s %s." % [actor, fverb(actor_id, Lang.t("è stata distrutta"), Lang.t("sono stati distrutti"))]
	return ""


# --- Fase 4: corte, comandanti, governatori, lealtà ----------------------------------
# I personaggi (fase 4a) si leggono direttamente dallo stato. Della fase 4b (lealtà delle province,
# rivolte, riemersioni, guerre civili) sono dati per scontati solo nomi opzionali, letti in modo
# difensivo con `prop` ed `event_kind`: se mancano, le righe corrispondenti non compaiono.

const ATTR_LABELS := {
	"command": "Comando",
	"dread": "Terrore",
	"piety": "Pietà",
	"acumen": "Acume",
	"loyalty": "Lealtà",
	"influence": "Influenza",
}

## Nomi possibili (4b) di lealtà corrente, obiettivo e dettaglio dei termini su ProvinceState.
const LOYALTY_KEYS := ["loyalty", "lealta"]
const LOYALTY_TARGET_KEYS := ["loyalty_target", "target_loyalty", "loyalty_goal", "lealta_obiettivo"]
const LOYALTY_TERMS_KEYS := ["loyalty_terms", "loyalty_breakdown", "loyalty_detail", "loyalty_target_terms", "target_terms", "lealta_termini", "lealta_dettaglio"]
const TERM_NAME_KEYS := ["nome", "name", "termine", "term", "id", "chiave", "key"]
const TERM_VALUE_KEYS := ["valore", "value", "delta"]

## Etichette dei termini della lealtà obiettivo (chiave in minuscolo -> testo).
const TERM_LABELS := {
	"base": "Base",
	"luogo": "Luogo leggendario",
	"tax": "Tassa",
	"tassa": "Tassa",
	"garrison": "Guarnigione",
	"guarnigione": "Guarnigione",
	"buildings": "Edifici",
	"edifici": "Edifici",
	"rebels": "Ribellione regionale",
	"ribelli": "Ribellione regionale",
	"ribellione": "Ribellione regionale",
	"religion": "Religione",
	"religione": "Religione",
	"distance": "Distanza dal capo",
	"distanza": "Distanza dal capo",
	"dread": "Terrore del governatore",
	"terrore": "Terrore del governatore",
	"acume": "Acume del governatore",
	"acumen": "Acume del governatore",
	"governor": "Governatore",
	"governatore": "Governatore",
	"ribellione_regionale": "Ribellione regionale",
	"spies": "Spie",
	"spy": "Spie",
	"spie": "Spie",
	"inquisitor": "Inquisitore",
	"inquisitori": "Inquisitori",
	"inquisitore": "Inquisitore",
	"excommunication": "Scomunica",
	"scomunica": "Scomunica",
	"occupazione": "Occupazione",
	"fazione": "Tratti della fazione",
}


static func attr_label(attr: String) -> String:
	if ATTR_LABELS.has(attr):
		return Lang.t(str(ATTR_LABELS[attr]))
	return attr.capitalize()


## Titolo del capo della fazione per le frasi: «re», oppure il titolo proprio di auror.cfg (`titolo_capo`: per gli Auror
## «Imperatore Dio», richiesta di Federico del 16/11/2026), tradotto.
static func leader_rank(state: GameState, faction_id: String) -> String:
	var title := state.rules.dynasty.leader_title(faction_id) if state != null and state.rules != null else ""
	return Lang.t(title) if title != "" else Lang.t("re")


## Ruolo di un personaggio per le frasi, in minuscolo («capo», «erede», «generale»...); il capo con un titolo proprio porta
## quello, con le sue maiuscole («Imperatore Dio»).
static func character_role_text(state: GameState, c: Character) -> String:
	if c.role == Character.ROLE_LEADER and state != null and state.rules != null:
		var title := state.rules.dynasty.leader_title(c.faction)
		if title != "":
			return Lang.t(title)
	return role_label(c.role).to_lower()


## Ruolo in parole, con la maiuscola iniziale: "Capo", "Erede", "Principe", "Principessa", "Generale".
static func role_label(role: String) -> String:
	if role == Character.ROLE_LEADER:
		return Lang.t("Capo")
	if role == Character.ROLE_HEIR:
		return Lang.t("Erede")
	if role == Character.ROLE_PRINCE:
		return Lang.t("Principe")
	if role == Character.ROLE_PRINCESS:
		return Lang.t("Principessa")
	if role == Character.ROLE_GENERAL:
		return Lang.t("Generale")
	return role.capitalize()


## "1 stella", "3 stelle".
static func stars_text(stars: int) -> String:
	if stars == 1:
		return Lang.t("1 stella")
	return Lang.t("%d stelle") % stars


## Valore numerico per i termini della lealtà: intero con segno, un decimale se serve.
static func number_text(v: Variant, with_sign: bool = false) -> String:
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if absf(f - roundf(f)) >= 0.05:
			if with_sign and f > 0.0:
				return "+%.1f" % f
			return "%.1f" % f
		v = roundi(f)
	var n := int_of(v)
	if with_sign:
		return signed(n)
	return "%d" % n


## Nome italiano di una catena di vizi e virtù (data/ui/vizi_virtu.cfg: "fearsome" -> "Capacità di comando"); poi il nome
## delle regole, poi l'id leggibile. Il prefisso secret_ aggiunge «(segreto)».
static func vnv_name(state: GameState, chain: String) -> String:
	var key := chain.to_lower()
	var secret := key.begins_with("secret_")
	if secret:
		key = key.trim_prefix("secret_")
	var table := _vnv_table()
	var name := str(table.get_value("nomi", key, "")) if table != null else ""
	if name == "":
		if state != null and state.rules != null and state.rules.vnv.has_chain(chain):
			name = state.rules.vnv.chain_name(chain)
		else:
			name = key.replace("_", " ").capitalize()
	return Lang.t("%s (segreto)") % name if secret else name


## Vizio o virtù al livello dato: il titolo del livello se la tabella lo ha («Grande condottiero»), altrimenti
## «Nome (livello N)».
static func vnv_label(state: GameState, chain: String, level: int) -> String:
	var table := _vnv_table()
	var titles: Array = table.get_value("livelli", chain.to_lower(), []) if table != null else []
	if level >= 1 and not titles.is_empty():
		return str(titles[mini(level, titles.size()) - 1])
	return Lang.t("%s (livello %d)") % [vnv_name(state, chain), level]


static var _vnv_cfg: ConfigFile = null

static func _vnv_table() -> ConfigFile:
	if _vnv_cfg == null:
		var c := ConfigFile.new()
		if c.load(Lang.data_path("res://data/ui/vizi_virtu.cfg")) == OK:
			_vnv_cfg = c
	return _vnv_cfg


## Vizi e virtù di un personaggio: "Grande condottiero", "Istruzione (livello 2)", in ordine alfabetico di catena.
static func vnv_texts(state: GameState, c: Character) -> PackedStringArray:
	var out := PackedStringArray()
	var chains: Array = c.vnv.keys()
	chains.sort()
	for chain in chains:
		out.append(vnv_label(state, str(chain), int_of(c.vnv[chain])))
	return out


## Valore efficace di un attributo (titolo, carica, vizi e virtù, valori fissi della fazione).
static func attr_value(state: GameState, c: Character, attr: String) -> int:
	return c.effective(attr, state.rules, state.campaign)


## Attributi in una riga: "Comando 5 stelle · Terrore 3 · Pietà 4 · Acume 2 · Lealtà 7".
## Il capo ha anche l'influenza e non la lealtà. Con `short` solo comando, terrore, acume e lealtà.
static func attributes_line(state: GameState, c: Character, short: bool = false) -> String:
	var parts := PackedStringArray()
	parts.append(Lang.t("Comando %s") % stars_text(c.stars(state.rules, state.campaign)))
	parts.append(Lang.t("Terrore %d") % attr_value(state, c, Character.ATTR_DREAD))
	if not short:
		parts.append(Lang.t("Pietà %d") % attr_value(state, c, Character.ATTR_PIETY))
	parts.append(Lang.t("Acume %d") % attr_value(state, c, Character.ATTR_ACUMEN))
	if c.role == Character.ROLE_LEADER:
		if not short:
			parts.append(Lang.t("Influenza %d") % attr_value(state, c, Character.ATTR_INFLUENCE))
	else:
		parts.append(Lang.t("Lealtà %d") % attr_value(state, c, Character.ATTR_LOYALTY))
	return " · ".join(parts)


## Nome del titolo di una provincia: quello di AddTitle oppure "Governatore di <provincia>".
static func title_name(state: GameState, province_id: String) -> String:
	var def: CampaignData.TitleDef = state.campaign.title_for(province_id)
	if def != null and def.display_name != "":
		return RegionNames.translate_title(state.campaign, def.display_name)   # fase 8: «Duca di Scozia»
	return Lang.t("Governatore di %s") % region_name(state, province_id)


## Titolo con la provincia tra parentesi se il nome non la contiene già: "Duca di Bassa".
static func title_with_place(state: GameState, province_id: String, label: String = "") -> String:
	var text := label
	if text == "":
		text = title_name(state, province_id)
	var place := region_name(state, province_id)
	if not text.contains(place):
		text += " (%s)" % place
	return text


## Nome della carica di Stato di un personaggio ("" se non ne ha).
static func office_name(state: GameState, c: Character) -> String:
	if c.office == "":
		return ""
	var def: CampaignData.OfficeDef = state.campaign.office_for(c.faction, c.office)
	if def != null and def.display_name != "":
		return RegionNames.translate_office(state.campaign, def.display_name)   # fase 8: cariche in italiano
	return c.office.replace("_", " ").capitalize()


# --- cariche di Stato (manuale p25: sbloccate dagli edifici, compaiono nella provincia che li ospita) ------------------


## Bonus di una carica in parole: "lealtà +2 · acume +2"; "" se non ne da'.
static func office_bonus_text(def: CampaignData.BonusDef) -> String:
	if def == null:
		return ""
	var parts := PackedStringArray()
	for pair in [[Lang.t("comando"), def.warcraft], [Lang.t("terrore"), def.dread], [Lang.t("pietà"), def.piety], [Lang.t("acume"), def.acumen], [Lang.t("lealtà"), def.loyalty]]:
		if int(pair[1]) != 0:
			parts.append("%s %s" % [pair[0], signed(int(pair[1]))])
	return " · ".join(parts)


## Cariche di Stato della fazione per la corte, nell'ordine del file: [{"edificio", "nome", "bonus", "titolare" (id, 0 =
## vacante), "provincia" (dove compare, "" = edificio da costruire), "serve" (nome italiano dell'edificio)}].
static func office_rows(state: GameState, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or state.campaign == null:
		return out
	for o in state.campaign.offices_of(faction_id):
		var holder := DynastyProcessor.office_holder(state, faction_id, o.building)
		var needs := building_label(o.building, 1)
		out.append({
			"edificio": o.building,
			"nome": DynastyProcessor.office_label(state, faction_id, o.building),
			"bonus": office_bonus_text(o),
			"titolare": holder.id if holder != null else 0,
			"provincia": DynastyProcessor.office_seat(state, faction_id, o.building),
			"serve": needs if needs != "" else o.building.replace("_", " ").capitalize(),
		})
	return out


## Sala del consiglio (richiesta di Federico del 20/11/2026: «i ritratti di chi ha cariche di corte con al centro il re»):
## il capo al centro e le cariche ai lati, le prime del file (le piu' alte: ciambellano, connestabile...) accanto al trono,
## alternando sinistra e destra. Esito {"capo": id del capo (0 se manca), "sinistra": [...], "destra": [...]}: voci di
## `office_rows` con "vicinanza" (1 = accanto al trono); "sinistra" va dall'esterno verso il trono e "destra" dal trono
## verso l'esterno, cioe' nell'ordine in cui si dispongono da sinistra a destra.
static func council_seats(state: GameState, faction_id: String) -> Dictionary:
	var leader := state.leader_of(faction_id) if state != null else null
	var left: Array[Dictionary] = []
	var right: Array[Dictionary] = []
	var rows := office_rows(state, faction_id)
	for i in rows.size():
		var seat: Dictionary = rows[i]
		seat["vicinanza"] = i / 2 + 1
		if i % 2 == 0:
			left.push_front(seat)
		else:
			right.append(seat)
	return {"capo": leader.id if leader != null else 0, "sinistra": left, "destra": right}


## Cariche che compaiono nella provincia (la sua sede: l'edificio piu' alto della fazione), nell'ordine del file.
static func offices_seated_in(state: GameState, province: ProvinceState) -> Array[CampaignData.OfficeDef]:
	var out: Array[CampaignData.OfficeDef] = []
	if province == null or state.campaign == null:
		return out
	for o in state.campaign.offices_of(province.owner):
		if DynastyProcessor.office_seat(state, province.owner, o.building) == province.id:
			out.append(o)
	return out


## Personaggi a cui si puo' dare la carica (GameCommands.assign_office): della fazione, vivi, adulti, non principesse
## ne' il capo, che non la detengono gia'.
static func eligible_officers(state: GameState, faction_id: String, building: String) -> Array[Character]:
	var out: Array[Character] = []
	if state.rules == null:
		return out
	var b := building.strip_edges().to_lower()
	for c in state.characters_of(faction_id):
		if c.role == Character.ROLE_LEADER or c.office == b:
			continue
		if not c.can_command(state.rules.dynasty, state.year):
			continue
		out.append(c)
	return out


## Voce del selettore della carica: nome, stelle, lealtà e l'eventuale carica che lascerebbe.
static func office_option_text(state: GameState, c: Character) -> String:
	var text := Lang.t("%s · %s · lealtà %d") % [c.full_name(), stars_text(c.stars(state.rules, state.campaign)), attr_value(state, c, Character.ATTR_LOYALTY)]
	var office := office_name(state, c)
	if office != "":
		text += Lang.t(" (lascia: %s)") % office
	return text


## Esercito comandato in parole: "Esercito 3 (Alta)"; senza esercito: "nessuno".
static func commanded_army_text(state: GameState, c: Character) -> String:
	if c.army > 0:
		var a: Army = state.army(c.army)
		if a != null:
			return "%s (%s)" % [army_title(a), region_name(state, a.region)]
	return Lang.t("nessuno")


## Righe di un personaggio per la corte: nome, ruolo ed età; attributi; titolo e carica;
## esercito; vizi e virtù.
static func character_lines(state: GameState, c: Character) -> PackedStringArray:
	var out := PackedStringArray()
	var head := Lang.t("%s — %s, %d anni") % [c.full_name(), character_role_text(state, c), c.age(state.year)]
	if c.role == Character.ROLE_HEIR and state.heir_of(c.faction) == c:
		head += Lang.t(", erede designato")
	if c.royal_blood and c.role != Character.ROLE_LEADER:
		head += Lang.t(", sangue reale")
	if c.is_hero:
		head += Lang.t(", eroe")
	out.append(head)
	out.append("  " + attributes_line(state, c))
	var posts := PackedStringArray()
	if c.title != "":
		posts.append(Lang.t("Titolo: %s") % title_with_place(state, c.title))
	var office := office_name(state, c)
	if office != "":
		posts.append(Lang.t("Carica: %s") % office)
	if not posts.is_empty():
		out.append("  " + " · ".join(posts))
	if c.role != Character.ROLE_PRINCESS and c.role != Character.ROLE_HEIR:
		out.append(Lang.t("  Esercito: %s") % commanded_army_text(state, c))
	elif c.army > 0:
		out.append(Lang.t("  Esercito: %s") % commanded_army_text(state, c))
	var traits := vnv_texts(state, c)
	if not traits.is_empty():
		out.append(Lang.t("  Vizi e virtù: %s") % ", ".join(traits))
	return out


## Sezioni del pannello della corte: [{"titolo": testo, "voci": [{"testo", "esercito", "personaggio"}]}].
## Capo, erede, principi, principesse, generali (solo personaggi vivi). Una sezione vuota ha una voce
## con il solo testo "nessuno" (personaggio 0). "esercito" è l'id dell'esercito comandato (0 = nessuno).
static func court_sections(state: GameState, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var defs := [
		[Lang.t("Capo"), Character.ROLE_LEADER, Lang.t("nessun capo")],
		[Lang.t("Erede"), Character.ROLE_HEIR, Lang.t("nessun erede")],
		[Lang.t("Principi"), Character.ROLE_PRINCE, Lang.t("nessun principe")],
		[Lang.t("Principesse"), Character.ROLE_PRINCESS, Lang.t("nessuna principessa")],
		[Lang.t("Generali"), Character.ROLE_GENERAL, Lang.t("nessun generale")],
	]
	var members := state.characters_of(faction_id)
	for d in defs:
		var role := str(d[1])
		var wanted: Array[Character] = []
		for c in members:
			if c.role == role:
				wanted.append(c)
		if role == Character.ROLE_HEIR:
			wanted.sort_custom(_older_first)
		var entries: Array[Dictionary] = []
		for c in wanted:
			entries.append({"testo": "\n".join(character_lines(state, c)), "esercito": c.army, "personaggio": c.id})
		if entries.is_empty():
			entries.append({"testo": str(d[2]), "esercito": 0, "personaggio": 0})
		out.append({"titolo": str(d[0]), "voci": entries})
	return out


static func _older_first(a: Character, b: Character) -> bool:
	if a.birth_year != b.birth_year:
		return a.birth_year < b.birth_year
	return a.id < b.id


# --- comandante dell'esercito ---

## Righe del comandante per il pannello dell'esercito; vuote se la fazione non ha dinastia.
static func commander_lines(state: GameState, army: Army) -> PackedStringArray:
	var out := PackedStringArray()
	var c: Character = state.commander_of(army.id)
	if c == null:
		if state.has_dynasty(army.faction):
			out.append(Lang.t("Comandante: nessuno"))
		return out
	out.append(Lang.t("Comandante: %s (%s, %d anni) — %s") % [c.full_name(), character_role_text(state, c), c.age(state.year), stars_text(c.stars(state.rules, state.campaign))])
	out.append("  " + attributes_line(state, c, true))
	return out


## Personaggi che possono prendere il comando dell'esercito (comando di GameCommands.set_commander):
## della stessa fazione, vivi, adulti e non principesse, nella stessa regione, non già al comando
## di questo esercito. Se lo guida il capo non si cambia.
static func eligible_commanders(state: GameState, army: Army) -> Array[Character]:
	var out: Array[Character] = []
	if army == null or state.rules == null:
		return out
	var current: Character = state.commander_of(army.id)
	if current != null and current.role == Character.ROLE_LEADER:
		return out
	for c in state.characters_of(army.faction):
		if c.army == army.id:
			continue
		if not c.can_command(state.rules.dynasty, state.year):
			continue
		if state.character_region(c) != army.region:
			continue
		out.append(c)
	return out


## Voce del selettore del comandante: nome, stelle, lealtà e, se guida un altro esercito, quale.
static func commander_option_text(state: GameState, c: Character) -> String:
	var text := Lang.t("%s · %s · lealtà %d") % [c.full_name(), stars_text(c.stars(state.rules, state.campaign)), attr_value(state, c, Character.ATTR_LOYALTY)]
	if c.army > 0:
		text += Lang.t(" (guida l'esercito %d)") % c.army
	return text


# --- governatore e lealtà della provincia ---

## Righe del governatore per il pannello della provincia; vuote se il proprietario non ha dinastia.
static func governor_lines(state: GameState, province_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var owner_id := ""
	var province: ProvinceState = state.province(province_id)
	if province != null:
		owner_id = province.owner
	var g: Character = state.governor_of(province_id)
	if g == null:
		if owner_id != "" and state.has_dynasty(owner_id):
			out.append(Lang.t("Governatore: nessuno"))
		return out
	out.append(Lang.t("Governatore: %s (%s, %d anni)") % [g.full_name(), character_role_text(state, g), g.age(state.year)])
	out.append(Lang.t("  Titolo: %s") % title_with_place(state, province_id))
	out.append(Lang.t("  %s · acume %d") % [stars_text(g.stars(state.rules, state.campaign)), attr_value(state, g, Character.ATTR_ACUMEN)])
	out.append(Lang.t("  Lealtà %d") % attr_value(state, g, Character.ATTR_LOYALTY))
	return out


## Personaggi a cui si può assegnare il titolo della provincia (comando di GameCommands.assign_title):
## della fazione proprietaria, vivi, adulti, non principesse né il capo, che non lo hanno già.
static func eligible_governors(state: GameState, province: ProvinceState) -> Array[Character]:
	var out: Array[Character] = []
	if province == null or state.rules == null:
		return out
	for c in state.characters_of(province.owner):
		if c.role == Character.ROLE_LEADER or c.title == province.id:
			continue
		if not c.can_command(state.rules.dynasty, state.year):
			continue
		out.append(c)
	return out


## Scelte del selettore del governatore (richiesta di Federico del 20/11/2026: «vedere per primi i generali presenti nella
## regione e di colore diverso quelli che hanno già dei titoli»). Voci {"personaggio": Character, "qui": bool, "titolato": bool,
## "testo"}: prima chi si trova nella provincia (al comando di un esercito o no, `GameState.character_region`), poi gli altri; in
## ogni gruppo prima chi non governa nulla, poi per acume decrescente; a parità resta l'ordine di `eligible_governors`.
static func governor_choices(state: GameState, province: ProvinceState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in eligible_governors(state, province):
		out.append({"personaggio": c, "qui": state.character_region(c) == province.id, "titolato": c.title != "",
			"punteggio": attr_value(state, c, Character.ATTR_ACUMEN), "testo": governor_option_text(state, c, true)})
	return _sorted_choices(out)


## Scelte del selettore di una carica di Stato (stessa richiesta, estesa alle cariche il 20/11/2026): come per il
## governatore, ma «titolato» vuol dire che ha gia' un'altra carica (una sola a testa: ricevendo questa la lascia) e a
## parità si ordina per stelle. `region_id`: provincia aperta, dove la carica ha sede.
static func office_choices(state: GameState, faction_id: String, building: String, region_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := SimUtil.norm(region_id)
	for c in eligible_officers(state, faction_id, building):
		out.append({"personaggio": c, "qui": state.character_region(c) == here, "titolato": c.office != "",
			"punteggio": c.stars(state.rules, state.campaign), "testo": office_option_text(state, c)})
	return _sorted_choices(out)


## Ordine comune dei selettori di personaggi: presenti prima, poi liberi prima dei titolati, poi `punteggio` decrescente,
## poi l'ordine d'origine.
static func _sorted_choices(items: Array[Dictionary]) -> Array[Dictionary]:
	for i in items.size():
		items[i]["ordine"] = i
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["qui"]) != bool(b["qui"]):
			return bool(a["qui"])
		if bool(a["titolato"]) != bool(b["titolato"]):
			return not bool(a["titolato"])
		if int(a["punteggio"]) != int(b["punteggio"]):
			return int(a["punteggio"]) > int(b["punteggio"])
		return int(a["ordine"]) < int(b["ordine"]))
	return items


## Voce del selettore del governatore: nome, stelle, acume, lealtà e l'eventuale provincia già governata.
## `with_effect`: in coda l'effetto sulla lealta' della provincia (ADR-150), «provincia +12».
static func governor_option_text(state: GameState, c: Character, with_effect: bool = false) -> String:
	var text := Lang.t("%s · %s · acume %d · lealtà %d") % [c.full_name(), stars_text(c.stars(state.rules, state.campaign)), attr_value(state, c, Character.ATTR_ACUMEN), attr_value(state, c, Character.ATTR_LOYALTY)]
	if with_effect:
		text += Lang.t(" · provincia %s") % signed(governor_loyalty_effect(state, c))
	if c.title != "":
		text += Lang.t(" (governa %s)") % region_name(state, c.title)
	return text


## Termini della lealtà obiettivo come [{"nome": testo, "valore": testo con segno}]. `raw` è un
## Dictionary (termine -> valore, anche {"valore": n}) o un elenco di voci (Dictionary con nome e
## valore, oppure coppie [nome, valore]); altro: nessun termine.
static func loyalty_terms_of(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		for k in d:
			var value: Variant = d[k]
			if typeof(value) == TYPE_DICTIONARY:
				value = prop(value, TERM_VALUE_KEYS)
			if _is_number(value):
				out.append({"nome": term_label(str(k)), "valore": number_text(value, true)})
	elif typeof(raw) == TYPE_ARRAY:
		var items: Array = raw
		for item in items:
			if typeof(item) == TYPE_ARRAY:
				var pair: Array = item
				if pair.size() >= 2 and _is_number(pair[1]):
					out.append({"nome": term_label(str(pair[0])), "valore": number_text(pair[1], true)})
			elif item is Dictionary or item is Object:
				var term_name: Variant = prop(item, TERM_NAME_KEYS)
				var term_value: Variant = prop(item, TERM_VALUE_KEYS)
				if term_name != null and _is_number(term_value):
					out.append({"nome": term_label(str(term_name)), "valore": number_text(term_value, true)})
	return out


## Dettaglio dell'ultimo calcolo della lealta' (`ProvinceState.last_loyalty`, chiavi italiane).
const LOYALTY_DETAIL_KEYS := ["last_loyalty", "ultima_lealta"]
## Termini del dettaglio, nell'ordine in cui si mostrano; tutti tranne «base» solo se diversi da zero.
const LOYALTY_DETAIL_TERMS := ["base", "tassa", "guarnigione", "edifici", "ribellione_regionale", "religione", "distanza", "terrore", "acume", "spie", "inquisitori", "inquisitore", "scomunica", "occupazione", "fazione", "luogo"]


## Coppie [termine, valore] del dettaglio della lealta': solo i termini noti (non «somma», «uomini», «passi»), con
## i valori diversi da zero e, sempre, la base. Vuoto se il dettaglio non ha termini.
static func loyalty_detail_pairs(detail: Dictionary) -> Array:
	var out: Array = []
	for key in LOYALTY_DETAIL_TERMS:
		if not detail.has(key):
			continue
		var value: Variant = detail[key]
		if not _is_number(value):
			continue
		if key != "base" and float(value) == 0.0:
			continue
		out.append([key, value])
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Etichetta di un termine della lealtà: nota (tassa, guarnigione...) oppure l'id leggibile.
static func term_label(term: String) -> String:
	var key := term.strip_edges().to_lower()
	if TERM_LABELS.has(key):
		return Lang.t(str(TERM_LABELS[key]))
	return term.replace("_", " ").strip_edges().capitalize()


## Stati della lealtà mostrati all'interfaccia (richiesta di Federico del 16/11/2026: il rischio di rivolta va reso chiaro).
const LOYALTY_LOYAL := "fedele"
const LOYALTY_CALM := "tranquilla"
const LOYALTY_RESTLESS := "scontenta"
const LOYALTY_REVOLT := "rivolta"
## Sopra la soglia di rivolta di almeno tanto la provincia è «fedele».
const LOYALTY_LOYAL_MARGIN := 50
## Da questo rischio annuo in su la rivolta è «probabile».
const LOYALTY_REVOLT_RISK := 0.25


## Quadro chiaro della lealtà di una provincia: {"valore" (adesso), "massimo", "soglia" (sotto si rischia la rivolta),
## "obiettivo" (dove tende), "fine_anno" (lealtà prevista a fine anno, quando si sorteggia la rivolta), "rischio" (probabilità
## di rivolta a fine anno, 0..1, come il sorteggio: `ProvinceProcessor.revolt_risk`), "stato" (LOYALTY_*), "titolo" («Fedele»,
## «Tranquilla», «Scontenta», «Rivolta probabile»), "rischio_testo" («Rischio di rivolta a fine anno: 15%»), "tendenza"
## («in calo verso 60: 76 a fine anno»), "termini" ([nome, valore] di ciò che la determina), "spiegazione"}.
## ADR-150 (27/11/2026): si calcola adesso (`ProvinceProcessor.live_loyalty`), non dal fine anno precedente, cosi' una tassa,
## un governatore o una guarnigione nuovi si vedono subito; "variazione" = effetto delle leve immediate non ancora registrato
## (truppe entrate o uscite nel turno: conta al fine anno).
static func loyalty_status(state: GameState, province: ProvinceState) -> Dictionary:
	var pr := state.rules.province
	var live := ProvinceProcessor.live_loyalty(state, province)
	var current := int(live["corrente"])
	var target := int(live["obiettivo"])
	var end := clampi(ProvinceProcessor.approach(current, target, pr.drift), 0, pr.max_loyalty)
	var risk := ProvinceProcessor.revolt_risk(state, province, end)
	var status := LOYALTY_CALM
	var title := Lang.t("Tranquilla")
	if risk >= LOYALTY_REVOLT_RISK:
		status = LOYALTY_REVOLT
		title = Lang.t("Rivolta probabile")
	elif risk > 0.0 or end < pr.revolt_threshold:
		status = LOYALTY_RESTLESS
		title = Lang.t("Scontenta")
	elif end >= pr.revolt_threshold + LOYALTY_LOYAL_MARGIN:
		status = LOYALTY_LOYAL
		title = Lang.t("Fedele")
	var trend := Lang.t("stabile")
	if end > current:
		trend = Lang.t("in crescita verso %d: %d a fine anno") % [target, end]
	elif end < current:
		trend = Lang.t("in calo verso %d: %d a fine anno") % [target, end]
	var risk_text := Lang.t("Rischio di rivolta a fine anno: nessuno")
	if risk > 0.0:
		risk_text = Lang.t("Rischio di rivolta a fine anno: %s") % percent_text(risk)
	var terms: Array = []
	for pair in loyalty_detail_pairs(live):
		terms.append([term_label(str(pair[0])), int(roundf(float(pair[1])))])
	var explanation := Lang.t("Sotto %d di lealtà, a ogni fine anno la provincia può ribellarsi: %s di probabilità per ogni punto sotto %d, al massimo %s.") % [
		pr.revolt_threshold, percent_text(pr.revolt_k), pr.revolt_threshold, percent_text(pr.revolt_max_chance)]
	return {"valore": current, "massimo": pr.max_loyalty, "soglia": pr.revolt_threshold, "obiettivo": target, "fine_anno": end,
		"rischio": risk, "stato": status, "titolo": title, "rischio_testo": risk_text, "tendenza": trend, "termini": terms,
		"spiegazione": explanation, "variazione": int(live["variazione_immediata"])}


## Effetto di un governatore sulla lealta' della provincia che governa (ADR-150): terrore e acume efficaci per i loro
## punti di province.cfg. Lo stesso calcolo di `ProvinceProcessor.loyalty_terms`.
static func governor_loyalty_effect(state: GameState, c: Character) -> int:
	var pr := state.rules.province
	return c.effective(Character.ATTR_DREAD, state.rules, state.campaign) * pr.dread_per_point \
		+ c.effective(Character.ATTR_ACUMEN, state.rules, state.campaign) * pr.acumen_per_point


## Effetto del livello di tassa sulla lealta' (termine «tassa»), per le voci del selettore.
static func tax_option_text(state: GameState, level: int) -> String:
	return Lang.t("%s (%d%%) · lealtà %s") % [tax_name(level), roundi(state.rules.tax_multiplier(level) * 100.0),
		signed(state.rules.province.tax_term(level))]


## Popolo dei ribelli di una regione (`SetRegionRebels` e' l'indice nell'elenco dei popoli ribelli, non una probabilita':
## richiesta di Federico del 16/11/2026, il numero mostrato non si capiva): «i Sassoni», "" se manca. Elenco nei testi
## propri del remake (data/testi/<lingua>, [popoli_ribelli] nomi).
static func rebel_people(index: int) -> String:
	var list := ItalianTexts.array("popoli_ribelli", "nomi")
	return list[index].strip_edges() if index >= 0 and index < list.size() else ""


## Compatibilita' con il cambio di lingua (l'elenco ora sta in ItalianTexts, che si azzera da solo).
static func reset_rebel_peoples() -> void:
	pass


## Riga breve per la scheda Provincia: «Lealtà: Scontenta (85 su 200) · rivolta a fine anno 15%».
static func loyalty_summary(state: GameState, province: ProvinceState) -> String:
	var st := loyalty_status(state, province)
	var line := Lang.t("Lealtà: %s (%d su %d)") % [str(st["titolo"]), int(st["valore"]), int(st["massimo"])]
	if float(st["rischio"]) > 0.0:
		line += Lang.t(" · rivolta a fine anno %s") % percent_text(float(st["rischio"]))
	return line


## Percentuale di una probabilità 0..1: «15%», «2,5%».
static func percent_text(chance: float) -> String:
	var value := chance * 100.0
	var text := "%d%%" % roundi(value) if absf(value - roundf(value)) < 0.05 else "%.1f%%" % value
	return text if Lang.is_english() else text.replace(".", ",")


## Righe della lealtà di una provincia (ProvinceState o Dictionary): lealtà corrente con l'obiettivo e,
## se la simulazione li espone, i termini dell'obiettivo. Vuote se la lealtà non è esposta (fase 4b assente).
static func loyalty_lines(province: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var current: Variant = prop(province, LOYALTY_KEYS)
	var target: Variant = prop(province, LOYALTY_TARGET_KEYS)
	# Fase 4b/5a: il dettaglio dell'ultimo calcolo (ProvinceState.last_loyalty) porta obiettivo e termini.
	var detail: Variant = prop(province, LOYALTY_DETAIL_KEYS)
	var detail_dict := {}
	if typeof(detail) == TYPE_DICTIONARY:
		detail_dict = detail
	if not _is_number(target) and _is_number(detail_dict.get("obiettivo")):
		target = detail_dict["obiettivo"]
	if not _is_number(current) and not _is_number(target):
		return out
	var line := ""
	if _is_number(current):
		line = Lang.t("Lealtà: %s") % number_text(current)
		if _is_number(target):
			line += Lang.t(" · obiettivo %s") % number_text(target)
	else:
		line = Lang.t("Lealtà obiettivo: %s") % number_text(target)
	out.append(line)
	var terms := loyalty_terms_of(prop(province, LOYALTY_TERMS_KEYS))
	if terms.is_empty() and not detail_dict.is_empty():
		terms = loyalty_terms_of(loyalty_detail_pairs(detail_dict))
	if not terms.is_empty():
		out.append(Lang.t("Termini dell'obiettivo:"))
		for term in terms:
			out.append("  %s: %s" % [str(term["nome"]), str(term["valore"])])
	if _is_number(current) and float(current) < 100.0:
		out.append(Lang.t("Sotto 100 la provincia rischia la rivolta."))
	return out


# --- testi degli eventi della fase 4 ---

## Testo libero dell'evento (campo "testo" scritto dalla simulazione), ripiego dei testi composti.
static func _free_text(e: Dictionary) -> String:
	return text_of(e.get("testo", "")).strip_edges()


static func _cause_suffix(cause: String) -> String:
	match cause:
		"":
			return ""
		"vecchiaia":
			return Lang.t(" di vecchiaia")
		"estinzione":
			return Lang.t(" con l'estinzione della dinastia")
		"fazione_distrutta":
			return Lang.t(" con la caduta della fazione")
		"rogo":
			return Lang.t(" sul rogo")
	return " (%s)" % cause.replace("_", " ")


## Nome di un personaggio da un campo d'evento: il numero del personaggio (anche come testo o decimale dei salvataggi
## JSON) diventa il suo nome completo (segnalazione di Federico del 22/11/2026: per le fazioni riemerse usciva un numero);
## un testo resta com'e'. "" se manca o il personaggio non c'e'.
static func character_label(state: GameState, value: Variant) -> String:
	var raw := text_of(value)
	var id := -1
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		id = int(value)
	elif raw.is_valid_int() or raw.is_valid_float():
		id = int(float(raw))
	if id < 0:
		return raw
	var c := state.character(id) if state != null else null
	return c.full_name() if c != null else ""


## Testo di un evento della fase 4 (4a: personaggi; 4b: province); vuoto se `kind` non è uno dei loro tipi.
## Se mancano i campi essenziali ripiega sul campo "testo" dell'evento.
static func _format_phase4(state: GameState, kind: String, e: Dictionary) -> String:
	var fallback_text := _free_text(e)
	var who := text_of(e.get("nome", ""))
	var role := text_of(e.get("ruolo", ""))
	var where := _place(state, e, ["provincia", "regione"])
	if kind == event_kind("EV_BIRTH"):
		if who == "":
			return fallback_text
		var child := role_label(role).to_lower()
		if role == Character.ROLE_HEIR:
			child = Lang.t("erede al trono")
		if child == "":
			return Lang.t("Nasce %s.") % who
		return Lang.t("Nasce %s, %s.") % [who, child]
	if kind == event_kind("EV_COMING_OF_AGE"):
		if who == "":
			return fallback_text
		var age := int_of(e.get("eta"))
		var status := Lang.t("è maggiorenne")
		if role == Character.ROLE_PRINCESS:
			status = Lang.t("è in età da marito")
		if age > 0:
			return Lang.t("%s compie %d anni ed %s.") % [who, age, status]
		return "%s %s." % [who, status]
	if kind == event_kind("EV_DEATH"):
		if who == "":
			return fallback_text
		var cause := text_of(e.get("causa", ""))
		var death_age := int_of(e.get("eta"))
		if cause == "ritiro":
			if death_age > 0:
				return Lang.t("%s si ritira a vita privata (%d anni).") % [who, death_age]
			return Lang.t("%s si ritira a vita privata.") % who
		var details := PackedStringArray()
		if role != "":
			details.append(role_label(role).to_lower())
		if death_age > 0:
			details.append(Lang.t("%d anni") % death_age)
		var text := Lang.t("Muore %s") % who
		if not details.is_empty():
			text += " (%s)" % ", ".join(details)
		return text + _cause_suffix(cause) + "."
	if kind == event_kind("EV_SUCCESSION"):
		if who == "":
			return fallback_text
		var text := Lang.t("%s sale al trono") % who
		var before := text_of(e.get("precedente_nome", ""))
		if before != "":
			text += Lang.t(" dopo %s") % before
		var by_heir: Variant = e.get("per_eredita")
		if typeof(by_heir) == TYPE_BOOL:
			if bool(by_heir):
				text += Lang.t(" (erede)")
			else:
				var contenders := int_of(e.get("contendenti"))
				if contenders > 0:
					text += Lang.t(" (senza erede maggiorenne: altri %d contendenti)") % contenders
				else:
					text += Lang.t(" (senza erede maggiorenne)")
		return text + "."
	if kind == event_kind("EV_FACTION_EXTINCT"):
		var extinct := Lang.t("La dinastia %s") % fprep("di", _actor_id(e))
		if e.has("province"):
			var lost := list_of(e.get("province")).size()
			if lost == 1:
				return Lang.t("%s si estingue senza eredi: 1 provincia diventa ribelle.") % extinct
			if lost > 1:
				return Lang.t("%s si estingue senza eredi: %d province diventano ribelli.") % [extinct, lost]
			return Lang.t("%s si estingue senza eredi.") % extinct
		if e.has("fazione"):
			return Lang.t("%s si estingue senza eredi.") % extinct
		return fallback_text
	if kind == event_kind("EV_HERO_APPEARS"):
		if who == "":
			return fallback_text
		if where != "":
			return Lang.t("Compare l'eroe %s a %s.") % [who, where]
		return Lang.t("Compare l'eroe %s.") % who
	if kind == event_kind("EV_VNV_GAINED"):
		var chain := text_of(e.get("catena", ""))
		if who == "" or chain == "":
			return fallback_text
		return Lang.t("%s ottiene %s.") % [who, vnv_label(state, chain, maxi(1, int_of(e.get("livello"), 1)))]
	if kind == event_kind("EV_TITLE_CHANGED"):
		var province_id := text_of(e.get("provincia", ""))
		if who == "" or province_id == "":
			return fallback_text
		var label := title_with_place(state, province_id, text_of(e.get("titolo", "")))
		match text_of(e.get("azione", "")):
			"assegnato":
				return Lang.t("%s riceve il titolo di %s.") % [who, label]
			"revocato":
				return Lang.t("Il titolo di %s è revocato a %s.") % [label, who]
			"ceduto":
				return Lang.t("%s lascia il titolo di %s.") % [who, label]
			"perso":
				return Lang.t("%s perde il titolo di %s.") % [who, label]
		return fallback_text if fallback_text != "" else Lang.t("Titolo di %s: %s.") % [label, who]
	if kind == event_kind("EV_OFFICE_CHANGED"):
		var office_label := text_of(e.get("carica", ""))
		if who == "" or office_label == "":
			return fallback_text
		match text_of(e.get("azione", "")):
			"assegnato":
				return Lang.t("%s riceve la carica di %s.") % [who, office_label]
			"revocato":
				return Lang.t("La carica di %s è revocata a %s.") % [office_label, who]
			"ceduto":
				return Lang.t("%s lascia la carica di %s.") % [who, office_label]
			"perso":
				return Lang.t("%s perde la carica di %s.") % [who, office_label]
		return fallback_text if fallback_text != "" else Lang.t("Carica di %s: %s.") % [office_label, who]
	if kind == event_kind("EV_STAR_CHANGED"):
		if who == "" or not e.has("stelle_prima") or not e.has("stelle_dopo"):
			return fallback_text
		var before_stars := int_of(e.get("stelle_prima"))
		var after_stars := int_of(e.get("stelle_dopo"))
		var cause_text := ""
		match text_of(e.get("motivo", "")):
			"vittoria":
				cause_text = Lang.t(" dopo la vittoria")
			"sconfitta":
				cause_text = Lang.t(" dopo la sconfitta")
		if after_stars >= before_stars:
			return Lang.t("%s guadagna una stella di comando%s (ora %s).") % [who, cause_text, stars_text(after_stars)]
		return Lang.t("%s perde una stella di comando%s (ora %s).") % [who, cause_text, stars_text(after_stars)]
	return _format_phase4b(state, kind, e, fallback_text, where)


## Eventi della fase 4b. I campi opzionali sono letti con `prop`: senza luogo si usa il campo "testo".
static func _format_phase4b(state: GameState, kind: String, e: Dictionary, fallback_text: String, where: String) -> String:
	if kind == event_kind("EV_LOYALTY_LOW"):
		if where == "":
			return fallback_text
		var value: Variant = prop(e, ["lealta", "loyalty", "valore"])
		if _is_number(value):
			return Lang.t("Lealtà bassa a %s: %s.") % [where, number_text(value)]
		return Lang.t("Lealtà bassa a %s.") % where
	if kind == event_kind("EV_REBELLION"):
		if where == "":
			return fallback_text
		var text := Lang.t("Rivolta a %s") % where
		var men := int_of(prop(e, ["uomini", "forza", "ribelli"]))
		var loyal_to := text_of(prop(e, ["lealisti_di"]))
		if men > 0 and loyal_to != "":
			text += Lang.t(" (%d ribelli lealisti %s)") % [men, fprep("di", loyal_to, "to")]
		elif men > 0:
			text += Lang.t(" (%d ribelli)") % men
		if prop(e, ["conquistata", "provincia_conquistata"]) == true:
			text += Lang.t(": la provincia passa ai ribelli")
		return text + "."
	if kind == event_kind("EV_REBELLION_SPREAD"):
		if where == "":
			return fallback_text
		var origin := text_of(prop(e, ["da", "origine", "da_provincia"]))
		if origin != "":
			return Lang.t("Rivolta propagata da %s a %s.") % [region_name(state, origin), where]
		return Lang.t("Rivolta propagata a %s.") % where
	if kind == event_kind("EV_LOYALISTS_RETURN"):
		if where == "" or not e.has("fazione"):
			return fallback_text
		return Lang.t("I ribelli lealisti consegnano %s %s.") % [where, fprep("a", _actor_id(e))]
	if kind == event_kind("EV_FACTION_REEMERGED"):
		if not e.has("fazione"):
			return fallback_text
		var text := "%s %s" % [fsubj(_actor_id(e)), fverb(_actor_id(e), Lang.t("riemerge"), Lang.t("riemergono"))]
		if where != "":
			text += Lang.t(" a %s") % where
		var leader := character_label(state, prop(e, ["nome_capo", "capo", "nome"]))
		if leader != "":
			text += Lang.t(" con %s come capo") % leader
		return text + "."
	if kind == event_kind("EV_CIVIL_WAR"):
		if not e.has("fazione"):
			return fallback_text
		var text := Lang.t("Guerra civile %s") % fprep("di", _actor_id(e))
		var rebels := list_of(prop(e, ["generali", "personaggi", "ribelli"])).size()
		if rebels > 0:
			text += Lang.t(": %d generali passano ai ribelli") % rebels
		return text + "."
	return ""


# --- testi degli eventi della fase 5a (agenti e diplomazia) ---

const PROPOSAL_NAMES := {
	"alleanza": "un'alleanza",
	"tregua": "una tregua",
	"matrimonio": "un matrimonio",
}


## Testo di un evento della fase 5a (campi: vedi GameState, EV_AGENT_RECRUITED...); vuoto se `kind` non e' uno dei
## suoi tipi. Se mancano i campi essenziali ripiega sul campo "testo" dell'evento.
static func _format_phase5a(state: GameState, kind: String, e: Dictionary) -> String:
	var fallback_text := _free_text(e)
	var actor_id := SimUtil.norm(text_of(e.get("fazione", "")))
	var actor := faction_name(actor_id)
	var other_id := SimUtil.norm(text_of(e.get("con", "")))
	var other := faction_name(other_id)
	var where := _place(state, e, ["regione", "provincia"])
	var at := Lang.t(" a %s") % where if where != "" else ""
	var agent_id := int_of(e.get("agente"))
	var agent_type := text_of(e.get("tipo_agente", ""))
	var agent_text := CampaignUiAgents.label_of(state, agent_id, agent_type)
	var victim := text_of(e.get("nome", ""))
	if kind == event_kind("EV_AGENT_RECRUITED"):
		var value := int_of(e.get("valore"), -1)
		var value_text := Lang.t(" (valore %d)") % value if value >= 0 else ""
		if text_of(e.get("origine", "")) == "principessa":
			var princess := state.character(int_of(e.get("personaggio")))
			var princess_name := princess.full_name() if princess != null else Lang.t("Una principessa")
			return Lang.t("%s è in età da marito: diventa un'agente%s%s.") % [princess_name, at, value_text]
		if agent_id <= 0 and agent_type == "":
			return fallback_text
		return Lang.t("Nuovo agente%s: %s%s.") % [at, agent_text, value_text]
	if kind == event_kind("EV_AGENT_MOVED"):
		if not e.has("da") or not e.has("a"):
			return fallback_text
		var from_name := region_name(state, text_of(e.get("da")))
		var to_name := region_name(state, text_of(e.get("a")))
		var journey := ""
		if bool(e.get("arrivato", false)):
			journey = Lang.t(" Fine del viaggio.")
		elif text_of(e.get("destinazione", "")) != "":
			journey = Lang.t(" In viaggio verso %s.") % region_name(state, text_of(e.get("destinazione")))
		if bool(e.get("via_mare", false)):
			return Lang.t("%s (%s): da %s a %s via mare (%s).%s") % [agent_text, actor, from_name, to_name, chain_names(state, e.get("catena", [])), journey]
		return Lang.t("%s (%s): da %s a %s.%s") % [agent_text, actor, from_name, to_name, journey]
	if kind == event_kind("EV_AGENT_JOURNEY_STOPPED"):
		if not e.has("verso"):
			return fallback_text
		return Lang.t("%s (%s) si ferma a %s: nessun percorso porta più a %s.") % [agent_text, actor, region_name(state, text_of(e.get("regione"))), region_name(state, text_of(e.get("verso")))]
	if kind == event_kind("EV_ALLIANCE_FORMED"):
		if actor_id == "" or other_id == "":
			return fallback_text
		return Lang.t("%s e %s stringono un'alleanza%s.") % [fsubj(actor_id), fart(other_id), at]
	if kind == event_kind("EV_TRUCE"):
		if actor_id == "" or other_id == "":
			return fallback_text
		var until := int_of(e.get("fino_al"))
		if until > 0:
			return Lang.t("%s e %s firmano una tregua fino al %d%s.") % [fsubj(actor_id), fart(other_id), until, at]
		return Lang.t("%s e %s firmano una tregua%s.") % [fsubj(actor_id), fart(other_id), at]
	if kind == event_kind("EV_ALLIANCE_BROKEN") or kind == event_kind("EV_TRUCE_BROKEN"):
		if actor_id == "" or other_id == "":
			return fallback_text
		if kind == event_kind("EV_ALLIANCE_BROKEN") and text_of(e.get("motivo", "")) == "scomunica":
			return Lang.t("L'alleanza tra %s e %s cade per la scomunica.") % [fart(actor_id), fart(other_id)]
		if kind == event_kind("EV_ALLIANCE_BROKEN") and text_of(e.get("motivo", "")) == "alleanze_in_conflitto":
			# segnalazione di Federico (20/11/2026): non e' un attacco di chi rompe, ma un alleato che ne attacca un altro
			var defender_id := SimUtil.norm(text_of(e.get("difensore", "")))
			var broke := "%s %s l'alleanza con %s" % [fsubj(actor_id), fverb(actor_id, Lang.t("rompe"), Lang.t("rompono")), fart(other_id)]
			if defender_id == "":
				return Lang.t("%s: ha attaccato un altro alleato.") % broke
			return Lang.t("%s: non si può restare alleati di chi attacca %s.") % [broke, fart(defender_id)]
		var noun := Lang.t("l'alleanza") if kind == event_kind("EV_ALLIANCE_BROKEN") else Lang.t("la tregua")
		var text := Lang.t("%s %s %s con %s") % [fsubj(actor_id), fverb(actor_id, Lang.t("rompe"), Lang.t("rompono")), noun, fart(other_id)]
		if where != "":
			text += Lang.t(" attaccando a %s") % where
		text += "."
		var lost := int_of(e.get("influenza_persa"))
		if lost > 0:
			text += Lang.t(" L'influenza del suo capo scende di %d.") % lost
		return text
	if kind == event_kind("EV_TRUCE_EXPIRED"):
		if actor_id == "" or other_id == "":
			return fallback_text
		return Lang.t("La tregua tra %s e %s è scaduta.") % [fart(actor_id), fart(other_id)]
	if kind == event_kind("EV_PROPOSAL_REFUSED"):
		if actor_id == "" or other_id == "":
			return fallback_text
		var proposal := Lang.t(text_of(PROPOSAL_NAMES.get(text_of(e.get("missione", "")), "una proposta")))
		var refused := Lang.t("%s %s %s proposta %s%s") % [fsubj(other_id), fverb(other_id, Lang.t("rifiuta"), Lang.t("rifiutano")), proposal, fprep("da", actor_id, "by"), at]
		if e.has("probabilita"):
			refused += Lang.t(" (probabilità %s)") % CampaignUiAgents.chance_text(float(e.get("probabilita")))
		return refused + "."
	if kind == event_kind("EV_MARRIAGE"):
		if actor_id == "":
			return fallback_text
		if bool(e.get("nozze_capo", false)):
			# nuove nozze del capo immortale (20/11/2026): "nome" e' il capo, "sposa" la nobildonna, "da" la sua fazione
			var bride_name := text_of(e.get("sposa", ""))
			var origin_id := SimUtil.norm(text_of(e.get("da", "")))
			if victim == "" or bride_name == "":
				return fallback_text
			if origin_id == "":
				return Lang.t("%s prende in moglie %s%s.") % [victim, bride_name, at]
			return Lang.t("%s prende in moglie %s, nobildonna %s%s.") % [victim, bride_name, fprep("di", origin_id), at]
		if other_id == "":
			if victim == "":
				return fallback_text
			return Lang.t("Una principessa %s sposa il generale %s%s: la sua lealtà cresce ed entra nella linea di sangue.") % [fprep("di", actor_id), victim, at]
		var bride := Lang.t("Una principessa") if victim == "" else Lang.t("La principessa %s") % victim
		var wedding := Lang.t("%s %s sposa un nobile %s%s") % [bride, fprep("di", actor_id), fprep("di", other_id), at]
		if bool(e.get("nuova_alleanza", false)):
			wedding += Lang.t(": nasce un'alleanza")
		return wedding + "."
	if kind == event_kind("EV_BRIBE") or kind == event_kind("EV_BRIBE_REFUSED"):
		if actor_id == "" or other_id == "":
			return fallback_text
		var army_id := int_of(e.get("esercito"))
		if kind == event_kind("EV_BRIBE_REFUSED"):
			return Lang.t("L'esercito %d %s rifiuta la corruzione %s%s.") % [army_id, fprep("di", other_id), fprep("di", actor_id, "by"), at]
		var bribe := Lang.t("%s %s l'esercito %d %s per %d denari%s.") % [fsubj(actor_id), fverb(actor_id, Lang.t("corrompe"), Lang.t("corrompono")), army_id, fprep("di", other_id), int_of(e.get("prezzo")), at]
		var province_id := text_of(e.get("provincia", ""))
		if province_id != "":
			bribe += Lang.t(" Con la guarnigione passa %s.") % region_name(state, province_id)
		return bribe
	if kind == event_kind("EV_ASSASSINATION") or kind == event_kind("EV_ASSASSINATION_FAILED"):
		if actor_id == "" or victim == "":
			return fallback_text
		var target_text := victim if other_id == "" else "%s (%s)" % [victim, other]
		if kind == event_kind("EV_ASSASSINATION"):
			return "%s %s %s%s." % [fsubj(actor_id), fverb(actor_id, Lang.t("assassina"), Lang.t("assassinano")), target_text, at]
		var failed := Lang.t("L'assassino %s fallisce il colpo contro %s%s") % [fprep("di", actor_id), target_text, at]
		if bool(e.get("assassino_morto", false)):
			failed += Lang.t(" e muore")
		return failed + "."
	if kind == event_kind("EV_AGENT_CAPTURED"):
		if actor_id == "" or other_id == "":
			return fallback_text
		var by := Lang.t("dal forte di confine")
		var capturer_id := int_of(e.get("catturatore_agente"))
		if capturer_id > 0:
			by = Lang.t("da %s") % (CampaignUiAgents.label_of(state, capturer_id) if state.agent(capturer_id) != null else Lang.t("un agente"))
		var victim_type := CampaignUiAgents.type_label(agent_type) if agent_type != "" else Lang.t("agente")
		return Lang.t("%s %s un agente %s%s: %s, preso %s.") % [fsubj(actor_id), fverb(actor_id, Lang.t("cattura"), Lang.t("catturano")), fprep("di", other_id), at, victim_type, by]
	if kind == event_kind("EV_GATES_OPENED"):
		if actor_id == "":
			return fallback_text
		var gates := Lang.t("Una spia %s apre le porte del castello%s") % [fprep("di", actor_id), at]
		var besieged := text_of(e.get("assediata", ""))
		if besieged != "":
			var besieged_id := SimUtil.norm(besieged)
			gates += Lang.t(": %s %s la provincia") % [fart(besieged_id), fverb(besieged_id, Lang.t("perde"), Lang.t("perdono"))]
		return gates + "."
	if kind == event_kind("EV_MISSION_FAILED"):
		var mission := text_of(e.get("missione", ""))
		if mission == "" or actor_id == "":
			return fallback_text
		var mission_name := Lang.t(text_of(CampaignUiAgents.MISSION_NAMES.get(mission, mission)))
		var reason := humanize_ids(state, text_of(e.get("motivo", "")))
		var failure := Lang.t("Missione fallita (%s): %s %s%s") % [mission_name, agent_text, fprep("di", actor_id), at]
		if reason != "":
			failure += ": %s" % reason
		return failure + "."
	return ""


# --- testi degli eventi della fase 5b (religione e Inquisizione) ---


## Testo di un evento della fase 5b (campi: vedi GameState, EV_HERETIC_REVOLT e EV_INQUISITION); vuoto se `kind` non e'
## uno dei suoi tipi. Se mancano i campi essenziali ripiega sul campo "testo" dell'evento.
static func _format_phase5b(state: GameState, kind: String, e: Dictionary) -> String:
	var fallback_text := _free_text(e)
	var actor_id := SimUtil.norm(text_of(e.get("fazione", "")))
	var actor := faction_name(actor_id)
	var where := _place(state, e, ["provincia", "regione"])
	if kind == event_kind("EV_HERETIC_REVOLT"):
		if where == "" or actor_id == "":
			return fallback_text
		var text := Lang.t("Rivolta eretica a %s (%s)") % [where, actor]
		var heretics: Variant = e.get("eretici")
		if _is_number(heretics):
			text += Lang.t(": gli eretici sono il %s della popolazione") % CampaignUiReligion.percent_text(float(heretics))
		var men := int_of(e.get("uomini"))
		if men > 0:
			text += (", " if _is_number(heretics) else ": ") + Lang.t("%d ribelli") % men
		return text + "."
	if kind == event_kind("EV_INQUISITION") or kind == event_kind("EV_INQUISITION_FAILED"):
		if actor_id == "":
			return fallback_text
		var victim := text_of(e.get("nome", ""))
		if victim == "":
			victim = Lang.t("un agente") if text_of(e.get("bersaglio_tipo", "")) == AgentMissions.TARGET_AGENT else Lang.t("un personaggio")
		var other_id := SimUtil.norm(text_of(e.get("con", "")))
		var victim_text := victim if other_id == "" else "%s %s" % [victim, fprep("di", other_id)]
		var at := " a %s" % where if where != "" else ""
		var chance := ""
		if _is_number(e.get("probabilita")):
			chance = Lang.t(" (probabilità %s)") % CampaignUiAgents.chance_text(float(e.get("probabilita")))
		if kind == event_kind("EV_INQUISITION"):
			return Lang.t("L'Inquisizione %s manda sul rogo %s%s%s.") % [fprep("di", actor_id), victim_text, at, chance]
		var inquisitor := CampaignUiAgents.label_of(state, int_of(e.get("agente")), text_of(e.get("tipo_agente", "")))
		return Lang.t("Il processo %s (%s) contro %s%s fallisce%s.") % [fprep("di", actor_id), inquisitor, victim_text, at, chance]
	return ""


# --- schede della pergamena della provincia (veste nuova, ADR-029) -----------------------------------------------------

const TAB_PROVINCE := 0
const TAB_CASTLE := 1
const TAB_GOVERNMENT := 2
const TAB_BUILDINGS := 3


## Schede disponibili: in una provincia altrui non c'e' il governo (governatore e lealta' sono affari del proprietario).
## Stima delle forze di un esercito altrui senza informazioni di una spia (18/11/2026): uomini arrotondati a 50.
static func army_estimate(army: Army) -> String:
	var men := maxi(50, int(round(float(army.men_total()) / 50.0)) * 50)
	return Lang.t("Forze stimate: circa %d uomini. Per conoscere unità e comandante servono una provincia confinante, una vostra flotta vicina o una spia.") % men


## Stima della guarnigione di una provincia altrui senza informazioni (uomini arrotondati a 100).
static func garrison_estimate(state: GameState, province: ProvinceState) -> String:
	var men := 0
	for a in state.armies_in(province.id):
		if a.faction == province.owner and not a.is_fleet:
			men += a.men_total()
	if men == 0:
		return Lang.t("Guarnigione: nessuna truppa in vista. Per i dettagli servono una provincia confinante, una flotta vicina o una spia.")
	return Lang.t("Guarnigione: circa %d uomini. Per unità e comandanti servono una provincia confinante, una vostra flotta vicina o una spia.") % maxi(100, int(round(float(men) / 100.0)) * 100)


static func province_tabs(own: bool) -> Array:
	if own:
		return [TAB_PROVINCE, TAB_CASTLE, TAB_GOVERNMENT, TAB_BUILDINGS]
	return [TAB_PROVINCE, TAB_CASTLE, TAB_BUILDINGS]


static func province_tab_name(tab: int) -> String:
	match tab:
		TAB_CASTLE:
			return Lang.t("Castello")
		TAB_GOVERNMENT:
			return Lang.t("Governo")
		TAB_BUILDINGS:
			return Lang.t("Edifici")
	return Lang.t("Provincia")


## Divide le righe «Nome: valore» della descrizione di una provincia in coppie per la tabella a due colonne ("coppie",
## nell'ordine) e in righe da lasciare a tutta larghezza ("righe"): quelle senza i due punti o con un valore lungo.
static func fact_rows(text: String, max_value: int = 24) -> Dictionary:
	var pairs: Array = []
	var wide := PackedStringArray()
	for line in text.split("\n", false):
		var cut := line.find(": ")
		if cut <= 0 or line.length() - cut - 2 > max_value:
			wide.append(line)
		else:
			pairs.append([line.substr(0, cut), line.substr(cut + 2)])
	return {"coppie": pairs, "righe": wide}
