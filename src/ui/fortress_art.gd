class_name FortressArt
extends RefCounted
## Fortezza bianca degli Auror (ADR-076, richiesta di Federico del 16/11/2026): una cittadella bianca a terrazze sul fianco
## della montagna, ispirata alla citta' bianca del Signore degli Anelli ma con i colori e il drago degli Auror. Si vede solo
## nella regione natia degli Auror (`Scenario.home_region`, la Norvegia) e solo in modalita' Auror: sulla mappa prende il
## posto del castello (qualunque grado e qualunque proprietario: e' il luogo, non la guarnigione) ed e' piu' grande degli altri
## di `MAP_SCALE`; nella barra, nella pergamena e nella finestra della provincia e' l'icona del castello costruito.
## Immagini preparate da tools/prepara_fortezza_auror.py dal dipinto di AI Playground; finche' mancano resta il castello
## del grado, come in ogni altra provincia.

const MAP_ORIGINAL := "campmap/pieces/buildings/FORTEZZA_AUROR.Buf"      ## -> assets/rifatti/.../fortezza_auror.png
const ICON_ORIGINAL := "campmap/review_panel/buildings/FORTEZZA_AUROR.BIF"
const MAP_SCALE := 1.5                                                    ## altezza sulla mappa rispetto agli altri castelli


## Vero per la regione natia degli Auror in modalita' Auror (anche senza le immagini).
static func is_fortress(province_id: String) -> bool:
	if province_id.strip_edges() == "":
		return false
	var home := Scenario.home_region(AurorUnits.faction())
	return home != "" and home == province_id.strip_edges().to_upper()


## Percorso «originale» della pedina della fortezza per PieceArt.castle_piece, "" se la provincia non e' quella o
## l'immagine non e' ancora pronta.
static func map_original(province_id: String) -> String:
	return MAP_ORIGINAL if is_fortress(province_id) and AssetLibrary.is_remade(MAP_ORIGINAL) else ""


## Icona del castello costruito nella provincia, null se non e' la fortezza (o manca l'immagine).
static func icon(province_id: String) -> Texture2D:
	if not is_fortress(province_id) or not AssetLibrary.is_remade(ICON_ORIGINAL):
		return null
	return AssetLibrary.texture(ICON_ORIGINAL)
