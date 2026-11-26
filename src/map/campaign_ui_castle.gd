class_name CampaignUiCastle
extends RefCounted
## Castelli sulla mappa (richiesta di Federico del 2026-11-10): cosa succede lasciando un esercito sul castello e cosa
## mostra il pannello di rassegna quando si clicca un castello. Funzioni pure sullo stato, per i test; gli ordini passano
## dai comandi della simulazione (GameCommands.garrison_castle, order_garrison_move, order_assault, order_move).
##
## Esercito lasciato sul castello:
## - proprio, nella stessa regione: si barricano le unita' che ci stanno, le altre restano fuori (BARRICATA);
## - proprio, in un'altra regione: ci va e all'arrivo si barrica (VAI_E_BARRICATI);
## - altrui, in un'altra regione: ci va per assediarlo (ASSEDIO, un movimento d'attacco come sulla provincia);
## - altrui, nella stessa regione con il proprio assedio in corso: ordina l'assalto per fine anno (ASSALTO);
## - negli altri casi nulla, con il motivo in "testo" (NIENTE).

const BARRICATA := "barricata"
const VAI_E_BARRICATI := "vai_e_barricati"
const ASSEDIO := "assedio"
const ASSALTO := "assalto"
const NIENTE := "niente"


## Piano per l'esercito `army` del giocatore lasciato sul castello di `region_id`: {"azione", "testo"}.
static func drop_plan(state: GameState, player_id: String, army: Army, region_id: String) -> Dictionary:
	if army == null or army.stacks.is_empty():
		return _plan(NIENTE, "")
	var where := CampaignUiText.region_name(state, region_id)
	if army.is_fleet:
		return _plan(NIENTE, Lang.t("Le flotte non entrano nei castelli."))
	var province := state.province(region_id)
	if province == null or Combat.castle_level(state, region_id) <= 0:
		return _plan(NIENTE, Lang.t("%s non ha un castello.") % where)
	var own := province.owner == SimUtil.norm(player_id)
	if own:
		if army.region == province.id:
			if army.in_castle:
				return _plan(NIENTE, Lang.t("%s è già nel castello di %s.") % [CampaignUiText.army_title(army), where])
			return _plan(BARRICATA, "")
		return _plan(VAI_E_BARRICATI, "")
	if army.region != province.id:
		return _plan(ASSEDIO, "")
	if army.in_castle:
		return _plan(NIENTE, "")
	var siege := state.siege_in(province.id)
	if siege == null or siege.faction != army.faction:
		return _plan(NIENTE, Lang.t("Nessun assedio tuo al castello di %s: comincia a fine anno, se nel castello c'è il nemico.") % where)
	if army.assault_ordered:
		return _plan(NIENTE, Lang.t("L'assalto al castello di %s è già ordinato: avverrà a fine anno.") % where)
	return _plan(ASSALTO, "")


static func _plan(action: String, text: String) -> Dictionary:
	return {"azione": action, "testo": text}


## Contenuto del pannello di rassegna per il castello di `region_id`: {"titolo", "righe", "carte", "famiglia", "livello",
## "tipo", "nota"}. Ogni carta e' {"esercito": id, "pila": indice, "unita", "uomini", "valore", "fazione"}, nell'ordine degli
## eserciti nel castello. "tipo" e' il nome del castello senza il livello (in grassetto accanto all'icona, richiesta di
## Federico dell'11/11/2026), "nota" i posti occupati della guarnigione ("" fuori vista).
## `seen` = la provincia e' in vista (nebbia di guerra): fuori vista la guarnigione altrui non si conosce.
static func review(state: GameState, region_id: String, player_id: String, seen: bool) -> Dictionary:
	var province := state.province(region_id)
	var lines := PackedStringArray()
	var cards: Array = []
	var out := {"titolo": Lang.t("Castello · %s") % CampaignUiText.region_name(state, region_id), "righe": lines, "carte": cards,
		"famiglia": "", "livello": 0, "tipo": "", "nota": ""}
	if province == null:
		return out
	var c := state.rules.combat
	var level := province.level_of(c.castle_family)
	out["famiglia"] = c.castle_family
	out["livello"] = level
	if level > 0:
		out["tipo"] = type_name(state, c.castle_family, level)
	out["titolo"] = Lang.t("Castello · %s · %s") % [CampaignUiText.region_name(state, region_id), CampaignUiText.faction_name(province.owner)]
	var own := province.owner == SimUtil.norm(player_id)
	if not own and not seen:
		lines.append(Lang.t("Provincia fuori vista: la guarnigione non si conosce."))
		return out
	for a in state.armies_in(region_id):
		if not a.in_castle or a.is_fleet or a.stacks.is_empty():
			continue
		for i in a.stacks.size():
			var st := a.stacks[i]
			cards.append({"esercito": a.id, "pila": i, "unita": st.unit_id, "uomini": st.men, "valore": st.value, "fazione": a.faction,
				"armi": st.weapon, "armatura": st.armour})
	out["nota"] = Lang.t("Guarnigione %d/%d") % [Combat.garrison_load(state, region_id), Combat.garrison_capacity(state, region_id)]
	var load_text := str(out["nota"]).replace(Lang.t("Guarnigione "), Lang.t("Guarnigione: "))
	lines.append((Lang.t("%s posti (fortezza: ci entra un'intera armata)") if Combat.is_fortress(state, region_id) else Lang.t("%s posti (la cavalleria conta doppio)")) % load_text)
	if cards.is_empty():
		lines.append(Lang.t("Nessuna truppa nel castello.") + (Lang.t(" Trascina un tuo esercito sul castello per barricarlo.") if own else ""))
	for siege_line in CampaignUiText.siege_lines(state, region_id):
		lines.append(siege_line)
	return out


## Nome del tipo di castello senza «(livello N)»: «Fortezza», «Castello con mura».
static func type_name(state: GameState, family_id: String, level: int) -> String:
	var full := CampaignUiText.building_name(state, family_id, level)
	var cut := full.rfind(Lang.t(" (livello "))
	return full.substr(0, cut) if cut > 0 else full


## Voci della rassegna del castello raggruppate per armata (richiesta di Federico dell'11/11/2026: le armate accanto
## all'icona del castello): prima di ogni armata una voce {"intestazione": «Esercito 8», "esercito": id, "suggerimento"
## (comandante, unita' e uomini)}, poi le sue carte (le stesse di `review`).
static func review_entries(state: GameState, info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cards: Array = info.get("carte", [])
	var current := 0
	for item in cards:
		var card: Dictionary = item
		var army_id := int(card["esercito"])
		if army_id != current:
			current = army_id
			var army := state.army(army_id)
			var label := CampaignUiText.army_title(army) if army != null else Lang.t("Esercito %d") % army_id
			var tip := label
			if army != null:
				var commander := state.commander_of(army.id)
				if commander != null:
					tip += " · %s" % commander.full_name()
				tip += Lang.t("\n%d unità · %d uomini") % [army.stacks.size(), army.men_total()]
			out.append({"intestazione": label, "esercito": army_id, "suggerimento": tip})
		out.append(card)
	return out
