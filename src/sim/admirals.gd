class_name Admirals
extends RefCounted
## Ammiragli al comando delle flotte (richiesta di Federico del 2026-11-13, ADR-056). Dall'originale (Loc/Italian/ToolTip.txt,
## Events.txt, names.txt): ogni flotta «la comanda un ammiraglio»; «gli ammiragli salgono di rango vincendo le battaglie» e
## «aumentano la capacita' di combattimento della flotta: piu' alto e' il rango, maggiore l'incremento»; la scheda mostra le
## battaglie navali vinte e perse e il nome si legge «Ammiraglio X con N navi».
##
## Nel remake l'ammiraglio e' un dato della flotta (`Army.admiral`, salvato come «ammiraglio»), non un personaggio della
## dinastia: {"nome", "stelle", "vinte", "perse"}. Nasce con la flotta (`GameState.create_army`) a `stelle_iniziali`; ogni
## `vittorie_per_stella` battaglie navali vinte guadagna una stella, fino a `stelle_max` (regola deterministica, PROVVISORIA:
## l'originale non dice quante vittorie servono). Le stelle valgono come quelle di comando di un generale (`Combat.command_stars`,
## stesso peso `star_weight` di scontri.cfg). Unendo due flotte resta l'ammiraglio migliore. Gli ammiragli delle fazioni con
## `ammiragli_al_massimo` (auror.cfg: gli Auror) hanno sempre `stelle_max`. Parametri in scontri.cfg [ammiragli].


## Ammiraglio nuovo per la flotta `army`: nome dalla lista della fazione (scelto con l'id, nessun sorteggio), stelle iniziali
## o il massimo per le fazioni con `ammiragli_al_massimo`.
static func new_admiral(state: GameState, army: Army) -> Dictionary:
	var stars := 0
	if state.rules != null:
		stars = maxi(state.rules.combat.admiral_start_stars, floor_of(state, army.faction))
	return {"nome": admiral_name(state, army), "stelle": stars, "vinte": 0, "perse": 0}


## Nome dell'ammiraglio: un nome e un cognome delle liste della fazione, scelti con l'id della flotta.
static func admiral_name(state: GameState, army: Army) -> String:
	var forenames := CharacterFactory.forenames_of(state, army.faction)
	var surnames := CharacterFactory.surnames_of(state, army.faction)
	var name := forenames[posmod(army.id * 7 + 3, forenames.size())] if not forenames.is_empty() else Lang.t("Senza nome")
	if not surnames.is_empty():
		name += " " + surnames[posmod(army.id * 11 + 5, surnames.size())]
	return name


## Stelle minime della fazione: `stelle_max` per le fazioni di `ammiragli_al_massimo`, altrimenti 0.
static func floor_of(state: GameState, faction_id: String) -> int:
	if state.rules == null:
		return 0
	return state.rules.combat.admiral_max_stars if state.rules.max_admiral_factions.has(SimUtil.norm(faction_id)) else 0


## Stelle dell'ammiraglio della flotta, entro il massimo e mai sotto il minimo della fazione; -1 se la flotta non ne ha.
static func stars(state: GameState, army: Army) -> int:
	if army == null or not army.is_fleet or army.admiral.is_empty():
		return -1
	var top := state.rules.combat.admiral_max_stars if state.rules != null else 10
	return clampi(maxi(int(army.admiral.get("stelle", 0)), floor_of(state, army.faction)), 0, top)


## Ogni flotta senza ammiraglio ne riceve uno, e gli Auror tornano al massimo (partita nuova, salvataggi di prima, fine anno).
static func ensure(state: GameState) -> void:
	if state.rules != null and not state.rules.combat.admirals_on:
		return
	for a in state.armies:
		if not a.is_fleet:
			continue
		if a.admiral.is_empty():
			a.admiral = new_admiral(state, a)
		else:
			var minimum := floor_of(state, a.faction)
			if int(a.admiral.get("stelle", 0)) < minimum:
				a.admiral["stelle"] = minimum


## Dopo uno scontro navale: le flotte vincitrici contano una vittoria e ogni `vittorie_per_stella` vittorie salgono di una
## stella; le perdenti contano una sconfitta. Restituisce gli ammiragli promossi: [{"esercito", "nome", "stelle"}].
static func after_battle(state: GameState, winners: Array[Army], losers: Array[Army]) -> Array[Dictionary]:
	var promoted: Array[Dictionary] = []
	var c := state.rules.combat
	for a in winners:
		if not a.is_fleet or a.admiral.is_empty():
			continue
		var won := int(a.admiral.get("vinte", 0)) + 1
		a.admiral["vinte"] = won
		var before := int(a.admiral.get("stelle", 0))
		if c.admiral_wins_per_star > 0 and won % c.admiral_wins_per_star == 0 and before < c.admiral_max_stars:
			a.admiral["stelle"] = before + 1
			promoted.append({"esercito": a.id, "nome": str(a.admiral.get("nome", "")), "stelle": before + 1})
	for a in losers:
		if a.is_fleet and not a.admiral.is_empty() and state.armies.has(a):
			a.admiral["perse"] = int(a.admiral.get("perse", 0)) + 1
	return promoted


## Nave dell'ammiraglio (richiesta di Federico del 2026-11-14, ADR-062): la nave piu' forte della flotta (attacco navale,
## prod col. 32, lo stesso di Combat.stack_strength), a parita' la piu' costosa, poi la prima; -1 se la flotta non ha
## ammiraglio. Non solo il costo: la caracca degli Auror costa 300 ma e' la nave migliore. Si ricava ogni volta (nessun dato salvato): se quella nave affonda o viene
## separata, l'ammiraglio passa alla migliore che resta, come il comandante tra le pile di un esercito.
static func flagship(state: GameState, army: Army) -> int:
	if stars(state, army) < 0 or army.stacks.is_empty():
		return -1
	var best := 0
	var best_score := Vector2i(-1, -1)
	for i in army.stacks.size():
		var unit := state.units.get_unit(army.stacks[i].unit_id) if state.units != null else null
		var score := Vector2i(unit.ship_attack, unit.cost) if unit != null else Vector2i.ZERO
		if score > best_score:
			best = i
			best_score = score
	return best


## Unione di due flotte: `target` tiene l'ammiraglio migliore (piu' stelle, a parita' piu' vittorie) tra il suo e quello di
## `source`.
static func merge_into(source: Army, target: Army) -> void:
	if not source.is_fleet or not target.is_fleet or source.admiral.is_empty():
		return
	if target.admiral.is_empty() or _better(source.admiral, target.admiral):
		target.admiral = source.admiral.duplicate()


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("stelle", 0)) != int(b.get("stelle", 0)):
		return int(a.get("stelle", 0)) > int(b.get("stelle", 0))
	return int(a.get("vinte", 0)) > int(b.get("vinte", 0))
