extends Node
## Diagnostica della musica (25/11/2026, segnalazione di Federico: la musica salta, piu' spesso muovendo la mappa o le
## pedine). Scrive in godot.log (user://logs): latenza reale del driver all'avvio, poi ogni volta che la posizione del
## brano resta indietro rispetto al tempo reale (buffer audio esaurito) o salta, con la durata del fotogramma peggiore
## dell'ultimo secondo; ogni 30 secondi un riepilogo dei fotogrammi lenti. Nessun effetto sul gioco.

const LAG_REPORT := 0.06      ## secondi di ritardo accumulati in un secondo che meritano una riga
const SUMMARY_EVERY := 30.0
const MAX_LINES := 400        ## tetto per partita, per non gonfiare il log
## 26/11/2026: con un periodo di 10 ms, un mix fermo da piu' di 25 ms vuol dire che il driver ha gia' suonato silenzio
## (salto udibile) anche se la posizione del brano non resta indietro. Contati e riassunti ogni 30 s.
const LATE_MIX := 0.025

var player: AudioStreamPlayer
var _stream: AudioStream = null
var _last_pos := -1.0
var _wall_start := 0
var _pos_start := 0.0
var _lag_reported := 0.0
var _window := 0.0
var _window_worst := 0.0
var _summary_t := 0.0
var _slow_frames := 0
var _worst_frame := 0.0
var _lines := 0
var _late_mixes := 0
var _worst_mix := 0.0
var _in_late := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	log_line("avvio: driver %s, latenza reale %.1f ms (impostata %s ms), mix %d Hz, uscita '%s'" % [
		str(ProjectSettings.get_setting("audio/driver/driver", "")), AudioServer.get_output_latency() * 1000.0,
		str(ProjectSettings.get_setting("audio/driver/output_latency", 15)), int(AudioServer.get_mix_rate()),
		AudioServer.output_device])
	_raise_priority()


## 26/11/2026 (la musica salta di nuovo): su Windows il processo del gioco passa a priorita' alta, cosi' il thread
## dell'audio (buffer da 10 ms) non aspetta dietro a browser e altri programmi. Non serve l'amministratore; nei test
## senza finestra e nell'editor non si tocca nulla.
func _raise_priority() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless" or Engine.is_editor_hint():
		return
	var pid := OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command",
		"(Get-Process -Id %d).PriorityClass = 'High'" % OS.get_process_id()], false)
	log_line("priorita' del processo: alta" if pid > 0 else "priorita' del processo: non cambiata")


func log_line(text: String) -> void:
	if _lines >= MAX_LINES:
		return
	_lines += 1
	print("[audio %s] %s" % [Time.get_time_string_from_system(), text])


## Nuovo brano: azzera i riferimenti (chiamata da GameAudio).
func track_started(file_name: String) -> void:
	_stream = null
	_last_pos = -1.0
	log_line("brano: %s" % file_name)


func _process(delta: float) -> void:
	var frame_ms := delta * 1000.0
	_window_worst = maxf(_window_worst, frame_ms)
	_worst_frame = maxf(_worst_frame, frame_ms)
	if frame_ms > 50.0:
		_slow_frames += 1
	var since_mix := AudioServer.get_time_since_last_mix()
	if since_mix > LATE_MIX and player != null and is_instance_valid(player) and player.playing:
		if not _in_late:
			_late_mixes += 1
		_in_late = true
		_worst_mix = maxf(_worst_mix, since_mix)
	else:
		_in_late = false
	_window += delta
	_summary_t += delta
	if _window >= 1.0:
		_window = 0.0
		_window_worst = frame_ms
	if _summary_t >= SUMMARY_EVERY:
		if _slow_frames > 0:
			log_line("ultimi %d s: %d fotogrammi oltre 50 ms, il peggiore %.0f ms" % [int(SUMMARY_EVERY), _slow_frames, _worst_frame])
		if _late_mixes > 0:
			log_line("ultimi %d s: %d mix audio in ritardo (probabili salti), il peggiore %.0f ms" % [int(SUMMARY_EVERY), _late_mixes, _worst_mix * 1000.0])
		_summary_t = 0.0
		_slow_frames = 0
		_worst_frame = 0.0
		_late_mixes = 0
		_worst_mix = 0.0
	if player == null or not is_instance_valid(player) or not player.playing:
		_last_pos = -1.0
		return
	var pos := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	var now := Time.get_ticks_usec()
	if player.stream != _stream or _last_pos < 0.0 or pos < 1.0:   # il primo secondo del brano fa da riferimento
		_stream = player.stream
		_wall_start = now
		_pos_start = pos
		_lag_reported = 0.0
		_last_pos = pos
		return
	if pos < _last_pos - 0.25:
		log_line("salto indietro: %.2f -> %.2f s (fotogramma peggiore %.0f ms)" % [_last_pos, pos, _window_worst])
		_wall_start = now
		_pos_start = pos
		_lag_reported = 0.0
	_last_pos = pos
	# ritardo = tempo reale trascorso - avanzamento del brano: cresce solo se il driver non riceve audio in tempo
	var lag := float(now - _wall_start) / 1000000.0 - (pos - _pos_start)
	if lag > _lag_reported + LAG_REPORT:
		log_line("musica in ritardo di %.0f ms (in tutto %.0f ms) a %.1f s, fotogramma peggiore %.0f ms" % [
			(lag - _lag_reported) * 1000.0, lag * 1000.0, pos, _window_worst])
		_lag_reported = lag
	elif lag < _lag_reported - 0.2:
		log_line("salto avanti di %.0f ms a %.1f s (fotogramma peggiore %.0f ms)" % [(_lag_reported - lag) * 1000.0, pos, _window_worst])
		_lag_reported = lag
