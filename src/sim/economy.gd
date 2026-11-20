class_name Economy
extends RefCounted
## Calcolo del reddito delle province e del mantenimento (fase 2, catalogo sezione Economia).
##
## Reddito di una provincia propria non contesa, per voce, arrotondato all'intero
## (PROVVISORIA: l'arrotondamento al fiorino non e' documentato, catalogo r.34):
##   agricoltura = roundi(SetAttributes x scala annua x terreno x tassa)
##   miniere     = roundi(somma delle rendite dei livelli costruiti x scala miniere)
##   commercio   = roundi(somma merci x moltiplicatore edificio x scala annua x fattore)
## Il commercio (catalogo r.38-r.41, manuale p22) ha tre parti (`trade_breakdown`):
##   locale       = merci della provincia con l'edificio commerciale (anche nell'entroterra, senza porto);
##   marittimo    = per ogni porto straniero raggiunto da una catena di flotte proprie (`trade_partners`), le merci che quel
##                  porto non ha x quota_marittima (servono porto ed edificio commerciale);
##   importazioni = per ogni porto raggiunto, le sue merci che la provincia non ha x quota_importazione (basta il porto).
## Le quote sono PROVVISORIE (economia.cfg). La tassa vale solo per l'agricoltura.
## Acume (fase 4a, manuale p17): agricoltura e commercio sono moltiplicati per
## 1 + 0,10 x acume del governatore della provincia + 0,02 x acume del capo (parametri in personaggi.cfg,
## sezione [economia]); senza personaggi il moltiplicatore e' 1 e nulla cambia. Le miniere non lo usano.
## Fase 6a: gli effetti di durata un anno di disastri e Peste Nera (`ProvinceState.temp_effects`) riducono l'agricoltura
## (chiave `agricoltura`) e tutto il reddito (chiave `reddito`); senza effetti i moltiplicatori valgono 1 e nulla cambia.
## Le merci aggiunte da eventi storici (`ProvinceState.extra_goods`) entrano nella somma del commercio.


## Voci del reddito di una provincia: agricoltura, miniere, commercio, totale, conteso.
## `acumen` e' la tabella di `acumen_table` (vuota = calcolo diretto, piu' lento).
static func province_income(state: GameState, province: ProvinceState, acumen: Dictionary = {}) -> Dictionary:
	var result := {"agricoltura": 0, "miniere": 0, "commercio": 0, "totale": 0, "conteso": false}
	var region: CampaignData.Region = state.campaign.region(province.id)
	if region == null:
		return result
	if is_contested(state, province):
		result["conteso"] = true
		return result
	var rules := state.rules
	var factor := acumen_multiplier(state, province, acumen)
	var income_factor := province.temp_factor(ProvinceState.TEMP_INCOME)
	var traits := rules.traits   # ADR-089: tratti storici della fazione proprietaria
	var farm := roundi(float(region.income) * rules.annual_scale * rules.farm_multiplier(province.level_of(rules.farm_family)) * rules.tax_multiplier(province.tax_level) * factor * province.temp_factor(ProvinceState.TEMP_FARM) * income_factor * traits.farm_factor(province.owner))
	var mines := roundi(float(mine_income(state, province)) * rules.mine_scale * income_factor * traits.mine_factor(province.owner))
	var parts := trade_breakdown(state, province, region, factor)
	var trade := roundi(float(int(parts["locale"]) + int(parts["marittimo"]) + int(parts["importazioni"])) * income_factor * traits.trade_factor(province.owner))
	result["commercio_locale"] = int(parts["locale"])
	result["commercio_marittimo"] = int(parts["marittimo"])
	result["importazioni"] = int(parts["importazioni"])
	result["rotte"] = Array(parts["partner"])
	result["agricoltura"] = farm
	result["miniere"] = mines
	result["commercio"] = trade
	result["totale"] = farm + mines + trade
	return result


## Vero se nella provincia c'e' un esercito di un'altra fazione o un assedio in corso
## (manuale p21: reddito zero per le province assediate o contese).
static func is_contested(state: GameState, province: ProvinceState) -> bool:
	if state.is_besieged(province.id):
		return true
	for a in state.armies_in(province.id):
		if a.faction != province.owner and not a.stacks.is_empty():
			return true
	return false


## Somma delle rendite (colonna 22 del file edifici) dei livelli di miniera costruiti.
static func mine_income(state: GameState, province: ProvinceState) -> int:
	var total := 0
	for family_id in state.rules.mine_families:
		var level := province.level_of(family_id)
		if level <= 0:
			continue
		var family: BuildingType = state.buildings.get_family(family_id)
		if family == null:
			continue
		var lv: BuildingType.Level = family.get_level(level)
		if lv != null:
			total += lv.income
	return total


## Commercio della provincia (somma delle tre parti di `trade_breakdown`), prima degli effetti temporanei.
static func trade_income(state: GameState, province: ProvinceState, region: CampaignData.Region, factor: float = 1.0) -> int:
	var parts := trade_breakdown(state, province, region, factor)
	return int(parts["locale"]) + int(parts["marittimo"]) + int(parts["importazioni"])


## Le tre parti del commercio: {"locale", "marittimo", "importazioni" (fiorini l'anno, arrotondati), "partner" (id delle
## province straniere raggiunte via mare, PackedStringArray)}. `hypothesis` (facoltativo, vedi `trade_partners`) calcola le rotte
## di un'ipotesi invece che delle flotte presenti: lo usa l'IA (ADR-053) con la stessa formula del giocatore.
static func trade_breakdown(state: GameState, province: ProvinceState, region: CampaignData.Region, factor: float = 1.0, hypothesis: Dictionary = {}) -> Dictionary:
	var out := {"locale": 0, "marittimo": 0, "importazioni": 0, "partner": PackedStringArray()}
	var rules := state.rules
	var has_port := region.has_port and province.level_of(rules.port_family) > 0
	var trade_level := 0
	for family_id in rules.trade_families:
		trade_level = maxi(trade_level, province.level_of(family_id))
	var goods := goods_of(state, province, region)
	var scale := rules.annual_scale * rules.trade_factor * factor
	var building := rules.trade_multiplier(trade_level) if trade_level > 0 else 0.0
	if trade_level > 0 and (has_port or rules.local_trade_without_port):
		out["locale"] = roundi(float(_sum(goods)) * building * scale)
	if not has_port or not rules.sea_trade:
		return out
	var partners := trade_partners(state, province, region, hypothesis)
	out["partner"] = partners
	var exports := 0.0
	var imports := 0.0
	for pid in partners:
		var q := state.province(pid)
		var q_region := state.campaign.region(pid)
		var q_goods := goods_of(state, q, q_region)
		var weight := partner_weight(state, q, q_region)
		for g in goods:
			if not q_goods.has(g):
				exports += float(goods[g]) * weight
		for g in q_goods:
			if not goods.has(g):
				imports += float(q_goods[g]) * weight
	if trade_level > 0:
		out["marittimo"] = roundi(exports * building * scale * rules.sea_trade_share)
	out["importazioni"] = roundi(imports * scale * rules.import_share)
	return out


## Quanto rende ogni porto raggiunto dalla provincia (finestra Economia, richiesta di Federico del 2026-11-13): stessa formula
## di `trade_breakdown`, porto per porto. Ogni voce: "provincia", "fazione", "peso" (`partner_weight`), "valore"
## (`partner_value`), "merci" e "importazioni" (fiorini l'anno, non arrotondati: la somma arrotondata e' quella di
## `trade_breakdown`), "fiorini" (le due parti insieme, arrotondate). Ordinate dal porto che rende di piu'; vuoto senza porto
## costruito o senza rotte.
static func trade_partner_details(state: GameState, province: ProvinceState, region: CampaignData.Region, factor: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rules := state.rules
	if region == null or not region.has_port or province.level_of(rules.port_family) <= 0 or not rules.sea_trade:
		return out
	var trade_level := 0
	for family_id in rules.trade_families:
		trade_level = maxi(trade_level, province.level_of(family_id))
	var goods := goods_of(state, province, region)
	var scale := rules.annual_scale * rules.trade_factor * factor
	var building := rules.trade_multiplier(trade_level) if trade_level > 0 else 0.0
	for pid in trade_partners(state, province, region):
		var q := state.province(pid)
		var q_region := state.campaign.region(pid)
		var q_goods := goods_of(state, q, q_region)
		var weight := partner_weight(state, q, q_region)
		var exports := 0.0
		var imports := 0.0
		for g in goods:
			if not q_goods.has(g):
				exports += float(goods[g]) * weight
		for g in q_goods:
			if not goods.has(g):
				imports += float(q_goods[g]) * weight
		var sold := exports * building * scale * rules.sea_trade_share if trade_level > 0 else 0.0
		var taxed := imports * scale * rules.import_share
		out.append({"provincia": pid, "fazione": q.owner, "peso": weight, "valore": partner_value(state, q, q_region),
			"merci": sold, "importazioni": taxed, "fiorini": roundi(sold + taxed), "k": out.size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := float(a["merci"]) + float(a["importazioni"])
		var fb := float(b["merci"]) + float(b["importazioni"])
		return fa > fb or (fa == fb and int(a["k"]) < int(b["k"])))
	return out


## Peso di un porto raggiunto nel commercio marittimo (richiesta di Federico del 2026-11-13, PROVVISORIA): un partner ricco e
## sviluppato compra e vende di piu', uno povero molto meno. `partner_value` / `sea_trade_reference`, tra 0 e
## `sea_trade_max_weight`; con riferimento 0 vale 1 (ogni porto uguale).
static func partner_weight(state: GameState, province: ProvinceState, region: CampaignData.Region) -> float:
	var rules := state.rules
	if rules.sea_trade_reference <= 0.0:
		return 1.0
	return clampf(partner_value(state, province, region) / rules.sea_trade_reference, 0.0, rules.sea_trade_max_weight)


## Valore economico di una provincia per i suoi partner commerciali: agricoltura (rendita base x scala annua x fattorie) +
## miniere + commercio locale (merci x edificio commerciale), senza tasse, acume, effetti temporanei ne' commercio via mare
## (che dipenderebbe a sua volta dai partner).
static func partner_value(state: GameState, province: ProvinceState, region: CampaignData.Region) -> float:
	if province == null or region == null:
		return 0.0
	var rules := state.rules
	var farm := float(region.income) * rules.annual_scale * rules.farm_multiplier(province.level_of(rules.farm_family))
	var mines := float(mine_income(state, province)) * rules.mine_scale
	var trade_level := 0
	for family_id in rules.trade_families:
		trade_level = maxi(trade_level, province.level_of(family_id))
	var local := 0.0
	if trade_level > 0:
		local = float(_sum(goods_of(state, province, region))) * rules.trade_multiplier(trade_level) * rules.annual_scale * rules.trade_factor
	return farm + mines + local


## Merci della provincia con il loro valore (SetTradableGoods e merci aggiunte dagli eventi): id -> valore del file.
static func goods_of(state: GameState, province: ProvinceState, region: CampaignData.Region) -> Dictionary:
	var out := {}
	if region != null:
		for good in region.trade_goods:
			out[good] = int(state.campaign.trade_goods.get(good, 0))
	if province != null:
		for good in province.extra_goods:
			if not out.has(good):
				out[good] = int(state.campaign.trade_goods.get(good, 0))
	return out


static func _sum(goods: Dictionary) -> int:
	var total := 0
	for g in goods:
		total += int(goods[g])
	return total


## Porti stranieri raggiunti dalla provincia via mare (manuale p22): si parte dalle zone di mare confinanti in cui c'e' una
## flotta della fazione e si prosegue di zona confinante in zona confinante finche' ci sono flotte proprie; una zona con una
## flotta di una fazione in guerra e' chiusa (blocco commerciale, manuale p33). Partner = province confinanti con quelle zone,
## di un'altra fazione non in guerra (non i ribelli), con il porto costruito; nell'ordine in cui si incontrano.
## `hypothesis` (ADR-053, «e se presidiassi queste zone?»): "zone" = zone di mare (id -> true) che contano come presidiate da una
## flotta propria; con "solo_ipotesi" vero le flotte proprie presenti non contano; "ignora_guerra" = id di una fazione con cui la
## guerra non chiude ne' zone ne' partner (commercio perso per quella guerra). Le flotte delle altre fazioni in guerra chiudono
## le zone anche nell'ipotesi. Vuoto = le flotte presenti, come sempre.
static func trade_partners(state: GameState, province: ProvinceState, region: CampaignData.Region, hypothesis: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var owner := province.owner
	if owner == "" or region == null:
		return out
	var usable := {}
	var queue: Array[String] = []
	for n in region.neighbours:
		var z := state.campaign.region(n)
		if z != null and z.is_sea and not usable.has(z.id) and _trade_zone_open(state, owner, z.id, hypothesis):
			usable[z.id] = true
			queue.append(z.id)
	var head := 0
	while head < queue.size():
		var zone := state.campaign.region(queue[head])
		head += 1
		for n in zone.neighbours:
			var next := state.campaign.region(n)
			if next == null:
				continue
			if next.is_sea:
				if not usable.has(next.id) and _trade_zone_open(state, owner, next.id, hypothesis):
					usable[next.id] = true
					queue.append(next.id)
				continue
			var q := state.province(next.id)
			if q == null or q.owner == "" or q.owner == owner or q.owner == GameState.REBEL or out.has(q.id):
				continue
			var at_war := state.at_war(owner, q.owner) and q.owner != str(hypothesis.get("ignora_guerra", ""))
			if at_war or not next.has_port or q.level_of(state.rules.port_family) <= 0:
				continue
			out.append(q.id)
	return out


## Zona di mare utile per le rotte della fazione: c'e' una sua flotta e nessuna flotta di una fazione in guerra con lei.
## Con `hypothesis` (vedi `trade_partners`) le zone dell'ipotesi contano come presidiate.
static func _trade_zone_open(state: GameState, faction_id: String, zone_id: String, hypothesis: Dictionary = {}) -> bool:
	var zones: Dictionary = hypothesis.get("zone", {})
	var own := zones.has(zone_id)
	var only_hypothesis := bool(hypothesis.get("solo_ipotesi", false))
	var ignored := str(hypothesis.get("ignora_guerra", ""))
	if only_hypothesis and not own:
		return false   # solo le zone dell'ipotesi contano come presidiate: le altre non servono alle rotte
	for a in state.armies_in(zone_id):
		if not a.is_fleet or a.stacks.is_empty():
			continue
		if a.faction == faction_id:
			if not only_hypothesis:
				own = true
		elif a.faction != ignored and state.at_war(faction_id, a.faction):
			return false
	return own


## Commercio via mare (marittimo + importazioni, fiorini l'anno) di tutte le province della fazione con il porto, con le flotte
## presenti o con l'ipotesi `hypothesis` (vedi `trade_partners`). Stessa formula di `trade_breakdown` (senza acume ne' effetti
## temporanei): l'IA la usa per confrontare piani di zone (ADR-053).
static func sea_trade_of(state: GameState, faction_id: String, hypothesis: Dictionary = {}) -> int:
	var total := 0
	var key := SimUtil.norm(faction_id)
	for p in state.provinces_of(key):
		var region := state.campaign.region(p.id)
		if region == null or not region.has_port or p.level_of(state.rules.port_family) <= 0:
			continue
		var parts := trade_breakdown(state, p, region, 1.0, hypothesis)
		total += int(parts["marittimo"]) + int(parts["importazioni"])
	return total


## Somma dei costi di mantenimento (colonna "Support Cost" del file unita') delle pile di un
## esercito o di una flotta, prima del moltiplicatore di regola. I tipi sconosciuti valgono 0.
static func army_support_sum(state: GameState, army: Army) -> int:
	var total := 0
	var traits := state.rules.traits
	for s in army.stacks:
		var u: UnitType = state.units.get_unit(s.unit_id)
		if u != null:
			# fase 8d: i mercenari costano di piu' (data/regole/mercenari.cfg); ADR-089: tratti della fazione
			var base := roundi(u.support_cost * state.rules.mercenaries.upkeep_factor) if s.mercenary else u.support_cost
			var f := traits.upkeep_factor(army.faction, u)
			total += base if f == 1.0 else roundi(float(base) * f)
	return total


## Mantenimento annuo di tutte le forze di una fazione, arrotondato (PROVVISORIA, catalogo r.43).
static func faction_upkeep(state: GameState, faction_id: String) -> int:
	var total := 0
	for a in state.armies_of(faction_id):
		total += army_support_sum(state, a)
	return roundi(float(total) * state.rules.upkeep_multiplier)


## Acume del governatore di ogni provincia e del capo di ogni fazione (valori efficaci), da calcolare una volta
## per fine anno: {"governatori": {provincia: acume}, "capi": {fazione: acume}}. Vuota senza personaggi.
static func acumen_table(state: GameState) -> Dictionary:
	var governors := {}
	var leaders := {}
	for c in state.characters:
		if not c.alive:
			continue
		var value := c.effective(Character.ATTR_ACUMEN, state.rules, state.campaign)
		if c.title != "":
			governors[c.title] = value
		if c.role == Character.ROLE_LEADER:
			leaders[c.faction] = value
	if governors.is_empty() and leaders.is_empty():
		return {}
	return {"governatori": governors, "capi": leaders}


## Moltiplicatore di agricoltura e commercio per l'acume (1,0 senza personaggi). Se la tabella e' vuota
## il valore si cerca direttamente tra i personaggi.
static func acumen_multiplier(state: GameState, province: ProvinceState, table: Dictionary = {}) -> float:
	if state.characters.is_empty():
		return 1.0
	var d := state.rules.dynasty
	var governor_value := 0
	var king_value := 0
	if table.is_empty():
		var g := state.governor_of(province.id)
		if g != null and g.faction == province.owner:
			governor_value = g.effective(Character.ATTR_ACUMEN, state.rules, state.campaign)
		var k := state.leader_of(province.owner)
		if k != null:
			king_value = k.effective(Character.ATTR_ACUMEN, state.rules, state.campaign)
	else:
		var governors: Dictionary = table.get("governatori", {})
		var leaders: Dictionary = table.get("capi", {})
		governor_value = int(governors.get(province.id, 0))
		king_value = int(leaders.get(province.owner, 0))
	return 1.0 + d.governor_acumen * float(governor_value) + d.king_acumen * float(king_value)
