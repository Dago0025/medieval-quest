class_name CampaignUiSites
extends RefCounted
## Testi dei luoghi leggendari per l'interfaccia (richiesta di Federico del 26/11/2026): riquadro al passaggio del mouse,
## scheda del luogo, righe degli effetti e degli esiti delle scelte. Logica pura, senza nodi.

const CATEGORY_LABELS := {"storico": "Luogo storico", "mitologico": "Luogo mitologico", "marino": "Luogo marino"}
const CATEGORY_COLORS := {
	"storico": Color(0.62, 0.40, 0.18),
	"mitologico": Color(0.50, 0.36, 0.78),
	"marino": Color(0.20, 0.55, 0.60),
}
const GOOD := "#2f6b30"
const BAD := "#93281e"

## Effetto -> [testo con %s per il valore, vero se un valore positivo e' un vantaggio, percentuale]
const EFFECT_TEXTS := {
	"agricoltura": ["Agricoltura %s", true, true],
	"commercio": ["Commercio %s", true, true],
	"miniere": ["Miniere %s", true, true],
	"reddito": ["Reddito della provincia %s", true, true],
	"commercio_marittimo": ["Commercio marittimo %s", true, true],
	"lealta": ["Lealta' della provincia %s", true, false],
	"valore_emissari": ["Emissari e principesse arruolati qui: %s stelle", true, false],
	"valore_spie": ["Spie e assassini arruolati qui: %s stelle", true, false],
	"valore_religiosi": ["Religiosi arruolati qui: %s stelle", true, false],
	"armi_reclute": ["Armi delle reclute %s livello", true, false],
	"mantenimento": ["Mantenimento %s denari l'anno", false, false],
	"difesa": ["Difesa del castello negli assalti %s", true, true],
	"anni_assedio": ["Resiste alla fame %s anni in piu'", true, false],
	"terremoti": ["Terremoti %s", false, true],
	"carestia": ["Carestie %s", false, true],
	"peste": ["Pestilenze %s", false, true],
	"inondazioni": ["Inondazioni %s", false, true],
	"tempeste": ["Tempeste per tutte le vostre flotte %s", false, true],
	"bersaglio_ia": ["Gli altri sovrani la desiderano %s", false, true],
}
const RELIGION_LABELS := {"CATHOLIC": "cattolici", "ORTHODOX": "ortodossi", "MUSLIM": "musulmani", "PAGAN": "pagani",
	"IMPERIAL": "culto Imperiale", "DHARMA": "Dharma", "altre": "altre religioni"}


static func category_label(category: String) -> String:
	return Lang.t(str(CATEGORY_LABELS.get(category, "Luogo leggendario")))


static func _signed(v: float, percent: bool) -> String:
	var n := roundi(v)
	return ("%+d%%" % n) if percent else ("%+d" % n)


## Righe degli effetti continui: [{"testo", "bonus" (bool)}], nell'ordine di EFFECT_TEXTS.
static func effect_lines(effects: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in EFFECT_TEXTS:
		if not effects.has(key):
			continue
		var v := float(effects[key])
		if is_zero_approx(v):
			continue
		var spec: Array = EFFECT_TEXTS[key]
		var text := Lang.t(str(spec[0])) % _signed(v, bool(spec[2]))
		if key == "mantenimento":
			text = Lang.t(str(spec[0])) % str(roundi(v))
		out.append({"testo": text, "bonus": (v > 0.0) == bool(spec[1])})
	var conv: Dictionary = effects.get("conversione", {})
	for r in conv:
		out.append({"testo": Lang.t("Ogni anno la popolazione si converte ai %s (%d)") % [Lang.t(str(RELIGION_LABELS.get(str(r), str(r)))), int(conv[r])], "bonus": true})
	return out


## Righe degli effetti di un luogo per la scheda: base, per religione, rovine, presidio e transito.
## Ogni voce {"titolo", "righe": effect_lines}.
static func sheet_sections(state: GameState, s: LegendarySites.Site) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s.is_sea():
		if not s.transit.is_empty():
			out.append({"titolo": Lang.t("Chi attraversa la zona"), "righe": [{"testo": Lang.t("Ogni flotta: %d%% l'anno di perdere una nave (chi presidia e' immune)") % int(s.transit.get("perdite", 0)), "bonus": false}]})
		if s.garrison_years > 0:
			out.append({"titolo": Lang.t("Chi presidia la zona per %d anni senza rivali") % s.garrison_years, "righe": effect_lines(s.garrison)})
		return out
	var year := state.year if state != null else 0
	var base := s.effects_after if s.after_year > 0 and year >= s.after_year else s.effects
	if not base.is_empty():
		out.append({"titolo": Lang.t("A chi possiede la provincia"), "righe": effect_lines(base)})
	for r in s.effects_religion:
		out.append({"titolo": Lang.t("Se il proprietario e' tra i %s") % Lang.t(str(RELIGION_LABELS.get(str(r), str(r)))), "righe": effect_lines(s.effects_religion[r])})
	if s.after_year > 0 and year < s.after_year and not s.effects_after.is_empty():
		out.append({"titolo": Lang.t("Dal %d") % s.after_year, "righe": effect_lines(s.effects_after)})
	if not s.discovery.is_empty():
		out.append({"titolo": Lang.t("Alla prima conquista"), "righe": outcome_lines(s.discovery)})
	return out


## Righe di un esito (scoperta, opzioni): [{"testo", "bonus"}].
static func outcome_lines(outcome: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var simple := [
		["tesoro", "%s denari", true], ["pieta_capo", "Pieta' del capo %s", true], ["terrore_capo", "Terrore del capo %s", true],
		["influenza_capo", "Influenza del capo %s", true], ["acume_capo", "Acume del capo %s", true],
		["lealta_generali", "Lealta' dei generali %s", true], ["stelle", "Stelle del comandante %s", true],
		["vita", "Anni di vita del comandante %s", true],
	]
	for spec in simple:
		var n := int(outcome.get(spec[0], 0))
		if n != 0:
			out.append({"testo": Lang.t(str(spec[1])) % ("%+d" % n), "bonus": (n > 0) == bool(spec[2])})
	if bool(outcome.get("muore", false)):
		out.append({"testo": Lang.t("Il comandante muore"), "bonus": false})
	var ships := int(outcome.get("navi_perse", 0))
	if ships > 0:
		out.append({"testo": Lang.t("%d navi perdute") % ships, "bonus": false})
	var men := int(outcome.get("uomini_persi", 0))
	if men > 0:
		out.append({"testo": Lang.t("%d%% degli uomini perduti") % men, "bonus": false})
	var order: Dictionary = outcome.get("ordine", {})
	if not order.is_empty():
		var pts := int(order.get("punti", 0))
		out.append({"testo": Lang.t("Lealta' %+d per %d anni") % [pts, int(order.get("anni", 1))], "bonus": pts > 0})
	var conv: Dictionary = outcome.get("conversione", {})
	for r in conv:
		out.append({"testo": Lang.t("Conversione ai %s") % Lang.t(str(RELIGION_LABELS.get(str(r), str(r)))), "bonus": true})
	if bool(outcome.get("fine_luogo", false)):
		out.append({"testo": Lang.t("Il luogo perde ogni effetto"), "bonus": false})
	return out


## Descrizione breve di un'opzione: costo, requisiti ed esiti con le loro probabilita'.
static func option_note(option: Dictionary) -> String:
	var parts := PackedStringArray()
	var req: Dictionary = option.get("richiede", {})
	if int(req.get("costo", 0)) > 0:
		parts.append(Lang.t("costa %d denari") % int(req["costo"]))
	if int(req.get("stelle", 0)) > 0:
		parts.append(Lang.t("comandante con %d+ stelle") % int(req["stelle"]))
	var results: Array = option.get("esiti", [])
	var bits := PackedStringArray()
	for r in results:
		var lines := outcome_lines(r)
		var txt := ", ".join(PackedStringArray(lines.map(func(l: Dictionary) -> String: return str(l["testo"]))))
		if txt == "":
			txt = Lang.t("nulla")
		bits.append((("%d%%: " % int(r.get("p", 100))) if results.size() > 1 else "") + txt)
	if not bits.is_empty():
		parts.append(" · ".join(bits))
	return " · ".join(parts)


## Proprietario o chi presidia, per il riquadro e la scheda.
static func holder_line(state: GameState, s: LegendarySites.Site) -> String:
	if s.is_sea():
		var holder := LegendarySites.garrison_holder(state, s)
		if holder != "":
			return Lang.t("Presidiato da %s") % SimUtil.faction_label(holder)
		var st: Dictionary = state.sites_state.get(s.id, {})
		var who := str(st.get("presidio", ""))
		if who != "":
			return Lang.t("%s lo presidia da %d anni su %d") % [SimUtil.faction_label(who), int(st.get("presidio_anni", 0)), s.garrison_years]
		return Lang.t("Nessuno presidia la zona")
	var p := state.province(s.region)
	if p == null:
		return ""
	return Lang.t("Possiede: %s") % SimUtil.faction_label(p.owner)


## Riquadro al passaggio del mouse (bbcode).
static func hover_text(state: GameState, s: LegendarySites.Site) -> String:
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % s.label(state.year))
	lines.append("%s · %s" % [category_label(s.category), WarProcessor.region_label(state, s.region)])
	var holder := holder_line(state, s)
	if holder != "":
		lines.append(holder)
	if not LegendarySites.is_active(state, s):
		lines.append(Lang.t("Il luogo non ha piu' effetti"))
	lines.append("[i]%s[/i]" % Lang.t("Clic: scheda del luogo"))
	return "\n".join(lines)


## Stato degli eventi del luogo per la scheda: righe leggibili.
static func event_lines(state: GameState, s: LegendarySites.Site, player_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var st: Dictionary = state.sites_state.get(s.id, {})
	for eid in s.events:
		var e := state.rules.sites.event(eid)
		if e == null:
			continue
		var note := ""
		match e.kind:
			LegendarySites.KIND_RECURRING:
				var next: Dictionary = st.get("prossimo", {})
				if e.until_year > 0 and state.year > e.until_year:
					note = Lang.t("non accade piu'")
				elif next.has(eid) and LegendarySites.owner_of(state, s) == SimUtil.norm(player_id):
					var years := int(next[eid]) - state.year
					note = Lang.t("tra circa %d anni") % years if years > 0 else Lang.t("pronto")
				else:
					var every := state.rules.sites.interval_of(e)
					note = Lang.t("ogni %d-%d anni, per chi possiede la provincia") % [every.x, every.y]
			LegendarySites.KIND_CONDITIONAL:
				var who := {LegendarySites.WHO_GENERAL: "un generale", LegendarySites.WHO_FLEET: "una flotta", LegendarySites.WHO_AGENT: "un agente"}
				note = Lang.t("quando %s si trova qui") % Lang.t(str(who.get(e.who, "qualcuno")))
			LegendarySites.KIND_HISTORICAL:
				note = Lang.t("nel %d") % e.year if not (st.get("fatti", []) as Array).has(eid) else Lang.t("gia' accaduto")
		out.append("«%s»: %s" % [e.label(), note])
	return out


## Scelte del giocatore in attesa per il luogo (per il sigillo sulla mappa).
static func has_pending(state: GameState, player_id: String, site_id: String) -> bool:
	for c in LegendarySiteProcessor.choices_for(state, player_id):
		if str(c["luogo"]) == site_id:
			return true
	return false


## Riga colorata (bbcode) di un effetto.
static func colored(line: Dictionary) -> String:
	return "[color=%s]%s %s[/color]" % [GOOD if bool(line["bonus"]) else BAD, "▲" if bool(line["bonus"]) else "▼", str(line["testo"])]


# --- finestre illustrate e scelte ------------------------------------------------------------------------------------------


## Tavola dipinta del luogo (assets/luoghi/<id>.png, tools/prepara_luoghi.py), "" se non c'e' ancora.
static func image_path(site_id: String) -> String:
	var path := "res://assets/luoghi/%s.png" % site_id
	return path if ResourceLoader.exists(path) else ""


static func picture(site_id: String) -> Texture2D:
	var path := image_path(site_id)
	return load(path) as Texture2D if path != "" else null


## Id delle scelte del giocatore in attesa, in ordine.
static func queue_ids(state: GameState, player_id: String) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	for c in LegendarySiteProcessor.choices_for(state, player_id):
		out.append(int(c["id"]))
	return out


## Finestra illustrata (forma di CampaignUiAlerts) per un evento di un luogo che riguarda il giocatore; vuota se non lo
## riguarda o se e' una scelta in attesa (ha la sua finestra con i pulsanti).
static func alert_window(state: GameState, kind: String, e: Dictionary, key: String) -> Dictionary:
	if state.rules == null or state.rules.sites.is_empty():
		return {}
	var s := state.rules.sites.site(CampaignUiText.text_of(e.get("luogo")))
	if s == null or SimUtil.norm(CampaignUiText.text_of(e.get("fazione"))) != key:
		return {}
	var w := {"categoria": category_label(s.category), "luogo": s.region, "luogo_leggendario": s.id, "immagine": image_path(s.id), "tema": "", "esito": ""}
	match kind:
		GameState.EV_SITE_DISCOVERED:
			w["titolo"] = s.label(state.year)
			w["testo"] = s.text()
			var lines := PackedStringArray()
			for sec in sheet_sections(state, s):
				for l in sec["righe"]:
					lines.append(("+ " if bool(l["bonus"]) else "- ") + str(l["testo"]))
			w["effetto"] = "\n".join(lines)
			w["esito"] = "buono"
		GameState.EV_SITE_EVENT:
			if CampaignUiText.int_of(e.get("scelta")) > 0:
				return {}
			w["titolo"] = CampaignUiText.text_of(e.get("titolo"))
			w["testo"] = CampaignUiText.text_of(e.get("testo"))
			w["effetto"] = CampaignUiText.text_of(e.get("esito"))
		GameState.EV_SITE_TRANSIT:
			w["titolo"] = s.label(state.year)
			w["testo"] = CampaignUiText.text_of(e.get("testo"))
			w["effetto"] = ""
			w["esito"] = "cattivo"
		_:
			return {}
	return w


## Finestra di una scelta in attesa: {"titolo", "testo", "categoria", "luogo", "luogo_leggendario", "opzioni":
## [{"testo", "nota", "problema"}]}; vuota se la scelta non c'e' piu'.
static func choice_window(state: GameState, player_id: String, choice_id: int) -> Dictionary:
	var c := LegendarySiteProcessor.choice(state, choice_id)
	if c.is_empty() or str(c["fazione"]) != SimUtil.norm(player_id):
		return {}
	var s := state.rules.sites.site(str(c["luogo"]))
	var e := state.rules.sites.event(str(c["evento"]))
	if s == null or e == null:
		return {}
	var ctx: Dictionary = c.get("contesto", {})
	var options: Array[Dictionary] = []
	for i in e.options.size():
		options.append({"testo": LegendarySites.SiteEvent.option_label(e.options[i]), "nota": option_note(e.options[i]),
			"problema": LegendarySiteProcessor.option_problem(state, e, player_id, ctx, i)})
	var who := ""
	var army := state.army(int(ctx.get("esercito", 0)))
	if army != null:
		var cmd := state.commander_of(army.id)
		if army.is_fleet and not army.admiral.is_empty():
			who = Lang.t("Ammiraglio: %s") % str(army.admiral.get("nome", ""))
		elif cmd != null:
			who = Lang.t("Comandante: %s") % cmd.full_name()
	return {
		"titolo": e.label(),
		"testo": e.body() + ("\n\n" + who if who != "" else ""),
		"categoria": "%s · %s" % [category_label(s.category), s.label(state.year)],
		"luogo": s.region,
		"luogo_leggendario": s.id,
		"opzioni": options,
	}
