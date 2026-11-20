class_name VictoryState
extends RefCounted
## Esito della partita (fase 6b), in `GameState.victory` e nei salvataggi (versione 9).
##
## `outcome`: "" = la partita e' in corso; "dominio" = il giocatore ha raggiunto la soglia di dominio (se `continues` e' falso
## la partita aspetta la scelta di continuare, vedi `GameCommands.continue_after_victory`); "sconfitta" = la fazione del
## giocatore e' estinta o senza province ne' eserciti (fine); "fine_campagna" = anno finale raggiunto (fine).
## `year`: anno in cui l'esito e' stato fissato (l'anno raggiunto dopo il fine anno). `domination_year`: anno della vittoria
## per dominio (0 = mai), conservato anche se poi la partita continua fino alla fine della campagna.
## `ranking`: classifica al momento dell'esito (righe di `VictoryProcessor.standings`).

const NONE := ""
const DOMINATION := "dominio"
const DEFEAT := "sconfitta"
const CAMPAIGN_END := "fine_campagna"

var outcome := NONE
var year := 0
var continues := false
var domination_year := 0
var ranking: Array = []


## Vero per gli esiti che chiudono la partita (sconfitta, fine della campagna).
func is_final() -> bool:
	return outcome == DEFEAT or outcome == CAMPAIGN_END


## Vero se la partita aspetta che il giocatore scelga se continuare dopo la vittoria per dominio.
func awaits_choice() -> bool:
	return outcome == DOMINATION and not continues


## Fissa la classifica come copia (Array senza tipo, come quella riletta dai salvataggi).
func set_ranking(rows: Array) -> void:
	ranking = []
	for row in rows:
		var d: Dictionary = row
		ranking.append(d.duplicate(true))


func to_dict() -> Dictionary:
	var rows: Array = []
	for row in ranking:
		var d: Dictionary = row
		rows.append(d.duplicate(true))
	return {
		"esito": outcome,
		"anno": year,
		"continua": continues,
		"anno_dominio": domination_year,
		"classifica": rows,
	}


static func from_dict(d: Dictionary) -> VictoryState:
	var v := VictoryState.new()
	v.outcome = str(d.get("esito", NONE))
	v.year = int(d.get("anno", 0))
	v.continues = bool(d.get("continua", false))
	v.domination_year = int(d.get("anno_dominio", 0))
	var rows: Array = d.get("classifica", [])
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = item
		v.ranking.append({
			"posizione": int(src.get("posizione", 0)),
			"fazione": str(src.get("fazione", "")),
			"province": int(src.get("province", 0)),
			"reddito": int(src.get("reddito", 0)),
			"netto": int(src.get("netto", 0)),
			"quota": VictoryProcessor.normalize_share(float(src.get("quota", 0.0))),
			"giocatore": bool(src.get("giocatore", false)),
		})
	return v
