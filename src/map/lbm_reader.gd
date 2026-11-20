class_name LbmReader
extends RefCounted
## Lettore di immagini IFF PBM (Deluxe Paint) con BODY compresso ByteRun1.
##
## È il formato di `Textures/campmap/LukMap.Lbm`: una bitmap a 8 bit per pixel
## in cui ogni valore è un indice di palette (qui usato come indice di regione).
## Il file è composto da chunk: BMHD (intestazione), CMAP (palette) e BODY
## (pixel, compressi a pacchetti PackBits). Il lettore non scrive mai il file.
##
## Uso:
##   var lbm := LbmReader.load_file(GameFiles.lookup_map())
##   if lbm.is_valid(): print(lbm.index_at(10, 20))

var width := 0
var height := 0
var bit_planes := 0
var compression := 0          ## 0 = nessuna, 1 = ByteRun1
var masking := 0
var transparent_index := 0
var palette := PackedColorArray()
var indices := PackedByteArray()   ## width * height byte, righe dall'alto
var error := ""                    ## vuoto se la lettura è riuscita


## Legge un file. In caso di problemi restituisce comunque un oggetto con `error` valorizzato.
static func load_file(path: String) -> LbmReader:
	if not FileAccess.file_exists(path):
		var missing := LbmReader.new()
		missing.error = "File non trovato: %s" % path
		return missing
	return parse(FileAccess.get_file_as_bytes(path))


## Decodifica il contenuto di un file IFF PBM.
static func parse(bytes: PackedByteArray) -> LbmReader:
	var reader := LbmReader.new()
	reader._parse(bytes)
	return reader


## Costruisce un lettore da indici già decodificati (utile nei test).
static func from_indices(w: int, h: int, data: PackedByteArray, pal: PackedColorArray = PackedColorArray()) -> LbmReader:
	var reader := LbmReader.new()
	if w <= 0 or h <= 0 or data.size() != w * h:
		reader.error = "Dimensioni incoerenti: %dx%d con %d byte" % [w, h, data.size()]
		return reader
	reader.width = w
	reader.height = h
	reader.bit_planes = 8
	reader.indices = data
	reader.palette = pal
	return reader


func is_valid() -> bool:
	return error == ""


## Indice di palette del pixel (x, y), oppure -1 se fuori dall'immagine.
func index_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return indices[y * width + x]


## Colore di palette per un indice, oppure Color.TRANSPARENT se l'indice non esiste.
func palette_color(index: int) -> Color:
	if index < 0 or index >= palette.size():
		return Color.TRANSPARENT
	return palette[index]


## Immagine a un canale (FORMAT_R8) con gli indici: il rosso normalizzato vale indice / 255.
func to_image() -> Image:
	if not is_valid():
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_R8, indices)


func _parse(bytes: PackedByteArray) -> void:
	if bytes.size() < 12 or _tag(bytes, 0) != "FORM" or _tag(bytes, 8) != "PBM ":
		error = "Non è un file IFF di tipo PBM"
		return
	var end := mini(bytes.size(), 8 + _u32(bytes, 4))
	var pos := 12
	var has_header := false
	var body := PackedByteArray()
	var has_body := false
	while pos + 8 <= end:
		var tag := _tag(bytes, pos)
		var chunk_len := _u32(bytes, pos + 4)
		var start := pos + 8
		var stop := mini(start + chunk_len, bytes.size())
		match tag:
			"BMHD":
				if stop - start < 14:
					error = "Chunk BMHD troppo corto"
					return
				width = _u16(bytes, start)
				height = _u16(bytes, start + 2)
				bit_planes = bytes[start + 8]
				masking = bytes[start + 9]
				compression = bytes[start + 10]
				transparent_index = _u16(bytes, start + 12)
				has_header = true
			"CMAP":
				palette = PackedColorArray()
				@warning_ignore("integer_division")
				var color_count := (stop - start) / 3
				for i in range(color_count):
					var o := start + i * 3
					palette.append(Color8(bytes[o], bytes[o + 1], bytes[o + 2]))
			"BODY":
				body = bytes.slice(start, stop)
				has_body = true
		pos = start + chunk_len + (chunk_len & 1)
	if not has_header:
		error = "Chunk BMHD mancante"
		return
	if not has_body:
		error = "Chunk BODY mancante"
		return
	if width <= 0 or height <= 0:
		error = "Dimensioni non valide: %dx%d" % [width, height]
		return
	if bit_planes != 8:
		error = "Supportati solo i PBM a 8 bit per pixel (trovati %d)" % bit_planes
		return
	if compression != 0 and compression != 1:
		error = "Compressione %d non supportata" % compression
		return
	# Ogni riga occupa un numero pari di byte (riempimento se la larghezza è dispari).
	var stride := width + (width & 1)
	var expected := stride * height
	var raw := body
	if compression == 1:
		raw = _unpack_byterun1(body, expected)
	if raw.size() < expected:
		error = "BODY troppo corto: %d byte decodificati su %d" % [raw.size(), expected]
		return
	if stride == width:
		indices = raw.slice(0, expected)
	else:
		indices = PackedByteArray()
		for y in range(height):
			indices.append_array(raw.slice(y * stride, y * stride + width))


## Decompressione ByteRun1 (PackBits): n in 0..127 = copia n+1 byte; n in 129..255 =
## ripete il byte successivo 257-n volte; n = 128 non fa nulla. Si ferma a `expected` byte.
static func _unpack_byterun1(packed: PackedByteArray, expected: int) -> PackedByteArray:
	var out := PackedByteArray()
	var size := packed.size()
	var i := 0
	while i < size and out.size() < expected:
		var n: int = packed[i]
		i += 1
		if n < 128:
			var count := n + 1
			out.append_array(packed.slice(i, mini(i + count, size)))
			i += count
		elif n > 128:
			if i >= size:
				break
			var run := PackedByteArray()
			run.resize(257 - n)
			run.fill(packed[i])
			out.append_array(run)
			i += 1
	if out.size() > expected:
		out.resize(expected)
	return out


static func _tag(bytes: PackedByteArray, offset: int) -> String:
	return bytes.slice(offset, offset + 4).get_string_from_ascii()


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 8) | bytes[offset + 1]


static func _u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]
