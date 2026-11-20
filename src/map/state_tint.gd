class_name StateTint
extends RefCounted
## Tinta dei proprietari sulla mappa letta dallo stato di gioco (GameState) invece che dallo
## startpos: riscrive la riga dei colori della tabella costruita da RegionMap.build_table.


## Colori della tinta per religione (tasto R): distinti tra loro e dal grigio delle religioni sconosciute.
const RELIGION_COLORS := {
	"CATHOLIC": Color(0.85, 0.72, 0.20),
	"ORTHODOX": Color(0.55, 0.30, 0.75),
	"MUSLIM": Color(0.15, 0.60, 0.30),
	"PAGAN": Color(0.55, 0.35, 0.18),
	"HERETIC": Color(0.80, 0.15, 0.15),
	"IMPERIAL": Color(0.92, 0.92, 0.95),   # Culto Imperiale degli Auror: bianco argento, i colori della fazione
}
const UNKNOWN_RELIGION_COLOR := Color(0.5, 0.5, 0.5)


## Colore di un proprietario: colore primario della fazione, grigio dei ribelli per FN_REBEL,
## fazioni sconosciute o proprietario vuoto.
static func owner_color(region_map: RegionMap, owner_id: String) -> Color:
	var key := owner_id.strip_edges().to_upper()
	if key == "" or key == "FN_REBEL":
		return region_map.rebel_color
	var f: CampaignData.Faction = region_map.data.faction(key)
	if f == null:
		return region_map.rebel_color
	return Color(f.color_primary, 1.0)


## Colore di una religione ("CATHOLIC", "HERETIC"...); sconosciuta: grigio.
static func religion_color(religion: String) -> Color:
	var key := religion.strip_edges().to_upper()
	if RELIGION_COLORS.has(key):
		var c: Color = RELIGION_COLORS[key]
		return c
	return UNKNOWN_RELIGION_COLOR


## Restituisce una nuova tabella con i colori dei proprietari presi dallo stato; la riga
## delle informazioni (evidenziata, gruppo, tipo) resta quella di `table`.
## Le regioni che lo stato non conosce mantengono il colore che avevano.
static func apply(table: Image, region_map: RegionMap, state: GameState) -> Image:
	return _paint(table, region_map, state, false)


## Come `apply`, ma ogni provincia ha il colore della sua religione maggioritaria (`ProvinceState.majority_religion`).
static func apply_religion(table: Image, region_map: RegionMap, state: GameState) -> Image:
	return _paint(table, region_map, state, true)


static func _paint(table: Image, region_map: RegionMap, state: GameState, by_religion: bool) -> Image:
	var bytes: PackedByteArray = table.get_data()
	for p in state.provinces:
		var region: CampaignData.Region = region_map.data.region(p.id)
		if region == null or region.is_sea:
			continue
		var tint: Color = religion_color(p.majority_religion()) if by_religion else owner_color(region_map, p.owner)
		for idx in region_map.indices_for_region(region):
			var o := (RegionMap.ROW_OWNER * RegionMap.TABLE_SIZE + idx) * 4
			bytes[o] = tint.r8
			bytes[o + 1] = tint.g8
			bytes[o + 2] = tint.b8
			bytes[o + 3] = 255
	return Image.create_from_data(RegionMap.TABLE_SIZE, 2, false, Image.FORMAT_RGBA8, bytes)
