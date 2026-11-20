class_name PieceArt
extends RefCounted
## Pedine della mappa dell'originale (fase 8): figure con lo stendardo per eserciti e flotte, figure degli agenti, pedine di
## crociata e jihad, dalle immagini di campmap/pieces esportate in PNG (AssetLibrary, ADR-007).
##
## Le pedine dell'originale sono dipinte con colori chiave che il gioco sostituisce con quelli della fazione: lo stendardo e'
## rosso puro, l'anello della base e' ciano e magenta. Qui: rosso e ciano -> colore primario della fazione (SetFactionCol, lo
## stesso della mappa), magenta -> secondario, con la stessa luminosita' del pixel originale. Anche le carte delle unita' hanno
## colori chiave sulle vesti e sugli scudi (158 carte su 234): magenta -> primario, verde -> secondario (PROVVISORIO: quale
## colore vada dove si vede a occhio confrontando con l'originale). Sullo scudo della figura si dipinge lo scudo della fazione (SetShieldImage, quinto argomento,
## per esempio F1003 in campmap/pieces/Units/Christian/Shields). Le pedine pronte restano in memoria per fazione e tipo.

const BASE := "campmap/pieces"
## Posizione dello scudo sulle figure (pixel dell'immagine originale), misurata sulle pedine esportate. PROVVISORIA finche'
## Federico non la conferma a occhio.
const SHIELD_ARMY := Rect2(4, 152, 31, 47)
const SHIELD_LEADER := Rect2(35, 150, 31, 47)
## Livelli del riempimento dello stendardo (uno per pila, con il massimo di 16 pile per esercito).
const FILL_STEPS := 16.0

## Castelli della mappa (campmap/pieces/buildings/*.Buf, stesso formato dei BIF): uno per grado di castello
## (CombatRules.castle_tier: 0 Fort ... 4 Fortress). Stockade, Warrior hold e Fortified village sono della campagna vichinga.
const CASTLE_PIECES := ["FORT.Buf", "KEEP.Buf", "CASTLE.Buf", "CITADEL.Buf", "FORTRESS.Buf"]
## Porto della mappa (campmap/ships/port.BIF): 8 fotogrammi, uno per orientamento del molo (SetPort, 0-7, fotogramma = +1;
## dedotto: Scozia 2 ha il molo verso est, Galles 5 verso ovest).
const PORT_IMAGE := "campmap/ships/port.BIF"
## Ombra dello stendardo (magenta nelle immagini dei castelli): nero trasparente.
const CASTLE_SHADOW := Color(0.0, 0.0, 0.0, 0.32)

static var _cache := {}


static func reset() -> void:
	_cache.clear()


## Cartella della cultura delle figure: Christian (cattolici e ortodossi), Muslim, Pagan.
static func culture_folder(religion: String) -> String:
	var r := religion.to_upper()
	if r.contains("MUSLIM"):
		return "Muslim"
	if r.contains("PAGAN"):
		return "Pagan"
	return "Christian"


## Cartella delle navi: Catholic, Orthodox, Muslim.
static func ship_folder(religion: String) -> String:
	var r := religion.to_upper()
	if r.contains("MUSLIM"):
		return "Muslim"
	if r.contains("ORTHODOX"):
		return "Orthodox"
	return "Catholic"


## Pedina di un esercito: `kind` = "army", "leader" (con un capo o un generale), "fleet", "crusade" o "jihad";
## `moving` = ha un percorso; `fill` = quanto e' piena l'armata (pile / massimo): lo stendardo e' colorato dal basso per quella
## parte e pallido sopra. Null se l'immagine manca (si torna ai segnalini disegnati).
static func army_piece(campaign: CampaignData, faction_id: String, kind: String, moving: bool, fill: float = 1.0) -> Texture2D:
	var state_name := "moving" if moving else "awaiting"
	var f := campaign.faction(faction_id) if campaign != null else null
	var religion := f.religion if f != null else ""
	var original := ""
	var shield_rect := SHIELD_ARMY
	match kind:
		"fleet":
			original = "%s/Ships/%s/fleet_held_%s.BIF" % [BASE, ship_folder(religion), state_name]
		"crusade":
			original = "%s/Agents/Crusade_held_%s.Bif" % [BASE, state_name]
		"jihad":
			original = "%s/Agents/Jihad_held_%s.BIF" % [BASE, state_name]
		"leader":
			original = "%s/Units/%s/army_leader_held_%s.BIF" % [BASE, culture_folder(religion), state_name]
			shield_rect = SHIELD_LEADER
		_:
			original = "%s/Units/%s/army_held_%s.BIF" % [BASE, culture_folder(religion), state_name]
	var with_shield := kind == "army" or kind == "leader"
	return _piece(campaign, faction_id, original, shield_rect if with_shield else Rect2(), fill)


## Carta dell'unita' con i colori della fazione `faction_id` al posto dei colori chiave, o null se manca l'immagine.
static func unit_card(campaign: CampaignData, faction_id: String, unit_id: String) -> Texture2D:
	var key := "carta|%s|%s" % [faction_id, unit_id.to_lower()]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var f := campaign.faction(faction_id) if campaign != null else null
	var culture := culture_folder(f.religion) if f != null else ""   # carte d'agente per cultura, come le pedine
	var source := AssetLibrary.unit_card(unit_id, culture)
	if source != null and AssetLibrary.is_remade(AssetLibrary.unit_card_path(unit_id, culture)):
		tex = source   # carta dipinta (ADR-043): non ha i colori chiave dell'originale da ricolorare
	elif source != null:
		var colors := faction_colors(campaign, faction_id)
		var img := source.get_image()
		img.convert(Image.FORMAT_RGBA8)
		recolor_card(img, colors[0], colors[1])
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Colori primario e secondario della fazione (SetFactionCol); grigi se la fazione non c'e' (ribelli).
static func faction_colors(campaign: CampaignData, faction_id: String) -> Array[Color]:
	var f := campaign.faction(faction_id) if campaign != null else null
	if f == null:
		return [Color(0.6, 0.6, 0.6), Color(0.3, 0.3, 0.3)]
	return [f.color_primary, f.color_secondary]


## Pedina di un agente del tipo `type_name` (EMISSARY, BISHOP...), o null se l'originale non ha la figura.
static func agent_piece(campaign: CampaignData, faction_id: String, type_name: String, moving: bool) -> Texture2D:
	var name := type_name.to_lower().replace("_", "")
	if name == "orthodoxbishop":
		name = "Orthodoxbishop"
	var state_name := "moving" if moving else "awaiting"
	# figure della cultura della fazione (Agents/Muslim, Agents/Pagan: assassini, emissari, spie, sciamani), poi le comuni
	var f := campaign.faction(faction_id) if campaign != null else null
	var culture := culture_folder(f.religion) if f != null else "Christian"
	var folders: Array[String] = []
	if culture != "Christian":
		folders.append("%s/Agents/%s/" % [BASE, culture])
	folders.append("%s/Agents/" % BASE)
	for folder in folders:
		for state in [state_name, "awaiting"]:
			var original := "%s%s_held_%s.BIF" % [folder, name, state]
			if AssetLibrary.has(original) or AssetLibrary.is_remade(original):
				return _piece(campaign, faction_id, original, Rect2())
	return null


## Porto con il molo orientato secondo `direction` (0-7), o null se l'immagine manca.
static func port_piece(direction: int) -> Texture2D:
	return AssetLibrary.texture(PORT_IMAGE, clampi(direction, 0, 7) + 1)


## Castello del grado `tier` (0-4) con lo stendardo del colore della fazione e il suo scudo sopra; null se il grado non
## esiste o l'immagine manca. Nelle immagini dei castelli lo stendardo e' rosso puro e la sua ombra a terra magenta.
## Come per gli eserciti (manuale p10: il colore nella bandiera indica quante truppe ci sono), lo stendardo e' colorato dal
## basso per la parte `fill` = guarnigione / posti del castello, pallido sopra: un castello vuoto ha lo stendardo pallido.
## Lo scudo sullo stendardo e' PROVVISORIO: l'originale usa una bandiera per fazione (Textures/campmap/Castleflags) la cui
## posizione sul castello non e' ancora ricavata (SetCastleFlagPos nello startpos).
## `special`: percorso di un castello proprio al posto di quello del grado (la fortezza degli Auror, FortressArt.map_original).
static func castle_piece(campaign: CampaignData, faction_id: String, tier: int, fill: float = 1.0, special: String = "") -> Texture2D:
	if tier < 0 or tier >= CASTLE_PIECES.size():
		return null
	var original := special if special != "" else "%s/buildings/%s" % [BASE, CASTLE_PIECES[tier]]
	var steps := roundi(clampf(fill, 0.0, 1.0) * FILL_STEPS)
	var key := "castello|%s|%d|%d|%s" % [faction_id, tier, steps, special]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var source := AssetLibrary.texture(original)
	if source != null:
		var colors := faction_colors(campaign, faction_id)
		var img := source.get_image()
		# il castello rifatto (ADR-061) arriva con le riduzioni intermedie: si ricolora l'immagine piena e si rifanno dopo,
		# altrimenti da lontano si vedrebbe lo stendardo rosso dell'originale
		var mipmaps := img.has_mipmaps()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		var banner := recolor_castle(img, FactionStyle.banner_color(faction_id, colors[0]), float(steps) / FILL_STEPS)
		_paint_banner_shield(img, campaign, faction_id, banner)
		if mipmaps:
			img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Castello: rosso -> colore dello stendardo (con la luminosita' del pixel) per la parte `fill` dal basso, pallido e
## trasparente sopra (come recolor_piece); magenta -> ombra trasparente. Restituisce il rettangolo dello stendardo (vuoto se
## l'immagine non ne ha).
static func recolor_castle(img: Image, banner: Color, fill: float = 1.0) -> Rect2i:
	var lo := Vector2i(img.get_width(), img.get_height())
	var hi := Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and key_of(c) == "rosso":
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	var cut := hi.y + 1 - roundi(float(hi.y - lo.y + 1) * clampf(fill, 0.0, 1.0)) if hi.x >= 0 else 0
	var empty := banner.lerp(Color(0.93, 0.9, 0.84), 0.75)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var k := key_of(c)
			if k == "rosso":
				var shade := minf(maxf(c.r, maxf(c.g, c.b)) / 0.95, 1.0)
				if y < cut:
					img.set_pixel(x, y, Color(empty.r * shade, empty.g * shade, empty.b * shade, c.a * 0.55))
				else:
					img.set_pixel(x, y, Color(banner.r * shade, banner.g * shade, banner.b * shade, c.a))
			elif k == "magenta":
				img.set_pixel(x, y, Color(CASTLE_SHADOW, CASTLE_SHADOW.a * c.a))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


static func _paint_banner_shield(img: Image, campaign: CampaignData, faction_id: String, banner: Rect2i) -> void:
	if banner.size.x < 12:
		return
	var w := banner.size.x - 6
	var size := Vector2i(w, roundi(float(w) * 1.2))
	var shield: Image = FactionStyle.shield_image(faction_id, size)
	if shield == null:
		var tex := AssetLibrary.faction_shield(faction_id, true)
		if tex == null:
			return
		shield = tex.get_image()
		if shield == null:
			return
		shield = shield.duplicate() as Image
		shield.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	else:
		shield = shield.duplicate() as Image
	shield.convert(Image.FORMAT_RGBA8)
	var at := Vector2i(banner.position.x + (banner.size.x - size.x) / 2, banner.position.y + 10)
	img.blend_rect(shield, Rect2i(Vector2i.ZERO, shield.get_size()), at)


# --- interni ------------------------------------------------------------------------------------------------------


## Stemma della fazione nello scudo di una pedina rifatta (`rect` = scudo dell'originale x `scale`): lo stemma dipinto del
## remake (data/fazioni.cfg [stemmi]) come sulle pedine dell'originale (30x36, 5 px sotto il bordo dello scudo), oppure
## lo scudo della pedina dell'originale (Units/<cultura>/Shields) ingrandito; nulla se la fazione non ha nessuno dei due.
static func _paint_remade_shield(img: Image, campaign: CampaignData, faction_id: String, rect: Rect2i, scale: int) -> void:
	var w := roundi(float(rect.size.x) * 30.0 / 31.0)
	var shield: Image = FactionStyle.shield_image(faction_id, Vector2i(w, roundi(float(w) * 1.2)))
	var at := rect.position + Vector2i(0, 5 * scale)
	if shield != null:
		shield = shield.duplicate() as Image
	else:
		var f := campaign.faction(faction_id) if campaign != null else null
		if f == null or f.shield_piece == "":
			return
		var tex := AssetLibrary.texture("%s/Units/%s/Shields/%s.BIF" % [BASE, culture_folder(f.religion), f.shield_piece])
		if tex == null:
			return
		shield = tex.get_image()
		shield.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_LANCZOS)
		at = rect.position
	shield.clear_mipmaps()
	shield.convert(Image.FORMAT_RGBA8)
	img.blend_rect(shield, Rect2i(Vector2i.ZERO, shield.get_size()), at)


static func _piece(campaign: CampaignData, faction_id: String, original: String, shield_rect: Rect2, fill: float = 1.0) -> Texture2D:
	var steps := roundi(clampf(fill, 0.0, 1.0) * FILL_STEPS)
	var key := "%s|%s|%d" % [faction_id, original.to_lower(), steps]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var source := AssetLibrary.texture(original)
	if source != null:
		var f := campaign.faction(faction_id) if campaign != null else null
		var colors := faction_colors(campaign, faction_id)
		var primary := colors[0]
		var secondary := colors[1]
		var img := source.get_image()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		var layout := AssetLibrary.remade_layout(original)
		if not layout.is_empty():
			# pedina rifatta (tools/prepara_pedine.py): si ricolorano solo stendardo e base, lo stemma va nel suo scudo
			var rects: Array[Rect2i] = []
			for k in ["stendardo", "base"]:
				if layout.has(k):
					rects.append(layout[k])
			recolor_piece(img, FactionStyle.banner_color(faction_id, primary), primary, secondary, float(steps) / FILL_STEPS, rects)
			if shield_rect.size != Vector2.ZERO and layout.has("scudo"):
				_paint_remade_shield(img, campaign, faction_id, layout["scudo"], int(layout.get("scala", 2)))
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
			_cache[key] = tex
			return tex
		recolor_piece(img, FactionStyle.banner_color(faction_id, primary), primary, secondary, float(steps) / FILL_STEPS)
		var custom := FactionStyle.shield_image(faction_id, Vector2i(30, 36)) if shield_rect.size != Vector2.ZERO else null
		if custom != null:
			var c_img := custom.duplicate() as Image
			c_img.convert(Image.FORMAT_RGBA8)
			img.blend_rect(c_img, Rect2i(Vector2i.ZERO, c_img.get_size()), Vector2i(shield_rect.position) + Vector2i(0, 5))
		elif shield_rect.size != Vector2.ZERO and f != null and f.shield_piece != "":
			var shield := AssetLibrary.texture("%s/Units/%s/Shields/%s.BIF" % [BASE, culture_folder(f.religion), f.shield_piece])
			if shield != null:
				var s_img := shield.get_image()
				s_img.convert(Image.FORMAT_RGBA8)
				img.blend_rect(s_img, Rect2i(Vector2i.ZERO, s_img.get_size()), Vector2i(shield_rect.position))
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Pedine: rosso e ciano -> primario, magenta -> secondario (vedi in testa al file), conservando la luminosita' dei pixel.
static func recolor(img: Image, primary: Color, secondary: Color) -> void:
	_recolor_keys(img, {"rosso": primary, "ciano": primary, "magenta": secondary})


## Pedine con lo stendardo: rosso -> colore dello stendardo per la parte `fill` dal basso, pallido e trasparente sopra; ciano
## -> primario, magenta -> secondario.
## `rects` (pedine rifatte): solo quei rettangoli contengono colori chiave e si scorrono solo quelli; vuoto = tutta l'immagine.
static func recolor_piece(img: Image, banner: Color, primary: Color, secondary: Color, fill: float, rects: Array[Rect2i] = []) -> void:
	var whole := Rect2i(Vector2i.ZERO, img.get_size())
	var areas: Array[Rect2i] = []
	for r in rects:
		var c := r.intersection(whole)
		if c.has_area():
			areas.append(c)
	if areas.is_empty():
		areas.append(whole)
	var top := img.get_height()
	var bottom := -1
	for area in areas:
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				if key_of(img.get_pixel(x, y)) == "rosso":
					top = mini(top, y)
					bottom = maxi(bottom, y)
	var cut := bottom + 1 - roundi(float(bottom - top + 1) * clampf(fill, 0.0, 1.0))
	var empty := banner.lerp(Color(0.93, 0.9, 0.84), 0.75)
	for area in areas:
		_recolor_piece_area(img, area, banner, primary, secondary, cut, empty)


static func _recolor_piece_area(img: Image, area: Rect2i, banner: Color, primary: Color, secondary: Color, cut: int, empty: Color) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var key := key_of(c)
			if key == "":
				continue
			var shade := minf(maxf(c.r, maxf(c.g, c.b)) / 0.95, 1.0)
			var target := primary if key == "ciano" else secondary if key == "magenta" else banner
			var alpha := c.a
			if key == "rosso" and y < cut:
				target = empty
				alpha = c.a * 0.55
			elif key == "verde":
				continue
			img.set_pixel(x, y, Color(target.r * shade, target.g * shade, target.b * shade, alpha))


## Carte delle unita': magenta -> primario, verde -> secondario.
static func recolor_card(img: Image, primary: Color, secondary: Color) -> void:
	_recolor_keys(img, {"magenta": primary, "verde": secondary})


## Colore chiave del pixel ("rosso", "verde", "ciano", "magenta" o ""): uno o due canali forti e gli altri quasi spenti
## rispetto a loro, anche nelle ombre (la tavolozza dell'originale ha varie sfumature di ogni colore chiave).
static func key_of(c: Color) -> String:
	var hi := maxf(c.r, maxf(c.g, c.b))
	if hi < 0.25:
		return ""
	var off := hi * 0.33   # i bordi sfumati delle zone chiave hanno un po' degli altri canali
	var near := hi * 0.7
	if c.r >= near and c.g <= off and c.b <= off:
		return "rosso"
	if c.g >= near and c.r <= off and c.b <= off:
		return "verde"
	if c.g >= near and c.b >= near and c.r <= off:
		return "ciano"
	if c.r >= near and c.b >= near and c.g <= off:
		return "magenta"
	return ""


static func _recolor_keys(img: Image, mapping: Dictionary) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var key := key_of(c)
			if key == "" or not mapping.has(key):
				continue
			var shade := minf(maxf(c.r, maxf(c.g, c.b)) / 0.95, 1.0)
			var target: Color = mapping[key]
			img.set_pixel(x, y, Color(target.r * shade, target.g * shade, target.b * shade, c.a))
