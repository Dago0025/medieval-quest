class_name Lang
extends RefCounted
## Lingua del gioco (2026-11-15, richiesta di Federico: «versione inglese di tutti i testi», scelta nel menu iniziale e
## ricordata nelle sessioni successive, ADR-066).
##
## Le frasi del codice restano scritte in italiano e passano da `Lang.t("...")`: con l'italiano tornano come sono, con
## l'inglese si cercano in `data/lingue/en.tsv` (italiano TAB inglese; a capo e tabulazioni scritti `\n` e `\t`). Il
## modello si traduce PRIMA di riempirlo: `Lang.t("Esercito %d: da %s a %s.") % [...]`. Una frase senza traduzione resta
## in italiano (e finisce in `missing()`, per i controlli).
##
## I nomi dei dati (unita', edifici, fazioni, vizi e virtu') in inglese stanno in `data/lingue/en/` con le stesse sezioni
## delle tabelle italiane (`Lang.data_path`); province, titoli e cariche in inglese sono quelli dei dati della XL, eventi e
## descrizioni quelli dell'installazione (senza le traduzioni di `_ITALIANO`).
##
## La lingua scelta si salva in `user://impostazioni.cfg` (chiave «lingua», `UserSettings`) e si applica all'avvio dal menu
## iniziale (`apply_saved`). Senza chiamate la lingua e' l'italiano: i test girano sempre in italiano.

const IT := "it"
const EN := "en"
const LANGUAGES := [IT, EN]
const NAMES := {IT: "Italiano", EN: "English"}
const TABLE_DIR := "res://data/lingue"

static var _code := IT
static var _tables := {}        ## codice -> {italiano: traduzione}
static var _missing := {}       ## frasi chieste senza traduzione (solo lingue diverse dall'italiano)
static var _translation: Translation = null   ## stessa tabella per la traduzione automatica dei nodi Control


## Codice della lingua in uso ("it", "en").
static func current() -> String:
	return _code


static func is_english() -> bool:
	return _code == EN


## Cambia la lingua: aggiorna la traduzione automatica dei nodi e azzera le tabelle dei nomi gia' lette.
static func set_language(code: String) -> void:
	var next := code if LANGUAGES.has(code) else IT
	_code = next
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	if next != IT:
		_translation = Translation.new()
		_translation.locale = next
		var table := _table(next)
		for k in table:
			_translation.add_message(k, table[k])
		TranslationServer.add_translation(_translation)
	TranslationServer.set_locale(next)
	_reset_name_caches()


## Lingua salvata nelle impostazioni dell'utente (italiano se manca).
static func saved() -> String:
	var code := str(UserSettings.get_value("lingua"))
	return code if LANGUAGES.has(code) else IT


static func apply_saved() -> void:
	set_language(saved())


## Sceglie e ricorda la lingua (impostazioni salvate subito). Falso se il file non e' scrivibile.
static func choose(code: String) -> bool:
	set_language(code)
	UserSettings.set_value("lingua", _code)
	return UserSettings.save()


## Frase tradotta nella lingua in uso; la frase italiana se e' l'italiano o se manca la traduzione.
static func t(text: String) -> String:
	if _code == IT or text == "":
		return text
	var table := _table(_code)
	if table.has(text):
		return str(table[text])
	_missing[text] = true
	return text


## Variante esplicita per lingua, quando la grammatica cambia la costruzione della frase.
static func pick(italian: String, english: String) -> String:
	return english if _code == EN else italian


## Percorso della tabella dei nomi nella lingua in uso: `res://data/nomi_unita.cfg` -> `res://data/lingue/en/nomi_unita.cfg`.
## Se la tabella della lingua non esiste il file non si apre e valgono i nomi dei dati (mai quelli italiani).
static func data_path(italian_path: String) -> String:
	if _code == IT:
		return italian_path
	return TABLE_DIR.path_join(_code).path_join(italian_path.get_file())


## Frasi chieste in questa sessione senza traduzione.
static func missing() -> PackedStringArray:
	return PackedStringArray(_missing.keys())


## Tabella esplicita (test); null torna al file.
static func use_table(code: String, table: Variant) -> void:
	if table == null:
		_tables.erase(code)
	else:
		_tables[code] = table


static func _table(code: String) -> Dictionary:
	if _tables.has(code):
		return _tables[code]
	var table := load_tsv(TABLE_DIR.path_join("%s.tsv" % code))
	_tables[code] = table
	return table


## Legge una tabella italiano TAB traduzione. Righe vuote e righe che iniziano con # si saltano.
static func load_tsv(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var cut := line.find("\t")
		if cut <= 0:
			continue
		var key := unescape(line.substr(0, cut))
		var value := unescape(line.substr(cut + 1))
		if value != "":
			out[key] = value
	return out


## `\n`, `\t` e `\\` della tabella nei caratteri veri.
static func unescape(text: String) -> String:
	if text.find("\\") < 0:
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "\\" and i + 1 < text.length():
			var n := text[i + 1]
			match n:
				"n":
					out += "\n"
				"t":
					out += "\t"
				"\\":
					out += "\\"
				_:
					out += c + n
			i += 2
			continue
		out += c
		i += 1
	return out


static func _reset_name_caches() -> void:
	RegionNames.reset()
	UnitTexts.reset()
	ItalianTexts.reset()
	CampaignUiText.reset_rebel_peoples()
	FactionStyle.reset()
	CampaignUiText.reset_tables()
