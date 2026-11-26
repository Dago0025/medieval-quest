class_name CharacterFactory
extends RefCounted
## Creazione dei personaggi (fase 4a): capo iniziale, figli, generali generati ed eroi famosi.
## Tutte le funzioni che estraggono numeri casuali li prendono dal generatore passato, in un ordine
## fisso documentato per ognuna (l'ordine dei sorteggi fa parte delle regole). `GameSetup` usa un
## generatore proprio (derivato dal seme); il fine anno usa `state.rng`.
##
## Nomi: dalle liste di `HeroesData` della fazione (nomi di battesimo, nomi reali, cognomi,
## principesse). Senza dati dei nomi (mondi di prova) si usano le liste di riserva qui sotto;
## PROVVISORIA. Il nome riservato al capo (`nome_solo_capo` di auror.cfg: Darkos per gli Auror) non va a eredi e principi.

const FALLBACK_FORENAMES := ["Adamo", "Bruno", "Carlo", "Dario", "Enrico", "Fabio", "Guido", "Ugo"]
const FALLBACK_SURNAMES := ["Rossi", "Bianchi", "Verdi", "Neri", "Gialli", "Blu"]
const FALLBACK_PRINCESSES := ["Anna", "Berta", "Clara", "Dora", "Elena", "Flavia"]


# --- nomi --------------------------------------------------------------------------------------


## Nomi reali della fazione (quelli dei re e dei loro figli maschi): l'indice e' quello dei numerali.
static func royal_names(state: GameState, faction_id: String) -> PackedStringArray:
	if state.heroes != null:
		var names := state.heroes.royal_names_of(faction_id)
		if not names.is_empty():
			return names
	return PackedStringArray(FALLBACK_FORENAMES)


## Indice del nome reale di un figlio maschio: a caso tra i nomi reali, escluso quello riservato al capo (`nome_solo_capo`).
## Un solo sorteggio, come prima: l'ordine dei numeri casuali non cambia.
static func child_name_index(state: GameState, faction_id: String, names: PackedStringArray, rng: RandomNumberGenerator) -> int:
	var reserved := state.rules.dynasty.leader_name(faction_id)
	var allowed: Array[int] = []
	for i in names.size():
		if reserved == "" or names[i] != reserved:
			allowed.append(i)
	if allowed.is_empty():
		return rng.randi_range(0, names.size() - 1)
	return allowed[rng.randi_range(0, allowed.size() - 1)]


## Partite salvate prima del 16/11/2026: eredi e principi che portano il nome riservato al capo (gli eredi Darkos degli Auror)
## ricevono un altro nome reale, scelto dall'id del personaggio senza usare il generatore casuale. Restituisce quanti.
static func rename_reserved_heirs(state: GameState) -> int:
	var renamed := 0
	for c in state.characters:
		if not c.alive or not c.male or c.role == Character.ROLE_LEADER:
			continue
		var reserved := state.rules.dynasty.leader_name(c.faction)
		if reserved == "" or c.forename != reserved:
			continue
		var names := royal_names(state, c.faction)
		var allowed: Array[int] = []
		for i in names.size():
			if names[i] != reserved:
				allowed.append(i)
		if allowed.is_empty():
			continue
		var index := allowed[c.id % allowed.size()]
		c.forename = names[index]
		c.name_index = index
		renamed += 1
	return renamed


static func forenames_of(state: GameState, faction_id: String) -> PackedStringArray:
	if state.heroes != null:
		var names := state.heroes.forenames_of(faction_id)
		if not names.is_empty():
			return names
	return PackedStringArray(FALLBACK_FORENAMES)


static func surnames_of(state: GameState, faction_id: String) -> PackedStringArray:
	if state.heroes != null:
		var names := state.heroes.surnames_of(faction_id)
		if not names.is_empty():
			return names
	return PackedStringArray(FALLBACK_SURNAMES)


static func princess_names_of(state: GameState, faction_id: String) -> PackedStringArray:
	if state.heroes != null:
		var names := state.heroes.princess_names_of(faction_id)
		if not names.is_empty():
			return names
	return PackedStringArray(FALLBACK_PRINCESSES)


# --- servizi -------------------------------------------------------------------------------------


## Limita un attributo a 0..massimo.
static func clamp_attr(state: GameState, value: int) -> int:
	return clampi(value, 0, state.rules.dynasty.max_attribute)


## Soglia di vecchiaia: eta' di base + intero casuale 0..scarto, +bonus per sangue reale ed eroi.
## Un sorteggio.
static func roll_old_age(state: GameState, privileged: bool, rng: RandomNumberGenerator) -> int:
	var d := state.rules.dynasty
	var threshold := d.old_age + rng.randi_range(0, d.old_age_spread)
	if privileged:
		threshold += d.royal_old_age_bonus
	return threshold


## Aggiunge un vizio o una virtu' dal suo id del gioco (per esempio "tyrant2", "secret_lust1").
## Una catena gia' presente sale solo se il livello nuovo e' maggiore. Vero se qualcosa e' cambiato.
static func add_vnv(c: Character, vnv_id: String) -> bool:
	var parsed := VnvRules.parse_id(vnv_id)
	var chain: String = parsed["catena"]
	if chain == "":
		return false
	var level: int = parsed["livello"]
	if level <= int(c.vnv.get(chain, 0)):
		return false
	c.vnv[chain] = level
	return true


## Se nome e numerale del re coincidono con un re famoso della fazione, ne prende attributi e
## vizio o virtu' (manuale p16). Vero se ha trovato una corrispondenza.
static func apply_famous_king(state: GameState, c: Character) -> bool:
	if state.heroes == null or c.name_index < 0:
		return false
	for k in state.heroes.kings_of(c.faction):
		if k.name_index == c.name_index and k.number == c.numeral:
			c.command = clamp_attr(state, k.command)
			c.dread = clamp_attr(state, k.dread)
			c.piety = clamp_attr(state, k.piety)
			c.acumen = clamp_attr(state, k.acumen)
			add_vnv(c, k.vnv)
			return true
	return false


# --- personaggi ------------------------------------------------------------------------------------


## Generale generato (PROVVISORIA: attributi casuali bassi). Sorteggi, in ordine: nome, cognome,
## eta', comando, terrore, pieta', acume, lealta', soglia di vecchiaia.
## `origin`: fazione da cui prendere nome e cognome (e il ritratto, `Character.origin`), "" = la propria.
static func make_general(state: GameState, faction_id: String, region_id: String, at_year: int, rng: RandomNumberGenerator, origin: String = "") -> Character:
	var d := state.rules.dynasty
	origin = SimUtil.norm(origin)
	if origin == SimUtil.norm(faction_id):
		origin = ""
	var forenames := forenames_of(state, origin if origin != "" else faction_id)
	var surnames := surnames_of(state, origin if origin != "" else faction_id)
	var c := state.create_character(faction_id)
	c.origin = origin
	c.role = Character.ROLE_GENERAL
	c.forename = forenames[rng.randi_range(0, forenames.size() - 1)]
	c.surname = surnames[rng.randi_range(0, surnames.size() - 1)]
	c.birth_year = at_year - rng.randi_range(d.general_age_min, d.general_age_max)
	c.command = rng.randi_range(d.general_attr_min, d.general_attr_max)
	c.dread = rng.randi_range(d.general_attr_min, d.general_attr_max)
	c.piety = rng.randi_range(d.general_attr_min, d.general_attr_max)
	c.acumen = rng.randi_range(d.general_attr_min, d.general_attr_max)
	c.loyalty = rng.randi_range(d.general_loyalty_min, d.general_loyalty_max)
	c.old_age = roll_old_age(state, false, rng)
	c.region = region_id
	return c


## Fazione «d'origine» del generale che nasce nell'esercito (richiesta di Federico del 22/11/2026: gli Auror arruolano
## truppe di ogni fazione; una truppa giapponese che diventa generale deve essere un giapponese con nome e ritratto).
## Solo per le fazioni di `generali_dalle_unita` (Rules.generals_from_units_factions). L'unita' da cui nasce il generale
## e' la prima con la candidatura migliore della col. 9 del prod (PREFERRED, poi OK, poi le altre), come nell'originale.
## "" se il generale resta della propria fazione: unita' esclusive, unita' di tutte le fazioni o della fazione stessa.
## Tra piu' fazioni dell'unita' si sceglie stabilmente con l'id dell'esercito.
static func unit_origin(state: GameState, army: Army) -> String:
	if state == null or army == null or state.units == null or state.campaign == null:
		return ""
	var owner := SimUtil.norm(army.faction)
	if not state.rules.generals_from_units_factions.has(owner):
		return ""
	var best: UnitType = null
	var best_rank := 99
	for s in army.stacks:
		var u := state.units.get_unit(s.unit_id)
		if u == null:
			continue
		var rank: int = {"PREFERRED": 0, "OK": 1}.get(u.general_candidate.strip_edges().to_upper(), 2)
		if rank < best_rank:
			best = u
			best_rank = rank
	if best == null or best.elite or best.all_factions:
		return ""
	var candidates := PackedStringArray()
	if not best.factions.is_empty():
		if best.factions.has(owner):
			return ""
		for f in best.factions:
			var fid := SimUtil.norm(f)
			if fid != GameState.REBEL and state.campaign.faction(fid) != null:
				candidates.append(fid)
	elif not best.cultures.is_empty():
		var own := state.campaign.faction(owner)
		if own != null and best.cultures.has(GameCommands.culture_key(own.culture)):
			return ""
		for cf in state.campaign.factions:
			if cf.id != GameState.REBEL and cf.id != owner and best.cultures.has(GameCommands.culture_key(cf.culture)):
				candidates.append(cf.id)
	if candidates.is_empty():
		return ""
	return candidates[absi(army.id) % candidates.size()]


## Capo iniziale di una fazione da `SetStartLeader` (formato in testa a campaign_data.gd): sceglie il
## primo re famoso il cui numerale e' uguale al contatore del suo nome (poi il primo nome con contatore
## maggiore di zero, poi il nome 0 numerale I), imposta i contatori dei numerali della fazione e prende gli
## attributi dal re famoso o a caso (PROVVISORIA). Sorteggi, in ordine: eta', quattro attributi (solo se
## il re non e' famoso), soglia di vecchiaia.
static func make_start_leader(state: GameState, faction: CampaignData.Faction, region_id: String, at_year: int, rng: RandomNumberGenerator) -> Character:
	var d := state.rules.dynasty
	var names := royal_names(state, faction.id)
	var counters := faction.leader_counters()
	var c := state.create_character(faction.id)
	c.role = Character.ROLE_LEADER
	c.royal_blood = true
	var famous: HeroesData.FamousKing = null
	if state.heroes != null:
		for k in state.heroes.kings_of(faction.id):
			if k.name_index >= 0 and k.name_index < counters.size() and counters[k.name_index] == k.number:
				famous = k
				break
	var index := -1
	var numeral := 0
	if famous != null:
		index = famous.name_index
		numeral = famous.number
	else:
		for i in counters.size():
			if counters[i] > 0:
				index = i
				numeral = counters[i]
				break
		if index < 0:
			index = 0
			numeral = 1
	for i in counters.size():
		state.set_royal_counter(faction.id, i, counters[i])
	state.set_royal_counter(faction.id, index, maxi(state.royal_counter(faction.id, index), numeral))
	c.name_index = index
	c.numeral = numeral
	c.forename = names[mini(index, names.size() - 1)]
	if famous != null and state.heroes != null:
		var famous_name := state.heroes.king_forename(famous)
		if famous_name != "":
			c.forename = famous_name
	c.region = region_id
	c.birth_year = at_year - rng.randi_range(d.start_age_min, d.start_age_max)
	if famous != null:
		c.command = clamp_attr(state, famous.command)
		c.dread = clamp_attr(state, famous.dread)
		c.piety = clamp_attr(state, famous.piety)
		c.acumen = clamp_attr(state, famous.acumen)
		add_vnv(c, famous.vnv)
	else:
		c.command = rng.randi_range(d.start_attr_min, d.start_attr_max)
		c.dread = rng.randi_range(d.start_attr_min, d.start_attr_max)
		c.piety = rng.randi_range(d.start_attr_min, d.start_attr_max)
		c.acumen = rng.randi_range(d.start_attr_min, d.start_attr_max)
	c.loyalty = d.max_attribute
	c.influence = clampi(d.start_influence, 0, d.max_attribute)
	c.old_age = roll_old_age(state, true, rng)
	return c


## Capo nuovo di una fazione che riemerge (fase 4b): sangue reale, nome reale a caso con il numerale successivo
## del suo nome, eta' e attributi come il capo iniziale non famoso (PROVVISORIA), ma con l'influenza del
## successore (parte da zero), attributi di un re famoso se nome e numerale coincidono. Sorteggi, in ordine:
## nome, eta', quattro attributi, soglia di vecchiaia.
## `age_min`/`age_max` >= 0 sostituiscono le eta' del capo iniziale (il Papa eletto, ADR-072).
static func make_new_leader(state: GameState, faction_id: String, region_id: String, at_year: int, rng: RandomNumberGenerator, age_min: int = -1, age_max: int = -1) -> Character:
	var d := state.rules.dynasty
	var names := royal_names(state, faction_id)
	var c := state.create_character(faction_id)
	c.role = Character.ROLE_LEADER
	c.royal_blood = true
	c.male = true
	var index := rng.randi_range(0, names.size() - 1)
	c.name_index = index
	c.forename = names[index]
	c.numeral = state.next_numeral(faction_id, index)
	c.region = region_id
	var lo := d.start_age_min if age_min < 0 else age_min
	var hi := d.start_age_max if age_max < 0 else maxi(lo, age_max)
	c.birth_year = at_year - rng.randi_range(lo, hi)
	c.command = rng.randi_range(d.start_attr_min, d.start_attr_max)
	c.dread = rng.randi_range(d.start_attr_min, d.start_attr_max)
	c.piety = rng.randi_range(d.start_attr_min, d.start_attr_max)
	c.acumen = rng.randi_range(d.start_attr_min, d.start_attr_max)
	apply_famous_king(state, c)
	c.loyalty = d.max_attribute
	c.influence = clampi(d.successor_influence, 0, d.max_attribute)
	c.old_age = roll_old_age(state, true, rng)
	return c


## Figlio o figlia di `parent` nato (o gia' nato) nell'anno `birth_year`: sangue reale, nome reale a caso
## (maschio) o nome da principessa (femmina), attributi entro `scarto_attributi` da quelli del padre
## (PROVVISORIA). Ruolo: erede il maschio (il chiamante lo declassa a principe se serve), principessa
## la femmina. Sorteggi, in ordine: nome, comando, terrore, pieta', acume, soglia di vecchiaia.
static func make_child(state: GameState, parent: Character, male: bool, birth_year: int, region_id: String, rng: RandomNumberGenerator) -> Character:
	var d := state.rules.dynasty
	var c := state.create_character(parent.faction)
	c.royal_blood = true
	c.male = male
	c.birth_year = birth_year
	c.region = region_id
	if male:
		var names := royal_names(state, parent.faction)
		var index := child_name_index(state, parent.faction, names, rng)
		c.forename = names[index]
		c.name_index = index
		c.role = Character.ROLE_HEIR
	else:
		var princess_names := princess_names_of(state, parent.faction)
		c.forename = princess_names[rng.randi_range(0, princess_names.size() - 1)]
		c.role = Character.ROLE_PRINCESS
	var spread := d.inherit_spread
	c.command = clamp_attr(state, parent.command + rng.randi_range(-spread, spread))
	c.dread = clamp_attr(state, parent.dread + rng.randi_range(-spread, spread))
	c.piety = clamp_attr(state, parent.piety + rng.randi_range(-spread, spread))
	c.acumen = clamp_attr(state, parent.acumen + rng.randi_range(-spread, spread))
	c.loyalty = clamp_attr(state, d.child_loyalty)
	c.old_age = roll_old_age(state, true, rng)
	return c


## Eroe famoso (tipo GENERAL) che compare nella regione indicata, con i suoi attributi e il suo vizio o
## virtu'. Sorteggi, in ordine: eta', soglia di vecchiaia.
static func make_hero(state: GameState, hero: HeroesData.FamousHero, region_id: String, at_year: int, rng: RandomNumberGenerator) -> Character:
	var d := state.rules.dynasty
	var c := state.create_character(hero.faction)
	c.role = Character.ROLE_GENERAL
	c.is_hero = true
	c.forename = hero.forename
	c.surname = hero.surname
	c.command = clamp_attr(state, hero.command)
	c.dread = clamp_attr(state, hero.dread)
	c.piety = clamp_attr(state, hero.piety)
	c.acumen = clamp_attr(state, hero.acumen)
	c.loyalty = clamp_attr(state, hero.loyalty)
	add_vnv(c, hero.vnv)
	c.birth_year = at_year - rng.randi_range(d.hero_age_min, d.hero_age_max)
	c.old_age = roll_old_age(state, true, rng)
	c.region = region_id
	return c
