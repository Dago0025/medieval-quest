class_name CampaignUiAlerts
extends RefCounted
## Avvisi degli eventi importanti dell'anno (richiesta di Federico del 2026-11-20): ogni avvenimento che conta per il giocatore
## ha una finestra illustrata propria, con l'immagine come sfondo, invece di restare una riga del resoconto. Le battaglie (di
## terra, navali, assalti e sortite) e gli altri eventi con un luogo portano la mappa su quel punto prima di aprirsi.
##
## Funzioni pure: leggono il registro degli eventi e producono finestre nella stessa forma di CampaignUiEvents.historical_window,
## con in piu' "categoria" (riga piccola sopra il titolo), "tema" (cartella di assets/eventi o tema di illustrazioni.cfg, vedi
## EventArt.theme_texture), "luogo" (provincia o zona di mare, "" se l'evento non ne ha) ed "esito" (ESITO_*: colore della
## categoria). Il resoconto di fine anno resta com'e': le finestre si aggiungono, non lo sostituiscono.

const ESITO_GOOD := "buono"
const ESITO_BAD := "cattivo"
const ESITO_NONE := ""

## Temi usati dagli avvisi: ognuno ha una serie propria in assets/eventi/<tema>/ o una voce in illustrazioni.cfg [temi]
## (test_ui_avvisi lo controlla).
const THEMES := [
	"battaglia_vittoria", "battaglia_sconfitta", "battaglia_navale_vittoria", "battaglia_navale_sconfitta",
	"assalto_vittoria", "assalto_sconfitta", "sortita", "assedio", "conquista", "provincia_persa", "guerra", "alleanza",
	"alleanza_rotta", "tregua", "matrimonio", "nascita", "morte", "incoronazione", "assassinio", "rivolta", "scomunica",
	"scomunica_revocata", "fazione_distrutta", "fazione_riemersa", "commercio", "inondazione", "carestia", "terremoto", "tempesta", "peste", "peste_nera", "orda",
]

## Ruoli della famiglia la cui morte merita una finestra (i generali restano nel resoconto).
const FAMILY_ROLES := [Character.ROLE_LEADER, Character.ROLE_HEIR, Character.ROLE_PRINCE, Character.ROLE_PRINCESS]


## Finestre degli avvisi per `player` nell'ordine del registro; `year` e' l'anno giocato (per la riga della categoria).
## Una provincia presa con un assalto o una battaglia del giocatore non apre una seconda finestra: la conquista si aggiunge
## all'esito della battaglia.
static func windows(state: GameState, player: String, year: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := SimUtil.norm(player)
	if state == null or key == "":
		return out
	var battle_at := {}   # regione -> indice in `out` dell'ultima battaglia del giocatore li'
	for e in state.events:
		var kind := str(e.get("tipo", ""))
		var y := CampaignUiText.int_of(e.get("anno"), year if year >= 0 else state.year)
		var w := {}
		if kind == GameState.EV_BATTLE:
			w = _battle(state, e, key)
			if not w.is_empty():
				battle_at[str(w["luogo"])] = out.size()
		elif kind == GameState.EV_PROVINCE_CAPTURED:
			var region := CampaignUiText.text_of(e.get("regione"))
			var conqueror := SimUtil.norm(CampaignUiText.text_of(e.get("fazione")))
			var previous := SimUtil.norm(CampaignUiText.text_of(e.get("precedente")))
			if conqueror != key and previous != key:
				continue
			if battle_at.has(region):
				var merged: Dictionary = out[int(battle_at[region])]
				merged["effetto"] = "%s %s" % [str(merged["effetto"]), Lang.t("La provincia passa a voi.") if conqueror == key else Lang.t("La provincia è perduta.")]
				continue
			w = _capture(state, e, key, conqueror == key)
		else:
			w = _other(state, kind, e, key)
		if w.is_empty():
			continue
		w["anno"] = y
		w["tipo"] = kind
		w["indice"] = -1
		w["chiave"] = str(w["tema"])
		w["originale"] = false
		w["provvisoria"] = false
		out.append(w)
	return out


## Vero se la finestra porta la mappa su un luogo.
static func has_place(w: Dictionary) -> bool:
	return str(w.get("luogo", "")) != ""


# --- battaglie e conquiste ---------------------------------------------------------------------------------------------


static func _battle(state: GameState, e: Dictionary, key: String) -> Dictionary:
	var attacker := SimUtil.norm(CampaignUiText.text_of(e.get("attaccante")))
	var defender := SimUtil.norm(CampaignUiText.text_of(e.get("difensore")))
	if attacker != key and defender != key:
		return {}
	var region := CampaignUiText.text_of(e.get("regione"))
	var place := CampaignUiText.region_name(state, region)
	var kind := CampaignUiText.text_of(e.get("scontro"))
	var won := SimUtil.norm(CampaignUiText.text_of(e.get("vincitore"))) == key
	var we_attack := attacker == key
	var theme := "battaglia"
	var category := Lang.t("Battaglia")
	var title := Lang.t("Battaglia di %s") % place
	if kind == BattleResult.KIND_NAVAL:
		theme = "battaglia_navale"
		category = Lang.t("Battaglia navale")
		title = Lang.t("Battaglia navale: %s") % place
	elif kind == BattleResult.KIND_ASSAULT:
		theme = "assalto"
		category = Lang.t("Assalto")
		title = Lang.t("Assalto al castello di %s") % place
	elif kind == BattleResult.KIND_SALLY:
		category = Lang.t("Sortita")
		title = Lang.t("Sortita dal castello di %s") % place
	if kind == BattleResult.KIND_SALLY:
		theme = "sortita"
	else:
		theme += "_vittoria" if (won if kind != BattleResult.KIND_ASSAULT else (we_attack == won)) else "_sconfitta"
	# nell'assalto il tema racconta il castello: preso (vittoria degli assalitori) o tenuto, chiunque sia il giocatore
	var ours_before := CampaignUiText.int_of(e.get("uomini_attaccante" if we_attack else "uomini_difensore"))
	var theirs_before := CampaignUiText.int_of(e.get("uomini_difensore" if we_attack else "uomini_attaccante"))
	var ours_lost := CampaignUiText.int_of(e.get("perdite_attaccante" if we_attack else "perdite_difensore"))
	var theirs_lost := CampaignUiText.int_of(e.get("perdite_difensore" if we_attack else "perdite_attaccante"))
	var enemy := defender if we_attack else attacker
	var effect := Lang.t("Perdite: voi %d uomini su %d, %s %d su %d.") % [ours_lost, ours_before, CampaignUiText.fart(enemy), theirs_lost, theirs_before]
	var captured := 0
	for c in CampaignUiText.list_of(e.get("catture")):
		if c is Dictionary:
			captured += CampaignUiText.int_of((c as Dictionary).get("uomini"))
	if captured > 0:
		effect += " " + (Lang.t("Catturati %d nemici.") % captured if won else Lang.t("%d dei vostri sono stati catturati.") % captured)
	return {
		"categoria": "%s · %s" % [category, Lang.t("Vittoria") if won else Lang.t("Sconfitta")],
		"titolo": title,
		"testo": CampaignUiText.battle_text(state, e),
		"effetto": effect,
		"tema": theme,
		"luogo": region,
		"esito": ESITO_GOOD if won else ESITO_BAD,
	}


static func _capture(state: GameState, e: Dictionary, key: String, ours: bool) -> Dictionary:
	var region := CampaignUiText.text_of(e.get("regione"))
	var place := CampaignUiText.region_name(state, region)
	return {
		"categoria": Lang.t("Conquista") if ours else Lang.t("Provincia perduta"),
		"titolo": Lang.t("Conquista di %s") % place if ours else Lang.t("Perdita di %s") % place,
		"testo": CampaignUiText.format_event(state, e),
		"effetto": Lang.t("La provincia è ora vostra.") if ours else Lang.t("La provincia passa al nemico."),
		"tema": "conquista" if ours else "provincia_persa",
		"luogo": region,
		"esito": ESITO_GOOD if ours else ESITO_BAD,
	}


# --- tutti gli altri ---------------------------------------------------------------------------------------------------


static func _other(state: GameState, kind: String, e: Dictionary, key: String) -> Dictionary:
	var actor := SimUtil.norm(CampaignUiText.text_of(e.get("fazione")))
	var region := CampaignUiText.text_of(CampaignUiText.prop(e, ["regione", "provincia"]))
	var mentions := CampaignUiText.event_mentions(e, key)
	var other := _other_faction(state, e, key)
	var text := CampaignUiText.format_event(state, e)
	if kind == GameState.EV_SITE_DISCOVERED or kind == GameState.EV_SITE_EVENT or kind == GameState.EV_SITE_TRANSIT:
		return CampaignUiSites.alert_window(state, kind, e, key)   # luoghi leggendari (26/11/2026)
	match kind:
		GameState.EV_SIEGE_STARTED:
			if SimUtil.norm(CampaignUiText.text_of(e.get("assediata"))) != key:
				return {}
			return _w(Lang.t("Assedio"), Lang.t("Assedio di %s") % CampaignUiText.region_name(state, region), text,
				Lang.t("Senza soccorsi la guarnigione resiste finché bastano le scorte."), "assedio", region, ESITO_BAD)
		GameState.EV_STARVED:
			if not mentions:
				return {}
			var ours := actor != key
			return _w(Lang.t("Assedio"), Lang.t("Resa per fame a %s") % CampaignUiText.region_name(state, region), text, "",
				"assedio", region, ESITO_BAD if ours else ESITO_GOOD)
		GameState.EV_WAR_DECLARED:
			if not mentions or other == "":
				return {}
			var by_us := actor == key
			return _w(Lang.t("Guerra"), Lang.t("Guerra %s") % CampaignUiText.fprep("con", other, "with"), text,
				Lang.t("Siete in guerra: le loro armate e flotte vi attaccheranno.") if not by_us else Lang.t("Avete aperto le ostilità."),
				"guerra", region, ESITO_NONE if by_us else ESITO_BAD)
		GameState.EV_ALLIANCE_FORMED:
			if not mentions or other == "":
				return {}
			return _w(Lang.t("Diplomazia"), Lang.t("Alleanza %s") % CampaignUiText.fprep("con", other, "with"), text, "", "alleanza", "", ESITO_GOOD)
		GameState.EV_ALLIANCE_BROKEN:
			if not mentions or other == "":
				return {}
			return _w(Lang.t("Diplomazia"), Lang.t("Alleanza rotta %s") % CampaignUiText.fprep("con", other, "with"), text, "", "alleanza_rotta", "", ESITO_BAD)
		GameState.EV_TRUCE:
			if not mentions or other == "":
				return {}
			return _w(Lang.t("Diplomazia"), Lang.t("Tregua %s") % CampaignUiText.fprep("con", other, "with"), text, "", "tregua", "", ESITO_GOOD)
		GameState.EV_TRUCE_BROKEN:
			if not mentions or other == "":
				return {}
			return _w(Lang.t("Diplomazia"), Lang.t("Tregua rotta %s") % CampaignUiText.fprep("con", other, "with"), text, "", "guerra", "", ESITO_BAD)
		GameState.EV_MARRIAGE:
			if not mentions:
				return {}
			var with_whom := Lang.t("Nozze %s") % CampaignUiText.fprep("con", other, "with") if other != "" else Lang.t("Nozze reali")
			return _w(Lang.t("Corte"), with_whom, text, "", "matrimonio", "", ESITO_GOOD)
		GameState.EV_BIRTH:
			if actor != key:
				return {}
			return _w(Lang.t("Corte"), Lang.t("Nasce %s") % CampaignUiText.text_of(e.get("nome")), text, "", "nascita", "", ESITO_GOOD)
		GameState.EV_DEATH:
			if actor != key or not FAMILY_ROLES.has(CampaignUiText.text_of(e.get("ruolo"))):
				return {}
			return _w(Lang.t("Corte"), Lang.t("Morte di %s") % CampaignUiText.text_of(e.get("nome")), text, "", "morte", "", ESITO_BAD)
		GameState.EV_SUCCESSION:
			if actor != key:
				return {}
			return _w(Lang.t("Corte"), Lang.t("Un nuovo sovrano: %s") % CampaignUiText.text_of(e.get("nome")), text, "", "incoronazione", "", ESITO_NONE)
		GameState.EV_ASSASSINATION:
			if not mentions:
				return {}
			return _w(Lang.t("Intrighi"), Lang.t("Assassinio"), text, "", "assassinio", region, ESITO_GOOD if actor == key else ESITO_BAD)
		GameState.EV_REBELLION, GameState.EV_HERETIC_REVOLT, GameState.EV_CIVIL_WAR:
			if not _owned_or_ours(state, region, actor, key):
				return {}
			var title := Lang.t("Rivolta a %s") % CampaignUiText.region_name(state, region)
			if kind == GameState.EV_HERETIC_REVOLT:
				title = Lang.t("Rivolta degli eretici a %s") % CampaignUiText.region_name(state, region)
			elif kind == GameState.EV_CIVIL_WAR:
				title = Lang.t("Guerra civile")
			return _w(Lang.t("Province"), title, text, "", "rivolta", region, ESITO_BAD)
		GameState.EV_EXCOMMUNICATION:
			if actor != key:
				return {}
			return _w(Lang.t("Papato"), Lang.t("Scomunica"), text, "", "scomunica", "", ESITO_BAD)
		GameState.EV_EXCOMMUNICATION_LIFTED:
			if actor != key:
				return {}
			return _w(Lang.t("Papato"), Lang.t("Scomunica revocata"), text, "", "scomunica_revocata", "", ESITO_GOOD)
		GameState.EV_FACTION_DESTROYED:
			if actor == key or actor == "":
				return {}
			return _w(Lang.t("Notizia"), Lang.t("Caduta %s") % CampaignUiText.fprep("di", actor, "of"), text, "", "fazione_distrutta", "", ESITO_NONE)
		GameState.EV_FACTION_REEMERGED, GameState.EV_PAPACY_REEMERGED:
			# ADR-114: il ritorno di una fazione sconfitta (o del Papato) si annuncia come la sua caduta
			if actor == key or actor == "":
				return {}
			return _w(Lang.t("Notizia"), Lang.t("Ritorno %s") % CampaignUiText.fprep("di", actor, "of"), text, "", "fazione_riemersa", region, ESITO_NONE)
		GameState.EV_AMERICAS_CONTACT:
			return _w(Lang.t("Notizia"), Lang.t("Il Nuovo Mondo"), text, "", "commercio", region, ESITO_NONE)
		GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_QUAKE, GameState.EV_PLAGUE:
			if not _owned_or_ours(state, region, SimUtil.norm(CampaignUiText.text_of(e.get("proprietario"))), key):
				return {}
			var theme := kind
			var label := {GameState.EV_FLOOD: Lang.t("Inondazione a %s"), GameState.EV_FAMINE: Lang.t("Carestia a %s"),
				GameState.EV_QUAKE: Lang.t("Terremoto a %s"), GameState.EV_PLAGUE: Lang.t("Peste a %s")}[kind] as String
			if kind == GameState.EV_PLAGUE and bool(e.get("peste_nera", false)):
				theme = "peste_nera"
				label = Lang.t("Peste Nera a %s")
			return _w(Lang.t("Disastro"), label % CampaignUiText.region_name(state, region), text, "", theme, region, ESITO_BAD)
		GameState.EV_STORM:
			if actor != key:
				return {}
			return _w(Lang.t("Disastro"), Lang.t("Tempesta: %s") % CampaignUiText.region_name(state, region), text, "", "tempesta", region, ESITO_BAD)
		GameState.EV_BLACK_DEATH:
			var first := ""
			var origin := CampaignUiText.list_of(e.get("regioni"))
			if not origin.is_empty():
				first = str(origin[0])
			return _w(Lang.t("Disastro"), Lang.t("La Peste Nera"), text, "", "peste_nera", first, ESITO_BAD)
		GameState.EV_HORDE_ARRIVES:
			return _w(Lang.t("Notizia"), Lang.t("L'Orda d'Oro"), text, "", "orda", region, ESITO_BAD)
	return {}


static func _w(category: String, title: String, text: String, effect: String, theme: String, place: String, outcome: String) -> Dictionary:
	return {"categoria": category, "titolo": title, "testo": text, "effetto": effect, "tema": theme, "luogo": place, "esito": outcome}


## Vero se la provincia e' del giocatore (o l'evento nomina il giocatore come proprietario).
static func _owned_or_ours(state: GameState, region: String, owner: String, key: String) -> bool:
	if owner == key:
		return true
	var p := state.province(region) if region != "" else null
	return p != null and p.owner == key


## La prima fazione diversa dal giocatore nominata dall'evento ("" se nessuna).
static func _other_faction(state: GameState, e: Dictionary, key: String) -> String:
	for k in ["fazione", "con", "contro", "destinatario", "a", "da", "bersaglio", "vittima_fazione", "fazione_vittima"]:
		var id := SimUtil.norm(CampaignUiText.text_of(e.get(k)))
		if id != "" and id != key and state.faction(id) != null:
			return id
	return ""
