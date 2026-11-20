class_name PrisonerProcessor
extends RefCounted
## Prigionieri e ritirata parziale (ADR-073; manuale p32 «Dopo la battaglia; ritirata» e p56 «Prigionieri»; richiesta di
## Federico del 2026-11-15). Parametri in `rules.combat` ([prigionieri] di scontri.cfg), tutti PROVVISORI.
##
## Presa (`WarProcessor`, durante le battaglie e gli assedi):
## - chi perde una battaglia e si ritira lascia prigioniera la quota `quota_catturati` dei sopravvissuti di ogni pila
##   (`take_share`; una pila non sparisce mai per questo: resta almeno un uomo), poi si ritira con il comandante (il re si
##   salva se il suo esercito ha una via di ritirata);
## - chi non ha vie di ritirata, la guarnigione di un castello espugnato o che cede per fame sono catturati per intero
##   (`capture_army`), con il comandante;
## - il comandante di un esercito annientato in battaglia e' catturato (`capture_commander`).
## I prigionieri dello stesso anno, luogo, vincitore e perdente stanno in una sola voce di `GameState.prisoners`:
## {"id", "vincitore", "perdente", "regione", "anno", "pile" (UnitStack.to_dict), "personaggi" (id), "comandante" (id del
## comandante vincitore, 0 = nessuno), "stato" (STATE_PENDING o STATE_RANSOM), "prezzo"}. I personaggi catturati non
## comandano e non stanno in nessuna regione (`Character.counters[CAPTIVE_KEY]` = id della voce): il re resta re.
## I ribelli sconfitti non fanno prigionieri (nessuno pagherebbe): le loro truppe catturate spariscono come prima.
##
## Decisione del vincitore: liberarli (tornano nella provincia piu' vicina di chi ha perso), chiedere il riscatto (chi ha perso
## paga e li riavrebbe nella provincia piu' vicina, oppure rifiuta e sono giustiziati: manuale p32) o giustiziarli tutti
## (il comandante vincitore conta i prigionieri giustiziati: vizio «Butcher»). Il giocatore decide con `GameCommands`
## (finestra dopo il resoconto); l'IA decide nel fine anno (`process_year`): giustizia se il suo capo ha almeno
## `terrore_esecuzione_ia` di terrore, altrimenti chiede il riscatto; da perdente paga sempre per il re o un erede (anche
## indebitandosi, come il giocatore: manuale p32), per gli altri solo se ha i fiorini. Decisioni del giocatore lasciate in
## sospeso: al fine anno seguente il riscatto si chiede (vincitore) o si paga (perdente) da solo (`settle_overdue`).
## Nessun sorteggio.

const STATE_PENDING := "da_decidere"
const STATE_RANSOM := "riscatto_chiesto"
const CAPTIVE_KEY := "prigioniero"

const OUTCOME_TAKEN := "presi"
const OUTCOME_RELEASED := "liberati"
const OUTCOME_RANSOM_ASKED := "riscatto_chiesto"
const OUTCOME_RANSOMED := "riscattati"
const OUTCOME_REFUSED := "riscatto_rifiutato"
const OUTCOME_EXECUTED := "giustiziati"


# --- presa -----------------------------------------------------------------------------------------------------------


## Id del comandante del primo esercito vincitore della battaglia che ne ha uno (0 se nessuno).
static func captor_commander(state: GameState, result: BattleResult) -> int:
	var ids := result.attacker_army_ids if result.attacker_won else result.defender_army_ids
	for army_id in ids:
		var c := state.commander_of(army_id)
		if c != null:
			return c.id
	return 0


## Vero se i prigionieri di `loser` presi da `captor` vanno registrati: niente flotte (affondate), niente ribelli sconfitti.
static func _takes_prisoners(state: GameState, captor: String, loser: String) -> bool:
	if captor == "" or loser == "" or captor == loser or loser == GameState.REBEL:
		return false
	return state.faction(loser) != null


## Ritirata parziale: toglie a ogni pila dell'esercito perdente `capture_share` dei suoi uomini (arrotondati per difetto,
## lasciandone almeno uno) e li registra come prigionieri di `captor`. Restituisce gli uomini presi.
static func take_share(state: GameState, army: Army, region_id: String, captor: String, captor_commander_id: int) -> int:
	if army.is_fleet or not _takes_prisoners(state, captor, army.faction):
		return 0
	var share := state.rules.combat.capture_share
	if share <= 0.0:
		return 0
	var taken: Array = []
	var men := 0
	for st in army.stacks:
		var n := mini(floori(float(st.men) * share), st.men - 1)
		if n <= 0:
			continue
		var copy := UnitStack.from_dict(st.to_dict())
		copy.men = n
		st.men -= n
		taken.append(copy.to_dict())
		men += n
	if not taken.is_empty():
		_add(state, captor, army.faction, region_id, taken, [], captor_commander_id)
	return men


## Cattura per intero (nessuna via di ritirata, castello espugnato o affamato): pile e comandante passano ai prigionieri.
## L'esercito lo toglie il chiamante. Restituisce gli uomini presi (0 se non si registrano prigionieri).
static func capture_army(state: GameState, army: Army, region_id: String, captor: String, captor_commander_id: int) -> int:
	if army.is_fleet or not _takes_prisoners(state, captor, army.faction):
		return 0
	var taken: Array = []
	var men := 0
	for st in army.stacks:
		if st.men > 0:
			taken.append(st.to_dict())
			men += st.men
	var people: Array = []
	var c := state.commander_of(army.id)
	if c != null and c.alive:
		people.append(c.id)
	if not taken.is_empty() or not people.is_empty():
		_add(state, captor, army.faction, region_id, taken, people, captor_commander_id)
	return men


## Il comandante di un esercito annientato (nessun sopravvissuto) e' catturato. Vero se c'era.
static func capture_commander(state: GameState, army_id: int, faction_id: String, region_id: String, captor: String, captor_commander_id: int) -> bool:
	if not _takes_prisoners(state, captor, faction_id):
		return false
	var c := state.commander_of(army_id)
	if c == null or not c.alive:
		return false
	_add(state, captor, faction_id, region_id, [], [c.id], captor_commander_id)
	return true


static func _add(state: GameState, captor: String, loser: String, region_id: String, stacks: Array, people: Array, captor_commander_id: int) -> void:
	var entry := {}
	for e in state.prisoners:
		if str(e["vincitore"]) == captor and str(e["perdente"]) == loser and str(e["regione"]) == region_id and int(e["anno"]) == state.year and str(e["stato"]) == STATE_PENDING:
			entry = e
			break
	if entry.is_empty():
		entry = {"id": state.next_prisoner_id, "vincitore": captor, "perdente": loser, "regione": region_id, "anno": state.year,
			"pile": [], "personaggi": [], "comandante": captor_commander_id, "stato": STATE_PENDING, "prezzo": 0, "annunciata": false}
		state.next_prisoner_id += 1
		state.prisoners.append(entry)
	var list: Array = entry["pile"]
	list.append_array(stacks)
	var chars: Array = entry["personaggi"]
	for cid in people:
		var c := state.character(int(cid))
		if c == null or chars.has(c.id):
			continue
		chars.append(c.id)
		c.army = 0
		c.region = ""
		c.counters[CAPTIVE_KEY] = int(entry["id"])
		if c.title != "":
			DynastyProcessor.release_title(state, c, "prigioniero", false)
		DynastyProcessor.release_office(state, c, "prigioniero", false)
	if int(entry["comandante"]) == 0:
		entry["comandante"] = captor_commander_id


# --- lettura ---------------------------------------------------------------------------------------------------------


## La voce con quell'id ({} se non c'e').
static func entry_of(state: GameState, prisoner_id: int) -> Dictionary:
	for e in state.prisoners:
		if int(e["id"]) == prisoner_id:
			return e
	return {}


## Uomini prigionieri della voce.
static func men_of(entry: Dictionary) -> int:
	var men := 0
	for d in entry.get("pile", []):
		men += int((d as Dictionary).get("uomini", 0))
	return men


## Personaggi vivi della voce, nell'ordine della cattura.
static func characters_of(state: GameState, entry: Dictionary) -> Array[Character]:
	var out: Array[Character] = []
	for cid in entry.get("personaggi", []):
		var c := state.character(int(cid))
		if c != null and c.alive:
			out.append(c)
	return out


## Vero se il personaggio e' prigioniero.
static func is_captive(c: Character) -> bool:
	return c != null and c.alive and int(c.counters.get(CAPTIVE_KEY, 0)) > 0


## Riscatto della voce: per ogni pila costo dell'unita' / uomini dell'unita' x uomini x `quota_riscatto`, piu' il re,
## gli eredi e i principi, i generali (PROVVISORIO).
static func price(state: GameState, entry: Dictionary) -> int:
	var c := state.rules.combat
	var total := 0.0
	for item in entry.get("pile", []):
		var d: Dictionary = item
		var u: UnitType = state.units.get_unit(str(d.get("unita", ""))) if state.units != null else null
		if u == null or u.men <= 0:
			continue
		total += float(u.cost) / float(u.men) * float(int(d.get("uomini", 0))) * c.ransom_share
	for ch in characters_of(state, entry):
		total += float(_person_price(c, ch))
	return maxi(0, roundi(total))


static func _person_price(c: CombatRules, ch: Character) -> int:
	if ch.role == Character.ROLE_LEADER:
		return c.ransom_leader
	if ch.royal_blood and (ch.role == Character.ROLE_HEIR or ch.role == Character.ROLE_PRINCE):
		return c.ransom_royal
	return c.ransom_general


## Voci in cui il giocatore `faction_id` deve decidere: come vincitore (STATE_PENDING) o come perdente a cui e' chiesto
## il riscatto (STATE_RANSOM), in ordine di id.
static func decisions_for(state: GameState, faction_id: String) -> Array[Dictionary]:
	var key := SimUtil.norm(faction_id)
	var out: Array[Dictionary] = []
	for e in state.prisoners:
		var st := str(e["stato"])
		if (st == STATE_PENDING and str(e["vincitore"]) == key) or (st == STATE_RANSOM and str(e["perdente"]) == key):
			out.append(e)
	return out


static func _is_player(state: GameState, faction_id: String) -> bool:
	var f := state.faction(faction_id)
	return f != null and f.is_player


# --- passo annuale -----------------------------------------------------------------------------------------------------


## Dopo le guerre del fine anno: voci non piu' valide (perdente distrutto: i prigionieri restano al loro destino; vincitore
## distrutto: liberati), annuncio delle voci nuove, decisioni dell'IA vincitrice e risposte dell'IA perdente.
static func process_year(state: GameState) -> void:
	for e in state.prisoners.duplicate():
		if not state.prisoners.has(e):
			continue
		var loser := state.faction(str(e["perdente"]))
		if loser == null or not loser.alive:
			state.prisoners.erase(e)
			continue
		var captor := state.faction(str(e["vincitore"]))
		if str(e["vincitore"]) != GameState.REBEL and (captor == null or not captor.alive):
			_release(state, e, OUTCOME_RELEASED)
			continue
		if not bool(e.get("annunciata", false)):
			e["annunciata"] = true
			_emit(state, e, OUTCOME_TAKEN, Lang.t("%s cattura %s a %s.") % [SimUtil.faction_label(str(e["vincitore"])), _captives_text(state, e), WarProcessor.region_label(state, str(e["regione"]))])
		if str(e["stato"]) == STATE_PENDING and not _is_player(state, str(e["vincitore"])):
			if _ai_executes(state, e):
				_execute(state, e, OUTCOME_EXECUTED)
			else:
				ask_ransom(state, e)


## All'inizio del fine anno: le decisioni lasciate in sospeso dal giocatore si prendono da sole (il vincitore chiede il
## riscatto, il perdente lo paga: manuale p32, «spesso il tuo generale li restituira' dietro riscatto»).
static func settle_overdue(state: GameState) -> void:
	for e in state.prisoners.duplicate():
		if not state.prisoners.has(e) or int(e["anno"]) >= state.year:
			continue
		if str(e["stato"]) == STATE_PENDING and _is_player(state, str(e["vincitore"])):
			ask_ransom(state, e)
		elif str(e["stato"]) == STATE_RANSOM and _is_player(state, str(e["perdente"])):
			answer_ransom(state, e, true)


## L'IA vincitrice giustizia se il suo capo ha almeno `terrore_esecuzione_ia` di terrore (ribelli: mai).
static func _ai_executes(state: GameState, e: Dictionary) -> bool:
	var captor := str(e["vincitore"])
	if captor == GameState.REBEL:
		return false
	var leader := state.leader_of(captor)
	return leader != null and leader.effective(Character.ATTR_DREAD, state.rules, state.campaign) >= state.rules.combat.ai_execute_dread


## L'IA perdente paga sempre per il re o per un erede/principe, per gli altri solo se ha i fiorini.
static func ai_pays(state: GameState, e: Dictionary) -> bool:
	for ch in characters_of(state, e):
		if ch.role == Character.ROLE_LEADER or (ch.royal_blood and (ch.role == Character.ROLE_HEIR or ch.role == Character.ROLE_PRINCE)):
			return true
	var loser := state.faction(str(e["perdente"]))
	return loser != null and loser.treasury >= price(state, e)


# --- esiti ---------------------------------------------------------------------------------------------------------------


## Il vincitore chiede il riscatto: al giocatore resta la risposta (STATE_RANSOM), l'IA risponde subito.
static func ask_ransom(state: GameState, e: Dictionary) -> void:
	e["prezzo"] = price(state, e)
	if _is_player(state, str(e["perdente"])):
		e["stato"] = STATE_RANSOM
		_emit(state, e, OUTCOME_RANSOM_ASKED, Lang.t("%s chiede %d fiorini di riscatto per %s.") % [SimUtil.faction_label(str(e["vincitore"])), int(e["prezzo"]), _captives_text(state, e)])
		return
	answer_ransom(state, e, ai_pays(state, e))


## Risposta di chi ha perso: pagando (anche a debito) i prigionieri tornano nella sua provincia piu' vicina e il vincitore
## incassa; rifiutando sono giustiziati.
static func answer_ransom(state: GameState, e: Dictionary, pay: bool) -> void:
	if not pay:
		_execute(state, e, OUTCOME_REFUSED)
		return
	var amount := int(e.get("prezzo", 0))
	if amount <= 0:
		amount = price(state, e)
		e["prezzo"] = amount
	var loser := state.faction(str(e["perdente"]))
	var captor := state.faction(str(e["vincitore"]))
	if loser != null:
		loser.spend(amount, "riscatti")
	if captor != null and captor.id != GameState.REBEL:
		captor.refund(amount, "riscatti")   # entrata: la voce «riscatti» del vincitore va in negativo
	_release(state, e, OUTCOME_RANSOMED)


## Liberazione (scelta del vincitore, riscatto pagato o vincitore scomparso): le pile tornano come esercito nella provincia
## di chi ha perso piu' vicina al luogo della cattura, al comando del primo personaggio liberato (il re per primo).
static func _release(state: GameState, e: Dictionary, outcome: String) -> void:
	var people := characters_of(state, e)
	var men := men_of(e)
	var home := nearest_home(state, str(e["perdente"]), str(e["regione"]))
	var text := ""
	if home == "":
		for ch in people:
			ch.counters.erase(CAPTIVE_KEY)
		text = Lang.t("%s non ha piu' province dove far tornare %s.") % [SimUtil.faction_label(str(e["perdente"])), _captives_text(state, e)]
	else:
		var army: Army = null
		if men > 0:
			army = state.create_army(str(e["perdente"]), home, false)
			for item in e["pile"]:
				var st := UnitStack.from_dict(item)
				if st.men > 0:
					army.stacks.append(st)
		people.sort_custom(func(a: Character, b: Character) -> bool: return a.role == Character.ROLE_LEADER and b.role != Character.ROLE_LEADER)
		for ch in people:
			ch.counters.erase(CAPTIVE_KEY)
			ch.region = home
			if army != null and state.commander_of(army.id) == null and ch.can_command(state.rules.dynasty, state.year + 1):
				ch.army = army.id
		var verb := Lang.t("riscattati") if outcome == OUTCOME_RANSOMED else Lang.t("liberati")
		text = Lang.t("%s %s tornano a %s.") % [_captives_text(state, e, people), verb, WarProcessor.region_label(state, home)]
		if outcome == OUTCOME_RANSOMED:
			text = Lang.t("%s paga %d fiorini a %s: %s") % [SimUtil.faction_label(str(e["perdente"])), int(e["prezzo"]), SimUtil.faction_label(str(e["vincitore"])), text]
	state.prisoners.erase(e)
	var extra := {"provincia_ritorno": home}
	if home == "":
		extra["uomini"] = 0   # nessuno torna: gli uomini restano persi (bilancio degli uomini)
	_emit(state, e, outcome, text, extra)


## Esecuzione: gli uomini sono persi, i personaggi muoiono (il re immortale degli Auror torna libero); il comandante
## vincitore conta i prigionieri giustiziati (vizio «Butcher»).
static func _execute(state: GameState, e: Dictionary, outcome: String) -> void:
	var men := men_of(e)
	var label := _captives_text(state, e)
	var spared: Array[Character] = []
	for ch in characters_of(state, e):
		ch.counters.erase(CAPTIVE_KEY)
		if ch.role == Character.ROLE_LEADER and state.rules.dynasty.is_king_immortal(ch.faction):
			spared.append(ch)
			continue
		DynastyProcessor.kill(state, ch, state.year + 1, "giustiziato", true)
	var home := ""
	if not spared.is_empty():
		home = refuge_of(state, str(e["perdente"]), str(e["regione"]))
		for ch in spared:
			ch.region = home
	var butcher := state.character(int(e.get("comandante", 0)))
	if butcher != null and butcher.alive and men > 0:
		butcher.counters["prigionieri"] = int(butcher.counters.get("prigionieri", 0)) + men
		DynastyProcessor.check_vnv(state, butcher)
	state.prisoners.erase(e)
	var text := Lang.t("%s giustizia %s.") % [SimUtil.faction_label(str(e["vincitore"])), label]
	if outcome == OUTCOME_REFUSED:
		text = Lang.t("%s rifiuta il riscatto: %s sono giustiziati da %s.") % [SimUtil.faction_label(str(e["perdente"])), label, SimUtil.faction_label(str(e["vincitore"]))]
	for ch in spared:
		if home != "":
			text += " " + Lang.t("%s sfugge al boia e ricompare a %s.") % [ch.full_name(), WarProcessor.region_label(state, home)]
	_emit(state, e, outcome, text)


## Dove ricompare il re immortale giustiziato: il `rifugio_re` della fazione (ADR-075: Darkos in Norvegia, la regione natia dal 16/11) se la provincia e'
## ancora sua, altrimenti la sua provincia piu' vicina al luogo della cattura.
static func refuge_of(state: GameState, faction_id: String, region_id: String) -> String:
	var refuge := state.rules.dynasty.king_refuge(faction_id)
	var p := state.province(refuge) if refuge != "" else null
	if p != null and p.owner == faction_id:
		return refuge
	return nearest_home(state, faction_id, region_id)


## Provincia di `faction_id` piu' vicina a `region_id` per terra (visita in ampiezza sui confini, nell'ordine di
## SetNeighbours), preferendo quelle senza eserciti nemici; "" se la fazione non ha province raggiungibili. Senza strade,
## la prima provincia della fazione.
static func nearest_home(state: GameState, faction_id: String, region_id: String) -> String:
	var owned := state.provinces_of(faction_id)
	if owned.is_empty():
		return ""
	var fallback := ""
	var seen := {region_id: true}
	var frontier: Array[String] = [region_id]
	while not frontier.is_empty():
		var next: Array[String] = []
		for rid in frontier:
			var p := state.province(rid)
			if p != null and p.owner == faction_id:
				if not WarProcessor.hostile_present(state, rid, faction_id, false):
					return rid
				if fallback == "":
					fallback = rid
			var region := state.campaign.region(rid)
			if region == null:
				continue
			for n in region.neighbours:
				var nr := state.campaign.region(n)
				if nr == null or nr.is_sea or seen.has(nr.id):
					continue
				seen[nr.id] = true
				next.append(nr.id)
		frontier = next
	return fallback if fallback != "" else owned[0].id


# --- testi ed eventi ---------------------------------------------------------------------------------------------------


static func _captives_text(state: GameState, e: Dictionary, people: Array[Character] = []) -> String:
	if people.is_empty():
		people = characters_of(state, e)
	var parts: Array[String] = []
	for ch in people:
		parts.append(ch.full_name())
	var men := men_of(e)
	if men > 0:
		parts.append(Lang.t("%d uomini di %s") % [men, SimUtil.faction_label(str(e["perdente"]))])
	if parts.is_empty():
		return Lang.t("nessuno")
	return ", ".join(parts)


static func _emit(state: GameState, e: Dictionary, outcome: String, text: String, extra: Dictionary = {}) -> void:
	var names: Array = []
	for ch in characters_of(state, e):
		names.append(ch.full_name())
	var data := {
		"fazione": str(e["vincitore"]),
		"perdente": str(e["perdente"]),
		"regione": str(e["regione"]),
		"prigionieri": int(e["id"]),
		"esito": outcome,
		"uomini": men_of(e),
		"personaggi": names,
		"prezzo": int(e.get("prezzo", 0)),
		"testo": text,
	}
	data.merge(extra, true)
	state.add_event(GameState.EV_PRISONERS, data)


# --- salvataggi ----------------------------------------------------------------------------------------------------------


## Voce riletta da un salvataggio (i numeri del JSON tornano interi).
static func normalize(d: Dictionary) -> Dictionary:
	var stacks: Array = []
	for item in d.get("pile", []):
		if typeof(item) == TYPE_DICTIONARY:
			stacks.append(UnitStack.from_dict(item).to_dict())
	var people: Array = []
	for cid in d.get("personaggi", []):
		people.append(int(cid))
	return {"id": int(d.get("id", 0)), "vincitore": str(d.get("vincitore", "")), "perdente": str(d.get("perdente", "")),
		"regione": str(d.get("regione", "")), "anno": int(d.get("anno", 0)), "pile": stacks, "personaggi": people,
		"comandante": int(d.get("comandante", 0)), "stato": str(d.get("stato", STATE_PENDING)), "prezzo": int(d.get("prezzo", 0)),
		"annunciata": bool(d.get("annunciata", true))}
