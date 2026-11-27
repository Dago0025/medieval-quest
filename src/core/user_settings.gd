class_name UserSettings
extends RefCounted
## Impostazioni dell'utente (fase 8c), in user://impostazioni.cfg: difficolta' predefinita dell'IA, inclinazione della
## plancia, volumi, lingua, controllo degli aggiornamenti. Le chiavi mancanti valgono i predefiniti; un file illeggibile si ignora.

const PATH := "user://impostazioni.cfg"
const DIFFICULTIES := ["facile", "normale", "difficile", "molto_difficile"]
const DIFFICULTY_NAMES := {"facile": "Facile", "normale": "Normale", "difficile": "Difficile", "molto_difficile": "Molto difficile"}

const DEFAULTS := {
	"difficolta": "normale",
	"inclinazione": 1.6,
	"volume_musica": 0.7,
	"volume_effetti": 0.8,
	"lingua": "it",          ## Lang.LANGUAGES (ADR-066): scelta nel menu iniziale, vale anche nelle sessioni successive
	"aggiornamenti": true,    ## ADR-144: controllo delle nuove versioni su GitHub all'avvio (UpdateCheck)
	"aggiornamenti_salta": "",   ## ADR-144: versione da non riproporre («Salta questa versione»)
}

static var _cfg: ConfigFile = null
static var path := PATH         ## sostituibile nei test


static func reset() -> void:
	_cfg = null


static func get_value(key: String) -> Variant:
	_ensure()
	return _cfg.get_value("utente", key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure()
	_cfg.set_value("utente", key, value)


static func save() -> bool:
	_ensure()
	return _cfg.save(path) == OK


static func difficulty() -> String:
	var d := str(get_value("difficolta"))
	return d if DIFFICULTIES.has(d) else str(DEFAULTS["difficolta"])


static func tilt() -> float:
	return clampf(float(get_value("inclinazione")), MapProjection.MIN_TILT, MapProjection.MAX_TILT)


static func _ensure() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	if FileAccess.file_exists(path) and _cfg.load(path) != OK:
		_cfg = ConfigFile.new()
