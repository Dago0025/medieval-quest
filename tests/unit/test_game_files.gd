extends RefCounted
## Test della ricerca delle immagini ingrandite (cartella HD).

const ROOT := "user://test_hd"


func _make_file(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()


func test_trova_png_con_suffisso_di_upscayl(t: TestContext) -> void:
	_make_file(ROOT + "/a/Textures/campmap/MapTex_upscayl_4x_ultrasharp.png")
	_make_file(ROOT + "/a/Textures/campmap/Altro.png")
	var found := GameFiles.find_hd_image(ROOT + "/a", "Textures/campmap/MapTex.tga")
	t.assert_eq(found.get_file(), "MapTex_upscayl_4x_ultrasharp.png")


func test_nessuna_immagine_hd(t: TestContext) -> void:
	_make_file(ROOT + "/b/Textures/campmap/MapTex.jpg")
	t.assert_eq(GameFiles.find_hd_image(ROOT + "/b", "Textures/campmap/MapTex.tga"), "", "solo PNG")
	t.assert_eq(GameFiles.find_hd_image(ROOT + "/inesistente", "Textures/campmap/MapTex.tga"), "")


## Dal 18/11/2026 (richiesta di Federico) i dati del gioco originale stanno nella cartella `originale/` del progetto: nessun
## percorso dell'installazione di Steam ne' impostazioni utente che ci rimandino.
func test_dati_nella_cartella_del_progetto(t: TestContext) -> void:
	t.assert_eq(GameFiles.data_dir(), ProjectSettings.globalize_path("res://originale"), "dall'editor e dai test")
	t.assert_false(GameFiles.data_dir().to_lower().contains("steamapps"))
	t.assert_eq(GameFiles.hd_dir(), GameFiles.game_dir().path_join("_ASSET_EXPORT/_HD"))
	t.assert_eq(GameFiles.startpos(), "res://data/campagna/EARLY_XL.TXT", "dati della campagna nel progetto")
	t.assert_true(GameFiles.campaign_available())
	t.assert_eq(GameFiles.prod_file("X.TXT"), "res://data/campagna/X.TXT")
	t.assert_eq(GameFiles.heroes_file("MTW_XL_EARLY_HEROES.TXT"), "res://data/campagna/MTW_XL_EARLY_HEROES.TXT")


## Ogni file che il gioco apre all'avvio di una partita c'e' nella cartella dei dati (se la cartella c'e').
func test_file_della_campagna_presenti(t: TestContext) -> void:
	if OS.get_environment("MTW_GAME_DIR") != "" or not DirAccess.dir_exists_absolute(GameFiles.data_dir()):
		t.skip("cartella originale/ non presente o dati da MTW_GAME_DIR")
		return
	t.assert_true(FileAccess.file_exists(GameFiles.path(".gdignore")), "manca originale/.gdignore")
	t.assert_true(FileAccess.file_exists(AssetLibrary.PROJECT_INDEX), "indice delle immagini nel progetto")
	var audio := ConfigFile.new()
	t.assert_eq(audio.load("res://data/ui/audio.cfg"), OK)
	for section in ["musica", "suoni"]:
		for key in audio.get_section_keys(section):
			var value: Variant = audio.get_value(section, key)
			var names: Array = value if value is Array else [value]
			for n in names:
				var found := GameAudio.find_file(GameAudio.MUSIC_DIR, str(n)) if section == "musica" else ""
				if section == "suoni":
					for d in GameAudio.SFX_DIRS:
						if found == "":
							found = GameAudio.find_file(d, str(n))
				t.assert_true(found != "", "manca il suono %s" % n)


## Audio proprio del progetto (18/11/2026): assets/audio/<musica|suoni>/<nome senza estensione>.<ogg|wav|mp3>.
func test_audio_del_progetto(t: TestContext) -> void:
	t.assert_eq(GameAudio.project_path("musica", "Brano che non esiste.wav"), "")
	t.assert_true(GameAudio.project_stream("suoni", "NON_ESISTE.WAV") == null)
	t.assert_true(DirAccess.dir_exists_absolute("res://assets/audio"), "cartella dell'audio proprio")
