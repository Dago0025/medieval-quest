class_name TurnProcessor
extends RefCounted
## Fine anno (ADR-008, spec. fase 3 §3): ordine fisso e deterministico. Fazioni e province sono
## visitate nell'ordine di dichiarazione, gli eserciti nell'ordine di id.
##   1. movimento (gli attacchi dichiarano guerra; i trasporti via mare si ricontrollano)  2. battaglie in campo e scontri navali, con le
##   ritirate dei perdenti  3. assedi  4. conquiste  5. fazioni distrutte  6. reddito e mantenimento
##   7. costruzioni  8. reclutamento  9. calendario
## Con i personaggi (fase 4a) si aggiungono: all'inizio la posizione dei personaggi si allinea a quella degli
## eserciti; dopo le fazioni distrutte le regole annuali di `DynastyProcessor` (morte, nascite, successioni,
## stelle, vizi e virtu'); dopo il reclutamento ogni esercito nuovo riceve un comandante.
## Con le province (fase 4b), dopo le regole della dinastia e prima del reddito: `ProvinceProcessor.process_year` (lealta' delle
## province, rivolte e propagazione, lealta' dei generali, guerre civili, riemersione delle fazioni estinte); un esercito
## ribelle nato da una rivolta segue le regole di guerra del turno dopo, e la provincia contesa non produce reddito.
## Con gli agenti e la diplomazia (fase 5a, spec. fase 5 §«Ordine del fine anno»): dopo il movimento degli eserciti
## il passo 1b `AgentProcessor.process_year` (movimento degli agenti, missioni, cattura degli agenti nemici, porte aperte
## dalle spie), prima delle battaglie; dopo le province `AgentProcessor.sync_year` (pulizia, principesse); nel
## reclutamento nascono gli agenti; per ultima, dopo i comandanti, la scadenza delle tregue.
## Con la religione (fase 5b), dopo le province e prima della pulizia degli agenti e del reddito:
## `ReligionProcessor.process_year` (deriva verso la religione del proprietario, conversione da edifici e religiosi,
## eresia, inquisitori, zelo); il processo dell'inquisitore e' una missione, risolta nel passo 1b.
## Ordine completo: 1 movimento  1b agenti (missioni, anche il processo)  2 battaglie  3 assedi  4 conquiste  5 fazioni
## distrutte  dinastia  province (4b)  religione (5b)  Papato (5c)  eventi (6a)  pulizia agenti e trattati  reddito
## (poi si azzerano gli effetti di un anno)  costruzioni  reclutamento  comandanti  scadenza delle tregue  calendario.
## Con gli eventi (fase 6a, spec. fase 6 §«Ordine del fine anno»): dopo il Papato e prima della pulizia di agenti e trattati
## e del reddito `EventProcessor.process_year` (eventi storici, disastri, Peste Nera, Orda d'Oro); gli effetti di durata un
## anno che lascia nelle province (`ProvinceState.temp_effects`) li legge il reddito e `EventProcessor.clear_temporary` li
## azzera subito dopo.
## Con la vittoria (fase 6b), dopo il calendario: `VictoryProcessor.check` (sconfitta del giocatore, dominio, fine della campagna
## nell'anno finale); i suoi eventi portano l'anno raggiunto. A partita finita (`GameState.is_game_over`, anche dopo la sconfitta
## o in attesa della scelta dopo la vittoria per dominio) il fine anno risponde "ok" falso e non cambia nulla.
## Con il Papato e le crociate (fase 5c): all'inizio `PapacyProcessor.snapshot` (gli eserciti crociati dell'anno);
## nel movimento ogni attacco passa da `PapacyProcessor.on_attack` (avvertimento papale per la dichiarazione di guerra
## della piu' grande tra due cattoliche, scomunica per l'attacco durante l'avvertimento o al Papato; gli eserciti
## crociati ne sono esenti, attraversano i territori altrui senza guerra e attaccano solo il proprietario del bersaglio);
## dopo la religione `PapacyProcessor.process_year` (revoca delle scomuniche, tregue papali, riemersione del Papato,
## zelo e esito delle crociate e dei jihad, doni papali); nel reclutamento `Crusade` e `Jihad` fanno nascere
## l'esercito crociato.
## Con il riaddestramento (`RetrainProcessor`): all'inizio del reclutamento gli ordini dati durante l'anno si applicano (la pila
## torna all'organico pieno, EV_RETRAINED) o si rimborsano (EV_RETRAIN_CANCELLED); poi nascono le reclute.
## Il registro `state.events` viene svuotato all'inizio e contiene gli eventi dell'anno.


## Esegue il fine anno. Restituisce un Dictionary:
##   "ok" (false solo se la partita e' gia' finita), "anno" (anno dopo il fine anno),
##   "finita" (partita finita: anno finale, sconfitta o vittoria per dominio in attesa della scelta), "errori" (anomalie dei dati, vuoto se tutto regolare),
##   "avvisi" (per esempio tesoro negativo).
static func end_year(state: GameState) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if state.is_game_over():
		errors.append(_game_over_message(state))
		return {"ok": false, "anno": state.year, "finita": true, "errori": errors, "avvisi": warnings}
	state.events.clear()
	PrisonerProcessor.settle_overdue(state)   # ADR-073: decisioni sui prigionieri lasciate in sospeso dal giocatore
	TroopUpgrades.apply_faction_minimum(state)   # armi e armatura minime della fazione (Auror: oro), anche per le pile passate di mano
	PapacyProcessor.snapshot(state)
	DynastyProcessor.sync_positions(state)
	_move_armies(state, errors)
	_merge_arrivals(state)
	_garrison_arrivals(state)
	AgentProcessor.process_year(state)
	WarProcessor.field_battles(state)
	WarProcessor.process_sieges(state)
	WarProcessor.conquests(state)
	WarProcessor.destroyed_factions(state)
	PrisonerProcessor.process_year(state)   # ADR-073: prigionieri dell'anno (decisioni dell'IA)
	DynastyProcessor.process_year(state)
	ProvinceProcessor.process_year(state)
	ReligionProcessor.process_year(state)
	PapacyProcessor.process_year(state)
	EventProcessor.process_year(state)
	AgentProcessor.sync_year(state)
	_income_and_upkeep(state, errors, warnings)
	EventProcessor.clear_temporary(state)
	_advance_construction(state)
	_advance_recruitment(state, errors)
	MercenaryProcessor.process_year(state)   # fase 8d: compagnie di mercenari (invecchiano, si spostano, compaiono)
	DynastyProcessor.ensure_commanders(state, state.rng, state.year + 1)
	DiplomacyProcessor.expire_truces(state, state.year + 1)
	Admirals.ensure(state)   # ADR-056: flotte nuove e Auror al massimo
	AurorUnits.ensure_king_guard(state)   # ADR-074: il re degli Auror ha sempre i Corazzieri del Drago
	for f in state.factions:
		f.close_year()   # saldo reale dell'anno e spese per voce (2026-11-13)
	state.year += 1
	state.era = state.era_for_year(state.year)
	SpyIntel.expire(state)   # informazioni delle spie scadute (18/11/2026)
	VictoryProcessor.check(state)
	return {"ok": true, "anno": state.year, "finita": state.is_game_over(), "errori": errors, "avvisi": warnings}


## Perche' la partita non va avanti (per il messaggio di errore di un fine anno rifiutato).
static func _game_over_message(state: GameState) -> String:
	if state.victory.outcome == VictoryState.DEFEAT:
		return Lang.t("La partita e' finita: sconfitta nell'anno %d") % state.victory.year
	if state.victory.awaits_choice():
		return Lang.t("Vittoria per dominio nell'anno %d: scegli se continuare a giocare") % state.victory.year
	return Lang.t("La partita e' gia' finita (anno %d)") % state.year


# --- 1. movimento ------------------------------------------------------------


## Ogni esercito con un percorso avanza di una regione. Entrare in una provincia di un'altra
## fazione, o dove ci sono suoi eserciti (flotte, per una flotta), e' un attacco: la guerra viene
## dichiarata ora (EV_WAR_DECLARED, mai contro i ribelli, gia' in guerra con tutti). Lo scontro
## si risolve subito dopo, nel passo delle battaglie. Un esercito che si muove lascia il castello
## e toglie l'assedio che stava tenendo.
static func _move_armies(state: GameState, errors: Array[String]) -> void:
	# I trasporti via mare si ricontrollano tutti prima che si muova qualcuno (spec. fase 3 §9):
	# l'esito non dipende dall'ordine di id delle flotte e degli eserciti.
	var broken := _broken_transports(state)
	_arrived_now.clear()
	var pursuers: Array[Army] = []
	for a in state.armies:
		if a.is_fleet and a.attack_target > 0:
			pursuers.append(a)   # si muovono per ultime, verso dove il bersaglio e' andato
			continue
		# le flotte percorrono fino al loro raggio di zone di mare in un anno; si fermano dove trovano un nemico
		var steps := Combat.fleet_range(state, a) if a.is_fleet else 1
		for k in steps:
			if a.path.is_empty():
				break
			if not _move_step(state, a, broken if k == 0 else {}, errors):
				break
	for a in pursuers:
		if state.armies.has(a):
			_pursue(state, a, errors)


## Flotta con un bersaglio (GameCommands.order_naval_attack), dopo il movimento di tutti gli altri. PROVVISORIA (il manuale non
## descrive l'inseguimento): la flotta cerca il bersaglio nella zona in cui e' arrivato quest'anno; se e' nella sua stessa zona
## lo attacca li', se e' entro il raggio delle navi lo raggiunge, altrimenti gli si avvicina e continua l'anno dopo. Se il
## bersaglio non c'e' piu' (affondato, catturato) l'ordine cade e la flotta resta dov'e'.
static func _pursue(state: GameState, a: Army, errors: Array[String]) -> void:
	var target := state.army(a.attack_target)
	if target == null or target.stacks.is_empty() or not target.is_fleet or target.faction == a.faction:
		a.attack_target = 0
		a.path = PackedStringArray()
		return
	if target.region == a.region:
		var enemies: Array[String] = [target.faction]
		_attack(state, a, enemies, a.region)
		# attacca chi ha dato l'ordine: conta come appena arrivata (nelle ritirate vale il primo mare libero)
		a.from_region = a.region
		a.arrived_year = state.year
		a.attack_target = 0
		a.path = PackedStringArray()
		return
	var route := GameCommands.fleet_path(state, a.id, target.region)
	if route.is_empty():
		a.attack_target = 0
		a.path = PackedStringArray()
		return
	a.path = route
	for k in Combat.fleet_range(state, a):
		if a.path.is_empty():
			break
		if not _move_step(state, a, {}, errors):
			break
	if a.region == target.region:
		a.attack_target = 0
		a.path = PackedStringArray()


## Un passo del percorso di `a`. Falso se l'esercito si ferma (percorso non valido, trasporto interrotto o regione ostile:
## li' combattera').
static func _move_step(state: GameState, a: Army, broken: Dictionary, errors: Array[String]) -> bool:
	var target := a.path[0]
	var region := state.campaign.region(target)
	if region == null:
		errors.append("Esercito %d: regione sconosciuta nel percorso (%s)" % [a.id, target])
		a.path = PackedStringArray()
		a.sea_route = PackedStringArray()
		return false
	if region.is_sea != a.is_fleet:
		errors.append("Esercito %d: %s non e' un terreno adatto (flotta=%s)" % [a.id, target, str(a.is_fleet)])
		a.path = PackedStringArray()
		a.sea_route = PackedStringArray()
		return false
	if broken.has(a.id):
		_block_transport(state, a, str(broken[a.id]))
		return false
	# fase 5c: un esercito crociato attraversa i territori altrui in pace e attacca solo il proprietario del suo bersaglio
	var enemies: Array[String] = []
	if a.is_crusade():
		enemies = PapacyProcessor.crusade_enemies(state, a, target)
	else:
		enemies = WarProcessor.hostile_factions(state, a.faction, a.is_fleet, target)
		_drop_newcomers(state, a, enemies, target)
	# flotta all'attacco di una flotta precisa: il bersaglio e' ostile anche se alleato o in tregua (il trattato si rompe)
	var aimed: Army = state.army(a.attack_target) if a.attack_target > 0 else null
	if aimed != null and aimed.region == target and not aimed.stacks.is_empty() and not enemies.has(aimed.faction):
		enemies.append(aimed.faction)
	_attack(state, a, enemies, target)
	var origin := a.region
	var by_sea := not a.sea_route.is_empty()
	var moved := {"esercito": a.id, "fazione": a.faction, "da": origin, "a": target}
	if by_sea:
		# sbarco: il punto di partenza per le ritirate e' l'ultima zona di mare della catena
		a.from_region = a.sea_route[a.sea_route.size() - 1]
		moved["via_mare"] = true
		moved["catena"] = Array(a.sea_route)
	else:
		a.from_region = origin
	a.arrived_year = state.year
	a.region = target
	a.in_castle = false
	a.assault_ordered = false
	a.path.remove_at(0)
	a.sea_route = PackedStringArray()
	_arrived_now[a.id] = true
	state.add_event(GameState.EV_MOVED, moved)
	return enemies.is_empty()


## Eserciti arrivati nel movimento di quest'anno (id -> true), azzerati all'inizio di `_move_armies`.
static var _arrived_now := {}


## Segnalazione di Federico (20/11/2026: «vengo accusato di attacchi inesistenti che rompono le mie alleanze»): gli ordini
## si danno sulla mappa com'e', ma a fine anno gli eserciti si muovono uno dopo l'altro. Chi va in una regione dove non c'e'
## nessuno da attaccare non deve ritrovarsi in guerra (o senza alleanza o tregua) perche' un esercito di un'altra fazione,
## con cui non e' in guerra, ci e' entrato prima di lui nello stesso fine anno: come se fossero arrivati insieme, i due
## convivono senza scontro. Restano ostili il proprietario della provincia, le fazioni gia' in guerra e chi c'era gia'.
## Solo a terra (in mare le flotte non in guerra convivono gia', WarProcessor.hostile_factions).
static func _drop_newcomers(state: GameState, a: Army, enemies: Array[String], target: String) -> void:
	if a.is_fleet or enemies.is_empty():
		return
	var province := state.province(target)
	var owner := province.owner if province != null else ""
	for enemy in enemies.duplicate():
		if enemy == owner or state.at_war(a.faction, enemy):
			continue
		var only_newcomers := true
		for other in state.armies_in(target):
			if other.faction == enemy and not other.is_fleet and not other.stacks.is_empty() and not _arrived_now.has(other.id):
				only_newcomers = false
				break
		if only_newcomers:
			enemies.erase(enemy)


## Attacco di `a` alle fazioni `enemies` entrando (o restando) in `target`: rottura di alleanze e tregue, avvertimento o
## scomunica del Papa (non per crociati e flotte), dichiarazione di guerra con il suo evento.
static func _attack(state: GameState, a: Army, enemies: Array[String], target: String) -> void:
	for enemy in enemies:
		# fase 5a: attaccare chi ha un'alleanza o una tregua con noi rompe il trattato (influenza del capo)
		DiplomacyProcessor.break_for_attack(state, a.faction, enemy, target)
		# fase 5c: avvertimento papale o scomunica (prima della dichiarazione: serve sapere se la guerra e' nuova)
		if not a.is_crusade() and not a.is_fleet:
			PapacyProcessor.on_attack(state, a.faction, enemy, target)
		if state.declare_war(a.faction, enemy):
			state.add_event(GameState.EV_WAR_DECLARED, {
				"fazione": a.faction,
				"contro": enemy,
				"regione": target,
				"esercito": a.id,
				"testo": Lang.t("%s dichiara guerra a %s (attacco a %s).") % [SimUtil.faction_label(a.faction), SimUtil.faction_label(enemy), WarProcessor.region_label(state, target)],
			})
			DiplomacyProcessor.resolve_conflicting_alliances(state, a.faction, enemy, target)


## Trasporti via mare la cui catena non regge piu' (id esercito -> motivo). Un esercito con una
## catena ma senza percorso non ha piu' un ordine: la catena si scarta senza evento.
static func _broken_transports(state: GameState) -> Dictionary:
	var out := {}
	for a in state.armies:
		if a.sea_route.is_empty():
			continue
		if a.path.is_empty():
			a.sea_route = PackedStringArray()
			continue
		var problem := GameCommands.transport_problem(state, a)
		if problem != "":
			out[a.id] = problem
	return out


## Il trasporto e' interrotto: l'esercito resta dov'e', senza ordine, e si registra l'evento.
static func _block_transport(state: GameState, a: Army, reason: String) -> void:
	var target := a.path[0] if not a.path.is_empty() else ""
	a.path = PackedStringArray()
	a.sea_route = PackedStringArray()
	state.add_event(GameState.EV_TRANSPORT_BLOCKED, {
		"fazione": a.faction,
		"regione": a.region,
		"esercito": a.id,
		"verso": target,
		"motivo": reason,
		"testo": Lang.t("Il trasporto via mare dell'esercito %d di %s da %s a %s e' interrotto (%s): l'esercito resta dov'e'.") % [
			a.id, SimUtil.faction_label(a.faction), WarProcessor.region_label(state, a.region), WarProcessor.region_label(state, target), reason],
	})


# --- 2. reddito e mantenimento ------------------------------------------------


## Per ogni fazione viva: mantenimento sottratto per primo, poi la somma dei redditi delle
## province (manuale p20). Se il tesoro finisce sotto zero: avviso ed evento.
static func _income_and_upkeep(state: GameState, errors: Array[String], warnings: Array[String]) -> void:
	var farm := {}
	var mines := {}
	var trade := {}
	var acumen := Economy.acumen_table(state)
	for p in state.provinces:
		var f := state.faction(p.owner)
		if f == null or not f.alive:
			p.last_income = {"agricoltura": 0, "miniere": 0, "commercio": 0, "totale": 0, "conteso": false}
			continue
		var inc := Economy.province_income(state, p, acumen)
		p.last_income = inc
		farm[f.id] = int(farm.get(f.id, 0)) + int(inc["agricoltura"])
		mines[f.id] = int(mines.get(f.id, 0)) + int(inc["miniere"])
		trade[f.id] = int(trade.get(f.id, 0)) + int(inc["commercio"])
	for a in state.armies:
		for s in a.stacks:
			if state.units.get_unit(s.unit_id) == null:
				errors.append("Esercito %d: unita' sconosciuta %s" % [a.id, s.unit_id])
	for f in state.factions:
		if not f.alive:
			continue
		var upkeep := Economy.faction_upkeep(state, f.id)
		var income_farm := int(farm.get(f.id, 0))
		var income_mines := int(mines.get(f.id, 0))
		var income_trade := int(trade.get(f.id, 0))
		var net := income_farm + income_mines + income_trade - upkeep
		f.treasury -= upkeep
		f.treasury += income_farm + income_mines + income_trade
		f.last_income = {
			"agricoltura": income_farm,
			"miniere": income_mines,
			"commercio": income_trade,
			"mantenimento": upkeep,
			"netto": net,
		}
		if f.treasury < 0:
			warnings.append("%s: tesoro negativo (%d) nell'anno %d" % [f.id, f.treasury, state.year])
			state.add_event(GameState.EV_NEGATIVE_TREASURY, {"fazione": f.id, "tesoro": f.treasury})


# --- 3. costruzioni -----------------------------------------------------------


## Avanza di un anno solo il primo elemento della coda; a zero anni il livello e' impostato.
static func _advance_construction(state: GameState) -> void:
	for p in state.provinces:
		if p.building_queue.is_empty():
			continue
		var item := p.building_queue[0]
		item.years_left -= 1
		if item.years_left > 0:
			continue
		p.building_queue.remove_at(0)
		p.set_level(item.key, maxi(p.level_of(item.key), item.level))
		state.add_event(GameState.EV_BUILT, {"fazione": p.owner, "provincia": p.id, "edificio": item.key, "livello": item.level})


# --- 4. reclutamento ----------------------------------------------------------


## Per ogni provincia uno o piu' passaggi della coda (`_recruit_round`): ogni passaggio avanza di un anno solo il primo
## elemento; a zero anni l'unita' nasce. Un passaggio l'anno, piu' d'uno per le fazioni con `reclutamenti_per_anno`.
static func _advance_recruitment(state: GameState, errors: Array[String]) -> void:
	# riaddestramento delle pile decimate (ordini dati durante l'anno): prima che nascano le reclute, cosi' gli indici delle
	# pile degli ordini sono ancora quelli dell'ordine
	RetrainProcessor.process_year(state)
	for p in state.provinces:
		if p.repeat_faction != "" and not p.repeats_units():
			# la provincia ha cambiato proprietario: la coda ripetuta si spegne
			p.repeat_faction = ""
			p.repeat_pending = PackedStringArray()
		var owner := state.faction(p.owner)
		var rounds := state.rules.recruit_rounds_of(p.owner, owner != null and owner.is_player)
		for r in rounds:
			if not _recruit_round(state, p, errors):
				break


## Un passaggio della coda di una provincia: un anno di addestramento al primo elemento, che a zero anni nasce
## (e con la coda ripetuta torna in fondo). Falso se la coda e' vuota o in pausa: i passaggi successivi non servono.
## Gli Auror del giocatore fanno piu' passaggi l'anno (`Rules.recruit_rounds_of`, auror.cfg).
static func _recruit_round(state: GameState, p: ProvinceState, errors: Array[String]) -> bool:
	if p.repeats_units():
		_retry_pending(state, p)
	if p.unit_queue.is_empty():
		return false
	var item := p.unit_queue[0]
	item.years_left -= 1
	if item.years_left > 0:
		return true
	p.unit_queue.remove_at(0)
	_spawn_unit(state, p, item, errors)
	if p.repeats_units():
		_requeue(state, p, item.key)
	return true


## Unioni ordinate trascinando un esercito su un altro (GameCommands.order_merge): chi e' arrivato nella regione del suo
## bersaglio vi confluisce, se c'e' posto e sono entrambi fuori dal castello (o entrambi dentro). Se il bersaglio non c'e'
## piu' o non c'e' posto l'ordine cade con un evento; chi e' ancora in viaggio lo conserva.
static func _merge_arrivals(state: GameState) -> void:
	var pending: Array[Army] = []
	for a in state.armies:
		if a.merge_target > 0:
			pending.append(a)
	for a in pending:
		if state.army(a.id) == null or a.stacks.is_empty():
			continue
		if not a.path.is_empty():
			continue
		var target := state.army(a.merge_target)
		a.merge_target = 0
		var reason := ""
		if target == null or target.stacks.is_empty() or target.faction != a.faction:
			reason = Lang.t("l'esercito da raggiungere non c'e' piu'")
		elif target.region != a.region:
			reason = Lang.t("l'esercito da raggiungere si e' spostato")
		elif target.in_castle != a.in_castle:
			reason = Lang.t("uno dei due e' nel castello")
		elif target.stacks.size() + a.stacks.size() > state.rules.max_stacks:
			reason = Lang.t("insieme supererebbero %d pile") % state.rules.max_stacks
		if reason != "":
			state.add_event(GameState.EV_MERGE_FAILED, {"fazione": a.faction, "esercito": a.id, "bersaglio": target.id if target != null else 0, "regione": a.region, "motivo": reason})
			continue
		var stacks := a.stacks.size()
		var r := GameCommands.merge_armies(state, a.faction, a.id, target.id)
		if bool(r["ok"]):
			state.add_event(GameState.EV_ARMIES_MERGED, {"fazione": target.faction, "esercito": a.id, "bersaglio": target.id, "regione": target.region, "pile": stacks})


## Barricate ordinate trascinando un esercito sul castello di una propria provincia confinante (GameCommands.order_garrison_move):
## chi e' arrivato si barrica con le pile che ci stanno, prima delle battaglie, cosi' il nemico che arriva lo stesso anno
## assedia invece di combattere in campo. Se la provincia non e' piu' propria o il castello e' pieno l'ordine cade con un
## evento; chi e' ancora in viaggio lo conserva.
static func _garrison_arrivals(state: GameState) -> void:
	var pending: Array[Army] = []
	for a in state.armies:
		if a.garrison_on_arrival:
			pending.append(a)
	for a in pending:
		if state.army(a.id) == null or a.stacks.is_empty() or not a.path.is_empty():
			continue
		a.garrison_on_arrival = false
		if a.in_castle:
			continue
		var r := GameCommands.garrison_castle(state, a.faction, a.id)
		if bool(r["ok"]):
			state.add_event(GameState.EV_ARMY_GARRISONED, {"fazione": a.faction, "esercito": a.id, "regione": a.region,
				"dentro": int(r["dentro"]), "fuori": int(r["fuori"]), "rimasto_fuori": int(r["rimasto_fuori"])})
		else:
			state.add_event(GameState.EV_GARRISON_FAILED, {"fazione": a.faction, "esercito": a.id, "regione": a.region,
				"motivo": str(r.get("errore", ""))})


## Coda ripetuta: l'unita' appena completata torna in fondo alla coda, pagata di nuovo. Se il tesoro non basta va tra
## quelle in attesa di fondi (la coda e' in pausa); se non e' piu' reclutabile (requisiti, epoca, crociata in corso) esce
## dal giro con un evento. Con altre unita' gia' in attesa si mette dietro di loro, per non cambiare l'ordine del giro.
static func _requeue(state: GameState, p: ProvinceState, unit_id: String) -> void:
	if not p.repeat_pending.is_empty():
		p.repeat_pending.append(unit_id)
		return
	var r := GameCommands.queue_unit(state, p.owner, p.id, unit_id)
	if bool(r["ok"]):
		return
	if bool(r.get("tesoro_insufficiente", false)):
		p.repeat_pending.append(unit_id)
		state.add_event(GameState.EV_QUEUE_PAUSED, {"fazione": p.owner, "provincia": p.id, "unita": unit_id, "costo": int(r.get("costo", 0))})
		return
	state.add_event(GameState.EV_QUEUE_DROPPED, {"fazione": p.owner, "provincia": p.id, "unita": unit_id, "motivo": str(r["errore"])})


## Coda ripetuta in pausa: rimette in coda le unita' in attesa, in ordine, finche' il tesoro basta. La prima che non si
## puo' pagare ferma il giro fino all'anno dopo; quelle non piu' reclutabili escono dal giro.
static func _retry_pending(state: GameState, p: ProvinceState) -> void:
	if p.repeat_pending.is_empty():
		return
	var queued := false
	while not p.repeat_pending.is_empty():
		var unit_id := p.repeat_pending[0]
		p.repeat_pending.remove_at(0)
		var r := GameCommands.queue_unit(state, p.owner, p.id, unit_id)
		if bool(r["ok"]):
			queued = true
			continue
		if bool(r.get("tesoro_insufficiente", false)):
			p.repeat_pending.insert(0, unit_id)
			return
		state.add_event(GameState.EV_QUEUE_DROPPED, {"fazione": p.owner, "provincia": p.id, "unita": unit_id, "motivo": str(r["errore"])})
	if queued:
		state.add_event(GameState.EV_QUEUE_RESUMED, {"fazione": p.owner, "provincia": p.id})


## L'unita' nuova entra nell'esercito di guarnigione della provincia (fermo, della stessa
## fazione, con meno pile del massimo), altrimenti in un esercito nuovo (manuale p26, p30).
## Le navi seguono la stessa regola nella prima zona di mare confinante (PROVVISORIA, catalogo r.89).
static func _spawn_unit(state: GameState, province: ProvinceState, item: QueueItem, errors: Array[String]) -> void:
	var unit := state.units.get_unit(item.key)
	if unit == null:
		errors.append("Reclutamento in %s: unita' sconosciuta %s" % [province.id, item.key])
		return
	if not unit.is_military():
		# fase 5a: gli agenti nascono nella provincia (AgentState), non in un esercito
		if AgentState.is_recruitable_type(unit.type_name):
			AgentProcessor.spawn_recruit(state, province, unit)
		elif PapacyProcessor.kind_of_unit(unit.type_name) != "":
			# fase 5c: crociata e jihad fanno nascere un esercito crociato
			PapacyProcessor.spawn_crusade(state, province, unit, item, errors)
		else:
			errors.append("Reclutamento in %s: %s non e' una truppa ne' un agente reclutabile" % [province.id, unit.id])
		return
	var region_id := province.id
	var fleet := unit.is_ship()
	if fleet:
		region_id = GameSetup.first_sea_neighbour(state.campaign, state.campaign.region(province.id))
		if region_id == "":
			errors.append("Reclutamento in %s: %s non ha una zona di mare confinante" % [province.id, unit.id])
			return
	# le truppe nuove nascono nel castello finche' c'e' posto (richiesta di Federico, 2026-11-10; la cavalleria conta doppio),
	# poi in campo; in una provincia assediata nascono comunque nel castello (altrimenti combatterebbero fuori)
	var inside := false
	if not fleet and Combat.castle_level(state, region_id) > 0:
		var weight := state.rules.combat.cavalry_garrison_weight if unit.is_cavalry() else 1
		inside = state.is_besieged(region_id) or Combat.garrison_load(state, region_id) + weight <= state.rules.combat.garrison_max
	var target: Army = null
	for a in state.armies_in(region_id):
		if a.faction == province.owner and a.is_fleet == fleet and a.in_castle == inside and a.path.is_empty() and a.crusade.is_empty() and not a.is_full(state.rules.max_stacks):
			target = a
			break
	if target == null:
		target = state.create_army(province.owner, region_id, fleet)
		target.in_castle = inside
	var recruit := state.new_stack(province.owner, unit.id, unit.men)
	TroopUpgrades.equip_recruit(state, recruit, province)   # armi, armatura e valore dagli edifici della provincia
	target.stacks.append(recruit)
	state.add_event(GameState.EV_RECRUITED, {"fazione": province.owner, "provincia": province.id, "unita": unit.id, "esercito": target.id})
