class_name RegionStyle
extends RefCounted
## Grafica degli edifici per la cultura d'origine della regione (richiesta di Federico del 22/11/2026: «quando si
## conquistano province la grafica degli edifici deve restare quella delle fazioni di partenza»). Esempio: gli Inglesi che
## conquistano il Giappone vedono ancora i castelli giapponesi sulla mappa e nella scheda; gli altri edifici restano con la
## grafica della cultura della regione (le varianti «asian» del Dharma), tranne quelli propri del conquistatore, cioe' gli
## edifici di una religione che la cultura della regione non ha (una chiesa cattolica costruita dagli Inglesi resta una
## chiesa cattolica). Solo grafica: le regole degli edifici non cambiano.
##
## Fazione d'origine = padrone della regione all'inizio della partita (`CampaignData.Region.owner`, dallo startpos della
## mappa scelta); cultura d'origine = `SetAttributes` della regione (CATHOLIC_CULTURE, DHARMA_CULTURE...), tradotta in
## religione da `data/regole/province.cfg [culture]`. Regioni dei ribelli all'inizio: i castelli prendono lo stile di chi le
## occupa adesso (il villaggio dei ribelli finche' restano loro, poi quello del conquistatore): lo stile dei ribelli non si
## eredita (Federico, 23/11/2026: «deve valere il seme grafico dell'occupante»).


## Fazione che possedeva la regione all'inizio della partita, "" se ribelli, mare o regione sconosciuta.
static func home_faction(state: GameState, region_id: String) -> String:
	if state == null or state.campaign == null or region_id == "":
		return ""
	var r := state.campaign.region(region_id)
	if r == null or r.is_sea:
		return ""
	var owner := SimUtil.norm(r.owner)
	if owner == "" or owner == GameState.REBEL:
		return ""
	return owner


## Religione della cultura d'origine della regione come chiave degli edifici (CATHOLIC, MUSLIM, DHARMA...), "" se ignota.
static func native_religion(state: GameState, region_id: String) -> String:
	if state == null or state.campaign == null or state.rules == null or region_id == "":
		return ""
	var r := state.campaign.region(region_id)
	if r == null or r.is_sea:
		return ""
	return ReligionRules.religion_key(state.rules.province.religion_of_culture(r.culture))


## Fazione di cui si usano i castelli propri (CastleStyle) nella regione: quella d'origine, anche dopo la conquista; per le
## regioni dei ribelli all'inizio, l'occupante attuale (FN_REBEL finche' non le conquista nessuno).
static func castle_faction(state: GameState, region_id: String) -> String:
	var home := home_faction(state, region_id)
	if home != "" or state == null:
		return home
	if is_auror_home(state, region_id):
		return AurorUnits.faction()   # regione dei ribelli conquistata per prima dagli Auror (ADR-136)
	var p := state.province(region_id)
	return SimUtil.norm(p.owner) if p != null else ""


## Religione con cui scegliere la variante dell'icona di un edificio nella regione (BuildingArt.icon): la religione della
## cultura d'origine; per gli edifici di una religione che quella cultura non ha, la religione del proprietario attuale
## (se l'edificio la ammette), altrimenti la prima religione dell'edificio. `fallback` se la regione non ha cultura nota.
static func building_religion(state: GameState, region_id: String, family: BuildingType, owner_id: String, fallback: String = "") -> String:
	if is_auror_home(state, region_id) and (family == null or family.religions.is_empty() \
			or GameCommands.building_allows_religion(family, "CATHOLIC")):
		return AUROR_RELIGION
	var native := native_religion(state, region_id)
	var own := _faction_religion(state, owner_id)
	if native == "":
		return own if own != "" else fallback
	if family == null or family.religions.is_empty() or GameCommands.building_allows_religion(family, native):
		return native
	if own != "" and GameCommands.building_allows_religion(family, own):
		return own
	return family.religions[0]


## Religione con cui BuildingArt sceglie le icone degli Auror (cartella «auror»).
const AUROR_RELIGION := "IMPERIAL"


## Vero, solo in modalita' Auror, per le regioni con la grafica degli Auror (ADR-136): quelle degli Auror all'inizio della
## partita (le isole di Atlantide) e quelle dei ribelli all'inizio che gli Auror hanno conquistato per primi (Federico,
## 25/11/2026), anche se poi passano ad altri. Li' edifici e castelli sono degli Auror; nelle terre di altre fazioni
## conquistate vale la cultura d'origine (ADR-119).
static func is_auror_home(state: GameState, region_id: String) -> bool:
	if not Scenario.auror or region_id == "" or state == null:
		return false
	var auror := AurorUnits.faction()
	var home := home_faction(state, region_id)
	if home != "":
		return home == auror
	var r := state.campaign.region(region_id) if state.campaign != null else null
	if r == null or r.is_sea:
		return false
	var p := state.province(region_id)
	return p != null and p.first_conqueror == auror


static func _faction_religion(state: GameState, faction_id: String) -> String:
	if state == null or state.campaign == null or faction_id == "":
		return ""
	var cf := state.campaign.faction(faction_id)
	if cf == null or cf.religion == "":
		return ""
	return GameCommands.religion_key(cf.religion)
