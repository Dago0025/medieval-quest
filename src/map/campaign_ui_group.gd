class_name CampaignUiGroup
extends RefCounted
## Selezione multipla degli eserciti (richiesta di Federico del 2026-11-10): con Alt si scelgono piu' pedine proprie, con
## il clic o con un riquadro, e le si manda insieme su un obiettivo trascinandone una o con il clic destro.
## Funzioni pure sullo stato: la scelta delle pedine non tocca la simulazione; gli ordini passano uno per uno dai comandi
## esistenti (GameCommands.order_move, cancel_move, order_merge), cosi' ogni esercito segue le regole di sempre: chi non
## puo' arrivare resta fermo e il motivo finisce nel messaggio. Truppe e navi non si scelgono insieme.

const MAX_NAMED_FAILURES := 3   ## eserciti che non partono nominati nel messaggio; gli altri diventano «e altri N»


## Aggiunge `army_id` al gruppo se non c'e', altrimenti lo toglie (Alt+clic).
static func toggle(group: Array[int], army_id: int) -> Array[int]:
	var out := group.duplicate()
	if out.has(army_id):
		out.erase(army_id)
	else:
		out.append(army_id)
	return out


## Aggiunge gli id che mancano, nell'ordine dato.
static func add_all(group: Array[int], ids: Array[int]) -> Array[int]:
	var out := group.duplicate()
	for id in ids:
		if not out.has(id):
			out.append(id)
	return out


## Il gruppo senza gli eserciti spariti, vuoti o di altre fazioni.
static func prune(state: GameState, player_id: String, group: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in group:
		var a := state.army(id)
		if a != null and a.faction == player_id and not a.stacks.is_empty() and not out.has(id):
			out.append(id)
	return out


## Motivo per cui `army` non entra nel gruppo, "" se puo': truppe e navi non si scelgono insieme.
static func join_problem(state: GameState, group: Array[int], army: Army) -> String:
	for id in group:
		var other := state.army(id)
		if other != null and other.is_fleet != army.is_fleet:
			return Lang.t("Truppe e navi non si scelgono insieme.")
	return ""


## Pedine prese con il riquadro (`boxed`, id in ordine) aggiunte al gruppo: solo proprie; con un gruppo gia' iniziato
## quelle del suo genere, altrimenti le truppe se ce ne sono, se no le flotte.
static func from_box(state: GameState, player_id: String, group: Array[int], boxed: Array[int]) -> Array[int]:
	var mine := prune(state, player_id, boxed)
	var want_fleet := false
	var current := prune(state, player_id, group)
	if not current.is_empty():
		want_fleet = state.army(current[0]).is_fleet
	else:
		want_fleet = true
		for id in mine:
			if not state.army(id).is_fleet:
				want_fleet = false
	var picked: Array[int] = []
	for id in mine:
		if state.army(id).is_fleet == want_fleet:
			picked.append(id)
	return add_all(current, picked)


## Ordina a tutti gli eserciti di `ids` di andare in `region_id` (movimento o attacco). Chi e' gia' li' resta (il suo
## movimento si annulla, come col clic destro sulla propria regione); le flotte verso una zona lontana seguono la rotta
## piu' breve. Esito: {"partiti": [id], "restano": [id], "falliti": [{"id", "errore"}], "attacco": bool,
## "rimborso": fiorini dei riaddestramenti annullati, "pile_riaddestramento": pile}.
static func order_move_all(state: GameState, player_id: String, ids: Array[int], region_id: String) -> Dictionary:
	var out := {"partiti": [], "restano": [], "falliti": [], "attacco": false, "rimborso": 0, "pile_riaddestramento": 0}
	for id in ids:
		var army := state.army(id)
		if army == null:
			continue
		if army.region == region_id:
			GameCommands.cancel_move(state, player_id, id)
			(out["restano"] as Array).append(id)
			continue
		var path := PackedStringArray([region_id])
		var here := state.campaign.region(army.region)
		if army.is_fleet and here != null and not here.neighbours.has(region_id):
			var route := GameCommands.fleet_path(state, id, region_id)
			if not route.is_empty():
				path = route
		var attack := CampaignUiText.attack_target(state, army, region_id)
		var r := GameCommands.order_move(state, player_id, id, path)
		if bool(r["ok"]):
			(out["partiti"] as Array).append(id)
			out["attacco"] = bool(out["attacco"]) or attack
			out["rimborso"] = int(out["rimborso"]) + int(r.get("rimborso_riaddestramento", 0))
			out["pile_riaddestramento"] = int(out["pile_riaddestramento"]) + int(r.get("pile_riaddestramento", 0))
		else:
			(out["falliti"] as Array).append({"id": id, "errore": str(r["errore"])})
	return out


## Unisce tutti gli eserciti di `ids` (tranne il bersaglio) a `target_id`: subito nella stessa regione, all'arrivo da
## quella accanto. Esito: {"subito": [id], "in_arrivo": [id], "falliti": [{"id", "errore"}]}.
static func merge_all(state: GameState, player_id: String, ids: Array[int], target_id: int) -> Dictionary:
	var out := {"subito": [], "in_arrivo": [], "falliti": []}
	for id in ids:
		if id == target_id or state.army(id) == null:
			continue
		var r := GameCommands.order_merge(state, player_id, id, target_id)
		if not bool(r["ok"]):
			(out["falliti"] as Array).append({"id": id, "errore": str(r["errore"])})
		elif bool(r.get("subito", false)):
			(out["subito"] as Array).append(id)
		else:
			(out["in_arrivo"] as Array).append(id)
	return out


## Messaggio dell'ordine di movimento di gruppo: quanti partono e verso dove, chi resta, chi non parte e perche'.
static func result_text(state: GameState, result: Dictionary, region_id: String) -> String:
	var gone: Array = result.get("partiti", [])
	var stay: Array = result.get("restano", [])
	var name_text := CampaignUiText.region_name(state, region_id)
	var parts := PackedStringArray()
	if not gone.is_empty():
		var who := _count_text(state, gone)
		if bool(result.get("attacco", false)):
			parts.append(Lang.t("%s: attacco a %s (la guerra si dichiara a fine anno).") % [who, name_text])
		else:
			parts.append(Lang.t("%s: movimento verso %s.") % [who, name_text])
	if not stay.is_empty():
		parts.append(Lang.t("%s già a %s: %s.") % [_count_text(state, stay), name_text, Lang.t("resta") if stay.size() == 1 else Lang.t("restano")])
	var failures := _failure_text(state, result.get("falliti", []), Lang.t("Non parte") if (result.get("falliti", []) as Array).size() == 1 else Lang.t("Non partono"))
	if failures != "":
		parts.append(failures)
	if int(result.get("pile_riaddestramento", 0)) > 0:
		parts.append(CampaignUiRetrain.refund_note({"pile_riaddestramento": result["pile_riaddestramento"], "rimborso_riaddestramento": result["rimborso"]}))
	if parts.is_empty():
		return Lang.t("Nessun esercito scelto.")
	return " ".join(parts)


## Messaggio dell'unione di gruppo su `target`.
static func merge_text(state: GameState, result: Dictionary, target: Army) -> String:
	var now: Array = result.get("subito", [])
	var later: Array = result.get("in_arrivo", [])
	var title := CampaignUiText.army_title(target)
	var parts := PackedStringArray()
	if not now.is_empty():
		parts.append(Lang.t("%s %s a %s.") % [_count_text(state, now), Lang.t("si unisce") if now.size() == 1 else Lang.t("si uniscono"), title])
	if not later.is_empty():
		parts.append(Lang.t("%s %s %s e vi si %s all'arrivo, se c'è posto.") % [_count_text(state, later), Lang.t("raggiunge") if later.size() == 1 else Lang.t("raggiungono"), title, Lang.t("unirà") if later.size() == 1 else Lang.t("uniranno")])
	var failures := _failure_text(state, result.get("falliti", []), Lang.t("Non si unisce") if (result.get("falliti", []) as Array).size() == 1 else Lang.t("Non si uniscono"))
	if failures != "":
		parts.append(failures)
	if parts.is_empty():
		return Lang.t("Nessun esercito da unire.")
	return " ".join(parts)


## «2 eserciti», «3 flotte», o il nome se e' uno solo.
static func _count_text(state: GameState, ids: Array) -> String:
	if ids.size() == 1:
		var a := state.army(int(ids[0]))
		return CampaignUiText.army_title(a) if a != null else Lang.t("1 esercito")
	var fleets := 0
	for id in ids:
		var a := state.army(int(id))
		if a != null and a.is_fleet:
			fleets += 1
	if fleets == ids.size():
		return Lang.t("%d flotte") % ids.size()
	return Lang.t("%d eserciti") % ids.size()


static func _failure_text(state: GameState, failures: Array, lead: String) -> String:
	if failures.is_empty():
		return ""
	var items := PackedStringArray()
	for i in mini(failures.size(), MAX_NAMED_FAILURES):
		var f: Dictionary = failures[i]
		var a := state.army(int(f["id"]))
		var title := CampaignUiText.army_title(a) if a != null else Lang.t("Esercito %d") % int(f["id"])
		items.append("%s (%s)" % [title, CampaignUiText.order_error_text(state, str(f["errore"])).trim_suffix(".")])
	var extra := failures.size() - MAX_NAMED_FAILURES
	var tail := Lang.t(" e altri %d") % extra if extra > 0 else ""
	return "%s: %s%s." % [lead, "; ".join(items), tail]
