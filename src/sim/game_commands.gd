class_name GameCommands
extends RefCounted
## Comandi del giocatore e dell'IA (ADR-008). Ogni comando valida e restituisce un esito:
## Dictionary con "ok" (bool) e "errore" (testo in italiano, vuoto se ok), piu' eventuali
## dati del comando. Lo stesso percorso serve al giocatore, all'IA e ai test.
## Ogni comando riceve la fazione che lo impartisce (`faction_id`) e controlla che sia
## proprietaria della provincia o dell'esercito.
##
## Le funzioni `can_*` fanno solo il controllo, senza modificare lo stato (per l'interfaccia).

const QUEUE_BUILDING := "costruzione"
const QUEUE_UNIT := "reclutamento"
## Famiglia di edifici del porto, necessaria (oltre a SetPort) per imbarcare truppe (spec. fase 3 §9).
const PORT_FAMILY := "PORT"
## Stato di una zona di mare per un trasporto (vedi `sea_zone_status`).
const ZONE_NO_FLEET := 0     ## nessuna flotta propria: la catena si ferma
const ZONE_PASSABLE := 1     ## almeno una flotta propria e nessuna ostile
const ZONE_BLOCKED := 2      ## una flotta di una fazione in guerra: la catena e' interrotta


static func success(extra: Dictionary = {}) -> Dictionary:
	var r := {"ok": true, "errore": ""}
	r.merge(extra)
	return r


static func failure(message: String) -> Dictionary:
	return {"ok": false, "errore": message}


# --- tassa -------------------------------------------------------------------


## Imposta il livello di tassa (0-4) di una provincia propria.
static func set_tax(state: GameState, faction_id: String, province_id: String, level: int) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	if not state.rules.is_valid_tax(level):
		return failure(Lang.t("Livello di tassa non valido: %d (ammessi da 0 a %d)") % [level, state.rules.tax_multipliers.size() - 1])
	state.province(province_id).tax_level = level
	return success()


# --- costruzioni -------------------------------------------------------------


## Controlla se la famiglia di edifici si puo' mettere in coda. Se si': "ok" vero e
## "livello", "costo", "anni" del prossimo livello.
static func can_queue_building(state: GameState, faction_id: String, province_id: String, family_id: String) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var province := state.province(province_id)
	var family := state.buildings.get_family(family_id)
	if family == null:
		return failure(Lang.t("Edificio sconosciuto: %s") % family_id)
	if province.building_queue.size() >= state.rules.max_building_queue:
		return failure(Lang.t("Coda di costruzione piena (%d)") % state.rules.max_building_queue)
	for q in province.building_queue:
		if q.key == family.id:
			return failure(Lang.t("%s e' gia' in coda di costruzione") % family.id)
	var next_level := province.level_of(family.id) + 1
	var lv := family.get_level(next_level)
	if lv == null:
		return failure(Lang.t("%s ha gia' il livello massimo") % family.id)
	var faction := state.faction(faction_id)
	if not lv.allows_faction(faction.id):
		return failure(Lang.t("%s non e' costruibile da %s") % [lv.token, faction.id])
	if not _religion_allows(state, family, faction.id):
		return failure(Lang.t("%s non e' costruibile con la religione di %s") % [family.id, faction.id])
	var region := state.campaign.region(province.id)
	for res in lv.resources:
		if region == null or not region.resources.has(res):
			return failure(Lang.t("%s richiede la risorsa %s nella regione") % [lv.token, res])
	if family.has_type("PORT") and (region == null or not region.has_port):
		return failure(Lang.t("%s richiede una regione costiera con porto") % family.id)
	# PROVVISORIA (catalogo r.72): l'epoca non limita gli edifici (il file edifici non ha periodi). Le invenzioni (col. 26)
	# si', dall'evento storico che le porta (ADR-114; gli Auror ne sono esenti).
	var invention := HistoricalLimits.missing_invention(state, faction.id, lv)
	if invention != "":
		return failure(Lang.t("%s richiede un'invenzione non ancora arrivata: %s") % [lv.token, invention_label(invention)])
	if not requirements_met(lv.requires, province, state.buildings):
		return failure(Lang.t("Requisiti di %s non soddisfatti") % lv.token)
	var cost := state.rules.traits.building_cost(faction.id, lv)   # ADR-089: tratti della fazione
	if faction.treasury < cost:
		return failure(Lang.t("Tesoro insufficiente: servono %d, ci sono %d") % [cost, faction.treasury])
	return success({"livello": next_level, "costo": cost, "anni": state.rules.traits.building_years(faction.id, lv)})


## Nome dell'invenzione per i messaggi (ADR-114).
static func invention_label(invention: String) -> String:
	match invention.strip_edges().to_upper():
		"GUNPOWDER":
			return Lang.t("polvere da sparo")
		"COMPASS":
			return Lang.t("bussola")
	return invention.capitalize()


## Mette in coda il prossimo livello della famiglia. Il costo e' pagato subito.
## PROVVISORIA (catalogo r.69): il manuale dice che il costo si paga all'avvio dei lavori.
static func queue_building(state: GameState, faction_id: String, province_id: String, family_id: String) -> Dictionary:
	var check := can_queue_building(state, faction_id, province_id, family_id)
	if not bool(check["ok"]):
		return check
	var province := state.province(province_id)
	var family := state.buildings.get_family(family_id)
	var cost := int(check["costo"])
	state.faction(faction_id).spend(cost, FactionState.SPEND_BUILDINGS)
	province.building_queue.append(QueueItem.new(QueueItem.KIND_BUILDING, family.id, int(check["livello"]), int(check["anni"]), cost))
	return check


## Demolizione (richiesta di Federico del 15/11; manuale p37 «Distruggere strutture»: pulsante Distruggi nella scheda
## dell'edificio, «ti verra' restituita una parte del prezzo di costruzione»). Toglie il livello piu' alto della famiglia e
## restituisce `Rules.demolish_refund` del suo costo (PROVVISORIA, 0,5: la campagna vichinga parla della meta' del valore).
## Non si demolisce: un edificio in coda di costruzione (va prima annullato), un livello che serve a un altro edificio della
## provincia, costruito o in coda. Se si': "livello" (quello tolto), "token", "rimborso".
static func can_demolish_building(state: GameState, faction_id: String, province_id: String, family_id: String) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var province := state.province(province_id)
	var family := state.buildings.get_family(family_id)
	if family == null:
		return failure(Lang.t("Edificio sconosciuto: %s") % family_id)
	var level := province.level_of(family.id)
	var lv := family.get_level(level)
	if level <= 0 or lv == null:
		return failure(Lang.t("%s non c'e' in questa provincia") % family.id)
	for q in province.building_queue:
		if q.key == family.id:
			return failure(Lang.t("%s e' in coda di costruzione: annulla prima i lavori") % family.id)
	var blocker := _demolish_blocker(state, province, family.id, level)
	if blocker != "":
		return failure(Lang.t("Serve a %s: non si puo' demolire") % blocker)
	return success({"livello": level, "token": lv.token, "rimborso": roundi(state.rules.traits.building_cost(faction_id, lv) * state.rules.demolish_refund)})


static func demolish_building(state: GameState, faction_id: String, province_id: String, family_id: String) -> Dictionary:
	var check := can_demolish_building(state, faction_id, province_id, family_id)
	if not bool(check["ok"]):
		return check
	var province := state.province(province_id)
	var family := state.buildings.get_family(family_id)
	province.set_level(family.id, int(check["livello"]) - 1)
	state.faction(faction_id).refund(int(check["rimborso"]), FactionState.SPEND_BUILDINGS)
	return check


## Token del primo edificio (costruito o in coda) i cui requisiti non sarebbero piu' soddisfatti senza il livello `level` di
## `family_id`; "" se nessuno.
static func _demolish_blocker(state: GameState, province: ProvinceState, family_id: String, level: int) -> String:
	province.set_level(family_id, level - 1)
	var blocker := ""
	for other in province.buildings.keys():
		var other_id := str(other)
		var other_level := province.level_of(other_id)
		if other_id == family_id or other_level <= 0:
			continue
		var fam := state.buildings.get_family(other_id)
		var olv := fam.get_level(other_level) if fam != null else null
		if olv != null and not requirements_met(olv.requires, province, state.buildings):
			blocker = olv.token
			break
	if blocker == "":
		for q in province.building_queue:
			var fam := state.buildings.get_family(q.key)
			var qlv := fam.get_level(q.level) if fam != null else null
			if qlv != null and not requirements_met(qlv.requires, province, state.buildings):
				blocker = qlv.token
				break
	province.set_level(family_id, level)
	return blocker


# --- reclutamento ------------------------------------------------------------


## Controlla se l'unita' si puo' mettere in coda. Se si': "costo" e "anni". Dalla fase 5a si reclutano anche gli
## agenti (emissari, spie, assassini, religiosi e inquisitori; non PRINCESS) con gli stessi controlli di requisiti,
## fazione, cultura e costo: alla fine della coda nasce un `AgentState` nella provincia. Dalla fase 5c si reclutano
## anche `Crusade` (fazione cattolica non scomunicata, una crociata alla volta, in coda o attiva) e `Jihad` (fazione
## musulmana): alla fine della coda nasce un esercito crociato (`Army.crusade`, vedi `PapacyProcessor`).
static func can_queue_unit(state: GameState, faction_id: String, province_id: String, unit_id: String) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var province := state.province(province_id)
	var unit := state.units.get_unit(unit_id)
	if unit == null:
		return failure(Lang.t("Unita' sconosciuta: %s") % unit_id)
	var crusade_kind := PapacyProcessor.kind_of_unit(unit.type_name)
	if not unit.is_military() and not AgentState.is_recruitable_type(unit.type_name) and crusade_kind == "":
		if unit.type_name == AgentState.PRINCESS:
			return failure(Lang.t("%s non e' reclutabile: le principesse nascono con la dinastia") % unit.id)
		return failure(Lang.t("%s non e' reclutabile (non e' una truppa, una nave o un agente)") % unit.id)
	if unit.unique:
		return failure(Lang.t("%s e' unico: non si arruola") % unit.id)   # Ankalagon
	if province.unit_queue_load() >= state.rules.max_unit_queue:
		return failure(Lang.t("Coda di reclutamento piena (%d)") % state.rules.max_unit_queue)
	var faction := state.faction(faction_id)
	var free := state.rules.lifts_unit_limits(faction.id, unit)   # gli Auror arruolano ogni truppa e nave (auror.cfg)
	if not free and not unit.recruitable_by(faction.id):
		return failure(Lang.t("%s non e' reclutabile da %s") % [unit.id, faction.id])
	if crusade_kind != "":
		# fase 5c: crociata (cattolici non scomunicati, una alla volta) e jihad (musulmani)
		var launch := PapacyProcessor.launch_problem(state, faction.id, crusade_kind)
		if launch != "":
			return failure(launch)
	if not free and not unit.available_in_period(state.era):
		return failure(Lang.t("%s non e' disponibile nell'epoca %s") % [unit.id, state.era])
	var region := state.campaign.region(province.id)
	if region != null:
		if not free and not unit.allows_region(region.id):
			return failure(Lang.t("%s non e' reclutabile in %s") % [unit.id, region.id])
		if not free and not unit.allows_culture(culture_key(region.culture)):
			return failure(Lang.t("%s non e' reclutabile con la cultura %s") % [unit.id, region.culture])
		if unit.is_ship() and not region.has_port:
			return failure(Lang.t("Le navi si costruiscono solo in regioni con porto"))
	if not requirements_met(unit.requires, province, state.buildings):
		return failure(Lang.t("Requisiti di %s non soddisfatti") % unit.id)
	if not HistoricalLimits.unit_inventions_ok(state, faction.id, unit):
		return failure(Lang.t("%s richiede un'invenzione non ancora arrivata") % unit.id)
	if not free and HistoricalLimits.is_mounted(unit) and not HistoricalLimits.horses_allowed(state, faction.id):
		return failure(Lang.t("%s non conosce ancora il cavallo: arrivera' con gli europei") % SimUtil.faction_label(faction.id))
	var price := state.rules.traits.unit_cost(faction.id, unit)   # ADR-089: tratti della fazione
	if faction.treasury < price:
		var poor := failure(Lang.t("Tesoro insufficiente: servono %d, ci sono %d") % [price, faction.treasury])
		poor["tesoro_insufficiente"] = true
		poor["costo"] = price
		return poor
	return success({"costo": price, "anni": state.rules.traits.unit_years(faction.id, unit)})


## Mette in coda l'unita'. Il costo e' pagato subito (stessa PROVVISORIA delle costruzioni).
static func queue_unit(state: GameState, faction_id: String, province_id: String, unit_id: String) -> Dictionary:
	var check := can_queue_unit(state, faction_id, province_id, unit_id)
	if not bool(check["ok"]):
		return check
	var unit := state.units.get_unit(unit_id)
	var cost := int(check["costo"])
	state.faction(faction_id).spend(cost, FactionState.SPEND_RECRUITS)
	state.province(province_id).unit_queue.append(QueueItem.new(QueueItem.KIND_UNIT, unit.id, 0, int(check["anni"]), cost))
	return check


## Coda di reclutamento ripetuta (richiesta di Federico): con `repeat` vero ogni unita' completata torna in fondo alla
## coda e si paga di nuovo; se il tesoro non basta la coda va in pausa finche' i fondi non tornano (TurnProcessor). Spenta,
## le unita' in attesa di fondi si dimenticano (non erano pagate). L'interfaccia la offre solo al giocatore.
static func set_unit_queue_repeat(state: GameState, faction_id: String, province_id: String, repeat: bool) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var province := state.province(province_id)
	if repeat:
		province.repeat_faction = province.owner
	else:
		province.repeat_faction = ""
		province.repeat_pending = PackedStringArray()
	return success({"ripeti": repeat})


# --- code --------------------------------------------------------------------


## Toglie una voce dalla coda `queue_name` (QUEUE_BUILDING o QUEUE_UNIT): rimborso del
## costo pagato, progressi persi (manuale p26).
static func cancel_queue_item(state: GameState, faction_id: String, province_id: String, queue_name: String, index: int) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var province := state.province(province_id)
	var queue: Array[QueueItem]
	if queue_name == QUEUE_BUILDING:
		queue = province.building_queue
	elif queue_name == QUEUE_UNIT:
		queue = province.unit_queue
	else:
		return failure(Lang.t("Coda sconosciuta: %s") % queue_name)
	if index < 0 or index >= queue.size():
		return failure(Lang.t("Indice di coda non valido: %d") % index)
	var item := queue[index]
	state.faction(faction_id).refund(item.cost_paid, FactionState.SPEND_BUILDINGS if queue_name == QUEUE_BUILDING else FactionState.SPEND_RECRUITS)
	queue.remove_at(index)
	return success({"rimborso": item.cost_paid})


# --- movimento ---------------------------------------------------------------


## Ordina il movimento lungo `path` (regioni in ordine, la prima confina con la posizione
## attuale e ogni passo confina con il precedente). Eserciti solo su terra, flotte solo su mare.
## Dalla fase 3 sono ammesse anche le regioni ostili: e' un attacco, la guerra viene dichiarata a
## fine anno quando il movimento parte. Un esercito che assedia puo' muoversi: l'ordine toglie il
## suo ordine d'assalto e, partendo, l'assedio. La guarnigione di un castello assediato non esce.
## Trasporto via mare (spec. fase 3 §9): un esercito di terra puo' ordinare come unico passo una
## provincia che non confina, se `sea_route` trova una catena; l'esito ha allora "via_mare" (vero)
## e "catena" (zone di mare in ordine), e la catena e' salvata in `Army.sea_route`.
static func order_move(state: GameState, faction_id: String, army_id: int, path: PackedStringArray) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	if path.is_empty():
		return failure(Lang.t("Percorso vuoto"))
	if army.in_castle and state.is_besieged(army.region):
		return failure(Lang.t("L'esercito %d e' assediato nel castello di %s e non puo' muoversi") % [army_id, army.region])
	var clean := PackedStringArray()
	var chain := PackedStringArray()
	var previous: CampaignData.Region = state.campaign.region(army.region)
	if previous == null:
		return failure(Lang.t("L'esercito %d e' in una regione sconosciuta (%s)") % [army_id, army.region])
	for step in path:
		var next: CampaignData.Region = state.campaign.region(step)
		if next == null:
			return failure(Lang.t("Regione sconosciuta nel percorso: %s") % step)
		if next.is_sea != army.is_fleet:
			if army.is_fleet:
				return failure(Lang.t("Le flotte si muovono solo in mare (%s e' terra)") % next.id)
			return failure(Lang.t("Gli eserciti si muovono solo a terra (%s e' mare)") % next.id)
		if not previous.neighbours.has(next.id):
			# Spec. fase 3 §9: un solo passo non confinante e' un trasporto via mare, se la catena esiste.
			if path.size() == 1 and not army.is_fleet:
				chain = sea_route(state, faction_id, previous.id, next.id)
			if chain.is_empty():
				var reason := ""
				if path.size() == 1 and not army.is_fleet:
					reason = ". " + sea_transport_problem(state, faction_id, previous.id, next.id)
				return failure(Lang.t("%s non confina con %s%s") % [next.id, previous.id, reason])
		clean.append(next.id)
		previous = next
	army.path = clean
	army.sea_route = chain
	army.pending_conflict = ""
	army.assault_ordered = false
	army.merge_target = 0
	army.garrison_on_arrival = false
	army.attack_target = 0
	var result := {"passi": clean.size(), "attacco": is_hostile_target(state, faction_id, clean[0], army.is_fleet)}
	if not chain.is_empty():
		result["via_mare"] = true
		result["catena"] = Array(chain)
	# un esercito che parte non si riaddestra: gli ordini di riaddestramento sono rimborsati
	_with_retrain_refund(result, RetrainProcessor.cancel_army_orders(state, army.id))
	return success(result)


## Percorso piu' breve di una flotta verso la zona di mare `target_id` (zone confinanti, la prima esclusa la partenza),
## vuoto se non c'e' o non e' una flotta. La flotta lo percorre per `Combat.fleet_range` zone all'anno (richiesta di
## Federico: come nell'originale le navi raggiungono zone di mare non confinanti). A parita' di lunghezza, ordine di SetNeighbours.
static func fleet_path(state: GameState, army_id: int, target_id: String) -> PackedStringArray:
	var army := state.army(army_id)
	var goal := SimUtil.norm(target_id)
	var target := state.campaign.region(goal)
	if army == null or not army.is_fleet or target == null or not target.is_sea or goal == army.region:
		return PackedStringArray()
	var parent := {army.region: ""}
	var queue: Array[String] = [army.region]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == goal:
			break
		var region := state.campaign.region(current)
		if region == null:
			continue
		for n in region.neighbours:
			var next := state.campaign.region(n)
			if next == null or not next.is_sea or parent.has(next.id):
				continue
			if not Combat.can_enter(state, army, next.id):
				continue   # troppo lontano dalla costa per le navi della flotta (18/11/2026)
			parent[next.id] = current
			queue.append(next.id)
	if not parent.has(goal):
		return PackedStringArray()
	var path := PackedStringArray()
	var step := goal
	while step != army.region:
		path.insert(0, step)
		step = str(parent[step])
	return path


## Attacco a una flotta precisa (richiesta di Federico, 2026-11-13): la flotta `army_id` della fazione va a combattere la
## flotta `target_id` di un'altra fazione, anche se sta nella sua stessa zona di mare (lo scontro e' a fine anno, senza
## muoversi) o se e' alleata o in tregua (il trattato si rompe). A fine anno la flotta la cerca dove si trova in quel momento
## (TurnProcessor._pursue): se si e' spostata entro il raggio delle navi la raggiunge, altrimenti si avvicina e continua
## l'anno dopo. La conferma della dichiarazione di guerra la chiede l'interfaccia (CampaignUiAttack).
## Esito: "stessa_zona" (bool), "passi" (zone fino al bersaglio), "anni" (stima per raggiungerlo, 0 = stessa zona),
## "guerra_nuova" (bool: non c'e' ancora la guerra), "relazione" (GameState.REL_*), "bersaglio" (id della regione).
static func order_naval_attack(state: GameState, faction_id: String, army_id: int, target_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	if not army.is_fleet:
		return failure(Lang.t("Solo una flotta puo' attaccare una flotta"))
	var target := state.army(target_id)
	if target == null or target.stacks.is_empty():
		return failure(Lang.t("Flotta bersaglio sconosciuta: %d") % target_id)
	if not target.is_fleet:
		return failure(Lang.t("Una flotta puo' attaccare solo un'altra flotta"))
	if target.faction == army.faction:
		return failure(Lang.t("La flotta %d e' della stessa fazione") % target_id)
	var same_zone := target.region == army.region
	var route := PackedStringArray()
	if not same_zone:
		route = fleet_path(state, army.id, target.region)
		if route.is_empty():
			return failure(Lang.t("Nessuna rotta per mare da %s a %s") % [army.region, target.region])
	army.path = route
	army.sea_route = PackedStringArray()
	army.pending_conflict = ""
	army.assault_ordered = false
	army.merge_target = 0
	army.garrison_on_arrival = false
	army.attack_target = target.id
	var reach := maxi(1, Combat.fleet_range(state, army))
	var result := {
		"stessa_zona": same_zone,
		"passi": route.size(),
		"anni": 0 if same_zone else ceili(float(route.size()) / float(reach)),
		"guerra_nuova": not state.at_war(army.faction, target.faction),
		"relazione": state.relation(army.faction, target.faction),
		"bersaglio": target.region,
	}
	_with_retrain_refund(result, RetrainProcessor.cancel_army_orders(state, army.id))
	return success(result)


## Vero se muoversi in `region_id` e' un attacco per la fazione: provincia di un'altra fazione
## (o dei ribelli) oppure regione con eserciti (flotte, per le flotte) di altre fazioni.
## Solo controllo, per l'interfaccia (freccia rossa).
static func is_hostile_target(state: GameState, faction_id: String, region_id: String, fleet: bool = false) -> bool:
	return not WarProcessor.hostile_factions(state, faction_id, fleet, region_id).is_empty()


## Annulla il movimento in corso di un esercito.
static func cancel_move(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	army.path = PackedStringArray()
	army.sea_route = PackedStringArray()
	army.pending_conflict = ""
	army.merge_target = 0
	army.garrison_on_arrival = false
	army.attack_target = 0
	return success()


# --- trasporto via mare (spec. fase 3 §9) -----------------------------------------------------
# Regole PROVVISORIE: il manuale (p33-34) descrive catene di zone di mare con flotte proprie, ma
# non il porto: qui serve SetPort e l'edificio PORT costruito nella provincia di partenza (propria);
# le flotte alleate (fase 5a) non bloccano le zone ma non contano come proprie; nessun limite di capienza;
# le flotte non si muovono. Gli agenti (fase 5a) usano le stesse catene.


## Motivo per cui da `region_id` non si puo' imbarcare per `faction_id` ("" se si puo'): la provincia
## deve essere propria, avere il porto (SetPort) e l'edificio PORT costruito.
## `troops` falso (agenti) con `[flotte] agenti_da_ogni_porto`: va bene il porto costruito di chiunque (ADR-035).
static func embark_problem(state: GameState, faction_id: String, region_id: String, troops: bool = true) -> String:
	var key := SimUtil.norm(faction_id)
	var region := state.campaign.region(region_id)
	if region == null or region.is_sea:
		return Lang.t("Si imbarca solo da una provincia di terra: %s") % region_id
	var province := state.province(region.id)
	var guest := not troops and state.rules.combat.agents_any_port
	if province == null or (province.owner != key and not guest):
		return Lang.t("Si imbarca solo da una provincia propria: %s non appartiene a %s") % [region.id, key]
	if not region.has_port:
		return Lang.t("%s non ha un porto") % region.id
	if province.level_of(PORT_FAMILY) < 1:
		return Lang.t("Il porto di %s non e' ancora costruito") % region.id
	return ""


## Stato della zona di mare per i trasporti di `faction_id`: ZONE_BLOCKED se c'e' una flotta di una
## fazione in guerra con lei o, con il blocco navale, di una fazione non alleata (anche se ci sono flotte proprie, ma con
## `blocco_solo_se_piu_navi` solo se ha piu' navi di quelle proprie), altrimenti ZONE_PASSABLE se c'e'
## almeno una flotta propria, altrimenti ZONE_NO_FLEET. Le flotte alleate (fase 5a) non bloccano e non
## contano come proprie. Solo controllo, per l'interfaccia.
## `troops` falso per gli agenti: il blocco navale delle flotte neutrali vale solo per le truppe.
static func sea_zone_status(state: GameState, faction_id: String, zone_id: String, troops: bool = true) -> int:
	var key := SimUtil.norm(faction_id)
	return int(_zone_status_map(state, key, troops).get(SimUtil.norm(zone_id), ZONE_NO_FLEET))


## Catena di zone di mare per portare un esercito di `faction_id` da `from_id` a `to_id`: la piu'
## corta (ricerca in ampiezza, ordine di SetNeighbours), vuota se non esiste. Vedi la spec. §9: la
## prima zona confina con la partenza, l'ultima con l'arrivo, ogni zona ha una flotta propria e
## nessuna flotta ostile. Se `to_id` non e' una provincia di terra diversa dalla partenza e' vuota.
## `troops` falso per gli agenti (le flotte neutrali non li bloccano).
static func sea_route(state: GameState, faction_id: String, from_id: String, to_id: String, troops: bool = true) -> PackedStringArray:
	var none := PackedStringArray()
	var key := SimUtil.norm(faction_id)
	var target := state.campaign.region(to_id)
	var origin := state.campaign.region(from_id)
	if target == null or target.is_sea or origin == null or origin.id == target.id:
		return none
	var search := _sea_search(state, key, origin.id, troops)
	var order: PackedStringArray = search["ordine"]
	for zone_id in order:
		var zone := state.campaign.region(zone_id)
		if zone == null or not zone.neighbours.has(target.id):
			continue
		# catena tutta della stessa ricerca: senza navi (nessun oceano) oppure tutta con flotte proprie (ADR-081)
		var parent: Dictionary = search["padre"] if search["padre"].has(zone_id) else search["padre_flotte"]
		var chain := PackedStringArray()
		var current: String = zone_id
		while current != "":
			chain.insert(0, current)
			current = str(parent.get(current, ""))
		return chain
	return none


## Province di terra raggiungibili via mare dall'esercito `army_id` di `faction_id`, nell'ordine
## della ricerca in ampiezza (poi dell'ordine dei vicini). Escluse la provincia dell'esercito e
## quelle che confinano con essa (ci si va a piedi). Vuoto per flotte, eserciti altrui o nel castello.
static func sea_destinations(state: GameState, faction_id: String, army_id: int) -> PackedStringArray:
	var out := PackedStringArray()
	var army := state.army(army_id)
	if army == null or army.is_fleet or army.in_castle or army.faction != SimUtil.norm(faction_id):
		return out
	return sea_destinations_from(state, army.faction, army.region)


## Come `sea_destinations` per qualunque viaggiatore di `faction_id` che parte da `from_id` (eserciti e agenti).
## `troops` falso per gli agenti (le flotte neutrali non li bloccano).
## `status` (facoltativo) e' la mappa delle zone di `sea_status` gia' calcolata per la stessa fazione e lo stesso `troops`: chi
## chiede le destinazioni di molte province nello stesso stato (i viaggi dell'IA, ADR-053) la calcola una volta sola.
static func sea_destinations_from(state: GameState, faction_id: String, from_id: String, troops: bool = true, status: Variant = null) -> PackedStringArray:
	var out := PackedStringArray()
	var origin := state.campaign.region(SimUtil.norm(from_id))
	if origin == null:
		return out
	var search := _sea_search(state, SimUtil.norm(faction_id), origin.id, troops, status)
	var order: PackedStringArray = search["ordine"]
	var seen := {}
	for zone_id in order:
		var zone := state.campaign.region(zone_id)
		if zone == null:
			continue
		for n in zone.neighbours:
			if seen.has(n):
				continue
			seen[n] = true
			var land := state.campaign.region(n)
			if land == null or land.is_sea or land.id == origin.id or origin.neighbours.has(land.id):
				continue
			out.append(land.id)
	return out


## Spiegazione leggibile (testo italiano) del perche' non c'e' una catena da `from_id` a `to_id`
## per `faction_id`; "" se invece la catena esiste. Per i messaggi d'errore dell'interfaccia.
static func sea_transport_problem(state: GameState, faction_id: String, from_id: String, to_id: String, troops: bool = true) -> String:
	var key := SimUtil.norm(faction_id)
	var origin := state.campaign.region(from_id)
	var target := state.campaign.region(to_id)
	if origin == null or target == null:
		return Lang.t("Regione sconosciuta")
	if target.is_sea:
		return Lang.t("Gli eserciti si muovono solo a terra")
	var embark := embark_problem(state, key, origin.id, troops)
	if embark != "":
		return Lang.t("Nessun trasporto via mare: %s") % embark
	var coastal := false
	for n in target.neighbours:
		var other := state.campaign.region(n)
		if other != null and other.is_sea:
			coastal = true
			break
	if not coastal:
		return Lang.t("Nessun trasporto via mare: %s non e' sulla costa") % target.id
	if not sea_route(state, key, origin.id, target.id, troops).is_empty():
		return ""
	if not _needs_fleet(state, troops):
		if map_has_oceans(state):
			return Lang.t("Nessun viaggio via mare tra %s e %s: per attraversare un oceano serve una flotta propria in ogni zona d'oceano, e le flotte nemiche chiudono le rotte") % [origin.id, target.id]
		return Lang.t("Nessun viaggio via mare: le flotte nemiche chiudono ogni rotta tra %s e %s") % [origin.id, target.id]
	var status := _zone_status_map(state, key, troops)
	var any_own := false
	for n in origin.neighbours:
		var near := state.campaign.region(n)
		if near != null and near.is_sea and int(status.get(near.id, ZONE_NO_FLEET)) == ZONE_PASSABLE:
			any_own = true
	if not any_own:
		return Lang.t("Nessun trasporto via mare: nessuna flotta propria libera nelle zone di mare di %s") % origin.id
	return Lang.t("Nessun trasporto via mare: nessuna catena di zone con flotte proprie e libere da flotte non alleate (blocco navale) collega %s a %s") % [origin.id, target.id]


## Ricontrolla il trasporto ordinato di un esercito al momento del movimento (fine anno): la
## partenza deve essere ancora un porto utilizzabile e la catena deve reggere (consecutiva, ogni
## zona con una flotta propria e nessuna ostile, ultima zona confinante con la destinazione).
## Restituisce "" se regge, altrimenti il motivo in italiano.
static func transport_problem(state: GameState, army: Army) -> String:
	if army.sea_route.is_empty() or army.path.size() != 1:
		return Lang.t("Trasporto non valido")
	return chain_problem(state, army.faction, army.region, army.sea_route, army.path[0])


## Come `transport_problem` ma per qualunque viaggiatore (esercito o agente, fase 5a): `from_id` e' la provincia
## di partenza, `chain` la catena di zone di mare, `target_id` la provincia di sbarco.
## `troops` falso per gli agenti: il blocco navale delle flotte neutrali vale solo per le truppe.
static func chain_problem(state: GameState, faction_id: String, from_id: String, chain: PackedStringArray, target_id: String, troops: bool = true) -> String:
	if chain.is_empty():
		return Lang.t("Trasporto non valido")
	var embark := embark_problem(state, faction_id, from_id, troops)
	if embark != "":
		return embark
	var status := _zone_status_map(state, faction_id, troops)
	var previous := state.campaign.region(from_id)
	var crosses_ocean := false
	for zone_id in chain:
		if is_ocean(state, zone_id):
			crosses_ocean = true
	for zone_id in chain:
		var zone := state.campaign.region(zone_id)
		if zone == null or not zone.is_sea or previous == null or not previous.neighbours.has(zone.id):
			return Lang.t("La catena di zone di mare non e' valida")
		var zone_state := int(status.get(zone.id, ZONE_NO_FLEET))
		if zone_state == ZONE_BLOCKED:
			return (Lang.t("blocco navale: flotta non alleata in %s") if troops else Lang.t("flotta nemica in %s")) % zone.id
		if zone_state == ZONE_NO_FLEET and _needs_fleet(state, troops):
			return Lang.t("nessuna flotta propria in %s") % zone.id
		if zone_state == ZONE_NO_FLEET and crosses_ocean:
			return Lang.t("rotta oceanica senza ponte di navi: nessuna flotta propria in %s") % zone.id
		previous = zone
	if previous == null or not previous.neighbours.has(target_id):
		return Lang.t("La catena di zone di mare non arriva a %s") % target_id
	return ""


## Mappa delle zone di mare per i trasporti di `faction_id` (vedi `_zone_status_map`), da passare a `sea_destinations_from`
## quando si chiedono le destinazioni di molte province nello stesso stato.
static func sea_status(state: GameState, faction_id: String, troops: bool = true) -> Dictionary:
	return _zone_status_map(state, SimUtil.norm(faction_id), troops)


## Zona di mare -> stato (ZONE_*) per la fazione, da un solo giro sugli eserciti. Le zone senza
## flotte non compaiono (= ZONE_NO_FLEET). Bloccano le flotte delle fazioni in guerra con `key` e, con il blocco navale
## (`[flotte] blocco_neutrali` di scontri.cfg, richiesta di Federico del 2026-11-10), quelle di ogni fazione non alleata.
## `troops` falso (agenti): bloccano solo le flotte nemiche, come nell'originale. Con `blocco_solo_se_piu_navi` (22/11/2026)
## una fazione blocca solo se nella zona ha piu' navi di `key` (`zone_blockers`).
static func _zone_status_map(state: GameState, key: String, troops: bool = true) -> Dictionary:
	var counts := _zone_fleet_counts(state, key, troops)
	var own: Dictionary = counts["proprie"]
	var hostile: Dictionary = counts["altrui"]
	var status := {}
	for zone in own:
		status[zone] = ZONE_PASSABLE
	for zone in hostile:
		if not _blockers_in(state, int(own.get(zone, 0)), hostile[zone]).is_empty():
			status[zone] = ZONE_BLOCKED   # flotta nemica; per le truppe anche neutrale (blocco navale)
	return status


## Fazioni che chiudono la zona di mare ai trasporti di `faction_id` (vuoto = nessun blocco): non alleate (per gli agenti solo
## in guerra) e, con `blocco_solo_se_piu_navi`, con piu' navi di quelle di `faction_id` nella zona.
static func zone_blockers(state: GameState, faction_id: String, zone_id: String, troops: bool = true) -> PackedStringArray:
	var key := SimUtil.norm(faction_id)
	var zone := SimUtil.norm(zone_id)
	var counts := _zone_fleet_counts(state, key, troops)
	return _blockers_in(state, int((counts["proprie"] as Dictionary).get(zone, 0)), (counts["altrui"] as Dictionary).get(zone, {}))


## Navi (unita' navali delle flotte) per zona: {"proprie": zona -> navi di `key`, "altrui": zona -> {fazione: navi}} delle
## fazioni che possono bloccare `key` (non alleate; per gli agenti solo quelle in guerra).
static func _zone_fleet_counts(state: GameState, key: String, troops: bool) -> Dictionary:
	var own := {}
	var hostile := {}
	for a in state.armies:
		if not a.is_fleet or a.stacks.is_empty():
			continue
		if a.faction == key:
			own[a.region] = int(own.get(a.region, 0)) + a.stacks.size()
		elif state.is_allied(key, a.faction):
			continue   # fase 5a: la flotta di un alleato non blocca la zona (e non conta come flotta propria)
		elif (troops and state.rules.combat.neutral_blockade) or state.at_war(key, a.faction):
			var per: Dictionary = hostile.get(a.region, {})
			per[a.faction] = int(per.get(a.faction, 0)) + a.stacks.size()
			hostile[a.region] = per
	return {"proprie": own, "altrui": hostile}


static func _blockers_in(state: GameState, own_ships: int, per_faction: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := per_faction.keys()
	keys.sort()
	for fid in keys:
		if not state.rules.combat.blockade_needs_more_ships or int(per_faction[fid]) > own_ships:
			out.append(str(fid))
	return out


## Ricerca in ampiezza sulle zone di mare percorribili a partire dalla provincia `from_id`
## (se non si puo' imbarcare, nulla). Restituisce {"ordine": PackedStringArray delle zone nell'ordine
## di scoperta, "padre": zona -> zona precedente ("" per la prima della catena), "padre_flotte": come "padre" per le zone
## raggiunte solo con il ponte di navi}. Agenti senza navi su una mappa con oceani (ADR-081): prima le zone senza oceani
## (anche senza flotte), poi le rotte con una flotta propria in ogni zona, le sole che attraversano un oceano.
static func _sea_search(state: GameState, key: String, from_id: String, troops: bool = true, status_in: Variant = null) -> Dictionary:
	var origin := state.campaign.region(from_id)
	if origin == null or embark_problem(state, key, origin.id, troops) != "":
		return {"ordine": PackedStringArray(), "padre": {}, "padre_flotte": {}}
	var status: Dictionary = status_in if typeof(status_in) == TYPE_DICTIONARY else _zone_status_map(state, key, troops)
	var need_fleet := _needs_fleet(state, troops)
	var free := _sea_bfs(state, status, origin, need_fleet)
	var order: PackedStringArray = free["ordine"]
	var by_fleet := {}
	if not need_fleet and map_has_oceans(state):
		var bridged := _sea_bfs(state, status, origin, true)
		by_fleet = bridged["padre"]
		var seen: Dictionary = free["padre"]
		for z in bridged["ordine"]:
			if not seen.has(z):
				order.append(z)
	return {"ordine": order, "padre": free["padre"], "padre_flotte": by_fleet}


static func _sea_bfs(state: GameState, status: Dictionary, origin: CampaignData.Region, need_fleet: bool) -> Dictionary:
	var order := PackedStringArray()
	var parent := {}
	for n in origin.neighbours:
		if _zone_open(state, status, n, need_fleet) and not parent.has(n):
			parent[n] = ""
			order.append(n)
	var i := 0
	while i < order.size():
		var zone := state.campaign.region(order[i])
		i += 1
		if zone == null:
			continue
		for n in zone.neighbours:
			if not parent.has(n) and _zone_open(state, status, n, need_fleet):
				parent[n] = zone.id
				order.append(n)
	return {"ordine": order, "padre": parent}


## `need_fleet` vero: serve una flotta propria e nessuna ostile. Falso (agenti che viaggiano senza navi): basta che la zona
## non sia chiusa da una flotta nemica, ma gli oceani (`is_ocean`) restano fuori: si attraversano solo con una rotta tutta di
## flotte proprie (ricerca con `need_fleet` vero, ADR-081), come le truppe.
static func _zone_open(state: GameState, status: Dictionary, zone_id: String, need_fleet: bool = true) -> bool:
	var region := state.campaign.region(zone_id)
	if region == null or not region.is_sea:
		return false
	var zone_state := int(status.get(region.id, ZONE_NO_FLEET))
	if need_fleet:
		return zone_state == ZONE_PASSABLE
	return (zone_state == ZONE_PASSABLE or zone_state == ZONE_NO_FLEET) and not is_ocean(state, region.id)


## Vero se la zona di mare e' un oceano (`[flotte] oceani` di scontri.cfg; richiesta di Federico del 16/11/2026): gli agenti
## lo attraversano solo con una flotta propria nella zona, come le truppe. Sulla mappa d'Europa nessuna zona e' oceano.
static func is_ocean(state: GameState, zone_id: String) -> bool:
	return state.rules.combat.oceans.has(zone_id)


## Vero se la mappa della partita ha almeno un oceano (sulla mappa d'Europa no).
static func map_has_oceans(state: GameState) -> bool:
	for id in state.rules.combat.oceans:
		if state.campaign.region(str(id)) != null:
			return true
	return false


## Serve una flotta propria in ogni zona della catena? Sempre per le truppe; per gli agenti solo se
## `[flotte] agenti_senza_navi` di scontri.cfg e' spento (richiesta di Federico dell'11/11/2026, ADR-034).
static func _needs_fleet(state: GameState, troops: bool) -> bool:
	return troops or not state.rules.combat.agents_free_sea


# --- assedi ------------------------------------------------------------------------------------


## Controlla se l'esercito puo' ricevere l'ordine di assalto: deve essere dell'assediante, fermo
## (senza percorso), in una regione dove c'e' un assedio suo. Solo controllo.
## Se non si puo' "errore" lo spiega; se l'assalto e' gia' ordinato "gia_ordinato" e' vero.
static func can_order_assault(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	if army.is_fleet:
		return failure(Lang.t("Le flotte non assaltano i castelli"))
	if army.in_castle:
		return failure(Lang.t("L'esercito %d e' nel castello") % army_id)
	var siege := state.siege_in(army.region)
	if siege == null or siege.faction != army.faction:
		return failure(Lang.t("L'esercito %d non sta assediando un castello") % army_id)
	if not army.path.is_empty():
		return failure(Lang.t("L'esercito %d ha un ordine di movimento: annullalo per assaltare") % army_id)
	if army.assault_ordered:
		var again := failure(Lang.t("L'assalto e' gia' ordinato"))
		again["gia_ordinato"] = true
		return again
	return success({"regione": siege.region, "gia_ordinato": false})


## Ordina l'assalto al castello: a fine anno l'assediante assalta invece di attendere. L'ordine vale
## per tutti gli eserciti assedianti della regione (partecipano tutti all'assalto).
static func order_assault(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var check := can_order_assault(state, faction_id, army_id)
	if not bool(check["ok"]):
		return check
	_set_assault(state, state.army(army_id).region, state.army(army_id).faction, true)
	return success({"regione": check["regione"]})


## Annulla l'ordine di assalto (dell'intero assedio).
static func cancel_assault(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	if not army.assault_ordered:
		return failure(Lang.t("Nessun assalto ordinato per l'esercito %d") % army_id)
	_set_assault(state, army.region, army.faction, false)
	return success({"regione": army.region})


static func _set_assault(state: GameState, region_id: String, faction_id: String, ordered: bool) -> void:
	for a in state.armies_in(region_id):
		if a.faction == faction_id and not a.is_fleet and not a.in_castle:
			a.assault_ordered = ordered


# --- guarnigione (richiesta di Federico) -------------------------------------


## Controlla se l'esercito puo' barricarsi nel castello della provincia in cui si trova: provincia propria con un
## castello, esercito di terra fuori dal castello e posto nella guarnigione (cavalleria doppia, massimo dalle regole).
## E' la scelta dell'originale di ritirarsi nel castello quando arriva il nemico: se a fine anno nessun nemico assedia,
## la guarnigione esce da sola (WarProcessor.refresh_sieges). Esito: "regione", "livello" del castello.
static func can_enter_castle(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	if army.is_fleet:
		return failure(Lang.t("Le flotte non entrano nei castelli"))
	if army.in_castle:
		return failure(Lang.t("L'esercito %d e' gia' nel castello") % army_id)
	var province := state.province(army.region)
	if province == null or province.owner != army.faction:
		return failure(Lang.t("Ci si barrica solo nel castello di una provincia propria"))
	var level := Combat.castle_level(state, army.region)
	if level <= 0:
		return failure(Lang.t("La provincia non ha un castello"))
	var room := Combat.garrison_capacity(state, army.region)
	if Combat.garrison_load(state, army.region) + Combat.garrison_weight(state, army) > room:
		return failure(_no_room_text(state, army.region))
	return success({"regione": army.region, "livello": level})


## Barrica l'esercito nel castello: l'eventuale ordine di movimento cade. Gli eserciti nemici che arrivano lo assediano
## invece di combattere in campo.
static func enter_castle(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var check := can_enter_castle(state, faction_id, army_id)
	if not bool(check["ok"]):
		return check
	var army := state.army(army_id)
	army.in_castle = true
	army.map_spot = Vector2.INF   # dentro il castello la pedina sta davanti al castello
	army.map_spot_region = ""
	army.path = PackedStringArray()
	army.sea_route = PackedStringArray()
	army.pending_conflict = ""
	army.assault_ordered = false
	return check


## Controlla se l'esercito puo' barricarsi almeno in parte nel castello della provincia in cui si trova (le stesse condizioni
## di can_enter_castle, ma basta che entri una pila). Solo controllo. Esito: "dentro" e "fuori" (pile), "regione", "livello".
static func can_garrison_castle(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	var split := _garrison_split(state, army)
	var keep: PackedInt32Array = split["dentro"]
	var check := can_enter_castle(state, faction_id, army_id)
	if not bool(check["ok"]) and not (str(check["errore"]).contains(Lang.t("Nel castello non c'e' posto")) and not keep.is_empty()):
		return check
	if keep.is_empty():
		return failure(_no_room_text(state, army.region))
	var level := Combat.castle_level(state, army.region)
	return success({"regione": army.region, "livello": level, "dentro": keep.size(), "fuori": (split["fuori"] as PackedInt32Array).size()})


## Barrica nel castello della provincia propria in cui si trova l'esercito le pile che ci stanno (trascinamento sul castello,
## richiesta di Federico del 2026-11-10): nell'ordine dell'esercito, saltando quelle che non entrano (la cavalleria conta
## doppio). Se non entrano tutte, le altre restano fuori in un esercito nuovo (fermo, senza comandante); il comandante resta
## con la parte che si barrica. Esito: "dentro" e "fuori" (pile), "rimasto_fuori" (id dell'esercito fuori, 0 se nessuno),
## "regione", "livello".
static func garrison_castle(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var check := can_garrison_castle(state, faction_id, army_id)
	if not bool(check["ok"]):
		return check
	var army := state.army(army_id)
	var leave: PackedInt32Array = _garrison_split(state, army)["fuori"]
	var outside_id := 0
	if not leave.is_empty():
		var split := split_army(state, faction_id, army_id, leave)
		if not bool(split["ok"]):
			return split
		outside_id = int(split["esercito"])
	var entered := enter_castle(state, faction_id, army_id)
	if not bool(entered["ok"]):
		return entered
	entered["dentro"] = army.stacks.size()
	entered["fuori"] = leave.size()
	entered["rimasto_fuori"] = outside_id
	return entered


## Indici delle pile dell'esercito che entrano nel castello della sua regione ("dentro") e di quelle che restano fuori
## ("fuori"), nell'ordine dell'esercito, con i posti ancora liberi.
static func _garrison_split(state: GameState, army: Army) -> Dictionary:
	var free := Combat.garrison_capacity(state, army.region) - Combat.garrison_load(state, army.region)
	var keep := PackedInt32Array()
	var leave := PackedInt32Array()
	var used := 0
	for i in army.stacks.size():
		var w := _garrison_stack_weight(state, army.stacks[i], army.region)
		if used + w <= free:
			keep.append(i)
			used += w
		else:
			leave.append(i)
	return {"dentro": keep, "fuori": leave}


static func _garrison_stack_weight(state: GameState, stack: UnitStack, region_id: String) -> int:
	var unit: UnitType = state.units.get_unit(stack.unit_id)
	return Combat.cavalry_weight(state, region_id) if unit != null and unit.is_cavalry() else 1


## Messaggio di castello pieno: nelle fortezze ogni unita' conta uno (26/11/2026).
static func _no_room_text(state: GameState, region_id: String) -> String:
	var room := Combat.garrison_capacity(state, region_id)
	if Combat.is_fortress(state, region_id):
		return Lang.t("Nel castello non c'e' posto: al massimo %d unita' nella fortezza") % room
	return Lang.t("Nel castello non c'e' posto: al massimo %d (la cavalleria conta doppio)") % room


## Trascinamento sul castello di una propria provincia diversa da quella dell'esercito: ordine di movimento verso
## `region_id` e, all'arrivo, barricata con le pile che ci stanno (`TurnProcessor._garrison_arrivals`). Esito: gli stessi
## campi di `order_move`.
static func order_garrison_move(state: GameState, faction_id: String, army_id: int, region_id: String) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	if army.is_fleet:
		return failure(Lang.t("Le flotte non entrano nei castelli"))
	var key := SimUtil.norm(region_id)
	if key == army.region:
		return failure(Lang.t("L'esercito e' gia' in %s: si barrica subito") % key)
	var province := state.province(key)
	if province == null or province.owner != army.faction:
		return failure(Lang.t("Ci si barrica solo nel castello di una provincia propria"))
	if Combat.castle_level(state, key) <= 0:
		return failure(Lang.t("La provincia non ha un castello"))
	var moved := order_move(state, faction_id, army_id, PackedStringArray([key]))
	if not bool(moved["ok"]):
		return moved
	army.garrison_on_arrival = true
	return moved


## Fa uscire l'esercito dal castello, se non e' assediato.
static func leave_castle(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id])
	if not army.in_castle:
		return failure(Lang.t("L'esercito %d non e' nel castello") % army_id)
	if state.is_besieged(army.region):
		return failure(Lang.t("L'esercito %d e' assediato e non puo' uscire dal castello") % army_id)
	army.in_castle = false
	return success({"regione": army.region})


# --- personaggi (fase 4a) ----------------------------------------------------


## Assegna a un personaggio il titolo di governatore di una provincia propria. Chi la governava lo perde
## (con il calo di lealta' della revoca); se il personaggio governava un'altra provincia la lascia. Il capo,
## i minorenni e le principesse non governano. Eventi EV_TITLE_CHANGED. Esito: "provincia", "personaggio".
static func assign_title(state: GameState, faction_id: String, character_id: int, province_id: String) -> Dictionary:
	var problem := _check_owned_province(state, faction_id, province_id)
	if problem != "":
		return failure(problem)
	var c := _own_character(state, faction_id, character_id)
	if c == null:
		return failure(Lang.t("Personaggio sconosciuto o non di %s: %d") % [faction_id, character_id])
	if c.role == Character.ROLE_LEADER:
		return failure(Lang.t("Il capo non puo' ricevere un titolo di governatore"))
	if not c.can_command(state.rules.dynasty, state.year):
		return failure(Lang.t("%s non puo' governare (minorenne o principessa)") % c.full_name())
	var key := SimUtil.norm(province_id)
	if c.title == key:
		return failure(Lang.t("%s governa gia' %s") % [c.full_name(), key])
	DynastyProcessor.assign_title(state, c, key)
	return success({"provincia": key, "personaggio": c.id})


## Toglie il titolo a un personaggio della fazione: la lealta' cala di `calo_lealta_revoca`.
## Eventi EV_TITLE_CHANGED. Esito: "provincia", "personaggio".
static func revoke_title(state: GameState, faction_id: String, character_id: int) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	var c := _own_character(state, faction.id, character_id)
	if c == null:
		return failure(Lang.t("Personaggio sconosciuto o non di %s: %d") % [faction_id, character_id])
	if c.title == "":
		return failure(Lang.t("%s non ha un titolo") % c.full_name())
	var province_id := c.title
	DynastyProcessor.release_title(state, c, "revocato", true)
	return success({"provincia": province_id, "personaggio": c.id})


## Assegna a un personaggio la carica di Stato legata a un edificio (`AddOffice`, manuale p25). La fazione deve avere
## l'edificio in una sua provincia; chi deteneva la carica la perde (calo di lealta' della revoca) e chi ne aveva un'altra
## la lascia. Il capo, i minorenni e le principesse non ricevono cariche. Eventi EV_OFFICE_CHANGED.
## Esito: "edificio", "personaggio", "provincia" (dove compare la carica).
static func assign_office(state: GameState, faction_id: String, character_id: int, building: String) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	var b := building.strip_edges().to_lower()
	if state.campaign.office_for(faction.id, b) == null:
		return failure(Lang.t("%s non ha una carica legata a %s") % [faction.id, b])
	var seat := DynastyProcessor.office_seat(state, faction.id, b)
	if seat == "":
		return failure(Lang.t("La carica si sblocca costruendo %s") % b)
	var c := _own_character(state, faction.id, character_id)
	if c == null:
		return failure(Lang.t("Personaggio sconosciuto o non di %s: %d") % [faction_id, character_id])
	if c.role == Character.ROLE_LEADER:
		return failure(Lang.t("Il capo non puo' ricevere una carica"))
	if not c.can_command(state.rules.dynasty, state.year):
		return failure(Lang.t("%s non puo' ricevere cariche (minorenne o principessa)") % c.full_name())
	if c.office == b:
		return failure(Lang.t("%s detiene gia' questa carica") % c.full_name())
	DynastyProcessor.assign_office(state, c, b)
	return success({"edificio": b, "personaggio": c.id, "provincia": seat})


## Toglie la carica di Stato a un personaggio della fazione: la lealta' cala di `calo_lealta_revoca`.
## Eventi EV_OFFICE_CHANGED. Esito: "edificio", "personaggio".
static func revoke_office(state: GameState, faction_id: String, character_id: int) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	var c := _own_character(state, faction.id, character_id)
	if c == null:
		return failure(Lang.t("Personaggio sconosciuto o non di %s: %d") % [faction_id, character_id])
	if c.office == "":
		return failure(Lang.t("%s non ha una carica") % c.full_name())
	var b := c.office
	DynastyProcessor.release_office(state, c, "revocato", true)
	return success({"edificio": b, "personaggio": c.id})


## Mette un personaggio al comando di un esercito o di una flotta della fazione. Il personaggio deve trovarsi
## nella stessa regione dell'esercito ed essere maggiorenne e non una principessa; il comandante di un esercito
## guidato dal capo non si sostituisce. Se il nuovo comandante guidava un altro esercito, i due si scambiano:
## il vecchio comandante prende l'altro esercito. Esito: "esercito", "personaggio", "precedente" (0 = nessuno).
static func set_commander(state: GameState, faction_id: String, army_id: int, character_id: int) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	var a := state.army(army_id)
	if a == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	if a.faction != faction.id:
		return failure(Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction.id])
	var c := _own_character(state, faction.id, character_id)
	if c == null:
		return failure(Lang.t("Personaggio sconosciuto o non di %s: %d") % [faction_id, character_id])
	if not c.can_command(state.rules.dynasty, state.year):
		return failure(Lang.t("%s non puo' comandare (minorenne o principessa)") % c.full_name())
	if c.army == army_id:
		return failure(Lang.t("%s comanda gia' l'esercito %d") % [c.full_name(), army_id])
	if state.character_region(c) != a.region:
		return failure(Lang.t("%s non si trova in %s") % [c.full_name(), a.region])
	var old := state.commander_of(army_id)
	if old != null and old.role == Character.ROLE_LEADER:
		return failure(Lang.t("Il capo non si puo' sostituire al comando dell'esercito %d") % army_id)
	var other_army := c.army
	var previous := 0
	if old != null:
		previous = old.id
		old.army = other_army
		old.region = a.region
	c.army = army_id
	c.region = a.region
	return success({"esercito": army_id, "personaggio": c.id, "precedente": previous})


static func _own_character(state: GameState, faction_id: String, character_id: int) -> Character:
	var c := state.character(character_id)
	if c == null or not c.alive or c.faction != SimUtil.norm(faction_id):
		return null
	return c


# --- agenti (fase 5a) ----------------------------------------------------------


## Motivo per cui l'agente non e' un agente della fazione ("" se lo e').
static func _agent_problem(state: GameState, faction_id: String, agent_id: int) -> String:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id
	var agent := state.agent(agent_id)
	if agent == null:
		return Lang.t("Agente sconosciuto: %d") % agent_id
	if agent.faction != faction.id:
		return Lang.t("L'agente %d non appartiene a %s") % [agent_id, faction_id]
	return ""


## Ordina il movimento di un agente lungo `path` (regioni di terra: la prima confina con la posizione attuale e ogni
## passo con il precedente; si muove di una regione all'anno come gli eserciti). Un solo passo non confinante e' un
## trasporto via mare con le stesse regole e funzioni degli eserciti (`sea_route`): l'esito ha allora "via_mare" e
## "catena". Gli agenti entrano in territorio altrui senza dichiarare guerra. L'ordine annulla la missione.
## Un solo passo verso una provincia fuori portata quest'anno e' un viaggio (richiesta del 2026-11-13, `AgentTravel`):
## l'agente parte per la tappa del primo anno e prosegue da solo; l'esito ha allora "viaggio", "destinazione", "anni"
## (e "via_mare", "catena" se la prima tappa e' per mare).
## Esito: "passi".
static func order_agent_move(state: GameState, faction_id: String, agent_id: int, path: PackedStringArray) -> Dictionary:
	var problem := _agent_problem(state, faction_id, agent_id)
	if problem != "":
		return failure(problem)
	var agent := state.agent(agent_id)
	if not state.proposal_of_agent(agent_id).is_empty():
		return failure(Lang.t("L'agente %d aspetta la risposta a una proposta e non si muove") % agent_id)
	if path.is_empty():
		return failure(Lang.t("Percorso vuoto"))
	var clean := PackedStringArray()
	var chain := PackedStringArray()
	var previous: CampaignData.Region = state.campaign.region(agent.region)
	if previous == null:
		return failure(Lang.t("L'agente %d e' in una regione sconosciuta (%s)") % [agent_id, agent.region])
	for step in path:
		var next: CampaignData.Region = state.campaign.region(step)
		if next == null:
			return failure(Lang.t("Regione sconosciuta nel percorso: %s") % step)
		if next.is_sea:
			return failure(Lang.t("Gli agenti si muovono solo a terra (%s e' mare)") % next.id)
		if not previous.neighbours.has(next.id):
			if path.size() == 1:
				chain = sea_route(state, faction_id, previous.id, next.id, false)
			if chain.is_empty():
				if path.size() == 1:
					return _order_agent_journey(state, faction_id, agent, next.id)
				return failure(Lang.t("%s non confina con %s") % [next.id, previous.id])
		clean.append(next.id)
		previous = next
	agent.path = clean
	agent.sea_route = chain
	agent.destination = ""
	agent.mission = {}
	var result := {"passi": clean.size()}
	if not chain.is_empty():
		result["via_mare"] = true
		result["catena"] = Array(chain)
	return success(result)


## Viaggio di piu' anni verso `target_id` (vedi `order_agent_move`). Fallisce se nessun percorso ci arriva.
static func _order_agent_journey(state: GameState, faction_id: String, agent: AgentState, target_id: String) -> Dictionary:
	var legs := AgentTravel.plan(state, faction_id, agent.region, target_id)
	if legs.is_empty():
		var reason := sea_transport_problem(state, faction_id, agent.region, target_id, false)
		return failure(Lang.t("%s non e' raggiungibile da %s: nessun percorso a piedi o via mare%s") % [
			target_id, agent.region, (" (%s)" % reason) if reason != "" else ""])
	var first: Dictionary = legs[0]
	var chain: PackedStringArray = first["catena"]
	agent.path = PackedStringArray([str(first["regione"])])
	agent.sea_route = chain
	agent.destination = target_id
	agent.mission = {}
	var result := {"passi": 1, "viaggio": true, "destinazione": target_id, "anni": legs.size(), "tappa": str(first["regione"])}
	if not chain.is_empty():
		result["via_mare"] = true
		result["catena"] = Array(chain)
	return success(result)


## Annulla il movimento in corso di un agente (e la missione, se l'agente si stava avvicinando al bersaglio).
static func cancel_agent_move(state: GameState, faction_id: String, agent_id: int) -> Dictionary:
	var problem := _agent_problem(state, faction_id, agent_id)
	if problem != "":
		return failure(problem)
	var agent := state.agent(agent_id)
	agent.path = PackedStringArray()
	agent.sea_route = PackedStringArray()
	agent.destination = ""
	if bool(agent.mission.get("avvicinamento", false)):
		agent.mission = {}
	return success()


## Ordina una missione (vedi `AgentMissions`): `kind` e `target` come nelle voci di `mission_options`. Il bersaglio
## deve stare nella regione dell'agente o in una confinante; in questo caso l'agente ci va prima (il suo percorso
## diventa quella regione) e la missione si risolve nel fine anno in cui e' arrivato. Una missione per agente: un
## nuovo ordine sostituisce il precedente. Esito: "tipo", "bersaglio", "regione", "probabilita", "prezzo" (corruzione).
static func order_mission(state: GameState, faction_id: String, agent_id: int, kind: String, target: Variant) -> Dictionary:
	var problem := _agent_problem(state, faction_id, agent_id)
	if problem != "":
		return failure(problem)
	var agent := state.agent(agent_id)
	if not state.proposal_of_agent(agent_id).is_empty():
		return failure(Lang.t("L'agente %d aspetta la risposta a una proposta e non ha altre missioni") % agent_id)
	var check := AgentMissions.validate(state, agent, kind, target)
	if not bool(check["ok"]):
		return failure(str(check["errore"]))
	var region_id := str(check["regione"])
	var clean: Variant = AgentMissions.normalize_target(kind, target)
	var approach := region_id != agent.region
	agent.path = PackedStringArray([region_id]) if approach else PackedStringArray()
	agent.sea_route = PackedStringArray()
	agent.destination = ""
	agent.mission = {"tipo": kind, "bersaglio": clean, "regione": region_id, "avvicinamento": approach}
	var price := 0
	if kind == AgentMissions.BRIBE:
		price = AgentMissions.bribe_price(state, state.army(int(clean)))
	return success({
		"tipo": kind,
		"bersaglio": clean,
		"regione": region_id,
		"probabilita": AgentMissions.chance(state, agent, kind, clean),
		"prezzo": price,
	})


## Annulla la missione di un agente (e il suo avvicinamento al bersaglio).
static func cancel_mission(state: GameState, faction_id: String, agent_id: int) -> Dictionary:
	var problem := _agent_problem(state, faction_id, agent_id)
	if problem != "":
		return failure(problem)
	var agent := state.agent(agent_id)
	if not agent.has_mission():
		return failure(Lang.t("L'agente %d non ha una missione") % agent_id)
	if bool(agent.mission.get("avvicinamento", false)):
		agent.path = PackedStringArray()
		agent.sea_route = PackedStringArray()
	agent.mission = {}
	return success()


## Anteprima per l'interfaccia: missioni valide dell'agente con bersagli, probabilita' e prezzo (vedi
## `AgentMissions.options`). Solo controllo. Esito: "agente", "missioni" (Array di Dictionary).
static func mission_options(state: GameState, faction_id: String, agent_id: int) -> Dictionary:
	var problem := _agent_problem(state, faction_id, agent_id)
	if problem != "":
		return failure(problem)
	var agent := state.agent(agent_id)
	var list: Array = AgentMissions.options(state, agent)
	return success({"agente": agent_id, "missioni": list})


## Prezzo della corruzione di un esercito (PROVVISORIA, vedi `AgentMissions.bribe_price`). Solo calcolo.
## Esito: "esercito", "prezzo", "comandante" (id, 0 = nessuno), "lealta" (del comandante) e "corruttibile" (falso per
## flotte e per eserciti del capo o dell'erede, con "motivo").
static func bribe_price(state: GameState, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito sconosciuto: %d") % army_id)
	var c := state.commander_of(army_id)
	var reason := AgentMissions.bribe_problem(state, "", army)
	var result := {
		"esercito": army_id,
		"prezzo": AgentMissions.bribe_price(state, army),
		"comandante": c.id if c != null else 0,
		"lealta": c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign) if c != null else 0,
		"corruttibile": reason == "",
	}
	if reason != "":
		result["motivo"] = reason
	return success(result)


# --- prigionieri (ADR-073) ------------------------------------------------------------------------


## Decisione del vincitore sui prigionieri della voce `prisoner_id` (PrisonerProcessor): `choice` = "libera", "riscatto"
## (chi ha perso risponde subito se e' dell'IA, altrimenti la richiesta resta in attesa della sua risposta) o "giustizia".
## Esito: "id", "scelta", "esito" (campo «esito» dell'ultimo EV_PRISONERS), "testo".
static func decide_prisoners(state: GameState, faction_id: String, prisoner_id: int, choice: String) -> Dictionary:
	var e := PrisonerProcessor.entry_of(state, prisoner_id)
	if e.is_empty():
		return failure(Lang.t("Prigionieri sconosciuti: %d") % prisoner_id)
	if str(e["vincitore"]) != SimUtil.norm(faction_id) or str(e["stato"]) != PrisonerProcessor.STATE_PENDING:
		return failure(Lang.t("Non spetta a %s decidere di questi prigionieri") % faction_id)
	var before := state.events.size()
	if choice == "libera":
		PrisonerProcessor._release(state, e, PrisonerProcessor.OUTCOME_RELEASED)
	elif choice == "riscatto":
		PrisonerProcessor.ask_ransom(state, e)
	elif choice == "giustizia":
		PrisonerProcessor._execute(state, e, PrisonerProcessor.OUTCOME_EXECUTED)
	else:
		return failure(Lang.t("Scelta sconosciuta: %s") % choice)
	return success(_prisoner_outcome(state, before, prisoner_id, choice))


## Risposta di chi ha perso alla richiesta di riscatto: pagando (anche a debito) i prigionieri tornano nella sua provincia
## piu' vicina; rifiutando sono giustiziati.
static func answer_ransom(state: GameState, faction_id: String, prisoner_id: int, pay: bool) -> Dictionary:
	var e := PrisonerProcessor.entry_of(state, prisoner_id)
	if e.is_empty():
		return failure(Lang.t("Prigionieri sconosciuti: %d") % prisoner_id)
	if str(e["perdente"]) != SimUtil.norm(faction_id) or str(e["stato"]) != PrisonerProcessor.STATE_RANSOM:
		return failure(Lang.t("Nessun riscatto chiesto a %s per questi prigionieri") % faction_id)
	var before := state.events.size()
	PrisonerProcessor.answer_ransom(state, e, pay)
	return success(_prisoner_outcome(state, before, prisoner_id, "paga" if pay else "rifiuta"))


static func _prisoner_outcome(state: GameState, before: int, prisoner_id: int, choice: String) -> Dictionary:
	var outcome := ""
	var text := ""
	for i in range(state.events.size() - 1, before - 1, -1):
		var ev: Dictionary = state.events[i]
		if str(ev.get("tipo", "")) == GameState.EV_PRISONERS:
			outcome = str(ev.get("esito", ""))
			text = str(ev.get("testo", ""))
			break
	return {"id": prisoner_id, "scelta": choice, "esito": outcome, "testo": text}


# --- proposte dell'IA al giocatore (fase 7b) -------------------------------------------


## Risposta di un giocatore a una proposta dell'IA (`GameState.pending_proposals`): accettando si applica l'esito come farebbe
## l'accettazione dell'IA (alleanza, tregua o matrimonio, con gli stessi eventi: EV_ALLIANCE_FORMED, EV_TRUCE, EV_MARRIAGE);
## rifiutando, EV_PROPOSAL_REFUSED. La proposta esce dall'elenco e l'agente torna libero (la principessa che sposa lascia la
## partita). Accettare di nuovo non si puo' se nel frattempo la situazione e' cambiata (alleanza tra fazioni non piu' neutrali,
## tregua senza guerra, principessa non piu' in eta'): la proposta cade e il comando fallisce. Esito: "id", "tipo", "da",
## "accettata", "evento" (tipo dell'evento registrato) e "testo".
static func answer_proposal(state: GameState, faction_id: String, proposal_id: int, accept: bool) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	var proposal := state.proposal(proposal_id)
	if proposal.is_empty():
		return failure(Lang.t("Proposta sconosciuta: %d") % proposal_id)
	if str(proposal.get("a", "")) != faction.id:
		return failure(Lang.t("La proposta %d non e' per %s") % [proposal_id, faction_id])
	var kind := str(proposal.get("tipo", ""))
	var from_id := str(proposal.get("da", ""))
	var agent := state.agent(int(proposal.get("agente", 0)))
	var proposer := state.faction(from_id)
	if agent == null or proposer == null or not proposer.alive:
		state.remove_proposal(proposal_id)
		return failure(Lang.t("La proposta %d non e' piu' valida: l'agente o il proponente sono scomparsi") % proposal_id)
	if accept:
		var problem := AgentProcessor.proposal_problem(state, agent, kind, faction.id)
		if problem != "":
			state.remove_proposal(proposal_id)
			return failure(problem)
	state.remove_proposal(proposal_id)
	var before := state.events.size()
	AgentProcessor.settle_proposal(state, agent, kind, faction.id, accept, -1.0)
	var event_type := ""
	var text := ""
	if state.events.size() > before:
		var last: Dictionary = state.events[state.events.size() - 1]
		event_type = str(last.get("tipo", ""))
		text = str(last.get("testo", ""))
	return success({"id": proposal_id, "tipo": kind, "da": from_id, "accettata": accept, "evento": event_type, "testo": text})


# --- crociate e jihad (fase 5c) ------------------------------------------------------


## Motivo per cui l'esercito non e' un esercito crociato della fazione ("" se lo e').
static func _crusade_army_problem(state: GameState, faction_id: String, army_id: int) -> String:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id
	var army := state.army(army_id)
	if army == null:
		return Lang.t("Esercito sconosciuto: %d") % army_id
	if army.faction != faction.id:
		return Lang.t("L'esercito %d non appartiene a %s") % [army_id, faction_id]
	if not army.is_crusade():
		return Lang.t("L'esercito %d non e' un esercito crociato") % army_id
	return ""


## Sceglie il bersaglio di una crociata o di un jihad (`region_id` vuoto = toglie il bersaglio). Validazione
## (`PapacyProcessor.target_problem`): provincia di terra non propria; crociata contro una fazione scomunicata, i ribelli,
## una fazione non cattolica o una provincia a maggioranza eretica; jihad contro una provincia non musulmana che un tempo
## lo era; mai il Papato; mai un alleato o una fazione in tregua. L'esercito dichiara guerra al proprietario solo quando
## entra nel bersaglio, e conquista solo quello. Se l'esercito non ha un percorso e non e' bloccato in un castello
## assediato, riceve il percorso piu' corto per terra (PROVVISORIA; vuoto se il bersaglio si raggiunge solo via mare:
## si ordina allora il movimento con `order_move`). Esito: "esercito", "bersaglio", "genere", "proprietario", "percorso"
## (Array di regioni, vuoto se l'esercito aveva gia' un ordine). L'evento EV_CRUSADE_TARGET esce nel fine anno.
static func set_crusade_target(state: GameState, faction_id: String, army_id: int, region_id: String) -> Dictionary:
	var problem := _crusade_army_problem(state, faction_id, army_id)
	if problem != "":
		return failure(problem)
	var army := state.army(army_id)
	if region_id.strip_edges() == "":
		army.crusade["bersaglio"] = ""
		return success({"esercito": army_id, "bersaglio": "", "genere": army.crusade_kind(), "proprietario": "", "percorso": []})
	var key := SimUtil.norm(region_id)
	var why := PapacyProcessor.target_problem(state, army, key)
	if why != "":
		return failure(why)
	army.crusade["bersaglio"] = key
	var route: Array = []
	if army.path.is_empty() and key != army.region and not (army.in_castle and state.is_besieged(army.region)):
		var found := PapacyProcessor.land_route(state, army.region, key)
		if not found.is_empty():
			army.path = found
			army.sea_route = PackedStringArray()
			army.assault_ordered = false
			route = Array(found)
	return success({
		"esercito": army_id,
		"bersaglio": key,
		"genere": army.crusade_kind(),
		"proprietario": state.province(key).owner,
		"percorso": route,
	})


## Anteprima per l'interfaccia: bersagli validi dell'esercito crociato, in ordine di dichiarazione delle province.
## Esito: "esercito", "genere", "bersaglio" (quello attuale, "" se nessuno), "zelo", "bersagli" (Array di
## {"regione", "nome", "proprietario", "motivo"}; motivo: scomunicato, ribelle, non_cattolico, eretici, musulmana).
## Solo controllo.
static func crusade_targets(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var problem := _crusade_army_problem(state, faction_id, army_id)
	if problem != "":
		return failure(problem)
	var army := state.army(army_id)
	return success({
		"esercito": army_id,
		"genere": army.crusade_kind(),
		"bersaglio": army.crusade_target(),
		"zelo": int(army.crusade.get("zelo", 0)),
		"bersagli": PapacyProcessor.targets_of(state, army),
	})


## Stato papale di una fazione per l'interfaccia (vedi `PapacyProcessor.status`): "scomunicata", "anno", "papato_vivo",
## "papa", "avvertimenti" (Array di {"contro", "anno", "scadenza"}), "crociata" (id dell'esercito, 0 = nessuna), "jihad"
## (id degli eserciti). Solo lettura.
static func papal_status(state: GameState, faction_id: String) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null:
		return failure(Lang.t("Fazione sconosciuta: %s") % faction_id)
	return success(PapacyProcessor.status(state, faction.id))


# --- vittoria (fase 6b) ------------------------------------------------------


## Dopo la vittoria per dominio il giocatore sceglie di continuare a giocare: la partita riprende (fino alla sconfitta o
## alla fine della campagna) e la vittoria non si ripete. Errore se la fazione non e' quella del giocatore o se non c'e' una
## vittoria per dominio in attesa della scelta.
static func continue_after_victory(state: GameState, faction_id: String) -> Dictionary:
	var faction := state.faction(faction_id)
	if faction == null:
		return failure(Lang.t("Fazione sconosciuta: %s") % faction_id)
	if not faction.is_player:
		return failure(Lang.t("Solo la fazione del giocatore puo' scegliere di continuare"))
	var v := state.victory
	if v.outcome != VictoryState.DOMINATION:
		return failure(Lang.t("Nessuna vittoria per dominio da cui continuare"))
	if v.continues:
		return failure(Lang.t("La partita continua gia'"))
	v.continues = true
	return success({"anno": v.year})


# --- regole condivise --------------------------------------------------------


## Vero se la condizione sugli edifici e' soddisfatta dalla provincia: almeno un gruppo (OR)
## i cui token (AND) sono tutti soddisfatti. PROVVISORIA (spec. fase 2): un requisito
## `FAMIGLIA+N` e' soddisfatto da un livello >= N. Token sconosciuto = non soddisfatto.
static func requirements_met(condition: Array[PackedStringArray], province: ProvinceState, table: BuildingProdLoader.BuildingTable) -> bool:
	if condition.is_empty():
		return true
	for group in condition:
		var group_ok := true
		for token in group:
			var lv := table.resolve(token)
			if lv == null or province.level_of(lv.family) < lv.level:
				group_ok = false
				break
		if group_ok:
			return true
	return false


## "CATHOLIC_CULTURE" -> "CATHOLIC": le culture delle unita' (colonna 32) non hanno il suffisso.
## PROVVISORIA (catalogo r.76): si assume che la colonna 32 sia confrontata con la cultura della regione.
static func culture_key(region_culture: String) -> String:
	var c := region_culture.strip_edges().to_upper()
	if c.ends_with("_CULTURE"):
		c = c.substr(0, c.length() - 8)
	return c


## "REL_ISLAMIC" -> "MUSLIM", "REL_CATHOLIC" -> "CATHOLIC": come le religioni dei file edifici.
static func religion_key(faction_religion: String) -> String:
	var r := faction_religion.strip_edges().to_upper()
	if r.begins_with("REL_"):
		r = r.substr(4)
	if r == "ISLAMIC":
		r = "MUSLIM"
	return r


## Religione di cui un culto usa edifici e agenti (richiesta di Federico del 16/11/2026: il Culto Imperiale degli Auror,
## per ora, quelli dei cattolici). Chiave di religione -> chiave di base.
const RELIGION_BASE := {"IMPERIAL": "CATHOLIC"}


## Religione di base di una chiave ("IMPERIAL" -> "CATHOLIC"); le altre restano come sono.
static func religion_base(key: String) -> String:
	return str(RELIGION_BASE.get(key, key))


## Vero se l'edificio con queste religioni (colonna 14) e' della religione `key` o della sua religione di base.
static func building_allows_religion(family: BuildingType, key: String) -> bool:
	return family.religions.has(key) or family.religions.has(religion_base(key))


## PROVVISORIA (catalogo r.72, manuale p34): un edificio con religioni indicate richiede
## che la fazione ne abbia una. Fazione senza religione nei dati = nessun vincolo. Il Culto Imperiale usa gli edifici
## cattolici (`religion_base`).
static func _religion_allows(state: GameState, family: BuildingType, faction_id: String) -> bool:
	if family.religions.is_empty():
		return true
	var cf := state.campaign.faction(faction_id)
	if cf == null or cf.religion == "":
		return true
	return building_allows_religion(family, religion_key(cf.religion))


## Messaggio d'errore se la fazione non e' attiva, la provincia non esiste o non e' sua; "" se va bene.
static func _check_owned_province(state: GameState, faction_id: String, province_id: String) -> String:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id
	var province := state.province(province_id)
	if province == null:
		return Lang.t("Provincia sconosciuta: %s") % province_id
	if province.owner != faction.id:
		return Lang.t("La provincia %s non appartiene a %s") % [province.id, faction.id]
	return ""


# --- dividere e unire gli eserciti --------------------------------------------------------------------------------
# Manuale p30: le pile di un esercito si possono separare in un esercito nuovo nella stessa regione, spostare in un altro
# esercito della stessa fazione nella stessa regione o unire tutte; massimo `max_stacks` pile per esercito. Le pile
# spostate non cambiano (uomini, valore). Il comandante resta con l'esercito di partenza; un esercito nuovo senza
# comandante ne riceve uno a fine anno (DynastyProcessor.ensure_commanders), o il giocatore lo sceglie con set_commander.
# Gli eserciti crociati non si dividono ne' si uniscono (zelo e bersaglio sono dell'esercito intero).


## Controlli comuni: esercito proprio, con pile, non crociato. Restituisce "" o il motivo.
static func _own_army_problem(state: GameState, faction_id: String, army: Army) -> String:
	if army == null:
		return Lang.t("Esercito inesistente")
	if army.faction != SimUtil.norm(faction_id):
		return Lang.t("Non e' un esercito di %s") % faction_id
	if army.stacks.is_empty():
		return Lang.t("L'esercito %d non ha pile") % army.id
	if army.is_crusade():
		return Lang.t("Un esercito crociato non si divide ne' si unisce")
	return ""


## Indici di pile validi, distinti e ordinati (dal piu' grande, per toglierli senza spostare gli altri). Vuoto se non validi.
static func _stack_indices(army: Army, indices: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	for i in indices:
		if i < 0 or i >= army.stacks.size() or seen.has(i):
			return PackedInt32Array()
		seen[i] = true
		out.append(i)
	out.sort()
	out.reverse()
	return out


## Toglie le pile indicate (indici dal piu' grande) e le restituisce nell'ordine originale dell'esercito.
static func _take_stacks(army: Army, desc_indices: PackedInt32Array) -> Array[UnitStack]:
	var taken: Array[UnitStack] = []
	for i in desc_indices:
		taken.push_front(army.stacks[i])
		army.stacks.remove_at(i)
	return taken


## Ankalagon (23/11/2026): la guardia unica del re non si separa da Darkos ne' si congeda. "" se nessuna pila e' legata.
static func _bound_problem(state: GameState, army: Army, order: PackedInt32Array) -> String:
	for i in order:
		if AurorUnits.is_bound_to_king(state, army, army.stacks[i]):
			return Lang.t("%s e' una cosa sola con il suo cavaliere: non si separa dal suo esercito") % UnitTexts.plural_name(army.stacks[i].unit_id)
	return ""


## Separa le pile `indices` dell'esercito in un esercito nuovo nella stessa regione (fermo, senza comandante, nel
## castello se lo era quello di partenza). Deve restare almeno una pila. Esito con "esercito" = id del nuovo.
static func split_army(state: GameState, faction_id: String, army_id: int, indices: PackedInt32Array) -> Dictionary:
	var army := state.army(army_id)
	var problem := _own_army_problem(state, faction_id, army)
	if problem != "":
		return failure(problem)
	var order := _stack_indices(army, indices)
	if order.is_empty():
		return failure(Lang.t("Scegli una o piu' pile valide dell'esercito %d") % army.id)
	if order.size() >= army.stacks.size():
		return failure(Lang.t("Deve restare almeno una pila nell'esercito di partenza"))
	var bound := _bound_problem(state, army, order)
	if bound != "":
		return failure(bound)
	var retrain := RetrainProcessor.cancel_army_orders(state, army.id)   # gli indici delle pile cambiano: ordini rimborsati
	var moved := _take_stacks(army, order)
	var fresh := state.create_army(army.faction, army.region, army.is_fleet)
	fresh.in_castle = army.in_castle
	fresh.from_region = army.from_region
	fresh.arrived_year = army.arrived_year
	for st in moved:
		fresh.stacks.append(st)
	return success(_with_retrain_refund({"esercito": fresh.id, "pile": moved.size()}, retrain))


## Sposta le pile `indices` dall'esercito `from_id` all'esercito `to_id` (stessa fazione, stessa regione, stesso tipo,
## entrambi nel castello o entrambi fuori). Se l'esercito di partenza resta vuoto sparisce e il suo comandante resta
## senza esercito. Esito con "pile" spostate e "rimosso" (vero se l'esercito di partenza e' sparito).
static func transfer_stacks(state: GameState, faction_id: String, from_id: int, to_id: int, indices: PackedInt32Array) -> Dictionary:
	var source := state.army(from_id)
	var target := state.army(to_id)
	var problem := _own_army_problem(state, faction_id, source)
	if problem == "":
		problem = _own_army_problem(state, faction_id, target)
	if problem != "":
		return failure(problem)
	if source.id == target.id:
		return failure(Lang.t("Scegli due eserciti diversi"))
	if source.region != target.region:
		return failure(Lang.t("Gli eserciti devono stare nella stessa regione"))
	if source.is_fleet != target.is_fleet:
		return failure(Lang.t("Truppe e navi non si mescolano"))
	if source.in_castle != target.in_castle:
		return failure(Lang.t("Un esercito e' nel castello e l'altro fuori"))
	var order := _stack_indices(source, indices)
	if order.is_empty():
		return failure(Lang.t("Scegli una o piu' pile valide dell'esercito %d") % source.id)
	var bound := _bound_problem(state, source, order)
	if bound != "":
		return failure(bound)
	if target.stacks.size() + order.size() > state.rules.max_stacks:
		return failure(Lang.t("Troppe pile: un esercito ne ha al massimo %d") % state.rules.max_stacks)
	var retrain := RetrainProcessor.cancel_army_orders(state, source.id)   # gli indici delle pile cambiano: ordini rimborsati
	var moved := _take_stacks(source, order)
	for st in moved:
		target.stacks.append(st)
	var removed := source.stacks.is_empty()
	if removed:
		Admirals.merge_into(source, target)   # ADR-056: resta l'ammiraglio migliore
		var commander := state.commander_of(source.id)
		if commander != null:
			commander.army = 0
		state.remove_army(source)
	return success(_with_retrain_refund({"pile": moved.size(), "rimosso": removed}, retrain))


## Unisce tutto l'esercito `from_id` nell'esercito `to_id` (stesse condizioni di transfer_stacks); `from_id` sparisce.
static func merge_armies(state: GameState, faction_id: String, from_id: int, to_id: int) -> Dictionary:
	var source := state.army(from_id)
	if source == null:
		return failure(Lang.t("Esercito inesistente"))
	var all := PackedInt32Array()
	for i in source.stacks.size():
		all.append(i)
	return transfer_stacks(state, faction_id, from_id, to_id, all)


## Unione trascinando un esercito su un altro proprio (come nell'originale): nella stessa regione si uniscono subito
## (`merge_armies`); in una regione raggiungibile `army_id` riceve l'ordine di movimento e confluisce in `target_id` a fine
## anno, appena arrivato, se c'e' posto (`TurnProcessor._merge_arrivals`). Esito: "subito" (vero se gia' uniti), "pile",
## e per il movimento gli stessi campi di `order_move`.
static func order_merge(state: GameState, faction_id: String, army_id: int, target_id: int) -> Dictionary:
	var source := state.army(army_id)
	var target := state.army(target_id)
	var problem := _own_army_problem(state, faction_id, source)
	if problem == "":
		problem = _own_army_problem(state, faction_id, target)
	if problem != "":
		return failure(problem)
	if source.id == target.id:
		return failure(Lang.t("Scegli due eserciti diversi"))
	if source.is_fleet != target.is_fleet:
		return failure(Lang.t("Truppe e navi non si mescolano"))
	if target.stacks.size() + source.stacks.size() > state.rules.max_stacks:
		return failure(Lang.t("Non c'e' posto: insieme farebbero %d pile, al massimo %d") % [target.stacks.size() + source.stacks.size(), state.rules.max_stacks])
	if source.region == target.region:
		var merged := merge_armies(state, faction_id, source.id, target.id)
		if bool(merged["ok"]):
			merged["subito"] = true
		return merged
	if target.in_castle and state.is_besieged(target.region):
		return failure(Lang.t("L'esercito %d e' assediato nel castello: non si puo' raggiungere") % target.id)
	var moved := order_move(state, faction_id, source.id, PackedStringArray([target.region]))
	if not bool(moved["ok"]):
		return moved
	source.merge_target = target.id
	moved["subito"] = false
	moved["pile"] = source.stacks.size()
	return moved


## Posizione della pedina scelta dal giocatore nella sua regione (`kind` = "esercito" o "agente", `spot` in coordinate
## della mappa). Solo aspetto: non cambia regole ne' ordini. Vector2.INF torna alla posizione automatica.
static func set_piece_spot(state: GameState, faction_id: String, kind: String, piece_id: int, spot: Vector2) -> Dictionary:
	var key := SimUtil.norm(faction_id)
	if kind == "agente":
		var agent := state.agent(piece_id)
		if agent == null or agent.faction != key:
			return failure(Lang.t("Agente sconosciuto o non tuo: %d") % piece_id)
		agent.map_spot = spot
		agent.map_spot_region = agent.region if spot != Vector2.INF else ""
		return success()
	var army := state.army(piece_id)
	if army == null or army.faction != key:
		return failure(Lang.t("Esercito sconosciuto o non tuo: %d") % piece_id)
	army.map_spot = spot
	army.map_spot_region = army.region if spot != Vector2.INF else ""
	return success()


## Eserciti della fazione con cui `army_id` puo' scambiare pile (stessa regione, tipo e posizione nel castello),
## per l'interfaccia.
static func merge_partners(state: GameState, faction_id: String, army_id: int) -> Array[Army]:
	var out: Array[Army] = []
	var army := state.army(army_id)
	if _own_army_problem(state, faction_id, army) != "":
		return out
	for other in state.armies_in(army.region):
		if other.id == army.id or _own_army_problem(state, faction_id, other) != "":
			continue
		if other.is_fleet == army.is_fleet and other.in_castle == army.in_castle:
			out.append(other)
	return out


## Aggiunge all'esito di un comando il rimborso degli ordini di riaddestramento annullati ("rimborso_riaddestramento" e
## "pile_riaddestramento"), solo se ce n'erano.
static func _with_retrain_refund(result: Dictionary, cancelled: Dictionary) -> Dictionary:
	if int(cancelled.get("pile", 0)) > 0:
		result["rimborso_riaddestramento"] = int(cancelled["rimborso"])
		result["pile_riaddestramento"] = int(cancelled["pile"])
	return result


# --- congedo (ADR-031) -------------------------------------------------------------------------------------------
# Richiesta di Federico dell'11/11/2026: sciogliere le unita' che non servono piu' per non pagarne il mantenimento.


## Controlli del congedo: esercito (o flotta) proprio, con pile, non crociato. Restituisce "" o il motivo.
static func disband_problem(state: GameState, faction_id: String, army: Army) -> String:
	if army == null:
		return Lang.t("Esercito inesistente")
	if army.faction != SimUtil.norm(faction_id):
		return Lang.t("Non e' un esercito di %s") % faction_id
	if army.stacks.is_empty():
		return Lang.t("L'esercito %d non ha pile") % army.id
	if army.is_crusade():
		return Lang.t("Un esercito crociato non si congeda: si scioglie da solo quando lo zelo finisce")
	return ""


## Congeda le pile `indices` dell'esercito o della flotta: lasciano subito l'esercito, senza rimborso, e da quest'anno non
## costano piu' mantenimento. Le truppe di terra diventano compagnie di mercenari nella provincia in cui si trovano
## (manuale p26 e p70, `[congedo] diventano_mercenari` in mercenari.cfg); le navi spariscono. Vale ovunque (in marcia, nel castello, in mare) e per ogni pila, mercenari compresi. Si possono
## congedare tutte: l'esercito sparisce e il suo comandante resta senza esercito, come dopo un'unione. Gli ordini di
## riaddestramento dell'esercito sono annullati e rimborsati (gli indici delle pile cambiano). Esito: "pile" e "uomini"
## congedati, "mantenimento" (fiorini l'anno risparmiati), "rimosso" (vero se l'esercito e' sparito), "mercenari"
## (compagnie di mercenari nate dal congedo).
static func disband_stacks(state: GameState, faction_id: String, army_id: int, indices: PackedInt32Array) -> Dictionary:
	var army := state.army(army_id)
	var problem := disband_problem(state, faction_id, army)
	if problem != "":
		return failure(problem)
	var order := _stack_indices(army, indices)
	if order.is_empty():
		return failure(Lang.t("Scegli una o piu' pile valide dell'esercito %d") % army.id)
	var bound := _bound_problem(state, army, order)
	if bound != "":
		return failure(bound)
	var upkeep_before := Economy.faction_upkeep(state, army.faction)
	var retrain := RetrainProcessor.cancel_army_orders(state, army.id)
	var gone := _take_stacks(army, order)
	var men := 0
	for st in gone:
		men += st.men
	var companies := 0 if army.is_fleet else MercenaryProcessor.add_disbanded(state, army.region, gone)
	var removed := army.stacks.is_empty()
	if removed:
		var commander := state.commander_of(army.id)
		if commander != null:
			commander.army = 0
		state.remove_army(army)
	var saved := upkeep_before - Economy.faction_upkeep(state, army.faction)
	return success(_with_retrain_refund({"pile": gone.size(), "uomini": men, "mantenimento": saved, "rimosso": removed, "mercenari": companies}, retrain))


# --- riaddestramento ---------------------------------------------------------------------------------------------
# Meccanica dell'originale (manuale p26): una pila decimata torna all'organico pieno pagando. Regole, costo e limiti in
# `RetrainProcessor` e `RetrainRules` (data/regole/riaddestramento.cfg); l'ordine si paga subito e si applica nel
# reclutamento di fine anno.


## Anteprima per l'interfaccia (solo lettura). Esercito riaddestrabile (proprio, di terra, fermo, in una provincia propria non
## assediata): esito ok con "pile" (una voce per pila: "indice", "unita", "uomini", "pieni", "mancanti", "costo", "si_puo",
## "motivo", "in_riaddestramento"; per una pila gia' ordinata il costo e' quello pagato), "posti" (pile ancora ordinabili
## nella provincia quest'anno) e "ordini" (pile gia' in riaddestramento). Altrimenti ok falso con il motivo.
static func retrain_options(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	var problem := RetrainProcessor.army_problem(state, faction_id, army)
	if problem != "":
		return failure(problem)
	var rt := state.rules.retrain
	var room := maxi(0, rt.max_per_province - RetrainProcessor.orders_in(state, army.region))
	var list: Array = []
	for i in army.stacks.size():
		var st := army.stacks[i]
		var unit := state.units.get_unit(st.unit_id)
		var full := unit.men if unit != null else st.men
		var ordered := RetrainProcessor.order_at(state, army.id, i)
		var why := RetrainProcessor.stack_problem(state, faction_id, army, i)
		var cost := int(ordered["costo"]) if not ordered.is_empty() else RetrainProcessor.stack_cost(state, st)
		if why == "" and room <= 0:
			why = Lang.t("Limite di %d pile riaddestrate nella provincia raggiunto") % rt.max_per_province
		list.append({
			"indice": i,
			"unita": st.unit_id,
			"uomini": st.men,
			"pieni": full,
			"mancanti": maxi(0, full - st.men),
			"costo": cost,
			"si_puo": why == "",
			"motivo": why,
			"in_riaddestramento": not ordered.is_empty(),
		})
	return success({"pile": list, "posti": room, "ordini": RetrainProcessor.orders_of(state, army.id).size()})


## Ordina il riaddestramento delle pile `indices` dell'esercito. Le pile che non si possono riaddestrare (piene, mercenarie,
## ordini militari, non reclutabili qui, gia' in riaddestramento, oltre il limite per provincia) sono saltate: l'esito le
## elenca in "rifiutate" ({"indice", "motivo"}); se nessuna e' accettata il comando fallisce con il primo motivo. Il costo
## totale delle pile accettate e' pagato subito: tesoro insufficiente = rifiuto di tutto. Esito: "pile" (accettate),
## "indici", "costo" (totale), "rifiutate".
static func order_retrain(state: GameState, faction_id: String, army_id: int, indices: PackedInt32Array) -> Dictionary:
	var army := state.army(army_id)
	var problem := RetrainProcessor.army_problem(state, faction_id, army)
	if problem != "":
		return failure(problem)
	var order := _stack_indices(army, indices)
	if order.is_empty():
		return failure(Lang.t("Scegli una o piu' pile valide dell'esercito %d") % army.id)
	order.reverse()   # _stack_indices le da' dalla piu' grande: qui si va in ordine crescente
	var rt := state.rules.retrain
	var room := maxi(0, rt.max_per_province - RetrainProcessor.orders_in(state, army.region))
	var accepted: Array[int] = []
	var rejected: Array = []
	var total := 0
	for i in order:
		var why := RetrainProcessor.stack_problem(state, faction_id, army, i)
		if why == "" and accepted.size() >= room:
			why = Lang.t("Limite di %d pile riaddestrate nella provincia raggiunto") % rt.max_per_province
		if why != "":
			rejected.append({"indice": i, "motivo": why})
			continue
		accepted.append(i)
		total += RetrainProcessor.stack_cost(state, army.stacks[i])
	if accepted.is_empty():
		var first: Dictionary = rejected[0]
		return failure(str(first["motivo"]))
	var faction := state.faction(faction_id)
	if faction.treasury < total:
		return failure(Lang.t("Tesoro insufficiente: servono %d, ci sono %d") % [total, faction.treasury])
	faction.spend(total, FactionState.SPEND_RETRAIN)
	for i in accepted:
		var st := army.stacks[i]
		state.retrain_orders.append({
			"esercito": army.id,
			"fazione": army.faction,
			"provincia": army.region,
			"pila": i,
			"unita": st.unit_id,
			"uomini": st.men,
			"costo": RetrainProcessor.stack_cost(state, st),
			"anno": state.year,
		})
	return success({"pile": accepted.size(), "indici": accepted, "costo": total, "rifiutate": rejected})


## Anteprima del ripristino delle forze (ADR-046, solo lettura): esercito proprio, di terra, fermo, in una provincia propria
## non assediata (RetrainProcessor.army_problem). Esito ok con "indici" (pile da riportare all'organico pieno, in ordine),
## "pile", "uomini" (mancanti), "costo" (totale), "in_corso" (pile gia' in riaddestramento) ed "escluse" ({"indice",
## "motivo"}: pile non piene che non si ripristinano, per esempio oltre il limite se riaddestramento.cfg lo chiede).
static func restore_preview(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	var problem := RetrainProcessor.army_problem(state, faction_id, army)
	if problem != "":
		return failure(problem)
	var rt := state.rules.retrain
	var room := maxi(0, rt.max_per_province - RetrainProcessor.orders_in(state, army.region)) if rt.restore_uses_limit else army.stacks.size()
	var indices: Array[int] = []
	var excluded: Array = []
	var men := 0
	var cost := 0
	for i in army.stacks.size():
		var why := RetrainProcessor.restore_problem(state, faction_id, army, i)
		if why == Lang.t("La pila e' gia' al completo") or why == Lang.t("La pila e' gia' in riaddestramento"):
			continue
		if why == "" and indices.size() >= room:
			why = Lang.t("Limite di %d pile riaddestrate nella provincia raggiunto") % rt.max_per_province
		if why != "":
			excluded.append({"indice": i, "motivo": why})
			continue
		var st := army.stacks[i]
		indices.append(i)
		men += state.units.get_unit(st.unit_id).men - st.men
		cost += RetrainProcessor.stack_cost(state, st)
	return success({"indici": indices, "pile": indices.size(), "uomini": men, "costo": cost,
		"in_corso": RetrainProcessor.orders_of(state, army.id).size(), "escluse": excluded})


## «Ripristina» (richiesta di Federico, 2026-11-13, ADR-046): un clic ordina il riaddestramento di tutte le pile dell'esercito
## che hanno perso uomini; si paga subito e a fine anno tornano all'organico pieno (RetrainProcessor.process_year; se
## l'esercito si muove l'ordine e' rimborsato). Col tesoro che non basta per tutte si ordinano, in ordine, quelle che si possono
## pagare. Esito: "pile", "indici", "uomini", "costo", "rimaste" (pile non pagate), "escluse" (come restore_preview).
static func restore_army(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var preview := restore_preview(state, faction_id, army_id)
	if not bool(preview["ok"]):
		return preview
	var army := state.army(army_id)
	var indices: Array = preview["indici"]
	var excluded: Array = preview["escluse"]
	if indices.is_empty():
		if not excluded.is_empty():
			return failure(str((excluded[0] as Dictionary)["motivo"]))
		if int(preview["in_corso"]) > 0:
			return failure(Lang.t("Le pile che hanno perso uomini sono gia' in riaddestramento"))
		return failure(Lang.t("L'esercito %d e' gia' al pieno delle forze") % army.id)
	var faction := state.faction(faction_id)
	var accepted: Array[int] = []
	var men := 0
	var total := 0
	for item in indices:
		var i := int(item)
		var st := army.stacks[i]
		var cost := RetrainProcessor.stack_cost(state, st)
		if total + cost > faction.treasury:
			continue
		accepted.append(i)
		total += cost
		men += state.units.get_unit(st.unit_id).men - st.men
	if accepted.is_empty():
		return failure(Lang.t("Tesoro insufficiente: servono %d, ci sono %d") % [int(preview["costo"]), faction.treasury])
	faction.spend(total, FactionState.SPEND_RETRAIN)
	for i in accepted:
		var st := army.stacks[i]
		state.retrain_orders.append({
			"esercito": army.id,
			"fazione": army.faction,
			"provincia": army.region,
			"pila": i,
			"unita": st.unit_id,
			"uomini": st.men,
			"costo": RetrainProcessor.stack_cost(state, st),
			"anno": state.year,
			"ripristino": true,
		})
	return success({"pile": accepted.size(), "indici": accepted, "uomini": men, "costo": total,
		"rimaste": indices.size() - accepted.size(), "escluse": excluded})


## Annulla tutti gli ordini di riaddestramento dell'esercito e rimborsa il costo pagato. Esito: "pile" e "rimborso".
static func cancel_retrain(state: GameState, faction_id: String, army_id: int) -> Dictionary:
	var army := state.army(army_id)
	if army == null:
		return failure(Lang.t("Esercito inesistente"))
	if army.faction != SimUtil.norm(faction_id):
		return failure(Lang.t("Non e' un esercito di %s") % faction_id)
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return failure(Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id)
	if RetrainProcessor.orders_of(state, army.id).is_empty():
		return failure(Lang.t("Nessun riaddestramento da annullare per l'esercito %d") % army.id)
	var cancelled := RetrainProcessor.cancel_army_orders(state, army.id)
	return success({"pile": int(cancelled["pile"]), "rimborso": int(cancelled["rimborso"])})


# --- mercenari (fase 8d) -----------------------------------------------------------------------------------------


## Compagnie di mercenari della provincia per la fazione: [{"indice", "unita", "uomini", "valore", "costo", "ok", "errore"}].
static func mercenary_options(state: GameState, faction_id: String, province_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Array = state.mercenaries.get(province_id, [])
	for i in list.size():
		var c: Dictionary = list[i]
		var check := can_hire_mercenary(state, faction_id, province_id, i)
		out.append({"indice": i, "unita": str(c.get("unita", "")), "uomini": int(c.get("uomini", 0)), "valore": int(c.get("valore", 0)),
			"costo": int(check.get("costo", 0)), "ok": bool(check["ok"]), "errore": str(check["errore"])})
	return out


## Si puo' assoldare la compagnia `index` della provincia? {"ok", "errore", "costo"}. Serve la provincia propria, la compagnia,
## il tesoro; le truppe entrano nel primo esercito fermo e non pieno della provincia, o in uno nuovo.
static func can_hire_mercenary(state: GameState, faction_id: String, province_id: String, index: int) -> Dictionary:
	var province := state.province(province_id)
	if province == null:
		return failure(Lang.t("Provincia sconosciuta: %s") % province_id)
	if province.owner != SimUtil.norm(faction_id):
		return failure(Lang.t("Puoi assoldare mercenari solo nelle tue province"))
	var list: Array = state.mercenaries.get(province_id, [])
	if index < 0 or index >= list.size():
		return failure(Lang.t("Questa compagnia di mercenari non c'e' piu'"))
	var c: Dictionary = list[index]
	var unit := state.units.get_unit(str(c.get("unita", "")))
	if unit == null:
		return failure(Lang.t("Unita' sconosciuta: %s") % str(c.get("unita", "")))
	if HistoricalLimits.is_mounted(unit) and not HistoricalLimits.horses_allowed(state, faction_id) \
			and not state.rules.lifts_unit_limits(faction_id, unit):
		return failure(Lang.t("%s non conosce ancora il cavallo: arrivera' con gli europei") % SimUtil.faction_label(faction_id))
	var cost := state.rules.mercenaries.hire_cost(unit.cost)
	var faction := state.faction(faction_id)
	if faction == null or faction.treasury < cost:
		var r := failure(Lang.t("Tesoro insufficiente: servono %d fiorini") % cost)
		r["costo"] = cost
		return r
	return success({"costo": cost})


## Assolda la compagnia: paga, la toglie dalla provincia e la mette in un esercito (pila con `mercenary` vero).
static func hire_mercenary(state: GameState, faction_id: String, province_id: String, index: int) -> Dictionary:
	var check := can_hire_mercenary(state, faction_id, province_id, index)
	if not bool(check["ok"]):
		return check
	var fid := SimUtil.norm(faction_id)
	var list: Array = state.mercenaries[province_id]
	var c: Dictionary = list[index]
	list.remove_at(index)
	if list.is_empty():
		state.mercenaries.erase(province_id)
	var cost := int(check["costo"])
	state.faction(fid).spend(cost, FactionState.SPEND_MERCENARIES)
	var target: Army = null
	for a in state.armies_in(province_id):
		if a.faction == fid and not a.is_fleet and a.path.is_empty() and a.crusade.is_empty() and not a.is_full(state.rules.max_stacks):
			target = a
			break
	if target == null:
		target = state.create_army(fid, province_id, false)
		target.in_castle = state.is_besieged(province_id)
	var st := state.new_stack(fid, str(c.get("unita", "")), int(c.get("uomini", 0)), int(c.get("valore", 0)))
	st.mercenary = true
	target.stacks.append(st)
	state.add_event(GameState.EV_MERCENARY_HIRED, {"fazione": fid, "provincia": province_id, "unita": st.unit_id, "uomini": st.men,
		"costo": cost, "esercito": target.id})
	return success({"costo": cost, "esercito": target.id, "unita": st.unit_id})
