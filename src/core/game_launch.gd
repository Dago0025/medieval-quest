class_name GameLaunch
extends RefCounted
## Scelte del menu iniziale (fase 8c) passate alla mappa della campagna: fazione del giocatore, difficolta', seme della
## partita nuova o salvataggio da caricare. Vuote = i valori di scenes/campaign_settings.gd (la mappa resta avviabile da sola).

static var faction := ""        ## id della fazione del giocatore per la partita nuova ("" = quella predefinita)
static var difficulty := ""     ## difficolta' dell'IA ("" = impostazioni dell'utente, poi quella predefinita)
static var seed_value := 0      ## seme della partita nuova (0 = quello predefinito)
static var load_save := ""      ## salvataggio da caricare all'avvio ("" = partita nuova)


static func reset() -> void:
	faction = ""
	difficulty = ""
	seed_value = 0
	load_save = ""


static func new_game(faction_id: String, ai_difficulty: String, seed_number: int) -> void:
	reset()
	faction = faction_id
	difficulty = ai_difficulty
	seed_value = seed_number


static func load_game(save_name: String) -> void:
	reset()
	load_save = save_name
