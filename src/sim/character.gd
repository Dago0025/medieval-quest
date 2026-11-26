class_name Character
extends RefCounted
## Un personaggio della dinastia o dell'esercito (fase 4a): capo, erede, principe, principessa o
## generale. Lo stato sta in `GameState.characters`, in ordine di id.
##
## Attributi 0..10 (specifica; l'eseguibile usa 0..9): comando, terrore, pieta', acume, lealta'
## (influenza solo per il capo). I valori memorizzati sono quelli di base; il valore usato dalle
## regole e' `effective()`: base + titolo + carica + vizi e virtu', con i valori fissi degli Auror
## (data/regole/auror.cfg) e limite 0..massimo.
##
## Ruoli (interpretazione della specifica 4a, manuale p17-p18):
## - `capo`: il capofazione;
## - `erede`: un figlio maschio minorenne (meno di 16 anni) oppure l'erede designato (il maschio
##   vivo piu' anziano tra i figli); ereditano a 16 anni;
## - `principe`: figlio maschio maggiorenne non designato, generale di sangue reale;
## - `principessa`: figlia (agente dalla fase 5); maggiorenne a 15 anni, si ritira a 32;
## - `generale`: tutti gli altri (anche ex principi dopo l'incoronazione dell'erede, eroi famosi).

const ROLE_LEADER := "capo"
const ROLE_HEIR := "erede"
const ROLE_PRINCE := "principe"
const ROLE_PRINCESS := "principessa"
const ROLE_GENERAL := "generale"

const ATTR_COMMAND := "command"
const ATTR_DREAD := "dread"
const ATTR_PIETY := "piety"
const ATTR_ACUMEN := "acumen"
const ATTR_LOYALTY := "loyalty"
const ATTR_INFLUENCE := "influence"

var id := 0
var forename := ""           ## nome di battesimo
var surname := ""            ## cognome (generali ed eroi; vuoto per i membri della famiglia reale)
var numeral := 0             ## numerale del re (2 = "II"); 0 = nessuno
var faction := ""
var role := ROLE_GENERAL
var birth_year := 0
var royal_blood := false
var is_hero := false         ## eroe famoso (FAMOUS_HEROES): soglia di vecchiaia +10
var male := true
## Indice del nome nell'elenco dei nomi reali della fazione (numerali dei re); -1 se non e' un nome reale.
var name_index := -1
## Fazione di nome e ritratto, se diversa dalla propria (generale degli Auror nato da una truppa straniera, 22/11/2026);
## "" = la propria.
var origin := ""

var command := 0
var dread := 0
var piety := 0
var acumen := 0
var loyalty := 0
var influence := 0           ## solo per il capo

## Vizi e virtu' ottenuti: catena (per esempio "fearsome") -> livello (da 1).
var vnv := {}
## Contatori per i vizi e le virtu' e per l'influenza (vittorie, ritirate, uccisioni...).
var counters := {}

var title := ""              ## id della provincia che governa ("" = nessun titolo)
var office := ""             ## carica di Stato: edificio associato in minuscolo ("" = nessuna)
var army := 0                ## id dell'esercito che comanda (0 = nessuno)
var region := ""             ## dove si trova quando non comanda un esercito
var alive := true
var old_age := 40            ## soglia di vecchiaia, estratta alla creazione
var death_year := 0
var death_cause := ""        ## vecchiaia, ritiro, estinzione, fazione_distrutta...


func _init(character_id: int = 0) -> void:
	id = character_id


## Nome con numerale e cognome: "Darkos II", "William Marshal".
func full_name() -> String:
	var out := forename
	if numeral > 0:
		out += " " + HeroesData.roman(numeral)
	if surname != "":
		out += " " + surname
	return out.strip_edges()


func age(at_year: int) -> int:
	return at_year - birth_year


## Maggiorenne all'anno indicato: i maschi a `eta_principe`, le femmine a `eta_principessa`;
## il capo lo e' sempre.
func is_adult(rules: DynastyRules, at_year: int) -> bool:
	if role == ROLE_LEADER:
		return true
	var limit := rules.prince_age if male else rules.princess_age
	return age(at_year) >= limit


## Puo' comandare un esercito o governare una provincia (non le principesse, non i minorenni).
func can_command(rules: DynastyRules, at_year: int) -> bool:
	return alive and role != ROLE_PRINCESS and is_adult(rules, at_year)


## Valore di base di un attributo (senza titolo, carica, vizi e virtu').
func base_value(attr: String) -> int:
	match attr:
		ATTR_COMMAND:
			return command
		ATTR_DREAD:
			return dread
		ATTR_PIETY:
			return piety
		ATTR_ACUMEN:
			return acumen
		ATTR_LOYALTY:
			return loyalty
		ATTR_INFLUENCE:
			return influence
	return 0


func set_base_value(attr: String, value: int) -> void:
	match attr:
		ATTR_COMMAND:
			command = value
		ATTR_DREAD:
			dread = value
		ATTR_PIETY:
			piety = value
		ATTR_ACUMEN:
			acumen = value
		ATTR_LOYALTY:
			loyalty = value
		ATTR_INFLUENCE:
			influence = value


## Valore usato dalle regole: valore fisso della fazione (Auror: comando, fedelta' e, per il
## capo, influenza) oppure base + titolo + carica + vizi e virtu', limitato a 0..massimo.
func effective(attr: String, rules: Rules, campaign: CampaignData) -> int:
	var dr := rules.dynasty
	var fixed := dr.fixed_value(faction, attr)
	if fixed >= 0 and (attr != ATTR_INFLUENCE or role == ROLE_LEADER):
		return clampi(fixed, 0, dr.max_attribute)
	var total := base_value(attr)
	if campaign != null:
		if title != "":
			var t := campaign.title_for(title)
			if t != null:
				total += t.bonus(attr)
		if office != "":
			var o := campaign.office_for(faction, office)
			if o != null:
				total += o.bonus(attr)
	for chain in vnv:
		var level: int = vnv[chain]
		total += rules.vnv.delta(str(chain), level, attr)
	return clampi(total, 0, dr.max_attribute)


## Stelle di comando (= comando efficace).
func stars(rules: Rules, campaign: CampaignData) -> int:
	return effective(ATTR_COMMAND, rules, campaign)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"nome": forename,
		"cognome": surname,
		"numerale": numeral,
		"fazione": faction,
		"ruolo": role,
		"nascita": birth_year,
		"sangue_reale": royal_blood,
		"eroe": is_hero,
		"maschio": male,
		"indice_nome": name_index,
		"comando": command,
		"terrore": dread,
		"pieta": piety,
		"acume": acumen,
		"lealta": loyalty,
		"influenza": influence,
		"vnv": vnv.duplicate(),
		"contatori": counters.duplicate(),
		"titolo": title,
		"carica": office,
		"esercito": army,
		"regione": region,
		"vivo": alive,
		"soglia_vecchiaia": old_age,
		"anno_morte": death_year,
		"causa_morte": death_cause,
	}.merged({"origine": origin} if origin != "" else {})


## Fazione da cui vengono nome e ritratto: `origin` se c'e', altrimenti la propria.
func look_faction() -> String:
	return origin if origin != "" else faction


static func from_dict(d: Dictionary) -> Character:
	var c := Character.new(int(d.get("id", 0)))
	c.forename = str(d.get("nome", ""))
	c.surname = str(d.get("cognome", ""))
	c.numeral = int(d.get("numerale", 0))
	c.faction = str(d.get("fazione", ""))
	c.role = str(d.get("ruolo", ROLE_GENERAL))
	c.birth_year = int(d.get("nascita", 0))
	c.royal_blood = bool(d.get("sangue_reale", false))
	c.is_hero = bool(d.get("eroe", false))
	c.male = bool(d.get("maschio", true))
	c.name_index = int(d.get("indice_nome", -1))
	c.command = int(d.get("comando", 0))
	c.dread = int(d.get("terrore", 0))
	c.piety = int(d.get("pieta", 0))
	c.acumen = int(d.get("acume", 0))
	c.loyalty = int(d.get("lealta", 0))
	c.influence = int(d.get("influenza", 0))
	var vnv_data: Dictionary = d.get("vnv", {})
	for key in vnv_data:
		c.vnv[str(key)] = int(vnv_data[key])
	var counter_data: Dictionary = d.get("contatori", {})
	for key in counter_data:
		c.counters[str(key)] = int(counter_data[key])
	c.title = str(d.get("titolo", ""))
	c.office = str(d.get("carica", ""))
	c.army = int(d.get("esercito", 0))
	c.region = str(d.get("regione", ""))
	c.alive = bool(d.get("vivo", true))
	c.old_age = int(d.get("soglia_vecchiaia", 40))
	c.death_year = int(d.get("anno_morte", 0))
	c.death_cause = str(d.get("causa_morte", ""))
	c.origin = str(d.get("origine", ""))
	return c
