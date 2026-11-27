class_name UpdateCheck
extends Node
## Controllo delle nuove versioni su GitHub all'avvio (ADR-144, richiesta di Federico del 27/11/2026: «un modo per vedere
## all'avvio del gioco se ci sono nuove versioni rilasciate su GitHub da scaricare»).
##
## Una sola richiesta HTTPS all'API pubblica delle release (`releases/latest`: esclude bozze e pre-release), senza
## token: funziona solo se la repo e' pubblica (con la repo privata GitHub risponde 404 e il controllo tace). Il tag
## della release (`v2026.11.27`) si confronta con la versione del gioco, `application/config/version` di project.godot,
## numero per numero. Se la release e' piu' recente emette `update_found` con versione, pagina e installer.
## Qualunque errore (niente rete, timeout, risposta strana, limite di richieste) si ignora in silenzio: il gioco non
## deve mai bloccarsi o mostrare errori per questo.
##
## Impostazioni (`UserSettings`): «aggiornamenti» (vero/falso, si spegne dal menu Impostazioni) e
## «aggiornamenti_salta» (versione che il giocatore ha scelto di non farsi riproporre).

signal update_found(info: Dictionary)   ## {"versione", "pagina", "installer", "nome", "data"}

const REPO := "Dago0025/medieval-quest"
const API_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
const RELEASES_PAGE := "https://github.com/%s/releases/latest" % REPO
const TIMEOUT_S := 8.0

var _http: HTTPRequest = null


## Versione del gioco in uso (es. "2026.11.27"); "0.0.0" se manca in project.godot.
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Numeri di una versione o di un tag: "v2026.11.27" -> [2026, 11, 27]. Toglie la «v» iniziale e un eventuale
## suffisso dopo il trattino ("2026.11.27-beta" -> [2026, 11, 27]). Vuoto se non e' una versione.
static func parse_version(text: String) -> PackedInt32Array:
	var s := text.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var dash := s.find("-")
	if dash >= 0:
		s = s.substr(0, dash)
	var out := PackedInt32Array()
	for part in s.split("."):
		if not part.is_valid_int():
			return PackedInt32Array()
		out.append(part.to_int())
	return out


## Vero se `remote` e' una versione successiva a `local` (numeri mancanti = 0: "2026.11" < "2026.11.1").
static func is_newer(remote: String, local: String) -> bool:
	var r := parse_version(remote)
	var l := parse_version(local)
	if r.is_empty():
		return false
	for i in maxi(r.size(), l.size()):
		var a := r[i] if i < r.size() else 0
		var b := l[i] if i < l.size() else 0
		if a != b:
			return a > b
	return false


## Dati utili della risposta di `releases/latest` (Dictionary del JSON). Vuoto se non e' una release valida.
## «installer»: l'indirizzo del primo allegato .exe (o vuoto: si apre la pagina della release).
static func parse_release(release: Variant) -> Dictionary:
	if not release is Dictionary:
		return {}
	var d := release as Dictionary
	if bool(d.get("draft", false)) or bool(d.get("prerelease", false)):
		return {}
	var tag := str(d.get("tag_name", ""))
	if parse_version(tag).is_empty():
		return {}
	var installer := ""
	var assets: Variant = d.get("assets", [])
	if assets is Array:
		for a in assets:
			if a is Dictionary and str((a as Dictionary).get("name", "")).to_lower().ends_with(".exe"):
				installer = str((a as Dictionary).get("browser_download_url", ""))
				break
	var page := str(d.get("html_url", ""))
	return {
		"versione": tag.trim_prefix("v").trim_prefix("V"),
		"pagina": page if page.begins_with("https://") else RELEASES_PAGE,
		"installer": installer if installer.begins_with("https://") else "",
		"nome": str(d.get("name", "")),
		"data": str(d.get("published_at", "")).substr(0, 10),
	}


## Decide se proporre la release al giocatore: piu' recente della versione in uso e non saltata.
static func should_offer(info: Dictionary, local: String, skipped: String) -> bool:
	if info.is_empty():
		return false
	var v := str(info.get("versione", ""))
	return is_newer(v, local) and v != skipped


static func enabled() -> bool:
	return bool(UserSettings.get_value("aggiornamenti"))


## Ricorda di non riproporre questa versione (le successive si propongono di nuovo).
static func skip_version(version: String) -> void:
	UserSettings.set_value("aggiornamenti_salta", version)
	UserSettings.save()


## Avvia il controllo (una volta per nodo). Non fa nulla se il controllo e' spento o se il nodo non e' nell'albero.
func start() -> void:
	if _http != null or not enabled() or not is_inside_tree():
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	_http.use_threads = true
	_http.request_completed.connect(_on_completed)
	add_child(_http)
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: MedievalQuest/%s" % current_version(),   # GitHub rifiuta le richieste senza User-Agent
		"X-GitHub-Api-Version: 2022-11-28",
	])
	if _http.request(API_URL, headers) != OK:
		_finish()


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_finish()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var info := parse_release(JSON.parse_string(body.get_string_from_utf8()))
	if should_offer(info, current_version(), str(UserSettings.get_value("aggiornamenti_salta"))):
		update_found.emit(info)


func _finish() -> void:
	if _http != null:
		_http.queue_free()
