class_name RegionMap
extends RefCounted
## Collega la bitmap delle regioni (LukMap.Lbm) ai dati della campagna.
##
## Regola verificata sul file originale:
## - regione di terra: indice di palette (i >> 1) - 1, nell'ordine di
##   DeclareLandRegion; ogni regione usa quindi due indici consecutivi,
##   2k+2 e 2k+3, che sono la stessa regione;
## - zona di mare k: indice 216 + k;
## - altri indici (0, oltre le zone dichiarate): nessuna regione.
## Le coordinate dello startpos (SetCastle, SetPort, SetOrigin) divise per 16
## sono i pixel della bitmap, che ha lo stesso sistema di coordinate della mappa.
##
## Mappa del mondo (ADR-077, WorldMap): indici a 16 bit, una sola voce per regione (gruppo = indice), terra da 1, mare da
## `WorldMap.sea_first`; la tabella e' larga 2048 e lo shader confronta gli indici (`index_groups`). Le costanti dello schema
## originale diventano variabili statiche che `_init` imposta secondo la bitmap ricevuta.
##
## La "tabella" è un'immagine 256x2 letta dallo shader `campaign_map.gdshader`:
## per ogni indice di palette, la riga 0 dà il colore del proprietario (alfa 0 =
## nessuna tinta) e la riga 1 dà R = evidenziata (255/0), G = gruppo della
## regione (indici della stessa regione hanno lo stesso gruppo, quindi niente
## confine tra 2k+2 e 2k+3), B = tipo (0 nessuna, 128 mare, 255 terra).

const LAND_FIRST_INDEX := 2
const LEGACY_SEA_FIRST := 216
const LEGACY_TABLE_SIZE := 256
const WORLD_TABLE_SIZE := 2048
const STARTPOS_SCALE := 16
static var SEA_FIRST_INDEX := LEGACY_SEA_FIRST
static var TABLE_SIZE := LEGACY_TABLE_SIZE
## Vero con la mappa del mondo (l'ultima RegionMap creata decide).
static var world := false
const ROW_OWNER := 0
const ROW_INFO := 1
const KIND_NONE := 0
const KIND_SEA := 128
const KIND_LAND := 255
var lbm: LbmReader
var data: CampaignData

var rebel_color := Color8(140, 140, 140)   ## colore delle province dei ribelli (o senza fazione)

var _land: Array[CampaignData.Region] = []
var _sea: Array[CampaignData.Region] = []
var _by_index := {}       ## mappa del mondo: indice -> regione
var _index_of := {}       ## mappa del mondo: id -> indice


func _init(bitmap: LbmReader, campaign: CampaignData) -> void:
	lbm = bitmap
	data = campaign
	_land = campaign.land_regions()
	_sea = campaign.sea_regions()
	var wm := bitmap as WorldMap
	world = wm != null
	if world:
		SEA_FIRST_INDEX = wm.sea_first
		TABLE_SIZE = WORLD_TABLE_SIZE
		for r in campaign.regions:
			var i := int(wm.index_of.get(r.id, 0))
			if i > 0 and i < TABLE_SIZE:
				_by_index[i] = r
				_index_of[r.id] = i
	else:
		SEA_FIRST_INDEX = LEGACY_SEA_FIRST
		TABLE_SIZE = LEGACY_TABLE_SIZE


## Regione associata a un indice di palette, oppure null.
func region_for_index(palette_index: int) -> CampaignData.Region:
	if world:
		return _by_index.get(palette_index)
	if palette_index >= SEA_FIRST_INDEX:
		var s := palette_index - SEA_FIRST_INDEX
		if s < _sea.size():
			return _sea[s]
		return null
	if palette_index >= LAND_FIRST_INDEX:
		var k := (palette_index >> 1) - 1
		if k < _land.size():
			return _land[k]
	return null


## Indici di palette usati da una regione: due per la terra, uno per il mare.
func indices_for_region(region: CampaignData.Region) -> PackedInt32Array:
	if world:
		return PackedInt32Array([int(_index_of.get(region.id, 0))])
	if region.is_sea:
		return PackedInt32Array([SEA_FIRST_INDEX + region.index])
	var first := 2 * region.index + LAND_FIRST_INDEX
	return PackedInt32Array([first, first + 1])


## Gruppo di un indice: 0 = nessuna regione, 1..107 = terra, 216.. = mare.
## Indici con lo stesso gruppo appartengono alla stessa regione.
static func group_for_index(palette_index: int) -> int:
	if world:
		return maxi(0, palette_index)
	if palette_index < LAND_FIRST_INDEX:
		return 0
	if palette_index < SEA_FIRST_INDEX:
		return palette_index >> 1
	return palette_index


## Regione al pixel (x, y) della bitmap, oppure null (nessuna regione o fuori mappa).
func region_at_pixel(x: int, y: int) -> CampaignData.Region:
	var palette_index := lbm.index_at(x, y)
	if palette_index < 0:
		return null
	return region_for_index(palette_index)


## Regione a una coordinata dello startpos (pixel * 16).
func region_at_startpos(pos: Vector2i) -> CampaignData.Region:
	var pixel := startpos_to_pixel(pos)
	return region_at_pixel(pixel.x, pixel.y)


static func startpos_to_pixel(pos: Vector2i) -> Vector2i:
	return Vector2i(floori(pos.x / float(STARTPOS_SCALE)), floori(pos.y / float(STARTPOS_SCALE)))


## Colore del proprietario: colore primario della fazione, grigio per i ribelli.
func owner_color(region: CampaignData.Region) -> Color:
	if region.owner == "FN_REBEL":
		return rebel_color
	var f := data.faction(region.owner)
	if f == null:
		return rebel_color
	return Color(f.color_primary, 1.0)


## Costruisce la tabella (256x2, RGBA8) letta dallo shader. `selected` è la regione evidenziata.
## I byte sono scritti direttamente (senza set_pixel) per evitare arrotondamenti sui canali.
func build_table(selected: CampaignData.Region = null) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(TABLE_SIZE * 2 * 4)
	bytes.fill(0)
	for i in range(TABLE_SIZE):
		var region := region_for_index(i)
		var kind := KIND_NONE
		var highlight := 0
		var o := (ROW_OWNER * TABLE_SIZE + i) * 4
		var n := (ROW_INFO * TABLE_SIZE + i) * 4
		if region != null:
			if region.is_sea:
				kind = KIND_SEA
			else:
				kind = KIND_LAND
				var tint := owner_color(region)
				bytes[o] = tint.r8
				bytes[o + 1] = tint.g8
				bytes[o + 2] = tint.b8
				bytes[o + 3] = 255
			if region == selected:
				highlight = 255
		bytes[n] = highlight
		bytes[n + 1] = group_for_index(i) & 255   # nel mondo lo shader confronta gli indici (index_groups)
		bytes[n + 2] = kind
		bytes[n + 3] = 255
	return Image.create_from_data(TABLE_SIZE, 2, false, Image.FORMAT_RGBA8, bytes)
