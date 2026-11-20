class_name MarkerLayout
extends RefCounted
## Logica pura (senza nodi) dei segnalini di eserciti e flotte sulla mappa:
## disposizione affiancata nella stessa regione, raggruppamento per regione,
## punto di ancoraggio delle zone senza castello (baricentro) e geometria delle frecce.

const ROW_MAX := 4


## Scostamenti (in pixel dello schermo) dei segnalini di una stessa regione: fino a `per_row`
## per riga, righe centrate attorno all'ancora. Un segnalino solo sta nell'ancora.
static func slot_offsets(count: int, spacing: float, per_row: int = ROW_MAX) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	var columns := maxi(1, per_row)
	var rows := ceili(count / float(columns))
	for i in range(count):
		var row := floori(float(i) / float(columns))
		var in_row := mini(columns, count - row * columns)
		var col := i - row * columns
		var x := (float(col) - float(in_row - 1) / 2.0) * spacing
		var y := (float(row) - float(rows - 1) / 2.0) * spacing
		out.append(Vector2(x, y))
	return out


## Regione -> id degli eserciti che vi si trovano, in ordine crescente di id.
## `shown`: id -> regione in cui disegnare l'esercito al posto della sua (pedine in viaggio, CampaignUiMoves).
static func group_by_region(armies: Array[Army], shown: Dictionary = {}) -> Dictionary:
	var out := {}
	for a in armies:
		var key: String = shown.get(a.id, a.region)
		var ids: PackedInt32Array = out.get(key, PackedInt32Array())
		ids.append(a.id)
		out[key] = ids
	for key in out:
		var ids: PackedInt32Array = out[key]
		ids.sort()
		out[key] = ids
	return out


## Regione -> id degli agenti che vi si trovano, in ordine crescente di id (fase 5a).
static func group_agents_by_region(agents: Array[AgentState], shown: Dictionary = {}) -> Dictionary:
	var out := {}
	for a in agents:
		var key: String = shown.get(a.id, a.region)
		var ids: PackedInt32Array = out.get(key, PackedInt32Array())
		ids.append(a.id)
		out[key] = ids
	for key in out:
		var ids: PackedInt32Array = out[key]
		ids.sort()
		out[key] = ids
	return out


## Disposizione di eserciti e agenti della stessa regione senza sovrapposizioni (fase 5a): tutti i segnalini
## condividono la stessa griglia, prima gli eserciti poi gli agenti, riga per riga.
## Esito: {"eserciti": scostamenti, "agenti": scostamenti, "righe": numero di righe}.
static func mixed_slots(army_count: int, agent_count: int, spacing: float, per_row: int = ROW_MAX) -> Dictionary:
	var armies := maxi(0, army_count)
	var agents := maxi(0, agent_count)
	var all := slot_offsets(armies + agents, spacing, per_row)
	var army_slots := PackedVector2Array()
	var agent_slots := PackedVector2Array()
	for i in range(all.size()):
		if i < armies:
			army_slots.append(all[i])
		else:
			agent_slots.append(all[i])
	var columns := maxi(1, per_row)
	return {"eserciti": army_slots, "agenti": agent_slots, "righe": ceili((armies + agents) / float(columns))}



## Scostamento da sommare agli slot di `mixed_slots` nelle regioni con il castello disegnato: tutte le pedine di campo
## alla destra del bordo `side` (ArmyLayer.castle_side_offset), anche quando sono tante e gli slot centrati andrebbero a
## coprire il castello (richiesta di Federico: il castello si deve poter cliccare).
static func castle_shift(layout: Dictionary, side: Vector2) -> Vector2:
	var min_x := 0.0
	for key in ["eserciti", "agenti"]:
		for slot in (layout.get(key, PackedVector2Array()) as PackedVector2Array):
			min_x = minf(min_x, slot.x)
	return Vector2(side.x - min_x, side.y)


## Posizioni delle pedine dentro i confini della loro regione (richiesta di Federico, 2026-11-10: niente pedine in mare).
## `anchor` e' l'ancora della regione (castello), `offsets` gli scostamenti voluti in coordinate della mappa, `inside(p)`
## dice se il punto `p` della mappa sta nella regione, `spacing` e' la distanza minima tra due pedine, `avoid` un rettangolo
## da lasciare libero (il castello; vuoto = nessuno). Ogni pedina resta dove la vuole il disegno se il punto e' buono,
## altrimenti va nel punto buono libero piu' vicino a quello voluto, cercato su una griglia di passo `spacing / 2` attorno
## all'ancora fino a `max_radius`. Se non ce n'e' uno (regioni minuscole), la pedina si avvicina all'ancora.
static func fit_positions(anchor: Vector2, offsets: PackedVector2Array, inside: Callable, spacing: float, avoid: Rect2 = Rect2(), max_radius: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := maxf(1.0, spacing * 0.5)
	var radius := max_radius if max_radius > 0.0 else spacing * 8.0
	var grid: Array[Vector2] = []
	var rings := ceili(radius / step)
	for gy in range(-rings, rings + 1):
		for gx in range(-rings, rings + 1):
			var p := anchor + Vector2(gx, gy) * step
			if p.distance_to(anchor) <= radius:
				grid.append(p)
	for off in offsets:
		var wanted := anchor + off
		if _good_spot(wanted, out, inside, spacing, avoid):
			out.append(wanted)
			continue
		var best := Vector2.INF
		var best_d := INF
		for p in grid:
			var d := p.distance_squared_to(wanted)
			if d < best_d and _good_spot(p, out, inside, spacing, avoid):
				best = p
				best_d = d
		if best == Vector2.INF:
			# niente posto libero: si accetta di stringersi, ma sempre dentro la regione
			for p in grid:
				var d2 := p.distance_squared_to(wanted)
				if d2 < best_d and bool(inside.call(p)) and not (avoid.has_area() and avoid.has_point(p)):
					best = p
					best_d = d2
		out.append(best if best != Vector2.INF else anchor)
	return out


static func _good_spot(p: Vector2, placed: PackedVector2Array, inside: Callable, spacing: float, avoid: Rect2) -> bool:
	if avoid.has_area() and avoid.has_point(p):
		return false
	if not bool(inside.call(p)):
		return false
	# le pedine sono alte: una sopra l'altra devono stare piu' distanti che una accanto all'altra
	for q in placed:
		if absf(q.x - p.x) < spacing * 0.8 and absf(q.y - p.y) < spacing * 2.2:
			return false
	return true

## Indice del segnalino sotto `point` (centri e punto nello stesso sistema di coordinate,
## `half` = metà del lato). Con segnalini sovrapposti vince l'ultimo (il più in alto). -1 se nessuno.
static func hit_index(centers: PackedVector2Array, half: Vector2, point: Vector2) -> int:
	var i := centers.size() - 1
	while i >= 0:
		var c := centers[i]
		if absf(point.x - c.x) <= half.x and absf(point.y - c.y) <= half.y:
			return i
		i -= 1
	return -1


## Punta di una freccia che termina in `to` (triangolo con la punta in `to`). Vuoto se i due punti coincidono.
static func arrow_head(from: Vector2, to: Vector2, size: float) -> PackedVector2Array:
	var dir := to - from
	if dir.length() < 0.001:
		return PackedVector2Array()
	var d := dir.normalized()
	var n := d.orthogonal()
	var base := to - d * size
	return PackedVector2Array([to, base + n * size * 0.5, base - n * size * 0.5])


## Tratti di una polilinea tratteggiata (per la freccia del trasporto via mare): alterna `dash`
## visibile e `gap` vuoto lungo la linea, anche attraverso i vertici. Ogni tratto e' una polilinea
## di almeno due punti. Con `gap` <= 0 la linea e' continua (un solo tratto). Vuoto con meno di
## due punti o `dash` <= 0. Le lunghezze sono nell'unita' dei punti (pixel dello schermo).
static func dashed_segments(points: PackedVector2Array, dash: float, gap: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if points.size() < 2 or dash <= 0.0:
		return out
	if gap <= 0.0:
		out.append(points)
		return out
	var drawing := true
	var left := dash
	var current := PackedVector2Array([points[0]])
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.0001:
			continue
		var dir := (b - a) / length
		var pos := 0.0
		while length - pos > left:
			pos += left
			var p := a + dir * pos
			if drawing:
				current.append(p)
				out.append(current)
				current = PackedVector2Array()
				drawing = false
				left = gap
			else:
				current = PackedVector2Array([p])
				drawing = true
				left = dash
		left -= length - pos
		if drawing:
			current.append(b)
	if drawing and current.size() >= 2:
		out.append(current)
	return out


## Vero se un movimento verso una regione è un attacco: la regione ha un proprietario diverso dalla
## fazione che si muove (anche i ribelli), oppure vi stanno eserciti di altre fazioni
## (`present_factions` = fazioni degli eserciti presenti, esclusi quelli che si muovono).
## Le regioni di mare non hanno proprietario: contano solo le forze presenti.
static func is_attack_target(faction: String, region_owner: String, present_factions: PackedStringArray) -> bool:
	var mine := faction.strip_edges().to_upper()
	var owner_id := region_owner.strip_edges().to_upper()
	if owner_id != "" and owner_id != mine:
		return true
	for f in present_factions:
		var other := f.strip_edges().to_upper()
		if other != "" and other != mine:
			return true
	return false


## Scostamento in pixel dello schermo del simbolo di assedio rispetto all'ancora della regione
## (sopra i segnalini, che sono centrati sull'ancora, anche con più righe).
static func siege_symbol_offset(marker_rows: int, spacing: float) -> Vector2:
	var rows := maxi(1, marker_rows)
	return Vector2(0.0, -(float(rows) * spacing / 2.0 + 10.0))


## Punto di ancoraggio di zone della bitmap (per esempio le zone di mare): il pixel della zona
## più vicino al baricentro (il baricentro può cadere fuori da una zona concava), al centro del pixel.
## - `pixels`: indici di palette, `width` x `height`, righe dall'alto;
## - `group_of`: indice di palette -> gruppo (come RegionMap.group_for_index), 256 voci;
## - `wanted`: gruppi richiesti (chiavi del Dictionary);
## - `step`: passo di campionamento (2 = un pixel su quattro). I gruppi non trovati con il
##   campionamento vengono cercati di nuovo pixel per pixel.
## Restituisce gruppo -> Vector2; i gruppi senza pixel mancano.
static func zone_anchors(pixels: PackedByteArray, width: int, height: int, group_of: PackedInt32Array, wanted: Dictionary, step: int = 2) -> Dictionary:
	var result := {}
	if width <= 0 or height <= 0 or pixels.size() < width * height or wanted.is_empty():
		return result
	var stride := maxi(1, step)
	var interesting := PackedByteArray()
	interesting.resize(256)
	interesting.fill(0)
	for i in range(mini(256, group_of.size())):
		if wanted.has(group_of[i]):
			interesting[i] = 1
	# Passo 1: somme per indice di palette.
	var sum_x := PackedFloat64Array()
	var sum_y := PackedFloat64Array()
	var count := PackedInt32Array()
	sum_x.resize(256)
	sum_y.resize(256)
	count.resize(256)
	sum_x.fill(0.0)
	sum_y.fill(0.0)
	count.fill(0)
	var y := 0
	while y < height:
		var row := y * width
		var x := 0
		while x < width:
			var idx: int = pixels[row + x]
			if interesting[idx] == 1:
				sum_x[idx] += x
				sum_y[idx] += y
				count[idx] += 1
			x += stride
		y += stride
	# Baricentro per gruppo (gli indici dello stesso gruppo si sommano).
	var group_sum := {}
	var group_count := {}
	for i in range(256):
		if count[i] == 0:
			continue
		var g: int = group_of[i]
		var s: Vector2 = group_sum.get(g, Vector2.ZERO)
		group_sum[g] = s + Vector2(sum_x[i], sum_y[i])
		group_count[g] = int(group_count.get(g, 0)) + count[i]
	var centroid_of_index := PackedVector2Array()
	centroid_of_index.resize(256)
	for i in range(256):
		if count[i] == 0:
			continue
		var g: int = group_of[i]
		var total: Vector2 = group_sum[g]
		centroid_of_index[i] = total / float(int(group_count[g]))
	# Passo 2: il pixel campionato più vicino al baricentro.
	var best_dist := PackedFloat64Array()
	var best_pos := PackedVector2Array()
	best_dist.resize(256)
	best_pos.resize(256)
	best_dist.fill(1.0e30)
	y = 0
	while y < height:
		var row2 := y * width
		var x2 := 0
		while x2 < width:
			var idx2: int = pixels[row2 + x2]
			if interesting[idx2] == 1 and count[idx2] > 0:
				var d := Vector2(x2, y).distance_squared_to(centroid_of_index[idx2])
				if d < best_dist[idx2]:
					best_dist[idx2] = d
					best_pos[idx2] = Vector2(x2, y)
			x2 += stride
		y += stride
	var best_group_dist := {}
	for i in range(256):
		if count[i] == 0:
			continue
		var g: int = group_of[i]
		var current: float = best_group_dist.get(g, 1.0e30)
		if best_dist[i] < current:
			best_group_dist[g] = best_dist[i]
			result[g] = best_pos[i] + Vector2(0.5, 0.5)
	# Gruppi non trovati con il campionamento: nuova ricerca pixel per pixel.
	if stride > 1:
		var missing := {}
		for g in wanted:
			if not result.has(g):
				missing[g] = true
		if not missing.is_empty():
			var again := zone_anchors(pixels, width, height, group_of, missing, 1)
			for g in again:
				result[g] = again[g]
	return result
