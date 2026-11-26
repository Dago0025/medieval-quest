class_name GameFiles
extends RefCounted
## Trova i file del gioco originale. Dal 26/11/2026 il gioco non ne usa piu' (audio, tavole e fine partita sono tutti in
## assets/, e prendono il posto di questi ovunque): restano come riserva per editor, test e strumenti di confronto.
## Dati della campagna (`data/campagna`), testi (`data/testi`), icone e pergamene (`assets/rifatti`) sono del progetto.
##
## I file stanno nella cartella `originale/` del progetto, con i percorsi relativi del gioco. Ha un `.gdignore` (Godot non la
## importa) e non entra nel repository (.gitignore): e' contenuto del gioco originale. Si cerca cosi', nell'ordine:
## 1. variabile d'ambiente MTW_GAME_DIR (solo per sviluppo e test);
## 2. dall'editor e dai test: `res://originale`;
## 3. dall'eseguibile esportato: `originale/` accanto all'exe, poi nella cartella sopra (build/ sta nel progetto).
## Si rigenera con `tools/copia_originale.py <cartella del gioco>`. Senza la cartella il gioco parte lo stesso, senza
## musica, suoni e quelle immagini.

const DATA_FOLDER := "originale"
const MAIN_STARTPOS := "EARLY_XL.TXT"


static func game_dir() -> String:
	var from_env := OS.get_environment("MTW_GAME_DIR")
	if from_env != "":
		return from_env
	return data_dir()


## Cartella `originale/` del progetto (editor e test) o accanto all'eseguibile (gioco esportato).
static func data_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + DATA_FOLDER)
	var exe_dir := OS.get_executable_path().get_base_dir()
	for candidate in [exe_dir.path_join(DATA_FOLDER), exe_dir.get_base_dir().path_join(DATA_FOLDER)]:
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return exe_dir.path_join(DATA_FOLDER)


static func is_available() -> bool:
	return DirAccess.dir_exists_absolute(game_dir())


static func path(relative: String) -> String:
	return game_dir().path_join(relative)


## Dati della campagna del remake (dal 18/11/2026 nel progetto, `data/campagna`): startpos, prod di unita' ed edifici,
## file dei nomi e dei re famosi. Nati dai file della XL 3.0 con la mod, sono ora dati del remake e si modificano qui.
const CAMPAIGN_DIR := "res://data/campagna"


static func startpos(file_name: String = MAIN_STARTPOS) -> String:
	return CAMPAIGN_DIR.path_join(file_name)


## Vero se ci sono i dati per cominciare una campagna (startpos del progetto).
static func campaign_available() -> bool:
	return FileAccess.file_exists(startpos())


## File prod di unita' o edifici (nomi dallo startpos, `Prodfiles::`).
static func prod_file(file_name: String) -> String:
	return CAMPAIGN_DIR.path_join(file_name)


## I testi localizzati (Loc) si trovano in Loc/Italian (tradotti in italiano il 2026-11-09). In inglese (ADR-066) valgono
## gli originali in `_INGLESE` (copiati dal salvataggio del gioco precedente alla traduzione), se ci sono.
const ENGLISH_FOLDER := "_INGLESE"

static func loc_file(file_name: String) -> String:
	if Lang.is_english():
		var en := path(ENGLISH_FOLDER).path_join(file_name)
		if FileAccess.file_exists(en):
			return en
	return path("Loc/Italian").path_join(file_name)


## File dei nomi, dei re famosi e degli eroi (SetNameData dello startpos: MTW_XL_EARLY_HEROES.TXT), in `data/campagna`.
static func heroes_file(file_name: String) -> String:
	return CAMPAIGN_DIR.path_join(file_name)


static func lookup_map() -> String:
	return path("Textures/campmap/LukMap.Lbm")


static func hd_dir() -> String:
	return path("_ASSET_EXPORT/_HD")


## Versione ingrandita di un'immagine del gioco, se esiste: cerca nella cartella HD,
## allo stesso percorso relativo, un PNG il cui nome inizia con il nome originale
## (Upscayl aggiunge un suffisso, per esempio `MapTex_upscayl_4x_...png`).
## Restituisce "" se non c'è.
static func hd_image(relative: String) -> String:
	return find_hd_image(hd_dir(), relative)


## Come hd_image, ma con la cartella HD esplicita (usato anche dai test).
static func find_hd_image(hd_root: String, relative: String) -> String:
	var folder := hd_root.path_join(relative.get_base_dir())
	if not DirAccess.dir_exists_absolute(folder):
		return ""
	var base := relative.get_file().get_basename().to_lower()
	var files := DirAccess.get_files_at(folder)
	files.sort()
	for f in files:
		if f.get_extension().to_lower() == "png" and f.to_lower().begins_with(base):
			return folder.path_join(f)
	return ""
