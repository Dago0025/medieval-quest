class_name DynastyProcessor
extends RefCounted
## Regole annuali dei personaggi e delle dinastie (spec. fase 4 §4a). `TurnProcessor.end_year` chiama
## `process_year` dopo gli scontri e le fazioni distrutte, prima dell'economia, e `ensure_commanders`
## alla fine (dopo il reclutamento, che puo' creare eserciti nuovi).
##
## Anni: il fine anno dell'anno Y porta all'anno Y + 1; le eta' si contano all'anno nuovo (`new_year`),
## i nati hanno anno di nascita Y + 1, gli eventi portano l'anno Y (come tutti gli altri).
## Mondi senza personaggi (dati di prova senza `SetStartLeader`): non succede nulla e non si
## estrae nessun numero casuale.
##
## Ordine fisso di ogni anno (ogni passo scorre i personaggi in ordine di id e le fazioni in ordine di
## dichiarazione; tutti i sorteggi passano da `state.rng`):
##   1. fazioni distrutte: i loro personaggi escono dal gioco  2. titoli di province perse
##   3. conseguenze delle battaglie dell'anno (contatori, stelle, vizi e virtu')  4. influenza del capo per
##   le province perse e conquistate  5. anni di tassa alta del capo (catena Dread)  6. invecchiamento e
##   morte, ritiro delle principesse  7. maggiore eta'  8. successioni ed estinzioni  9. nascite
##   10. comparsa degli eroi famosi  11. comandanti degli eserciti senza capo.


# --- passo annuale -----------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	if state.characters.is_empty():
		return
	var new_year := state.year + 1
	_retire_dead_factions(state, new_year)
	_clean_titles(state)
	_clean_offices(state)
	_after_battles(state)
	_province_influence(state)
	_tax_counters(state)
	_aging(state, new_year)
	_coming_of_age(state, new_year)
	_successions(state, new_year)
	_births(state, new_year)
	_heroes(state, new_year)
	ensure_commanders(state, state.rng, new_year)


## Allinea la posizione dei personaggi a quella degli eserciti che comandano (da chiamare prima
## che gli eserciti si muovano o spariscano).
static func sync_positions(state: GameState) -> void:
	for c in state.characters:
		if c.alive and c.army > 0:
			var a := state.army(c.army)
			if a != null:
				c.region = a.region


# --- 1-2. fazioni distrutte e titoli ---------------------------------------------------------


static func _retire_dead_factions(state: GameState, new_year: int) -> void:
	for c in state.characters:
		if not c.alive:
			continue
		var f := state.faction(c.faction)
		if f == null or not f.alive:
			kill(state, c, new_year, "fazione_distrutta", false)


static func _clean_titles(state: GameState) -> void:
	for c in state.characters:
		if not c.alive or c.title == "":
			continue
		var p := state.province(c.title)
		if p == null or p.owner != c.faction:
			release_title(state, c, "perso", false)


# --- 3. battaglie ---------------------------------------------------------------------------------


## Per ogni EV_BATTLE dell'anno: i comandanti dei vincitori contano una vittoria, gli uomini uccisi
## (divisi tra i vincitori) e, il primo, i prigionieri; i comandanti dei perdenti contano una sconfitta
## e, se il loro esercito si e' ritirato, una ritirata. Poi un sorteggio per la stella di ogni
## comandante (vincitori, poi perdenti, nell'ordine dell'evento) e il controllo dei vizi e delle virtu'.
static func _after_battles(state: GameState) -> void:
	var battles: Array[Dictionary] = []
	for e in state.events:
		if str(e.get("tipo", "")) == GameState.EV_BATTLE:
			battles.append(e)
	for e in battles:
		var attacker_won := bool(e.get("vittoria_attaccante", false))
		var attackers: Array = e.get("eserciti_attaccanti", [])
		var defenders: Array = e.get("eserciti_difensori", [])
		var winners: Array = defenders
		var losers: Array = attackers
		var enemy_losses := int(e.get("perdite_attaccante", 0))
		if attacker_won:
			winners = attackers
			losers = defenders
			enemy_losses = int(e.get("perdite_difensore", 0))
		var retreated := {}
		var retreat_list: Array = e.get("ritirate", [])
		for item in retreat_list:
			var retreat: Dictionary = item
			retreated[int(retreat.get("esercito", 0))] = true
		var winner_commanders: Array[Character] = []
		for army_id in winners:
			var c := state.commander_of(int(army_id))
			if c != null and not winner_commanders.has(c):
				winner_commanders.append(c)
		var share := 0
		if not winner_commanders.is_empty():
			share = floori(float(enemy_losses) / float(winner_commanders.size()))
		var first := true
		for c in winner_commanders:
			_bump(c, "vittorie", 1)
			_bump(c, "uccisioni", share)
			first = false   # ADR-073: i prigionieri contano quando si giustiziano (PrisonerProcessor), non quando si prendono
			_roll_star(state, c, true, str(e.get("regione", "")))
			check_vnv(state, c)
		var seen: Array[Character] = []
		for army_id in losers:
			var c := state.commander_of(int(army_id))
			if c == null or seen.has(c):
				continue
			seen.append(c)
			_bump(c, "sconfitte", 1)
			if retreated.has(int(army_id)):
				_bump(c, "ritirate", 1)
			_roll_star(state, c, false, str(e.get("regione", "")))
			check_vnv(state, c)


static func _bump(c: Character, key: String, amount: int) -> void:
	c.counters[key] = int(c.counters.get(key, 0)) + amount


## Un sorteggio: dopo una vittoria (o una sconfitta) il comandante guadagna (o perde) una stella con la
## probabilita' dei parametri. Non vale per i comandi fissi (Auror).
static func _roll_star(state: GameState, c: Character, won: bool, region_id: String) -> void:
	var d := state.rules.dynasty
	if d.fixed_value(c.faction, Character.ATTR_COMMAND) >= 0:
		return
	var chance := d.star_win_chance if won else d.star_loss_chance
	if state.rng.randf() >= chance:
		return
	var before := c.stars(state.rules, state.campaign)
	if won:
		if c.command >= d.max_attribute:
			return
		c.command += 1
	else:
		if c.command <= 0:
			return
		c.command -= 1
	var after := c.stars(state.rules, state.campaign)
	var text := Lang.t("%s guadagna una stella di comando (%d).") % [c.full_name(), after]
	if not won:
		text = Lang.t("%s perde una stella di comando (%d).") % [c.full_name(), after]
	_emit(state, GameState.EV_STAR_CHANGED, c, text, {
		"stelle_prima": before,
		"stelle_dopo": after,
		"motivo": "vittoria" if won else "sconfitta",
		"regione": region_id if region_id != "" else state.character_region(c),
	})


## Assegna i vizi e le virtu' delle catene attive il cui contatore ha raggiunto la soglia di un livello
## piu' alto di quello posseduto (EV_VNV_GAINED).
static func check_vnv(state: GameState, c: Character) -> void:
	var rules := state.rules.vnv
	for chain in rules.order:
		if rules.leader_only(chain) and c.role != Character.ROLE_LEADER:
			continue
		var count := int(c.counters.get(rules.counter_of(chain), 0))
		var level := rules.level_for_count(chain, count)
		if level > int(c.vnv.get(chain, 0)):
			c.vnv[chain] = level
			var vnv_id := "%s%d" % [chain, level]
			_emit(state, GameState.EV_VNV_GAINED, c, Lang.t("%s ottiene un vizio o una virtu': %s (livello %d).") % [c.full_name(), rules.chain_name(chain), level], {
				"vnv": vnv_id,
				"catena": chain,
				"livello": level,
			})


# --- 4-5. influenza e tassa ------------------------------------------------------------------------


## Influenza del capo: -1 ogni `province_per_punto` province perse, +1 ogni altrettante conquistate
## (catalogo "Variazioni dell'influenza"), in base agli EV_PROVINCE_CAPTURED dell'anno.
static func _province_influence(state: GameState) -> void:
	var captures: Array[Dictionary] = []
	for e in state.events:
		if str(e.get("tipo", "")) == GameState.EV_PROVINCE_CAPTURED:
			captures.append(e)
	for e in captures:
		_influence_step(state, str(e.get("fazione", "")), "province_conquistate", 1)
		_influence_step(state, str(e.get("precedente", "")), "province_perse", -1)


static func _influence_step(state: GameState, faction_id: String, counter: String, sign: int) -> void:
	if faction_id == "" or faction_id == GameState.REBEL:
		return
	var leader := state.leader_of(faction_id)
	if leader == null:
		return
	var d := state.rules.dynasty
	_bump(leader, counter, 1)
	if int(leader.counters[counter]) >= d.influence_step:
		leader.counters[counter] = int(leader.counters[counter]) - d.influence_step
		leader.influence = clampi(leader.influence + sign, 0, d.max_attribute)


## Catena Dread: per ogni capo, un anno in cui piu' di `quota_province_tassa_alta` delle sue province ha
## tassa alta conta come un anno di tassa alta (PROVVISORIA).
static func _tax_counters(state: GameState) -> void:
	var d := state.rules.dynasty
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var leader := state.leader_of(f.id)
		if leader == null:
			continue
		var owned := state.provinces_of(f.id)
		if owned.is_empty():
			continue
		var high := 0
		for p in owned:
			if p.tax_level >= d.high_tax_level:
				high += 1
		if float(high) / float(owned.size()) > d.high_tax_share:
			_bump(leader, "anni_tassa_alta", 1)
			check_vnv(state, leader)


# --- 6. invecchiamento e morte -----------------------------------------------------------------------


## Eta' del personaggio all'anno `new_year`. Principesse: a `eta_ritiro_principessa` si ritirano (EV_DEATH
## con causa "ritiro", nessun sorteggio). Gli altri, oltre la soglia di vecchiaia, muoiono con
## probabilita' (eta' - soglia + k) / divisore (un sorteggio); il capo di una fazione con `re_immortale` no. Con la
## longevita' della fazione (`vecchiaia_minima`, Auror) la soglia e il ritiro delle principesse non scendono sotto quella.
static func _aging(state: GameState, new_year: int) -> void:
	var d := state.rules.dynasty
	for c in state.characters:
		if not c.alive:
			continue
		var age := new_year - c.birth_year
		var long_life := d.longevity_threshold(c.faction, c.id)   # Auror: almeno 100-150 anni (18/11/2026)
		if c.role == Character.ROLE_PRINCESS and age >= maxi(d.princess_retire_age, long_life):
			kill(state, c, new_year, "ritiro", true)
			continue
		if c.role == Character.ROLE_LEADER and d.is_king_immortal(c.faction):
			continue
		var threshold := maxi(c.old_age, long_life)
		if age <= threshold:
			continue
		if state.rng.randf() < d.death_chance(age, threshold):
			kill(state, c, new_year, "vecchiaia", true)


## Toglie dal gioco un personaggio: non e' piu' vivo, perde titolo e carica. Con `emit` registra EV_DEATH.
## Il suo esercito resta indicato (serve alla successione) ma senza comandante vivo.
## Vero se il personaggio e' il capo di una fazione con `re_invulnerabile` (Darkos degli Auror, ADR-075): non muore mai.
static func is_invulnerable(state: GameState, c: Character) -> bool:
	return c != null and c.role == Character.ROLE_LEADER and state.rules.dynasty.is_king_invulnerable(c.faction)


static func kill(state: GameState, c: Character, new_year: int, cause: String, emit: bool) -> void:
	if is_invulnerable(state, c) and cause != "fazione_distrutta":
		return   # ADR-075: ultima difesa, chi chiama dovrebbe gia' averlo risparmiato
	var region_id := state.character_region(c)
	var age := new_year - c.birth_year
	if c.title != "":
		release_title(state, c, "perso", false)
	c.office = ""
	c.alive = false
	c.death_year = new_year
	c.death_cause = cause
	c.region = region_id
	if not emit:
		return
	var who := Lang.t("%s (%s di %s)") % [c.full_name(), Lang.t(c.role), SimUtil.faction_label(c.faction)]
	var text := Lang.t("%s muore di vecchiaia a %d anni.") % [who, age]
	if cause == "ritiro":
		text = Lang.t("%s si ritira a vita contemplativa a %d anni.") % [who, age]
	elif cause == "giustiziato":
		text = Lang.t("%s e' giustiziato da prigioniero a %d anni.") % [who, age]
	_emit(state, GameState.EV_DEATH, c, text, {"eta": age, "causa": cause, "regione": region_id})


# --- 7. maggiore eta' ---------------------------------------------------------------------------------


## Maschi a `eta_principe` anni, femmine a `eta_principessa` (EV_COMING_OF_AGE). Un `erede` che non e'
## l'erede designato (il maschio piu' anziano) diventa `principe`, generale di sangue reale.
static func _coming_of_age(state: GameState, new_year: int) -> void:
	var d := state.rules.dynasty
	for c in state.characters:
		if not c.alive or c.role == Character.ROLE_LEADER or not c.royal_blood:
			continue
		var age := new_year - c.birth_year
		if c.male and (c.role == Character.ROLE_HEIR or c.role == Character.ROLE_PRINCE) and age == d.prince_age:
			if c.role == Character.ROLE_HEIR and state.heir_of(c.faction) != c:
				c.role = Character.ROLE_PRINCE
			_emit(state, GameState.EV_COMING_OF_AGE, c, Lang.t("%s (%s di %s) compie %d anni ed e' maggiorenne.") % [c.full_name(), Lang.t(c.role), SimUtil.faction_label(c.faction), age], {"eta": age})
		elif not c.male and c.role == Character.ROLE_PRINCESS and age == d.princess_age:
			_emit(state, GameState.EV_COMING_OF_AGE, c, Lang.t("%s (principessa di %s) compie %d anni ed e' in eta' da marito.") % [c.full_name(), SimUtil.faction_label(c.faction), age], {"eta": age})


# --- 8. successioni ed estinzioni ------------------------------------------------------------------


## Per ogni fazione viva che aveva un capo e non ce l'ha piu': sale al trono l'erede designato se e'
## maggiorenne; altrimenti il generale di sangue reale maschio e maggiorenne con piu' comando (poi il piu'
## anziano), con `contendenti` = altri candidati (rischio di guerra civile, blocco 4b); altrimenti la
## fazione si estingue (manuale p18). Nessun sorteggio.
static func _successions(state: GameState, new_year: int) -> void:
	var d := state.rules.dynasty
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		if state.leader_of(f.id) != null or not state.has_dynasty(f.id):
			continue
		var predecessor := _last_leader(state, f.id)
		if is_elective(state, f.id):
			_elect_pope(state, f, predecessor, new_year)
			continue
		var heir := state.heir_of(f.id)
		if heir != null and heir.age(new_year) >= d.prince_age:
			_crown(state, heir, true, 0, predecessor, new_year)
			continue
		var best: Character = null
		var candidates := 0
		for c in state.characters:
			if not c.alive or c.faction != f.id or not c.male or not c.royal_blood:
				continue
			if c.role != Character.ROLE_PRINCE and c.role != Character.ROLE_GENERAL:
				continue
			if c.age(new_year) < d.prince_age:
				continue
			candidates += 1
			if best == null or _better_claim(state, c, best):
				best = c
		if best == null:
			_extinguish(state, f, predecessor, new_year)
		else:
			_crown(state, best, false, candidates - 1, predecessor, new_year)


## Vero se la fazione elegge il suo capo invece di trasmetterlo per sangue (ADR-072): il Papato, con `[elezione] elettivo`.
## Una fazione elettiva non ha nascite, eredi ne' principesse e non si estingue alla morte del capo.
static func is_elective(state: GameState, faction_id: String) -> bool:
	return faction_id == GameState.PAPAL and state.rules.papacy.elective


## Morto il Papa, se ne elegge un altro (ADR-072, Federico dal gioco originale): capo nuovo di
## `CharacterFactory.make_new_leader` con l'eta' di `[elezione]`, nella regione della sede (la capitale se e' ancora
## del Papato, altrimenti la prima provincia sua, altrimenti dove stava il predecessore). Prende l'esercito del
## predecessore se e' libero. Sorteggi: quelli di `make_new_leader`.
static func _elect_pope(state: GameState, f: FactionState, predecessor: Character, new_year: int) -> void:
	var pr := state.rules.papacy
	var region_id := ""
	var cf := state.campaign.faction(f.id) if state.campaign != null else null
	if cf != null and cf.leader_region != "":
		var capital := state.province(cf.leader_region)
		if capital != null and capital.owner == f.id:
			region_id = capital.id
	if region_id == "":
		var owned := state.provinces_of(f.id)
		if not owned.is_empty():
			region_id = owned[0].id
		elif predecessor != null:
			region_id = predecessor.region
	var c := CharacterFactory.make_new_leader(state, f.id, region_id, new_year, state.rng, pr.pope_age_min, pr.pope_age_max)
	if predecessor != null and c.army == 0 and predecessor.army > 0 and state.army(predecessor.army) != null and state.commander_of(predecessor.army) == null:
		c.army = predecessor.army
		c.region = state.army(predecessor.army).region
	var name_before := predecessor.full_name() if predecessor != null else ""
	var text := Lang.t("%s e' eletto Papa") % c.full_name()
	if name_before != "":
		text += Lang.t(" dopo %s") % name_before
	text += "."
	_emit(state, GameState.EV_SUCCESSION, c, text, {
		"precedente": predecessor.id if predecessor != null else 0,
		"precedente_nome": name_before,
		"per_eredita": false,
		"contendenti": 0,
		"fratelli_declassati": 0,
		"elezione": true,
	})


## Vero se `a` ha un diritto migliore di `b`: piu' comando efficace, poi piu' anziano, poi id minore.
static func _better_claim(state: GameState, a: Character, b: Character) -> bool:
	var stars_a := a.stars(state.rules, state.campaign)
	var stars_b := b.stars(state.rules, state.campaign)
	if stars_a != stars_b:
		return stars_a > stars_b
	if a.birth_year != b.birth_year:
		return a.birth_year < b.birth_year
	return a.id < b.id


## Ultimo capo morto della fazione (null se non ce n'e'): l'ultimo con ruolo capo nell'elenco.
static func _last_leader(state: GameState, faction_id: String) -> Character:
	var found: Character = null
	for c in state.characters:
		if c.faction == faction_id and c.role == Character.ROLE_LEADER and not c.alive:
			if found == null or c.death_year >= found.death_year:
				found = c
	return found


## Incorona `c`: diventa capo, prende il numerale del suo nome reale (e gli attributi di un re famoso
## con lo stesso nome e numerale), l'influenza del successore e l'esercito del predecessore se e' libero.
## Se sale l'erede, i fratelli perdono lo stato di principi e diventano generali ordinari (manuale p17).
static func _crown(state: GameState, c: Character, by_heir: bool, contenders: int, predecessor: Character, new_year: int) -> void:
	var d := state.rules.dynasty
	c.role = Character.ROLE_LEADER
	if c.name_index >= 0:
		c.numeral = state.next_numeral(c.faction, c.name_index)
		CharacterFactory.apply_famous_king(state, c)
	c.influence = clampi(d.successor_influence, 0, d.max_attribute)
	if c.title != "":
		release_title(state, c, "perso", false)
	release_office(state, c, "perso", false)   # il capo non detiene cariche (come i titoli)
	if predecessor != null:
		c.region = predecessor.region
		if c.army == 0 and predecessor.army > 0 and state.army(predecessor.army) != null and state.commander_of(predecessor.army) == null:
			c.army = predecessor.army
	var demoted := 0
	if by_heir:
		for o in state.characters:
			if o.alive and o.faction == c.faction and o != c and (o.role == Character.ROLE_HEIR or o.role == Character.ROLE_PRINCE):
				o.role = Character.ROLE_GENERAL
				demoted += 1
	var name_before := ""
	var id_before := 0
	if predecessor != null:
		name_before = predecessor.full_name()
		id_before = predecessor.id
	var text := Lang.t("%s sale al trono di %s") % [c.full_name(), SimUtil.faction_label(c.faction)]
	if name_before != "":
		text += Lang.t(" dopo %s") % name_before
	if by_heir:
		text += Lang.t(" (erede).")
	else:
		text += Lang.t(" (nessun erede maggiorenne: %d altri contendenti).") % contenders
	_emit(state, GameState.EV_SUCCESSION, c, text, {
		"precedente": id_before,
		"precedente_nome": name_before,
		"per_eredita": by_heir,
		"contendenti": contenders,
		"fratelli_declassati": demoted,
	})


## Estinzione (manuale p18): le province diventano ribelli (code svuotate, tassa normale), gli eserciti e gli
## agenti sono sciolti, i personaggi escono dal gioco, la fazione non e' piu' viva.
static func _extinguish(state: GameState, f: FactionState, predecessor: Character, new_year: int) -> void:
	var lost := PackedStringArray()
	var capital := ""
	var cf := state.campaign.faction(f.id)
	if cf != null:
		capital = cf.leader_region
	for p in state.provinces_of(f.id):
		lost.append(p.id)
		p.owner = GameState.REBEL
		p.building_queue.clear()
		p.unit_queue.clear()
		p.tax_level = state.rules.default_tax
	var disbanded_men := 0
	for a in state.armies_of(f.id):
		disbanded_men += a.men_total()
		state.remove_army(a)
	var kept: Array[AgentState] = []
	for ag in state.agents:
		if ag.faction != f.id:
			kept.append(ag)
	state.agents = kept
	for c in state.characters:
		if c.alive and c.faction == f.id:
			kill(state, c, new_year, "estinzione", false)
	f.alive = false
	WarProcessor.refresh_sieges(state)
	var region_id := capital
	if predecessor != null and predecessor.region != "":
		region_id = predecessor.region
	state.add_event(GameState.EV_FACTION_EXTINCT, {
		"fazione": f.id,
		"regione": region_id,
		"province": Array(lost),
		"uomini": disbanded_men,
		"testo": Lang.t("%s si estingue senza eredi: %d province diventano ribelli.") % [SimUtil.faction_label(f.id), lost.size()],
	})


# --- 9. nascite ----------------------------------------------------------------------------------------


## Un capo tra `eta_capo_min` e `eta_capo_max` anni ha probabilita' `p_nascita` di un figlio, maschio con
## probabilita' `p_maschio` (PROVVISORIA). Sorteggi: nascita; se nasce, sesso, poi quelli di
## `CharacterFactory.make_child`. I maschi sono `erede` (il piu' anziano e' l'erede designato).
static func _births(state: GameState, new_year: int) -> void:
	var d := state.rules.dynasty
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		if is_elective(state, f.id):
			continue   # il Papa non ha figli (ADR-072)
		var leader := state.leader_of(f.id)
		if leader == null:
			continue
		var age := leader.age(new_year)
		if age < d.birth_age_min:
			continue
		if age > d.birth_age_max and not _leader_wedded_and_fertile(state, leader, new_year):
			continue
		if state.rng.randf() >= d.birth_chance:
			continue
		var male := state.rng.randf() < d.son_chance
		var child := CharacterFactory.make_child(state, leader, male, new_year, state.character_region(leader), state.rng)
		var label := Lang.t("un figlio maschio") if male else Lang.t("una figlia")
		_emit(state, GameState.EV_BIRTH, child, Lang.t("%s di %s ha %s: %s.") % [leader.full_name(), SimUtil.faction_label(f.id), label, child.full_name()], {
			"padre": leader.id,
			"maschio": male,
		})


## Contatori del capo per le nuove nozze: anno delle ultime nozze e anno delle prossime.
const COUNTER_WEDDING := "nozze_anno"
const COUNTER_NEXT_WEDDING := "nozze_prossime"


## Nuove nozze del capo immortale (richiesta di Federico del 20/11/2026: Darkos I non moriva ma, passata l'eta' delle
## nascite, restava senza eredi). Per una fazione con `remarriage` (auror.cfg), oltre `eta_capo_max` il capo si risposa
## con una nobildonna giovane ogni `min`..`max` anni (il primo anno fuori dall'eta' delle nascite, poi a intervalli
## stabili, senza sorteggio) e per `fertile` anni dopo le nozze puo' avere figli con la probabilita' normale (non
## nell'anno delle nozze). Vero se quest'anno il capo puo' avere un figlio. PROVVISORIA: l'originale non ha nozze del re.
static func _leader_wedded_and_fertile(state: GameState, leader: Character, new_year: int) -> bool:
	var d := state.rules.dynasty
	var plan := d.remarriage(leader.faction)
	if plan.is_empty():
		return false
	var last := int(leader.counters.get(COUNTER_WEDDING, 0))
	var next := int(leader.counters.get(COUNTER_NEXT_WEDDING, 0))
	if last <= 0 or new_year >= next:
		_wed_leader(state, leader, new_year)
		return false
	var since := new_year - last
	return since >= 1 and since <= int(plan["fertile"])


## Il capo prende in moglie una nobildonna (nome da principessa di una fazione viva sorteggiata, la sua se non ce ne sono
## altre): contatori aggiornati ed evento EV_MARRIAGE con "nozze_capo", "sposa" e "da" (fazione della sposa).
static func _wed_leader(state: GameState, leader: Character, new_year: int) -> void:
	var origins: Array[String] = []
	for g in state.factions:
		if g.alive and g.id != leader.faction and g.id != GameState.REBEL and not CharacterFactory.princess_names_of(state, g.id).is_empty():
			origins.append(g.id)
	var origin := leader.faction
	if not origins.is_empty():
		origin = origins[state.rng.randi_range(0, origins.size() - 1)]
	var names := CharacterFactory.princess_names_of(state, origin)
	var bride := Lang.t("una nobildonna")
	if not names.is_empty():
		bride = names[state.rng.randi_range(0, names.size() - 1)]
	leader.counters[COUNTER_WEDDING] = new_year
	leader.counters[COUNTER_NEXT_WEDDING] = new_year + state.rules.dynasty.remarriage_interval(leader.faction, leader.id, new_year)
	var text := Lang.t("%s di %s prende in moglie %s, nobildonna di %s.") % [leader.full_name(), SimUtil.faction_label(leader.faction), bride, SimUtil.faction_label(origin)]
	_emit(state, GameState.EV_MARRIAGE, leader, text, {
		"con": "",
		"nozze_capo": true,
		"sposa": bride,
		"da": origin,
		"nuova_alleanza": false,
	})


# --- 10. eroi famosi -----------------------------------------------------------------------------------


## Chiave che identifica un eroe famoso in `GameState.heroes_done`.
static func hero_key(hero: HeroesData.FamousHero) -> String:
	return "%s|%s|%s|%d" % [hero.faction, hero.forename, hero.surname, hero.year]


## Gli eroi famosi di tipo GENERAL il cui anno e' arrivato compaiono nella loro regione se e' della loro
## fazione, altrimenti nella capitale (la regione del capo; se non e' piu' sua, la prima provincia).
## Una fazione senza dinastia, morta o senza province li aspetta; i ribelli e gli altri tipi di eroe
## (emissari, vescovi...) non compaiono (fase 5 e 4b). Sorteggi: quelli di `CharacterFactory.make_hero`.
static func _heroes(state: GameState, new_year: int) -> void:
	if state.heroes == null:
		return
	for h in state.heroes.heroes:
		if h.type_name != "GENERAL" or h.faction == GameState.REBEL or h.year > new_year:
			continue
		var key := hero_key(h)
		if state.heroes_done.has(key):
			continue
		var f := state.faction(h.faction)
		if f == null or not f.alive or not state.has_dynasty(h.faction):
			continue
		var region_id := _hero_region(state, h)
		if region_id == "":
			continue
		state.heroes_done[key] = true
		var c := CharacterFactory.make_hero(state, h, region_id, new_year, state.rng)
		_emit(state, GameState.EV_HERO_APPEARS, c, Lang.t("%s, eroe di %s, compare a %s.") % [c.full_name(), SimUtil.faction_label(c.faction), WarProcessor.region_label(state, region_id)], {"regione": region_id})


static func _hero_region(state: GameState, hero: HeroesData.FamousHero) -> String:
	if not hero.is_anywhere():
		var own := state.province(hero.region)
		if own != null and own.owner == hero.faction:
			return own.id
	var cf := state.campaign.faction(hero.faction)
	if cf != null and cf.leader_region != "":
		var capital := state.province(cf.leader_region)
		if capital != null and capital.owner == hero.faction:
			return capital.id
	var owned := state.provinces_of(hero.faction)
	if not owned.is_empty():
		return owned[0].id
	return ""


# --- 11. comandanti ---------------------------------------------------------------------------------------


## Ogni esercito e ogni flotta di una fazione con dinastia ha un comandante vivo della sua fazione:
## i comandanti il cui esercito non esiste piu' tornano liberi; per gli eserciti senza comandante si sceglie il
## personaggio libero della fazione, maggiorenne (non principessa), nella stessa regione, con piu' comando
## efficace (a parita' l'id minore); se non c'e' si genera un generale (`CharacterFactory.make_general`).
## `at_year` e' l'anno per le eta' (l'anno nuovo nel fine anno).
static func ensure_commanders(state: GameState, rng: RandomNumberGenerator, at_year: int) -> void:
	if state.characters.is_empty():
		return
	var commanded := {}
	for c in state.characters:
		if not c.alive or c.army <= 0:
			continue
		var a := state.army(c.army)
		if a == null or a.faction != c.faction or commanded.has(c.army):
			c.army = 0
			continue
		c.region = a.region
		commanded[c.army] = true
	for a in state.armies:
		if a.faction == GameState.REBEL or commanded.has(a.id):
			continue
		if state.leader_of(a.faction) == null:
			continue
		var pick := _free_character(state, a.faction, a.region, at_year)
		if pick == null:
			pick = CharacterFactory.make_general(state, a.faction, a.region, at_year, rng)
		pick.army = a.id
		pick.region = a.region
		commanded[a.id] = true


static func _free_character(state: GameState, faction_id: String, region_id: String, at_year: int) -> Character:
	var best: Character = null
	var best_stars := -1
	for c in state.characters:
		if not c.alive or c.faction != faction_id or c.army != 0:
			continue
		if not c.can_command(state.rules.dynasty, at_year):
			continue
		if state.character_region(c) != region_id:
			continue
		var stars := c.stars(state.rules, state.campaign)
		if best == null or stars > best_stars:
			best = c
			best_stars = stars
	return best


# --- titoli ----------------------------------------------------------------------------------------------------


## Titoli iniziali (PROVVISORIA): il comandante di un esercito di terra (non il capo, maggiorenne) fermo in
## una provincia della sua fazione senza governatore ne riceve il titolo. Cariche iniziali (PROVVISORIA):
## per ogni `AddOffice` della fazione il cui edificio e' costruito in una sua provincia, la carica va al primo
## personaggio libero (maggiorenne, non capo, non principessa, senza carica) in ordine di id.
static func assign_initial_titles(state: GameState, at_year: int) -> void:
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL or not state.has_dynasty(f.id):
			continue
		for a in state.armies_of(f.id):
			if a.is_fleet:
				continue
			var c := state.commander_of(a.id)
			if c == null or c.role == Character.ROLE_LEADER or c.title != "":
				continue
			if not c.can_command(state.rules.dynasty, at_year):
				continue
			var p := state.province(a.region)
			if p == null or p.owner != f.id or state.governor_of(p.id) != null:
				continue
			c.title = p.id
		for o in state.campaign.offices_of(f.id):
			if not _building_exists(state, f.id, o.building):
				continue
			for c in state.characters:
				if c.alive and c.faction == f.id and c.office == "" and c.role != Character.ROLE_LEADER and c.can_command(state.rules.dynasty, at_year):
					c.office = o.building
					break


static func _building_exists(state: GameState, faction_id: String, building: String) -> bool:
	for p in state.provinces_of(faction_id):
		if p.level_of(building) > 0:
			return true
	return false


## Nome del titolo di una provincia: quello di `AddTitle` oppure "Governatore di <provincia>".
static func title_label(state: GameState, region_id: String) -> String:
	var def := state.campaign.title_for(region_id)
	if def != null and def.display_name != "":
		return def.display_name
	return Lang.t("Governatore di %s") % WarProcessor.region_label(state, region_id)


## Assegna a `c` il titolo della provincia (governatore). Chi la governava perde il titolo (con il calo
## di lealta' della revoca); se `c` governava un'altra provincia la lascia. Registra EV_TITLE_CHANGED.
static func assign_title(state: GameState, c: Character, province_id: String) -> void:
	var key := SimUtil.norm(province_id)
	var previous := state.governor_of(key)
	if previous != null and previous != c:
		release_title(state, previous, "revocato", true)
	if c.title != "" and c.title != key:
		release_title(state, c, "ceduto", false)
	c.title = key
	_emit(state, GameState.EV_TITLE_CHANGED, c, Lang.t("%s riceve il titolo di %s (%s).") % [c.full_name(), title_label(state, key), WarProcessor.region_label(state, key)], {
		"azione": "assegnato",
		"provincia": key,
		"titolo": title_label(state, key),
		"regione": key,
	})


## Toglie a `c` il titolo. `reason`: "revocato" (comando o sostituzione), "ceduto" (passa a un'altra
## provincia), "perso" (provincia perduta, morte, incoronazione). Con `drop_loyalty` la lealta' cala di
## `calo_lealta_revoca` (minimo 0).
static func release_title(state: GameState, c: Character, reason: String, drop_loyalty: bool) -> void:
	if c.title == "":
		return
	var province_id := c.title
	c.title = ""
	if drop_loyalty:
		c.loyalty = maxi(0, c.loyalty - state.rules.dynasty.revoke_loyalty_drop)
	var text := Lang.t("%s perde il titolo di %s (%s).") % [c.full_name(), title_label(state, province_id), WarProcessor.region_label(state, province_id)]
	if reason == "revocato":
		text = Lang.t("Il titolo di %s (%s) e' revocato a %s.") % [title_label(state, province_id), WarProcessor.region_label(state, province_id), c.full_name()]
	_emit(state, GameState.EV_TITLE_CHANGED, c, text, {
		"azione": reason,
		"provincia": province_id,
		"titolo": title_label(state, province_id),
		"regione": province_id,
	})


# --- cariche di Stato (AddOffice, manuale p25) ------------------------------------------------------------------


## Cariche di Stato disponibili per la fazione: le `AddOffice` il cui edificio e' costruito in una sua provincia
## (la cancelleria crea il Cancelliere, l'ammiragliato l'Ammiraglio...), nell'ordine del file.
static func available_offices(state: GameState, faction_id: String) -> Array[CampaignData.OfficeDef]:
	var out: Array[CampaignData.OfficeDef] = []
	for o in state.campaign.offices_of(faction_id):
		if office_seat(state, faction_id, o.building) != "":
			out.append(o)
	return out


## Provincia della fazione in cui compare la carica (come un titolo provinciale, manuale p25): quella con l'edificio al
## livello piu' alto, a parita' la prima nell'ordine delle province. "" = edificio non costruito.
static func office_seat(state: GameState, faction_id: String, building: String) -> String:
	var best := ""
	var best_level := 0
	for p in state.provinces_of(faction_id):
		var level := p.level_of(building)
		if level > best_level:
			best = p.id
			best_level = level
	return best


## Chi detiene la carica legata all'edificio (null = vacante).
static func office_holder(state: GameState, faction_id: String, building: String) -> Character:
	var key := SimUtil.norm(faction_id)
	var b := building.strip_edges().to_lower()
	for c in state.characters:
		if c.alive and c.faction == key and c.office == b:
			return c
	return null


## Nome della carica in italiano (data/cariche.cfg); senza nome nel file, il nome dell'edificio.
static func office_label(state: GameState, faction_id: String, building: String) -> String:
	var def := state.campaign.office_for(faction_id, building)
	if def != null and def.display_name != "":
		return RegionNames.translate_office(state.campaign, def.display_name)
	return building.replace("_", " ").capitalize()


## Assegna a `c` la carica legata all'edificio. Chi la deteneva la perde (con il calo di lealta' della revoca);
## se `c` aveva un'altra carica la lascia (una sola carica a testa). Registra EV_OFFICE_CHANGED.
static func assign_office(state: GameState, c: Character, building: String) -> void:
	var b := building.strip_edges().to_lower()
	var previous := office_holder(state, c.faction, b)
	if previous != null and previous != c:
		release_office(state, previous, "revocato", true)
	if c.office != "" and c.office != b:
		release_office(state, c, "ceduto", false)
	c.office = b
	var label := office_label(state, c.faction, b)
	_emit(state, GameState.EV_OFFICE_CHANGED, c, Lang.t("%s riceve la carica di %s.") % [c.full_name(), label], {
		"azione": "assegnato",
		"edificio": b,
		"carica": label,
	})


## Toglie a `c` la carica. `reason`: "revocato" (comando o sostituzione), "ceduto" (passa a un'altra carica), "perso"
## (edificio o provincia perduti, incoronazione). Con `drop_loyalty` la lealta' cala di `calo_lealta_revoca`.
static func release_office(state: GameState, c: Character, reason: String, drop_loyalty: bool) -> void:
	if c.office == "":
		return
	var b := c.office
	var label := office_label(state, c.faction, b)
	c.office = ""
	if drop_loyalty:
		c.loyalty = maxi(0, c.loyalty - state.rules.dynasty.revoke_loyalty_drop)
	var text := Lang.t("%s perde la carica di %s.") % [c.full_name(), label]
	if reason == "revocato":
		text = Lang.t("La carica di %s e' revocata a %s.") % [label, c.full_name()]
	elif reason == "ceduto":
		text = Lang.t("%s lascia la carica di %s.") % [c.full_name(), label]
	_emit(state, GameState.EV_OFFICE_CHANGED, c, text, {
		"azione": reason,
		"edificio": b,
		"carica": label,
	})


## Le cariche il cui edificio la fazione non ha piu' (provincia perduta, edificio distrutto) restano senza titolare.
static func _clean_offices(state: GameState) -> void:
	for c in state.characters:
		if not c.alive or c.office == "":
			continue
		if state.campaign.office_for(c.faction, c.office) == null or office_seat(state, c.faction, c.office) == "":
			release_office(state, c, "perso", false)


# --- eventi ---------------------------------------------------------------------------------------------------


## Registra un evento su un personaggio: fazione, regione (dove si trova, salvo `extra`), id, nome e ruolo.
static func _emit(state: GameState, event_type: String, c: Character, text: String, extra: Dictionary = {}) -> void:
	var data := {
		"fazione": c.faction,
		"regione": state.character_region(c),
		"personaggio": c.id,
		"nome": c.full_name(),
		"ruolo": c.role,
		"testo": text,
	}
	data.merge(extra, true)
	state.add_event(event_type, data)
