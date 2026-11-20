class_name BattleResult
extends RefCounted
## Esito di una battaglia, di un assalto, di una sortita o di uno scontro navale (spec. fase 3 §4).
## Lo produce `Combat.resolve`; le ritirate e le catture dei perdenti le aggiunge `WarProcessor`.

const KIND_FIELD := "campo"
const KIND_ASSAULT := "assalto"
const KIND_SALLY := "sortita"
const KIND_NAVAL := "navale"

var kind := KIND_FIELD
var region := ""
## Attaccante e difensore: nell'assalto il difensore e' la guarnigione; nella sortita l'attaccante.
var attacker_faction := ""
var defender_faction := ""
var attacker_army_ids: Array[int] = []
var defender_army_ids: Array[int] = []
## Forze usate nel sorteggio (il difensore comprende il suo bonus o il moltiplicatore del castello).
var attacker_strength := 0.0
var defender_strength := 0.0
## Forza del difensore senza bonus.
var defender_base_strength := 0.0
var defender_multiplier := 1.0
var attacker_win_probability := 0.0
## Numero casuale estratto: l'attaccante vince se e' sotto la probabilita' (salvo esito forzato nei test).
var roll := 0.0
var attacker_won := false
var attacker_men_before := 0
var defender_men_before := 0
var attacker_losses := 0
var defender_losses := 0
var attacker_loss_fraction := 0.0
var defender_loss_fraction := 0.0
## Ritirate dei perdenti: {"esercito", "da", "a", "caso"}.
var retreats: Array[Dictionary] = []
## Eserciti perdenti catturati: {"esercito", "uomini", "caso"}.
var captures: Array[Dictionary] = []


func winner_faction() -> String:
	return attacker_faction if attacker_won else defender_faction


func loser_faction() -> String:
	return defender_faction if attacker_won else attacker_faction


## Uomini persi dalla fazione indicata in questa battaglia (0 se non ha partecipato).
func losses_of(faction_id: String) -> int:
	var key := SimUtil.norm(faction_id)
	var total := 0
	if key == attacker_faction:
		total += attacker_losses
	if key == defender_faction:
		total += defender_losses
	return total


## Dettagli per l'evento EV_BATTLE. Non contiene la chiave "tipo" (riservata al tipo di evento).
func to_dict() -> Dictionary:
	var attackers: Array = []
	for army_id in attacker_army_ids:
		attackers.append(army_id)
	var defenders: Array = []
	for army_id in defender_army_ids:
		defenders.append(army_id)
	return {
		"scontro": kind,
		"attaccante": attacker_faction,
		"difensore": defender_faction,
		"eserciti_attaccanti": attackers,
		"eserciti_difensori": defenders,
		"forza_attaccante": attacker_strength,
		"forza_difensore": defender_strength,
		"forza_difensore_base": defender_base_strength,
		"moltiplicatore_difensore": defender_multiplier,
		"prob_attaccante": attacker_win_probability,
		"tiro": roll,
		"vittoria_attaccante": attacker_won,
		"vincitore": winner_faction(),
		"perdente": loser_faction(),
		"uomini_attaccante": attacker_men_before,
		"uomini_difensore": defender_men_before,
		"perdite_attaccante": attacker_losses,
		"perdite_difensore": defender_losses,
		"frazione_perdite_attaccante": attacker_loss_fraction,
		"frazione_perdite_difensore": defender_loss_fraction,
		"ritirate": retreats.duplicate(true),
		"catture": captures.duplicate(true),
	}
