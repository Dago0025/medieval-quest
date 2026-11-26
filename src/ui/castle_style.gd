class_name CastleStyle
extends RefCounted
## Castelli propri di una cultura (richiesta di Federico del 22/11/2026: completare Giapponesi e Cinesi con i loro elementi
## di gioco; prompt GC01-04 e CC01-04 dei documenti del progetto). `data/castelli_cultura.cfg` dice lo stile di ogni
## fazione; per tutti i gradi di CombatRules.castle_tier (forte, mastio, castello, cittadella, fortezza) la pedina della
## mappa e l'icona del castello costruito sono quelle dello stile. Dal 23/11/2026 anche il forte (grado 0) ha lo stile
## della cultura, e i ribelli hanno il loro (stile «rebel»: un villaggio) - Federico: «vanno resi per fazione anche le prime
## fasi dei castelli». Un grado senza immagine dello stile resta quello comune.
## Immagini preparate da tools/prepara_castelli_cultura.py: una sola per grado, senza le evoluzioni (come gli altri castelli).
## Senza immagini resta il castello dell'originale.

const FILE := "res://data/castelli_cultura.cfg"
const TIER_NAMES := ["FORT", "KEEP", "CASTLE", "CITADEL", "FORTRESS"]   ## come PieceArt.CASTLE_PIECES
const AUROR_STYLE := "auror"   ## castelli gotici degli Auror (25/11/2026), solo in modalita' Auror
const FIRST_TIER := 0

static var _styles := {}
static var _loaded := false


static func reset() -> void:
	_styles.clear()
	_loaded = false


## Stile dei castelli della fazione ("japanese", "chinese"), "" se usa quelli comuni. La fazione degli Auror ha lo stile
## «auror» solo in modalita' Auror (Scenario.auror): nello scenario storico la stessa fazione sono i Danesi.
static func style_of(faction_id: String) -> String:
	if Scenario.auror and faction_id.strip_edges().to_upper() == AurorUnits.faction():
		return AUROR_STYLE
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(FILE) == OK and cfg.has_section("fazioni"):
			for k in cfg.get_section_keys("fazioni"):
				_styles[str(k).strip_edges().to_upper()] = str(cfg.get_value("fazioni", k, "")).strip_edges().to_lower()
	return str(_styles.get(faction_id.strip_edges().to_upper(), ""))


## Percorso «originale» della pedina del castello di grado `tier` nello stile della fazione, "" se non ce n'e' uno
## (fazione senza stile, forte, immagine non ancora pronta).
static func map_original(faction_id: String, tier: int) -> String:
	var style := style_of(faction_id)
	if style == "" or tier < FIRST_TIER or tier >= TIER_NAMES.size():
		return ""
	var path := "campmap/pieces/buildings/%s/%s.Buf" % [style, TIER_NAMES[tier]]
	return path if AssetLibrary.is_remade(path) else ""


## Percorso «originale» dell'icona del castello di grado `tier` nello stile della fazione, "" se non c'e'.
static func icon_original(faction_id: String, tier: int) -> String:
	var style := style_of(faction_id)
	if style == "" or tier < FIRST_TIER or tier >= TIER_NAMES.size():
		return ""
	var path := "campmap/review_panel/buildings/%s/%s.BIF" % [style, TIER_NAMES[tier]]
	return path if AssetLibrary.is_remade(path) else ""


## Icona del castello di grado `tier` per la fazione, null se usa quella comune.
static func icon(faction_id: String, tier: int) -> Texture2D:
	var path := icon_original(faction_id, tier)
	return AssetLibrary.texture(path) if path != "" else null
