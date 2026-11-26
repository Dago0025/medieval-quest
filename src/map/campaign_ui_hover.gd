class_name CampaignUiHover
extends RefCounted
## Informazioni al passaggio del mouse sulla mappa (richiesta di Federico, 2026-11-13, come nell'originale): sulla pedina di un
## esercito, di una flotta o di un agente chi e' e se e' vostro, nemico, alleato, in tregua o neutrale; su una zona di mare se
## le acque sono libere, vostre, nemiche o chiuse da un blocco navale ai vostri trasporti; su una provincia di chi e'.
## Funzioni pure sullo stato (ADR-003): il riquadro lo disegna scenes/campaign_map.gd. Con `rich` vero i testi sono in BBCode,
## con i colori del rapporto (richiesta di Federico, 2026-11-13): rosso i nemici, blu i neutrali, verde gli alleati.

const COLOR_ENEMY := "b3261e"     ## rosso: nemici (guerra, ribelli)
const COLOR_NEUTRAL := "1f5fbf"   ## blu: neutrali (pace, tregua)
const COLOR_ALLY := "2e7d32"      ## verde: alleati


## Tipo di rapporto per il colore: "nemico" (guerra, ribelli), "neutrale" (pace, tregua), "alleato", "" per la propria fazione.
static func relation_kind(state: GameState, player_id: String, faction_id: String) -> String:
	var me := SimUtil.norm(player_id)
	var other := SimUtil.norm(faction_id)
	if other == me or other == "":
		return ""
	if other == GameState.REBEL or state.at_war(me, other):
		return "nemico"
	if state.is_allied(me, other):
		return "alleato"
	return "neutrale"


## `text` nel colore del rapporto se `rich`, altrimenti com'e'.
static func paint(text: String, kind: String, rich: bool) -> String:
	if not rich or text == "":
		return text
	match kind:
		"nemico":
			return "[color=#%s]%s[/color]" % [COLOR_ENEMY, text]
		"neutrale":
			return "[color=#%s]%s[/color]" % [COLOR_NEUTRAL, text]
		"alleato":
			return "[color=#%s]%s[/color]" % [COLOR_ALLY, text]
	return text


## Rapporto con la fazione `faction_id` visto da `player_id`, in una riga: «In guerra con voi», «Alleati», «Tregua fino al
## 1012», «Neutrali, in pace»; «Ribelli» per i ribelli (sempre in guerra con tutti); vuoto per la propria fazione.
static func relation_line(state: GameState, player_id: String, faction_id: String) -> String:
	var me := SimUtil.norm(player_id)
	var other := SimUtil.norm(faction_id)
	if other == me:
		return ""
	if other == GameState.REBEL:
		return Lang.t("Ribelli: in guerra con tutti")
	match state.relation(me, other):
		GameState.REL_WAR:
			return Lang.t("In guerra con voi")
		GameState.REL_ALLIANCE:
			return Lang.t("Alleati")
		GameState.REL_TRUCE:
			return Lang.t("Tregua fino al %d") % state.truce_until(me, other)
	return Lang.t("Neutrali, in pace con voi")


## Testo per la pedina di un esercito o di una flotta: titolo, rapporto, unita' e uomini (le pedine nella nebbia non si
## vedono, quindi quel che c'e' sulla pedina si puo' dire).
static func army_text(state: GameState, player_id: String, army: Army, rich: bool = false) -> String:
	if army == null:
		return ""
	var lines := PackedStringArray()
	var kind := Lang.t("Flotta") if army.is_fleet else Lang.t("Esercito")
	if army.faction == SimUtil.norm(player_id):
		var title := CampaignUiText.army_title(army)
		var leader := state.commander_of(army.id)
		if leader != null:
			title += " · %s" % leader.full_name()
		elif army.is_fleet and CampaignUiText.admiral_caption(state, army) != "":
			title += " · %s" % CampaignUiText.admiral_caption(state, army)
		lines.append(title)
		lines.append(Lang.t("Vostro") if not army.is_fleet else Lang.t("Vostra"))
		var aim := CampaignUiAttack.target_line(state, army)
		if aim != "":
			lines.append(aim)
	else:
		var tone := relation_kind(state, player_id, army.faction)
		lines.append(paint("%s %s" % [kind, CampaignUiText.fprep("di", army.faction)], tone, rich))
		lines.append(paint(relation_line(state, player_id, army.faction), tone, rich))
	if army.is_fleet:
		lines.append(Lang.t("%d unità") % army.stack_count())
		if army.faction != SimUtil.norm(player_id) and Admirals.stars(state, army) >= 0:
			lines.append(Lang.t("La comanda l'ammiraglio %s") % str(army.admiral.get("nome", "")))
	else:
		lines.append(Lang.t("%d unità · %d uomini") % [army.stack_count(), army.men_total()])
	return "\n".join(lines)


## Testo per la pedina di un agente: tipo e nome, fazione e rapporto.
static func agent_text(state: GameState, player_id: String, agent: AgentState, rich: bool = false) -> String:
	if agent == null:
		return ""
	var lines := PackedStringArray([CampaignUiAgents.title(agent)])
	if agent.faction == SimUtil.norm(player_id):
		lines.append(Lang.t("Della vostra fazione"))
	else:
		var tone := relation_kind(state, player_id, agent.faction)
		lines.append(paint(CampaignUiText.fsubj(agent.faction), tone, rich))
		lines.append(paint(relation_line(state, player_id, agent.faction), tone, rich))
	return "\n".join(lines)


## Testo per una regione senza pedine sotto il puntatore. Zona di mare: nome e stato delle acque per i vostri trasporti
## (GameCommands.sea_zone_status): blocco navale, acque vostre, nemiche o libere, con le flotte presenti; nella nebbia solo
## il nome. Provincia: nome e proprietario con il rapporto. `seen`: regioni visibili (vuoto = tutte).
static func region_text(state: GameState, player_id: String, region_id: String, seen: Dictionary = {}, rich: bool = false) -> String:
	var region := state.campaign.region(region_id)
	if region == null:
		return ""
	var name_text := CampaignUiText.region_name(state, region.id)
	var visible := seen.is_empty() or seen.has(region.id)
	if not region.is_sea:
		var province := state.province(region.id)
		if province == null or province.owner == "":
			return name_text
		if province.owner == SimUtil.norm(player_id):
			return Lang.t("%s\nVostra provincia") % name_text
		var tone := relation_kind(state, player_id, province.owner)
		return "%s\n%s\n%s" % [name_text, paint(CampaignUiText.fsubj(province.owner), tone, rich), paint(relation_line(state, player_id, province.owner), tone, rich)]
	if not visible:
		return Lang.t("%s\nAcque non osservate") % name_text
	var me := SimUtil.norm(player_id)
	var enemies := PackedStringArray()
	var neutrals := PackedStringArray()
	var allies := PackedStringArray()
	var own := false
	for a in state.armies_in(region.id):
		if not a.is_fleet or a.stacks.is_empty():
			continue
		if a.faction == me:
			own = true
		elif state.at_war(me, a.faction):
			if not enemies.has(a.faction):
				enemies.append(a.faction)
		elif state.is_allied(me, a.faction):
			if not allies.has(a.faction):
				allies.append(a.faction)
		elif not neutrals.has(a.faction):
			neutrals.append(a.faction)
	var lines := PackedStringArray([name_text])
	var status := GameCommands.sea_zone_status(state, me, region.id, true)
	if not enemies.is_empty():
		lines.append(paint(Lang.t("Acque nemiche: flotte %s") % CampaignUiText.fnames(enemies, "di"), "nemico", rich))
	if status == GameCommands.ZONE_BLOCKED:
		var blockers := GameCommands.zone_blockers(state, me, region.id, true)   # solo chi ha piu' navi (22/11/2026)
		lines.append(paint(Lang.t("Blocco navale: i vostri eserciti non passano per mare (%s)") % CampaignUiText.fnames(blockers), "nemico", rich))
	elif status == GameCommands.ZONE_PASSABLE:
		lines.append(Lang.t("Acque vostre: la vostra flotta apre la rotta ai trasporti"))
		if not neutrals.is_empty() or not enemies.is_empty():
			lines.append(Lang.t("Nessun blocco navale: le altre flotte non hanno più navi delle vostre"))
	elif enemies.is_empty():
		lines.append(paint(Lang.t("Acque neutrali"), "neutrale", rich))
	if not neutrals.is_empty() and status != GameCommands.ZONE_BLOCKED:
		lines.append(paint(Lang.t("Flotte neutrali: %s") % CampaignUiText.fnames(neutrals), "neutrale", rich))
	if not allies.is_empty():
		lines.append(paint(Lang.t("Flotte alleate: %s") % CampaignUiText.fnames(allies), "alleato", rich))
	if own and status != GameCommands.ZONE_PASSABLE:
		lines.append(Lang.t("C'è una vostra flotta"))
	return "\n".join(lines)
