class_name BorderExtractor
extends RefCounted
## Estrae dalla bitmap delle regioni i confini come polilinee vettoriali.
##
## Algoritmo:
## 1. ogni indice di palette diventa un gruppo di regione (RegionMap.group_for_index):
##    gli indici pari e dispari della stessa regione hanno lo stesso gruppo e non
##    generano confini;
## 2. si scorrono i pixel una volta in orizzontale e una in verticale; dove due pixel
##    vicini hanno gruppi diversi si registra lo spigolo unitario che li separa
##    (vertici = angoli dei pixel, id = y * (larghezza + 1) + x), associato alla
##    coppia ordinata di gruppi (A < B);
## 3. per ogni coppia gli spigoli si concatenano in polilinee: si parte dai vertici
##    di grado diverso da 2 (estremi e incroci), poi restano i cicli chiusi. Il
##    risultato è deterministico: coppie in ordine crescente, si parte dal vertice
##    con id minore e si sceglie il vicino con id minore;
## 4. i vertici allineati si fondono (estrazione "grezza", coordinate intere);
## 5. la levigatura applica Douglas-Peucker (tolleranza in pixel della bitmap) e poi
##    Chaikin (taglio degli angoli), lasciando fissi gli estremi, così le polilinee
##    che si incontrano in un incrocio restano agganciate.
##
## Costo (stima su LukMap 2048x1536): 2 x 3,1 milioni di confronti tra byte, circa
## 120 mila spigoli, 661 polilinee. Misurato in Python lo stesso algoritmo: 0,4 s con
## numpy per la ricerca; in GDScript ci si aspetta da 2 a 5 secondi la prima volta,
## poi la cache (`CACHE_PATH`) riduce la lettura a pochi decimi di secondo.
## Va eseguito in un thread (vedi scenes/campaign_map.gd).

## Tipi di confine.
const KIND_LAND_LAND := 0   ## terra - terra
const KIND_COAST := 1       ## terra - mare direttamente adiacenti
const KIND_SEA_SEA := 2     ## mare - mare
const KIND_LAND_NONE := 3   ## terra - nessuna regione (nella mappa reale è la costa)
const KIND_SEA_NONE := 4    ## mare - nessuna regione

const CACHE_PATH := "user://cache/confini_v1.dat"
const CACHE_MAGIC := 0x4D544231
const CACHE_VERSION := 1
const MAX_CACHED_BORDERS := 100000

## Una polilinea di confine tra due gruppi di regione (group_a < group_b).
class Border:
	var group_a := 0
	var group_b := 0
	var kind := 0
	var closed := false                 ## true: il primo punto è ripetuto in fondo
	var points := PackedVector2Array()  ## coordinate in pixel della bitmap

	func involves(group: int) -> bool:
		return group_a == group or group_b == group

## Distanza massima (pixel della bitmap) tra la scalettatura e la polilinea semplificata.
var simplify_tolerance := 0.9
var smooth_iterations := 2

# Statistiche dell'ultima estrazione.
var edge_count := 0
var from_cache := false
var elapsed_ms := 0

var _ev0 := PackedInt32Array()   ## primo vertice di ogni spigolo
var _ev1 := PackedInt32Array()   ## secondo vertice
var _ekey := PackedInt32Array()  ## coppia di gruppi: a * 256 + b
var _used := PackedByteArray()


## Tipo di confine tra due gruppi diversi (l'ordine non conta).
static func kind_of(group_a: int, group_b: int) -> int:
	var ca := _class_of(group_a)
	var cb := _class_of(group_b)
	if ca == 0 or cb == 0:
		return KIND_SEA_NONE if maxi(ca, cb) == 2 else KIND_LAND_NONE
	if ca == 1 and cb == 1:
		return KIND_LAND_LAND
	if ca == 2 and cb == 2:
		return KIND_SEA_SEA
	return KIND_COAST


## 0 = nessuna regione, 1 = terra, 2 = mare.
static func _class_of(group: int) -> int:
	if group <= 0:
		return 0
	if group >= RegionMap.SEA_FIRST_INDEX:
		return 2
	return 1


## Estrazione completa: polilinee grezze, poi semplificate e levigate.
func extract(indices: PackedByteArray, w: int, h: int) -> Array[Border]:
	var borders := extract_raw(indices, w, h)
	for b in borders:
		b.points = smooth_points(b.points, b.closed, simplify_tolerance, smooth_iterations)
	return borders


## Polilinee a coordinate intere, con i soli vertici in cui la direzione cambia.
func extract_raw(indices: PackedByteArray, w: int, h: int) -> Array[Border]:
	var result: Array[Border] = []
	if w < 1 or h < 1 or indices.size() != w * h:
		return result
	var start := Time.get_ticks_msec()
	var group := PackedInt32Array()
	group.resize(256)
	for i in range(256):
		group[i] = RegionMap.group_for_index(i)
	var stride := w + 1
	_ev0 = PackedInt32Array()
	_ev1 = PackedInt32Array()
	_ekey = PackedInt32Array()

	# Spigoli verticali, tra pixel vicini sulla stessa riga: la linea sta a x (bordo sinistro del pixel destro).
	for y in range(h):
		var row := y * w
		var prev: int = indices[row]
		for x in range(1, w):
			var cur: int = indices[row + x]
			if cur != prev:
				var ga := group[prev]
				var gb := group[cur]
				if ga != gb:
					_ekey.append(ga * 256 + gb if ga < gb else gb * 256 + ga)
					_ev0.append(y * stride + x)
					_ev1.append((y + 1) * stride + x)
			prev = cur
	# Spigoli orizzontali, tra un pixel e quello sotto: la linea sta a y + 1.
	for y in range(h - 1):
		var row := y * w
		for x in range(w):
			var a: int = indices[row + x]
			var b: int = indices[row + w + x]
			if a != b:
				var ga := group[a]
				var gb := group[b]
				if ga != gb:
					_ekey.append(ga * 256 + gb if ga < gb else gb * 256 + ga)
					var v := (y + 1) * stride + x
					_ev0.append(v)
					_ev1.append(v + 1)

	edge_count = _ekey.size()
	_used = PackedByteArray()
	_used.resize(edge_count)
	_used.fill(0)

	# Ordinamento per coppia (counting sort sulla chiave a 16 bit).
	var offsets := PackedInt32Array()
	offsets.resize(65537)
	offsets.fill(0)
	for e in range(edge_count):
		offsets[_ekey[e] + 1] += 1
	for k in range(65536):
		offsets[k + 1] += offsets[k]
	var fill_pos := offsets.duplicate()
	var order := PackedInt32Array()
	order.resize(edge_count)
	for e in range(edge_count):
		var k := _ekey[e]
		order[fill_pos[k]] = e
		fill_pos[k] += 1

	for key in range(65536):
		var first := offsets[key]
		var last := offsets[key + 1]
		if last == first:
			continue
		var group_a := key >> 8
		var group_b := key & 255
		var kind := kind_of(group_a, group_b)
		var chains := _chain_edges(order.slice(first, last))
		for chain in chains:
			var border := Border.new()
			border.group_a = group_a
			border.group_b = group_b
			border.kind = kind
			border.closed = chain[0]
			border.points = _path_to_points(chain[1], stride)
			result.append(border)
	elapsed_ms = Time.get_ticks_msec() - start
	return result


## Concatena gli spigoli di una coppia. Restituisce un array di [chiusa: bool, vertici: PackedInt32Array].
func _chain_edges(ids: PackedInt32Array) -> Array:
	var adjacency := {}
	for e in ids:
		_adjacency_add(adjacency, _ev0[e], e)
		_adjacency_add(adjacency, _ev1[e], e)
	var vertices := PackedInt32Array(adjacency.keys())
	vertices.sort()
	var chains := []
	# Prima le polilinee aperte: partono da estremi (grado 1) e incroci (grado 4).
	for v in vertices:
		var list: PackedInt32Array = adjacency[v]
		if list.size() == 2:
			continue
		while true:
			var e := _next_unused(list, v)
			if e < 0:
				break
			chains.append([false, _walk(adjacency, v, e)])
	# Poi i cicli chiusi: il vertice di partenza è il minimo del ciclo.
	for v in vertices:
		var e := _next_unused(adjacency[v], v)
		if e >= 0:
			chains.append([true, _walk(adjacency, v, e)])
	return chains


func _adjacency_add(adjacency: Dictionary, vertex: int, edge: int) -> void:
	if adjacency.has(vertex):
		var list: PackedInt32Array = adjacency[vertex]
		list.append(edge)
		adjacency[vertex] = list
	else:
		adjacency[vertex] = PackedInt32Array([edge])


func _other_end(edge: int, vertex: int) -> int:
	return _ev1[edge] if _ev0[edge] == vertex else _ev0[edge]


## Spigolo non ancora usato che parte da `vertex` verso il vicino con id minore, oppure -1.
func _next_unused(list: PackedInt32Array, vertex: int) -> int:
	var best := -1
	var best_vertex := 0
	for c in list:
		if _used[c] != 0:
			continue
		var far := _other_end(c, vertex)
		if best < 0 or far < best_vertex:
			best = c
			best_vertex = far
	return best


## Percorre gli spigoli da `start` lungo `first_edge`, fino a un vertice di grado diverso da 2
## o al ritorno sul punto di partenza.
func _walk(adjacency: Dictionary, start: int, first_edge: int) -> PackedInt32Array:
	var path := PackedInt32Array([start])
	var v := start
	var e := first_edge
	while true:
		_used[e] = 1
		v = _other_end(e, v)
		path.append(v)
		var list: PackedInt32Array = adjacency[v]
		if list.size() != 2:
			break
		var next := -1
		for c in list:
			if _used[c] == 0:
				next = c
		if next < 0:
			break
		e = next
	return path


## Da id di vertici a punti, scartando quelli sul prolungamento del tratto precedente.
@warning_ignore("integer_division")
func _path_to_points(path: PackedInt32Array, stride: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := path.size()
	var px := 0
	var py := 0
	for i in range(n):
		var v := path[i]
		var x := v % stride
		var y := v / stride
		if i > 0 and i < n - 1:
			var nv := path[i + 1]
			var cross := (x - px) * (nv / stride - y) - (y - py) * (nv % stride - x)
			if cross == 0:
				continue
		out.append(Vector2(x, y))
		px = x
		py = y
	return out


# --- Levigatura ------------------------------------------------------------------

## Semplificazione e taglio degli angoli di una polilinea. Gli estremi non si muovono.
static func smooth_points(points: PackedVector2Array, closed: bool, tolerance: float, iterations: int) -> PackedVector2Array:
	var simple := simplify(points, tolerance)
	# Un anello minuscolo (un pixel isolato) collasserebbe in un segmento andata e ritorno: resta intero.
	if closed and simple.size() < 4:
		simple = points
	return chaikin(simple, closed, iterations)


## Douglas-Peucker (iterativo): toglie i punti che distano meno di `tolerance` dal segmento che li sostituisce.
static func simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3 or tolerance <= 0.0:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep.fill(0)
	keep[0] = 1
	keep[n - 1] = 1
	var tol2 := tolerance * tolerance
	var stack := PackedInt32Array([0, n - 1])
	while stack.size() > 0:
		var hi := stack[stack.size() - 1]
		var lo := stack[stack.size() - 2]
		stack.resize(stack.size() - 2)
		if hi <= lo + 1:
			continue
		var best := -1.0
		var best_i := -1
		var a := points[lo]
		var b := points[hi]
		for i in range(lo + 1, hi):
			var d := _dist2_to_segment(points[i], a, b)
			if d > best:
				best = d
				best_i = i
		if best > tol2:
			keep[best_i] = 1
			stack.append(lo)
			stack.append(best_i)
			stack.append(best_i)
			stack.append(hi)
	var out := PackedVector2Array()
	for i in range(n):
		if keep[i] == 1:
			out.append(points[i])
	return out


static func _dist2_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 == 0.0:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


## Chaikin: ogni tratto P-Q diventa due punti a 1/4 e 3/4. Nelle polilinee aperte
## restano gli estremi; in quelle chiuse (primo punto ripetuto in fondo) la curva si richiude.
static func chaikin(points: PackedVector2Array, closed: bool, iterations: int) -> PackedVector2Array:
	var current := points
	for _it in range(iterations):
		var n := current.size()
		if n < 3 or (closed and n < 4):
			return current
		var out := PackedVector2Array()
		if closed:
			var count := n - 1
			for i in range(count):
				var p := current[i]
				var q := current[(i + 1) % count]
				out.append(p * 0.75 + q * 0.25)
				out.append(p * 0.25 + q * 0.75)
			out.append(out[0])
		else:
			out.append(current[0])
			for i in range(n - 1):
				var p := current[i]
				var q := current[i + 1]
				out.append(p * 0.75 + q * 0.25)
				out.append(p * 0.25 + q * 0.75)
			out.append(current[n - 1])
		current = out
	return current


# --- Mappa del mondo (ADR-077) ------------------------------------------------------

const WORLD_MAGIC := 0x4D514231

## Confini precalcolati da tools/mondo/confini_mondo.py (stesso algoritmo, gruppi = indici a 16 bit). Vuoto se il file
## manca o non e' valido. Formato: magic, versione 1, larghezza, altezza, numero; per polilinea gruppo_a u16, gruppo_b u16,
## tipo u8, chiusa u8, punti u32, poi i punti in float32.
static func load_world(path: String) -> Array[Border]:
	var result: Array[Border] = []
	if not FileAccess.file_exists(path):
		return result
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != WORLD_MAGIC or f.get_32() != 1:
		return result
	f.get_32()
	f.get_32()
	var count := f.get_32()
	for _i in range(count):
		var b := Border.new()
		b.group_a = f.get_16()
		b.group_b = f.get_16()
		b.kind = f.get_8()
		b.closed = f.get_8() == 1
		var n := f.get_32()
		var raw := f.get_buffer(n * 8)
		if raw.size() != n * 8:
			result.clear()
			return result
		var floats := raw.to_float32_array()
		var pts := PackedVector2Array()
		pts.resize(n)
		for k in range(n):
			pts[k] = Vector2(floats[2 * k], floats[2 * k + 1])
		b.points = pts
		result.append(b)
	return result


# --- Cache -----------------------------------------------------------------------

## Chiave della cache: impronta SHA-256 e dimensione del file della mappa, più le dimensioni della bitmap.
static func cache_key(source_path: String, w: int, h: int) -> String:
	if not FileAccess.file_exists(source_path):
		return "senza-file|%dx%d" % [w, h]
	var size := 0
	var f := FileAccess.open(source_path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	return "%s|%d|%dx%d" % [FileAccess.get_sha256(source_path), size, w, h]


## Legge i confini dalla cache; array vuoto se manca, se la chiave o i parametri non coincidono o se è corrotta.
func load_cache(cache_path: String, key: String, w: int, h: int) -> Array[Border]:
	var result: Array[Border] = []
	if not FileAccess.file_exists(cache_path):
		return result
	var f := FileAccess.open(cache_path, FileAccess.READ)
	if f == null:
		return result
	if f.get_32() != CACHE_MAGIC or f.get_32() != CACHE_VERSION:
		return result
	if f.get_pascal_string() != key:
		return result
	if f.get_32() != w or f.get_32() != h:
		return result
	if not is_equal_approx(f.get_float(), simplify_tolerance) or f.get_32() != smooth_iterations:
		return result
	var count := f.get_32()
	if count <= 0 or count > MAX_CACHED_BORDERS:
		return result
	for _i in range(count):
		var border := Border.new()
		border.group_a = f.get_16()
		border.group_b = f.get_16()
		border.kind = f.get_8()
		border.closed = f.get_8() == 1
		var pts: Variant = f.get_var()
		if f.get_error() != OK or typeof(pts) != TYPE_PACKED_VECTOR2_ARRAY:
			result.clear()
			return result
		border.points = pts as PackedVector2Array
		result.append(border)
	return result


## Scrive la cache (prima in un file temporaneo, poi lo rinomina). false se non riesce.
func save_cache(cache_path: String, key: String, w: int, h: int, borders: Array[Border]) -> bool:
	if DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir()) != OK:
		return false
	var tmp := cache_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(CACHE_MAGIC)
	f.store_32(CACHE_VERSION)
	f.store_pascal_string(key)
	f.store_32(w)
	f.store_32(h)
	f.store_float(simplify_tolerance)
	f.store_32(smooth_iterations)
	f.store_32(borders.size())
	for b in borders:
		f.store_16(b.group_a)
		f.store_16(b.group_b)
		f.store_8(b.kind)
		f.store_8(1 if b.closed else 0)
		f.store_var(b.points)
	f.close()
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
	return DirAccess.rename_absolute(tmp, cache_path) == OK


## Usa la cache se valida, altrimenti estrae e la scrive. `from_cache` e `elapsed_ms` descrivono l'esito.
func load_or_extract(source_path: String, indices: PackedByteArray, w: int, h: int, cache_path: String = CACHE_PATH) -> Array[Border]:
	var start := Time.get_ticks_msec()
	var key := cache_key(source_path, w, h)
	var cached := load_cache(cache_path, key, w, h)
	if not cached.is_empty():
		from_cache = true
		elapsed_ms = Time.get_ticks_msec() - start
		return cached
	from_cache = false
	var borders := extract(indices, w, h)
	save_cache(cache_path, key, w, h, borders)
	elapsed_ms = Time.get_ticks_msec() - start
	return borders
