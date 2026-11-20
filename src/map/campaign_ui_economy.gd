class_name CampaignUiEconomy
extends RefCounted
## Proventi delle province nel dettaglio (pulsante Economia della barra, richiesta di Federico del 2026-11-10): per ogni
## provincia propria le voci del reddito previsto per quest'anno con le regole di Economy (agricoltura, miniere, commercio),
## la tassa e il motivo di un reddito nullo; in fondo i totali, il mantenimento delle forze e il saldo. Funzione pura.


## {"righe": [{"provincia", "nome", "agricoltura", "miniere", "commercio", "commercio_locale", "commercio_marittimo",
## "importazioni", "porti" (vedi `port_lines`), "totale", "tassa", "nota"}] ordinate per totale
## decrescente, "agricoltura", "miniere", "commercio", "totale", "mantenimento", "saldo", "tesoro", "anno_scorso"
## (le voci di Faction.last_income, vuoto prima del primo fine anno)}.
static func report(state: GameState, player_id: String) -> Dictionary:
	var acumen := Economy.acumen_table(state)
	var rows: Array[Dictionary] = []
	var sums := {"agricoltura": 0, "miniere": 0, "commercio": 0, "totale": 0}
	for p in state.provinces_of(player_id):
		var inc := Economy.province_income(state, p, acumen)
		var note := ""
		var ports: Array[Dictionary] = []
		if bool(inc["conteso"]):
			note = Lang.t("assediata") if state.is_besieged(p.id) else Lang.t("contesa: nemici nella provincia")
		else:
			# commercio marittimo (ADR-051/054): i porti raggiunti non si elencano piu' in una riga (richiesta di Federico del
			# 2026-11-13) ma nel dettaglio della provincia, dal piu' redditizio
			ports = port_lines(state, p, Economy.acumen_multiplier(state, p, acumen))
		rows.append({"provincia": p.id, "nome": CampaignUiText.region_name(state, p.id),
			"agricoltura": int(inc["agricoltura"]), "miniere": int(inc["miniere"]), "commercio": int(inc["commercio"]),
			"commercio_locale": int(inc.get("commercio_locale", 0)), "commercio_marittimo": int(inc.get("commercio_marittimo", 0)),
			"importazioni": int(inc.get("importazioni", 0)), "porti": ports,
			"totale": int(inc["totale"]), "tassa": CampaignUiText.tax_name(p.tax_level), "nota": note})
		for key in sums:
			sums[key] = int(sums[key]) + int(inc[key])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["totale"]) > int(b["totale"]) or (int(a["totale"]) == int(b["totale"]) and str(a["nome"]) < str(b["nome"])))
	var upkeep := Economy.faction_upkeep(state, player_id)
	var f := state.faction(player_id)
	var out := {"righe": rows, "mantenimento": upkeep, "saldo": int(sums["totale"]) - upkeep,
		"tesoro": f.treasury if f != null else 0, "anno_scorso": f.last_income.duplicate() if f != null else {}}
	for key in sums:
		out[key] = sums[key]
	return out


## Porti raggiunti dalla provincia per la finestra Economia, dal piu' redditizio: {"provincia", "nome", "fazione",
## "fazione_nome", "peso", "ricchezza" (testo: ricchissima, ricca, media, povera), "fiorini"}.
static func port_lines(state: GameState, p: ProvinceState, factor: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in Economy.trade_partner_details(state, p, state.campaign.region(p.id), factor):
		var weight := float(d["peso"])
		out.append({"provincia": str(d["provincia"]), "nome": CampaignUiText.region_name(state, str(d["provincia"])),
			"fazione": str(d["fazione"]), "fazione_nome": CampaignUiText.faction_name(str(d["fazione"])),
			"peso": weight, "ricchezza": wealth_label(weight), "fiorini": int(d["fiorini"])})
	return out


## Ricchezza di un porto dal suo peso nel commercio (ADR-054): oltre 1,5 ricchissimo, da 0,8 ricco, da 0,35 medio, sotto povero.
static func wealth_label(weight: float) -> String:
	if weight >= 1.5:
		return Lang.t("ricchissimo")
	if weight >= 0.8:
		return Lang.t("ricco")
	if weight >= 0.35:
		return Lang.t("medio")
	return Lang.t("povero")

