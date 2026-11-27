class_name CampaignUiPapacy
extends RefCounted
## Testi e dati dell'interfaccia della fase 5c (Papato, scomunica, crociate e jihad): funzioni pure che leggono lo stato
## e producono stringhe, righe o liste, senza modificarlo. L'interfaccia (scenes/) mostra e invia solo comandi
## (ADR-003, 008). Nessuna regola e' ricalcolata qui: stato papale, bersagli e motivi vengono da
## `GameCommands.papal_status`, `GameCommands.crusade_targets` e da `PapacyProcessor`.
##
## - barra in alto: indicatore di scomunica (testo e tooltip con gli effetti) e avviso del Papa;
## - esercito crociato: genere, segnalino (croce o mezzaluna), righe del pannello (zelo, bersaglio, province reclutate),
##   scelta del bersaglio (clic destro o elenco con nome, proprietario e motivo);
## - reclutamento di Crusade e Jihad: etichetta e motivo dell'indisponibilita';
## - pannello della diplomazia: colonna della scomunica e riga del Papato;
## - testi italiani degli eventi della 5c (crociata o jihad secondo il campo "genere").

## Segnalino dell'esercito crociato: la croce per la crociata, la mezzaluna per il jihad.
const BADGE_CROSS := "croce"
const BADGE_CRESCENT := "mezzaluna"

## Azioni del clic destro con un esercito del giocatore selezionato.
const CLICK_MOVE := "movimento"
const CLICK_TARGET := "bersaglio"

## Motivi per cui una provincia e' un bersaglio valido (PapacyProcessor.target_reason).
const TARGET_REASONS := {
	"scomunicato": "proprietario scomunicato",
	"ribelle": "in mano ai ribelli",
	"non_cattolico": "proprietario non cattolico",
	"eretici": "maggioranza eretica",
	"musulmana": "terra un tempo musulmana",
}

const EXCOMMUNICATION_REASONS := {
	"attacco_al_papato": "ha attaccato il Papato",
	"attacco_durante_avvertimento": "ha ignorato l'avvertimento del Papa",
}

const LIFTED_REASONS := {
	"morte_del_papa": "per la morte del Papa",
	"morte_del_capo": "per la morte del suo capo",
	"papato_distrutto": "perché il Papato è distrutto",
	"fazione_distrutta": "perché la fazione è scomparsa",
}

const FAILURE_REASONS := {
	"scioglimento": "lo zelo è esaurito e l'esercito si scioglie",
	"distrutto": "l'esercito è distrutto",
	"senza_pile": "l'esercito non ha più pile",
	"perso": "l'esercito è andato perso",
	"scomunica": "la fazione è scomunicata",
}


# --- generi -----------------------------------------------------------------------------------------------------


## "crociata" o "jihad" (qualunque altro valore, compreso il vuoto: crociata).
static func kind_name(kind: String) -> String:
	return Lang.t("jihad") if kind == PapacyProcessor.KIND_JIHAD else Lang.t("crociata")


## "La crociata" / "Il jihad", a inizio frase.
static func kind_noun(kind: String) -> String:
	return Lang.t("Il jihad") if kind == PapacyProcessor.KIND_JIHAD else Lang.t("La crociata")


## "Crociata" / "Jihad".
static func kind_label(kind: String) -> String:
	return Lang.t("Jihad") if kind == PapacyProcessor.KIND_JIHAD else Lang.t("Crociata")


## Etichetta dell'elenco di reclutamento: "[Crociata]" / "[Jihad]".
static func kind_tag(kind: String) -> String:
	return "[%s]" % kind_label(kind)


## Segnalino dell'esercito: "" per un esercito normale e per le flotte, altrimenti BADGE_CROSS o BADGE_CRESCENT.
static func badge_of(army: Army) -> String:
	if army == null or army.is_fleet or not army.is_crusade():
		return ""
	return BADGE_CRESCENT if army.crusade_kind() == PapacyProcessor.KIND_JIHAD else BADGE_CROSS


# --- barra in alto ----------------------------------------------------------------------------------------------


## Testo della scomunica: «Scomunicati dal 1150» (`own`: il giocatore) o «Scomunicata dal 1150».
static func excommunication_text(year: int, own: bool = true) -> String:
	var word := Lang.t("Scomunicati") if own else Lang.t("Scomunicata")
	if year <= 0:
		return word
	return Lang.t("%s dal %d") % [word, year]


## Indicatore di scomunica della fazione: {"scomunicata", "testo", "tooltip"}; vuoti se non e' scomunicata.
static func excommunication_info(state: GameState, faction_id: String) -> Dictionary:
	var status := GameCommands.papal_status(state, faction_id)
	if not bool(status.get("ok", false)) or not bool(status.get("scomunicata", false)):
		return {"scomunicata": false, "testo": "", "tooltip": ""}
	var pr := state.rules.papacy
	var tip := PackedStringArray()
	tip.append(Lang.t("Il Papa vi ha scomunicati."))
	tip.append(Lang.t("Effetti:"))
	tip.append(Lang.t("- l'influenza del capo cala di %d (una volta);") % pr.excommunication_influence)
	tip.append(Lang.t("- la lealtà obiettivo delle province scende fino a %d, in proporzione ai cattolici;") % pr.excommunication_loyalty)
	tip.append(Lang.t("- le alleanze con le fazioni cattoliche sono rotte;"))
	tip.append(Lang.t("- le vostre province sono bersaglio delle crociate;"))
	tip.append(Lang.t("- non potete bandire crociate."))
	tip.append(Lang.t("La scomunica cade con la morte del Papa o del vostro capo."))
	return {
		"scomunicata": true,
		"testo": excommunication_text(int(status.get("anno", 0)), true),
		"tooltip": "\n".join(tip),
	}


## Avvertimenti del Papa verso la fazione, per fazione protetta: [{"contro", "nome", "anno", "scadenza"}].
static func warnings_of(state: GameState, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var status := GameCommands.papal_status(state, faction_id)
	if not bool(status.get("ok", false)):
		return out
	var raw: Array = status.get("avvertimenti", [])
	for w in raw:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = w
		var against := str(d.get("contro", ""))
		out.append({
			"contro": against,
			"nome": CampaignUiText.faction_name(against),
			"anno": int(d.get("anno", 0)),
			"scadenza": int(d.get("scadenza", 0)),
		})
	return out


## Avviso evidente del Papa: {"visibile", "testo", "tooltip"}. «Il Papa vi ammonisce: non attaccate Beta fino al 1102.»
static func warning_info(state: GameState, faction_id: String) -> Dictionary:
	var warnings := warnings_of(state, faction_id)
	if warnings.is_empty():
		return {"visibile": false, "testo": "", "tooltip": ""}
	var text := Lang.t("Il Papa vi ammonisce: non attaccate ")
	if warnings.size() == 1:
		text += Lang.t("%s fino al %d.") % [str(warnings[0]["nome"]), int(warnings[0]["scadenza"])]
	else:
		var parts := PackedStringArray()
		for w in warnings:
			parts.append(Lang.t("%s (fino al %d)") % [str(w["nome"]), int(w["scadenza"])])
		text += _join_italian(parts) + "."
	var tip := Lang.t("Attaccare quelle fazioni prima della scadenza significa essere scomunicati.\nSe rispetterete il termine, il Papa imporrà una tregua di %d anni.") % state.rules.papacy.papal_truce_years
	return {"visibile": true, "testo": text, "tooltip": tip}


## "A", "A e B", "A, B e C".
static func _join_italian(parts: PackedStringArray) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	var head := parts.slice(0, parts.size() - 1)
	return Lang.t("%s e %s") % [", ".join(head), parts[parts.size() - 1]]


## Riga del Papato (pannello della diplomazia): «Papato: vivo · Papa Gregorio» o «Papato: distrutto · riemerge ...».
static func papacy_line(state: GameState) -> String:
	var status := GameCommands.papal_status(state, GameState.PAPAL)
	if not bool(status.get("ok", false)):
		return Lang.t("Papato: assente da questa partita")
	if not bool(status.get("papato_vivo", false)):
		return Lang.t("Papato: distrutto · ricompare con un'armata tra %d e %d anni nelle sue terre") % [state.rules.papacy.reemerge_years_min, state.rules.papacy.reemerge_years_max]
	var text := Lang.t("Papato: vivo")
	var pope := state.character(int(status.get("papa", 0)))
	if pope != null:
		text += Lang.t(" · Papa %s") % pope.full_name()
	return text


# --- pannello della diplomazia ----------------------------------------------------------------------------------


## Titoli delle colonne: quelli della 5a e la scomunica.
static func diplomacy_headers() -> PackedStringArray:
	var out := CampaignUiAgents.diplomacy_headers()
	out.append(Lang.t("Scomunica"))
	return out


## Righe della 5a con «scomunicata» (bool) e «testo_scomunica» (stato di ogni fazione viva, «Papa» per il Papato).
static func diplomacy_rows(state: GameState, player_id: String) -> Array[Dictionary]:
	var rows := CampaignUiAgents.diplomacy_rows(state, player_id)
	for row in rows:
		var faction_id := str(row["fazione"])
		var f := state.faction(faction_id)
		var excommunicated := f != null and f.excommunicated
		row["scomunicata"] = excommunicated
		if excommunicated:
			row["testo_scomunica"] = excommunication_text(f.excommunication_year, false)
		elif faction_id == GameState.PAPAL:
			row["testo_scomunica"] = Lang.t("Papa")
		else:
			row["testo_scomunica"] = "-"
	return rows


## Celle di una riga, nell'ordine delle colonne (6).
static func diplomacy_cells(row: Dictionary) -> PackedStringArray:
	var out := CampaignUiAgents.diplomacy_cells(row)
	out.append(str(row.get("testo_scomunica", "-")))
	return out


# --- esercito crociato ------------------------------------------------------------------------------------------


## Descrizione dell'esercito per il pannello: quella di sempre e, per un esercito crociato, le righe della crociata.
static func army_text(state: GameState, army: Army) -> String:
	var text := CampaignUiText.describe_army(state, army)
	var extra := crusade_lines(state, army)
	if extra.is_empty():
		return text
	return text + "\n" + "\n".join(extra)


## Righe del pannello di un esercito crociato (vuote per gli altri): tipo e zelo, bersaglio, province gia' reclutate e
## l'avviso delle soglie di zelo.
static func crusade_lines(state: GameState, army: Army) -> PackedStringArray:
	var out := PackedStringArray()
	if army == null or not army.is_crusade():
		return out
	var kind := army.crusade_kind()
	var pr := state.rules.papacy
	var zeal := int(army.crusade.get("zelo", 0))
	out.append(Lang.t("%s · zelo %d su 100") % [kind_label(kind), zeal])
	var target := army.crusade_target()
	if target == "":
		out.append(Lang.t("Bersaglio: nessuno (senza bersaglio lo zelo cala di altri %d all'anno)") % pr.zeal_decay_no_target)
	else:
		var province := state.province(target)
		var line := Lang.t("Bersaglio: %s") % CampaignUiText.region_name(state, target)
		if province != null and province.owner != "":
			line += " (%s)" % CampaignUiText.faction_name(province.owner)
		out.append(line)
	var done: Array = CampaignUiText.list_of(army.crusade.get("reclutate", []))
	var names := PackedStringArray()
	for id in done:
		names.append(CampaignUiText.region_name(state, str(id)))
	out.append(Lang.t("Province già reclutate: %s") % (", ".join(names) if not names.is_empty() else Lang.t("nessuna")))
	if zeal <= pr.zeal_dissolve:
		out.append(Lang.t("Zelo esaurito: l'esercito si scioglie a fine anno."))
	elif zeal < pr.zeal_desertion:
		out.append(Lang.t("Zelo molto basso: a fine anno %s disertano.") % armies_text(pr.desertion_stacks))
	elif zeal < pr.zeal_losses:
		out.append(Lang.t("Zelo basso: a fine anno si perde un'armata."))
	return out


## Azione del clic destro con `army` selezionato sulla regione: CLICK_TARGET per un esercito crociato senza bersaglio
## (a meno che la regione sia quella dell'esercito, che annulla il movimento); altrimenti CLICK_MOVE (movimento come
## per ogni esercito).
static func right_click_action(army: Army, region_id: String) -> String:
	if army == null or army.is_fleet or not army.is_crusade():
		return CLICK_MOVE
	if army.crusade_target() != "" or region_id == army.region:
		return CLICK_MOVE
	return CLICK_TARGET


## Testo del motivo di un bersaglio ("scomunicato" -> «proprietario scomunicato»); sconosciuto: il testo com'e'.
static func target_reason_text(reason: String) -> String:
	if TARGET_REASONS.has(reason):
		return Lang.t(str(TARGET_REASONS[reason]))
	return reason.replace("_", " ")


## Elenco dei bersagli scelti dall'anteprima di `GameCommands.crusade_targets`, in ordine alfabetico del nome:
## {"ok", "errore", "titolo", "bersaglio" (attuale), "voci": [{"regione", "nome", "proprietario", "motivo",
## "motivo_testo", "testo", "attuale"}]}. «testo»: «Nome · di Proprietario · motivo».
static func target_menu(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var r := GameCommands.crusade_targets(state, faction_id, army_id)
	if not bool(r.get("ok", false)):
		return {"ok": false, "errore": CampaignUiText.order_error_text(state, str(r.get("errore", ""))), "titolo": "", "bersaglio": "", "voci": []}
	var kind := str(r.get("genere", ""))
	var current := str(r.get("bersaglio", ""))
	var entries: Array[Dictionary] = []
	var raw: Array = r.get("bersagli", [])
	for b in raw:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = b
		var region_id := str(d.get("regione", ""))
		var place := CampaignUiText.region_name(state, region_id)
		var owner_id := str(d.get("proprietario", ""))
		var reason := str(d.get("motivo", ""))
		var owner_text := CampaignUiText.faction_name(owner_id) if owner_id != "" else Lang.t("nessuno")
		entries.append({
			"regione": region_id,
			"nome": place,
			"proprietario": owner_id,
			"motivo": reason,
			"motivo_testo": target_reason_text(reason),
			"testo": Lang.t("%s · di %s · %s") % [place, owner_text, target_reason_text(reason)],
			"attuale": region_id == current,
		})
	entries.sort_custom(_target_before)
	return {
		"ok": true,
		"errore": "",
		"titolo": Lang.t("%s %d: scegli il bersaglio (zelo %d)") % [kind_label(kind), army_id, int(r.get("zelo", 0))],
		"bersaglio": current,
		"voci": entries,
	}


static func _target_before(a: Dictionary, b: Dictionary) -> bool:
	var na := str(a["nome"])
	var nb := str(b["nome"])
	if na != nb:
		return na < nb
	return str(a["regione"]) < str(b["regione"])


## Messaggio dell'esito di `GameCommands.set_crusade_target` (il toast): bersaglio, proprietario, percorso.
static func target_result_text(state: GameState, result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return CampaignUiText.order_error_text(state, str(result.get("errore", Lang.t("Bersaglio non valido."))))
	var army_id := int(result.get("esercito", 0))
	var kind := str(result.get("genere", ""))
	var target := str(result.get("bersaglio", ""))
	if target == "":
		return Lang.t("%s %d: bersaglio tolto.") % [kind_label(kind), army_id]
	var owner_id := str(result.get("proprietario", ""))
	var text := Lang.t("%s %d: bersaglio %s") % [kind_label(kind), army_id, CampaignUiText.region_name(state, target)]
	if owner_id != "":
		text += " (%s)" % CampaignUiText.faction_name(owner_id)
	text += "."
	var route: Array = CampaignUiText.list_of(result.get("percorso", []))
	var army := state.army(army_id)
	if not route.is_empty():
		var names := PackedStringArray()
		for step in route:
			names.append(CampaignUiText.region_name(state, str(step)))
		text += Lang.t(" Percorso: %s.") % " > ".join(names)
	elif army != null and not army.path.is_empty():
		text += Lang.t(" L'esercito prosegue sul percorso già ordinato.")
	elif army != null and army.region != target:
		text += Lang.t(" Nessun percorso per terra: ordina il movimento con il clic destro.")
	if army != null and owner_id != "" and owner_id != GameState.REBEL and not state.at_war(army.faction, owner_id):
		text += Lang.t(" La guerra a %s si dichiara all'ingresso.") % CampaignUiText.faction_name(owner_id)
	return text


# --- reclutamento -----------------------------------------------------------------------------------------------


## Genere dell'unita' del file prod ("crociata" per Crusade, "jihad" per Jihad), "" per ogni altra.
static func unit_kind(unit: UnitType) -> String:
	return PapacyProcessor.kind_of_unit(unit.type_name)


## Vero se la voce di reclutamento va mostrata alla fazione: la crociata ai cattolici, il jihad ai musulmani.
static func recruit_visible(state: GameState, faction_id: String, kind: String) -> bool:
	if kind == "":
		return false
	return ReligionProcessor.faction_religion(state, faction_id) == PapacyProcessor.kind_religion(kind)


## Motivo breve per cui Crusade o Jihad non e' disponibile, letto dall'errore di `can_queue_unit` («scomunica»,
## «crociata già attiva», «crociata già in coda»); "" se l'errore non e' uno di questi.
static func unavailable_reason(error: String) -> String:
	if error.contains(Lang.t("scomunicata")):
		return Lang.t("scomunica")
	if error.contains(Lang.t("crociata attiva")):
		return Lang.t("crociata già attiva")
	if error.contains(Lang.t("crociata in coda")):
		return Lang.t("crociata già in coda")
	return ""


## Voce di reclutamento: «[Crociata] Crusade · 1000 denari, 4 anni» e, se non disponibile per un motivo papale,
## «(scomunica)».
static func recruit_text(unit: UnitType, kind: String, cost: int, years: int, error: String = "") -> String:
	var text := Lang.t("%s %s · %d denari, %d anni") % [kind_tag(kind), CampaignUiText.agent_unit_name(unit.id), cost, years]
	var reason := unavailable_reason(error)
	if reason != "":
		text += " (%s)" % reason
	return text


## Tooltip della voce: quello di base e una spiegazione del genere.
static func recruit_tip(kind: String, base_tip: String) -> String:
	var extra := ""
	if kind == PapacyProcessor.KIND_JIHAD:
		extra = Lang.t("Jihad: alla fine della coda nasce un esercito che si sceglie un bersaglio tra le province un tempo musulmane.")
	else:
		extra = Lang.t("Crociata: alla fine della coda nasce un esercito che si sceglie un bersaglio tra le province di scomunicati, ribelli, non cattolici o eretici. Una alla volta.")
	return "%s\n%s" % [base_tip, extra]


## Nome di una voce della coda di reclutamento: crociate e jihad portano l'etichetta, gli altri come CampaignUiAgents.
static func queue_label(state: GameState, unit_id: String) -> String:
	var unit := state.units.get_unit(unit_id)
	if unit != null:
		var kind := unit_kind(unit)
		if kind != "":
			return "%s %s" % [kind_tag(kind), CampaignUiText.agent_unit_name(unit_id)]
	return CampaignUiAgents.queue_label(state, unit_id)


# --- eventi -----------------------------------------------------------------------------------------------------


## Testo di un evento della 5c; vuoto se `kind` non e' uno dei suoi tipi. Senza i campi essenziali ripiega sul campo
## "testo" scritto dalla simulazione.
static func format_event(state: GameState, kind: String, e: Dictionary) -> String:
	var fallback_text := text_free(e)
	var actor_id := SimUtil.norm(CampaignUiText.text_of(e.get("fazione", "")))
	var actor := CampaignUiText.faction_name(actor_id)
	var other_id := SimUtil.norm(CampaignUiText.text_of(e.get("con", "")))
	var other := CampaignUiText.faction_name(other_id)
	var genre := CampaignUiText.text_of(e.get("genere", ""))
	if kind == GameState.EV_PAPAL_WARNING:
		var against_id := SimUtil.norm(CampaignUiText.text_of(e.get("contro", "")))
		if actor_id == "" or against_id == "":
			return fallback_text
		var text := Lang.t("Il Papa ammonisce %s: non %s %s") % [CampaignUiText.fart(actor_id), CampaignUiText.fverb(actor_id, Lang.t("attacchi"), Lang.t("attacchino")), CampaignUiText.fart(against_id)]
		var until := CampaignUiText.int_of(e.get("fino_al"))
		if until > 0:
			text += Lang.t(" fino al %d") % until
		return text + ", " + CampaignUiText.fverb(actor_id, Lang.t("o sarà scomunicata."), Lang.t("o saranno scomunicati."))
	if kind == GameState.EV_PAPAL_TRUCE:
		if actor_id == "" or other_id == "":
			return fallback_text
		var truce := Lang.t("Il Papa impone una tregua tra %s e %s") % [CampaignUiText.fart(actor_id), CampaignUiText.fart(other_id)]
		var truce_until := CampaignUiText.int_of(e.get("fino_al"))
		if truce_until > 0:
			truce += Lang.t(" fino al %d") % truce_until
		return truce + "."
	if kind == GameState.EV_EXCOMMUNICATION:
		if actor_id == "":
			return fallback_text
		var banned := Lang.t("%s %s dal Papa") % [CampaignUiText.fsubj(actor_id), CampaignUiText.fverb(actor_id, Lang.t("è scomunicata"), Lang.t("sono scomunicati"))]
		var why := CampaignUiText.text_of(e.get("motivo", ""))
		if EXCOMMUNICATION_REASONS.has(why):
			banned += " (%s)" % Lang.t(str(EXCOMMUNICATION_REASONS[why]))
		banned += "."
		var lost := CampaignUiText.int_of(e.get("influenza_persa"))
		if lost > 0:
			banned += Lang.t(" L'influenza del suo capo scende di %d.") % lost
		var broken := CampaignUiText.faction_ids_of(state, e.get("alleanze_rotte", []))
		if not broken.is_empty():
			banned += Lang.t(" Alleanze rotte con %s.") % CampaignUiText.fnames(broken)
		var refund := CampaignUiText.int_of(e.get("rimborso"))
		if refund > 0:
			banned += Lang.t(" Le crociate in coda sono annullate: rimborsati %d denari.") % refund
		return banned
	if kind == GameState.EV_EXCOMMUNICATION_LIFTED:
		if actor_id == "":
			return fallback_text
		var lifted := Lang.t("La scomunica %s è revocata") % CampaignUiText.fprep("di", actor_id)
		var lifted_why := CampaignUiText.text_of(e.get("motivo", ""))
		if LIFTED_REASONS.has(lifted_why):
			lifted += " " + Lang.t(str(LIFTED_REASONS[lifted_why]))
		return lifted + "."
	if kind == GameState.EV_PAPAL_GIFT:
		var amount := CampaignUiText.int_of(e.get("importo"))
		if actor_id == "" or amount <= 0:
			return fallback_text
		var gift := Lang.t("Dono del Papa per %s: %d denari") % [CampaignUiText.fart(actor_id), amount]
		var religious := CampaignUiText.int_of(e.get("religiosi"))
		if religious > 0:
			gift += Lang.t(" (%d religiosi)") % religious
		return gift + "."
	if kind == GameState.EV_PAPACY_REEMERGED:
		var where := CampaignUiText.region_name(state, CampaignUiText.text_of(e.get("provincia", e.get("regione", ""))))
		if where == "":
			return fallback_text
		var back := Lang.t("Il Papato riemerge a %s") % where
		var stacks := CampaignUiText.int_of(e.get("pile"))
		if stacks > 0:
			back += Lang.t(" con %s") % armies_text(stacks)
		var times := CampaignUiText.int_of(e.get("riemersioni"))
		if times > 0:
			back += Lang.t(" (riemersione %d)") % times
		return back + "."
	return _format_crusade_event(state, kind, e, actor_id, actor, genre, fallback_text)


## «1 armata», «4 armate»: le pile (unita') di crociate e jihad nei testi (richiesta di Federico del 2026-11-13).
static func armies_text(n: int) -> String:
	return "%d %s" % [n, Lang.t("armata") if n == 1 else Lang.t("armate")]


## Eventi di crociata e jihad (stessi tipi, distinti dal campo "genere").
static func _format_crusade_event(state: GameState, kind: String, e: Dictionary, actor_id: String, actor: String, genre: String, fallback_text: String) -> String:
	var noun := kind_noun(genre)
	actor = CampaignUiText.fprep("di", actor_id)   # «della crociata degli Inglesi»
	var army_id := CampaignUiText.int_of(e.get("esercito"))
	if kind == GameState.EV_CRUSADE_LAUNCHED:
		var place := CampaignUiText.region_name(state, CampaignUiText.text_of(e.get("provincia", e.get("regione", ""))))
		if actor_id == "" or place == "":
			return fallback_text
		var text := Lang.t("%s %s parte da %s") % [noun, actor, place]
		var stacks := CampaignUiText.int_of(e.get("pile"))
		if stacks > 0:
			text += Lang.t(" con %s") % armies_text(stacks)
		if e.has("zelo"):
			text += Lang.t(" (zelo %d)") % CampaignUiText.int_of(e.get("zelo"))
		# destinazione (22/11/2026): il bersaglio scelto alla partenza, con il suo proprietario
		var goal := CampaignUiText.text_of(e.get("bersaglio", ""))
		if goal != "":
			text += Lang.t(", diretta a %s") % CampaignUiText.region_name(state, goal) if genre != PapacyProcessor.KIND_JIHAD else Lang.t(", diretto a %s") % CampaignUiText.region_name(state, goal)
			var goal_owner := SimUtil.norm(CampaignUiText.text_of(e.get("proprietario", "")))
			if goal_owner != "":
				text += " (%s)" % CampaignUiText.faction_name(goal_owner)
		elif e.has("bersaglio"):
			text += Lang.t(", ancora senza bersaglio")
		return text + "."
	if kind == GameState.EV_CRUSADE_TARGET:
		if actor_id == "":
			return fallback_text
		var target_id := CampaignUiText.text_of(e.get("bersaglio", ""))
		var army_text_part := Lang.t(" (esercito %d)") % army_id if army_id > 0 else ""
		if target_id == "":
			var cleared := Lang.t("%s %s%s non ha più un bersaglio") % [noun, actor, army_text_part]
			var problem := CampaignUiText.humanize_ids(state, CampaignUiText.text_of(e.get("motivo", "")))
			if problem != "":
				cleared += ": " + problem
			return cleared + "."
		var aim := Lang.t("%s %s%s ha come bersaglio %s") % [noun, actor, army_text_part, CampaignUiText.region_name(state, target_id)]
		var owner_id := SimUtil.norm(CampaignUiText.text_of(e.get("proprietario", "")))
		if owner_id != "":
			aim += " (%s)" % CampaignUiText.faction_name(owner_id)
		return aim + "."
	if kind == GameState.EV_CRUSADE_RECRUITED:
		var province := CampaignUiText.region_name(state, CampaignUiText.text_of(e.get("provincia", e.get("regione", ""))))
		if actor_id == "" or province == "":
			return fallback_text
		var recruited := Lang.t("%s %s recluta %s a %s") % [noun, actor, armies_text(CampaignUiText.int_of(e.get("pile"))), province]
		if e.has("zelo_provincia"):
			recruited += Lang.t(" (zelo della provincia %d)") % CampaignUiText.int_of(e.get("zelo_provincia"))
		return recruited + "."
	if kind == GameState.EV_CRUSADE_DESERTION:
		if actor_id == "":
			return fallback_text
		var lost := Lang.t("%s %s perde %s") % [noun, actor, armies_text(CampaignUiText.int_of(e.get("pile")))]
		var cause := CampaignUiText.text_of(e.get("motivo", ""))
		if cause == "diserzione":
			lost += Lang.t(" per diserzione")
		elif cause == "perdite":
			lost += Lang.t(" per le perdite")
		if e.has("zelo"):
			lost += Lang.t(" (zelo %d)") % CampaignUiText.int_of(e.get("zelo"))
		return lost + "."
	if kind == GameState.EV_CRUSADE_SUCCEEDED:
		var conquered := CampaignUiText.text_of(e.get("bersaglio", e.get("regione", "")))
		if actor_id == "" or conquered == "":
			return fallback_text
		var won := Lang.t("%s %s conquista %s.") % [noun, actor, CampaignUiText.region_name(state, conquered)]
		var gain := CampaignUiText.int_of(e.get("influenza"))
		if gain > 0:
			won += Lang.t(" L'influenza del suo capo sale di %d.") % gain
		var reward := CampaignUiText.int_of(e.get("pile_ordine"))
		if reward > 0:
			var unit_text := CampaignUiText.text_of(e.get("unita_ordine", ""))
			won += Lang.t(" Ricompensa: %s") % armies_text(reward)
			if unit_text != "":
				won += Lang.t(" di %s") % CampaignUiText.unit_name(unit_text)
			won += "."
		return won
	if kind == GameState.EV_CRUSADE_FAILED:
		if actor_id == "":
			return fallback_text
		var failed := Lang.t("%s %s fallisce") % [noun, actor]
		var reason := CampaignUiText.text_of(e.get("motivo", ""))
		if FAILURE_REASONS.has(reason):
			failed += ": %s" % Lang.t(str(FAILURE_REASONS[reason]))
		failed += "."
		var change := CampaignUiText.int_of(e.get("influenza"))
		if change < 0:
			failed += Lang.t(" L'influenza del suo capo scende di %d.") % -change
		return failed
	return ""


static func text_free(e: Dictionary) -> String:
	return CampaignUiText.text_of(e.get("testo", "")).strip_edges()
