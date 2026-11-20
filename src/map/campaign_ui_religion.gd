class_name CampaignUiReligion
extends RefCounted
## Testi e dati dell'interfaccia della fase 5b (religione e Inquisizione): funzioni pure che leggono lo stato e producono
## stringhe, righe o colori, senza modificarlo. L'interfaccia (scenes/) mostra e invia solo comandi (ADR-003, 008).
##
## - nome italiano delle religioni (compresa l'eresia);
## - composizione religiosa di una provincia: solo le religioni presenti, in ordine decrescente, percentuali con al
##   massimo due decimali e senza decimali inutili;
## - righe del pannello della provincia (religione del proprietario, eretici oltre la soglia della rivolta, zelo);
## - legenda della tinta religiosa della mappa (i colori stanno in StateTint).
##
## Nessuna regola e' ricalcolata qui: la soglia e la religione del proprietario vengono da `ReligionProcessor` e da
## `rules.religion`. La simulazione non espone un «andamento atteso» della composizione: non lo si mostra.

const HERETIC_NAME := "Eretica"


## Nome italiano della religione ("CATHOLIC" -> "Cattolica", "HERETIC" -> "Eretica"); anche i token dei file
## ("REL_ISLAMIC"); vuoto: "sconosciuta".
static func religion_label(key: String) -> String:
	if key.strip_edges().to_upper() == ProvinceState.HERETIC:
		return Lang.t(HERETIC_NAME)
	return CampaignUiAgents.religion_name(key)


## Percentuale in italiano: al massimo due decimali, nessuno zero inutile, virgola decimale ("75%", "12,5%", "0,25%").
static func percent_text(value: float) -> String:
	var text := "%.2f" % maxf(0.0, value)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return (text if Lang.is_english() else text.replace(".", ",")) + "%"


## Religioni presenti nella provincia (percentuale > 0), dalla piu' diffusa alla meno; a parita' l'ordine fisso di
## `ProvinceState.RELIGIONS`. Ogni voce: "chiave", "nome", "pct" (float), "testo" ("Cattolica 75%").
static func composition(province: ProvinceState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in range(ProvinceState.RELIGIONS.size()):
		var key: String = ProvinceState.RELIGIONS[i]
		var pct := province.religion_pct(key)
		if pct > 0.0:
			rows.append({
				"chiave": key,
				"nome": religion_label(key),
				"pct": pct,
				"ordine": i,
				"testo": "%s %s" % [religion_label(key), percent_text(pct)],
			})
	rows.sort_custom(_more_widespread)
	return rows


static func _more_widespread(a: Dictionary, b: Dictionary) -> bool:
	var pa := float(a["pct"])
	var pb := float(b["pct"])
	if pa != pb:
		return pa > pb
	return int(a["ordine"]) < int(b["ordine"])


## Righe della composizione per il pannello: [{"testo", "proprietario", "rosso"}]. «proprietario»: e' la religione del
## proprietario; «rosso»: sono gli eretici e la provincia e' oltre la soglia della rivolta eretica
## (`ReligionProcessor.heretic_revolt`, `rules.religion.heretic_revolt_threshold`).
static func section_rows(state: GameState, province: ProvinceState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var owner_religion := ReligionProcessor.owner_religion(state, province)
	var revolt := ReligionProcessor.heretic_revolt(state, province)
	var threshold := state.rules.religion.heretic_revolt_threshold
	for row in composition(province):
		var key := str(row["chiave"])
		var text := str(row["testo"])
		var is_owner := key == owner_religion
		var red := key == ProvinceState.HERETIC and revolt
		if is_owner:
			text += Lang.t(" · religione del proprietario")
		if red:
			text += Lang.t(" · oltre il %s: rivolta eretica") % percent_text(threshold)
		out.append({"testo": text, "proprietario": is_owner, "rosso": red, "chiave": key})
	return out


## Riga dello zelo: «Zelo (Cattolica): 50 su 100»; senza religione del proprietario (ribelli) solo «Zelo: 50 su 100».
static func zeal_text(state: GameState, province: ProvinceState) -> String:
	var owner_religion := ReligionProcessor.owner_religion(state, province)
	if owner_religion == "":
		return Lang.t("Zelo: %d su 100") % province.zeal
	return Lang.t("Zelo (%s): %d su 100") % [religion_label(owner_religion), province.zeal]


## Legenda della tinta religiosa: una voce per religione, nell'ordine fisso: [{"chiave", "nome", "colore"}]. Il Culto
## Imperiale degli Auror compare solo in modalita' Auror.
static func legend_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in ProvinceState.RELIGIONS:
		var k: String = key
		if k == ProvinceState.IMPERIAL and not Scenario.auror:
			continue
		out.append({"chiave": k, "nome": religion_label(k), "colore": StateTint.religion_color(k)})
	return out
