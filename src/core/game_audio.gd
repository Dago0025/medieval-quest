class_name GameAudio
extends RefCounted
## Musica e suoni dall'installazione (fase 8d, ADR-007: i WAV restano nel gioco, si leggono a ogni avvio). I lettori stanno
## sotto la radice dell'albero, quindi la musica continua tra il menu e la mappa. Volumi da UserSettings; senza installazione
## o senza file tutto tace senza errori. Le playlist sono in data/ui/audio.cfg.

const TABLE := "res://data/ui/audio.cfg"
const MUSIC_DIR := "Sounds/Music"
const SFX_DIRS := ["Sounds/campmap", "Sounds/Frontend", "Sounds/GameEnd"]

static var _music: AudioStreamPlayer = null
static var _sfx: Array[AudioStreamPlayer] = []
static var _playlist: PackedStringArray = []
static var _playlist_key := ""
static var _track := -1
static var _cache := {}          ## percorso -> AudioStreamWAV (solo suoni brevi; la musica si rilegge)
static var _cfg: ConfigFile = null
static var _rng := RandomNumberGenerator.new()
static var enabled := true       ## i test e le catture lo spengono
static var _fade: Tween = null   ## dissolvenza in uscita al cambio di playlist
const AudioMonitorScript := preload("res://src/core/audio_monitor.gd")
static var _monitor: Node = null   ## diagnostica in godot.log (25/11/2026)
const FADE_OUT := 0.8            ## secondi


## Musica di un momento (sezione [musica] della tabella: "menu", "mappa_cristiana", "mappa_islamica", "vittoria"...).
## Se la stessa playlist sta gia' suonando non riparte.
static func play_music(key: String) -> void:
	if not enabled or not _ensure_players():
		return
	if key == _playlist_key and _music.playing:
		return
	var table := _table()
	_playlist = PackedStringArray(table.get_value("musica", key, [])) if table != null else PackedStringArray()
	_playlist_key = key
	_track = -1
	if _playlist.is_empty():
		_stop_fade()
		_music.stop()
		return
	if _music.playing and _music.is_inside_tree():
		# niente tagli netti tra menu, mappa e fine partita: il brano in corso sfuma, poi parte la nuova playlist
		_stop_fade()
		_fade = _music.create_tween()
		_fade.tween_property(_music, "volume_db", -60.0, FADE_OUT)
		_fade.tween_callback(_next_track)
		return
	_next_track()


## Chiave della musica della mappa per la religione della fazione del giocatore.
static func map_music_key(religion: String) -> String:
	var r := religion.to_upper()
	if r.contains("MUSLIM") or r.contains("ISLAM"):
		return "mappa_islamica"
	return "mappa_cristiana"


static func stop_music() -> void:
	_stop_fade()
	if _music != null:
		_music.stop()
	_playlist_key = ""


## Suono breve per nome della tabella ([suoni]: "seleziona", "lascia_amico", "fine_anno"...), o nome di file.
static func play_sfx(key: String) -> void:
	if not enabled or not _ensure_players():
		return
	var table := _table()
	var options: Array = []
	if table != null and table.has_section_key("suoni", key):
		var v: Variant = table.get_value("suoni", key)
		options = v if v is Array else [v]
	else:
		options = [key]
	if options.is_empty():
		return
	var file_name := str(options[_rng.randi_range(0, options.size() - 1)])
	var stream := _sfx_stream(file_name)
	if stream == null:
		return
	var player := _free_sfx_player()
	player.stream = stream
	player.volume_db = linear_to_db(maxf(float(UserSettings.get_value("volume_effetti")), 0.0001))
	if player.is_inside_tree():
		player.play()
	else:
		player.play.call_deferred()   # il lettore entra nell'albero al prossimo frame


## Riapplica i volumi delle impostazioni (dopo averle salvate).
static func apply_volumes() -> void:
	if _music != null:
		_music.volume_db = linear_to_db(maxf(float(UserSettings.get_value("volume_musica")), 0.0001))


## Audio proprio del progetto (richiesta di Federico del 18/11/2026: niente piu' file dell'originale): un file con lo stesso
## nome senza estensione in `res://assets/audio/<musica|suoni>/` (ogg, wav o mp3, importato da Godot) prende il posto del WAV
## dell'originale elencato in data/ui/audio.cfg. Null se non c'e'.
const PROJECT_AUDIO := "res://assets/audio"
const PROJECT_EXTENSIONS := ["ogg", "wav", "mp3"]

static func project_path(kind: String, file_name: String) -> String:
	var base := file_name.get_basename()
	for ext in PROJECT_EXTENSIONS:
		var p := "%s/%s/%s.%s" % [PROJECT_AUDIO, kind, base, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


static func project_stream(kind: String, file_name: String) -> AudioStream:
	var p := project_path(kind, file_name)
	return load(p) as AudioStream if p != "" else null


## Percorso reale di un file nella cartella del gioco senza distinguere maiuscole («VIKING TENSION.WAV»), "" se manca.
static func find_file(dir_relative: String, file_name: String) -> String:
	var dir := GameFiles.path(dir_relative)
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var exact := dir.path_join(file_name)
	if FileAccess.file_exists(exact):
		return exact
	var wanted := file_name.to_lower()
	for f in DirAccess.get_files_at(dir):
		if f.to_lower() == wanted:
			return dir.path_join(f)
	return ""


# --- interni ------------------------------------------------------------------------------------------------------


static func _table() -> ConfigFile:
	if _cfg == null:
		var c := ConfigFile.new()
		if c.load(TABLE) == OK:
			_cfg = c
	return _cfg


static func _ensure_players() -> bool:
	if _music != null and is_instance_valid(_music):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	_rng.randomize()
	_music = AudioStreamPlayer.new()
	_music.name = "Musica"
	_music.finished.connect(_next_track)
	tree.root.add_child.call_deferred(_music)
	_monitor = AudioMonitorScript.new()
	_monitor.name = "DiagnosticaAudio"
	_monitor.set("player", _music)
	tree.root.add_child.call_deferred(_monitor)
	_sfx.clear()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.name = "Suono%d" % i
		tree.root.add_child.call_deferred(p)
		_sfx.append(p)
	return true


static func _stop_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null


static func _next_track() -> void:
	_stop_fade()   # se il brano finisce durante la dissolvenza si parte una volta sola
	if _playlist.is_empty() or _music == null:
		return
	# ordine casuale senza ripetere subito lo stesso brano
	var pick := _rng.randi_range(0, _playlist.size() - 1)
	if _playlist.size() > 1 and pick == _track:
		pick = (pick + 1) % _playlist.size()
	_track = pick
	var stream := project_stream("musica", _playlist[pick])   # audio proprio del progetto (18/11/2026), poi l'originale
	if stream == null:
		var path := find_file(MUSIC_DIR, _playlist[pick])
		if path == "":
			return
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		return
	_music.stream = stream
	if _monitor != null and is_instance_valid(_monitor):
		_monitor.call("track_started", _playlist[pick])
	apply_volumes()
	if _music.is_inside_tree():
		_music.play()
	else:
		_music.ready.connect(func() -> void: _music.play(), CONNECT_ONE_SHOT)


static func _sfx_stream(file_name: String) -> AudioStream:
	if _cache.has(file_name):
		return _cache[file_name]
	var stream: AudioStream = project_stream("suoni", file_name)   # audio proprio del progetto (18/11/2026), poi l'originale
	if stream == null:
		var path := ""
		for d in SFX_DIRS:
			path = find_file(d, file_name)
			if path != "":
				break
		stream = AudioStreamWAV.load_from_file(path) if path != "" else null
	_cache[file_name] = stream
	return stream


static func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx:
		if not p.playing:
			return p
	return _sfx[0]
