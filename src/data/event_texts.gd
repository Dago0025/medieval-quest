class_name EventTexts
extends RefCounted
## Titoli e testi degli eventi di Events.txt (Loc/<lingua>/Events.txt): i 71 eventi storici e i messaggi dei disastri.
## I testi si leggono dall'installazione a ogni avvio e non entrano nel repository (ADR-007, ADR-011): il file dei dati
## (`data/eventi/eventi_storici.cfg`) contiene solo indici, date ed effetti.
##
## Gli eventi storici sono due liste a indice (`@["Historical_event_titles"]` e `@["Historical_event_text"]`), nello
## stesso ordine: l'indice `i` di `EV_HISTORICAL` ("indice") e' la posizione nelle due liste (0-70). I messaggi dei disastri
## sono voci semplici con un segnaposto `%s` per il nome della regione (la peste ha cinque varianti in una lista).
## La lettura e' di `LocLoader`; questa classe aggiunge solo i nomi delle etichette.

const FILE_NAME := "Events.txt"
const TITLES_LABEL := "Historical_event_titles"
const TEXTS_LABEL := "Historical_event_text"

## Messaggio lungo (con `%s`) e titolo breve di ogni disastro, per tipo di evento di `GameState`.
const DISASTER_MESSAGES := {
	"inondazione": "floodregmes_xzy",
	"carestia": "famineregmes_xzy",
	"terremoto": "quakeregmes_xzy",
	"tempesta": "taifunregmes_xzy",
	"peste": "plagueregmes_xzy",
	"peste_nera": "black_plagueregmes_xzy",
}
const DISASTER_TITLES := {
	"inondazione": "floodms_xzy",
	"carestia": "faminems_xzy",
	"terremoto": "earthquakems_xzy",
	"tempesta": "taifunms_xzy",
	"peste": "plaguems_xzy",
	"peste_nera": "black_plaguems_xzy",
}

var table: LocLoader.LocTable
var italian := false   ## vero se i testi vengono dall'installazione: allora valgono le traduzioni di ItalianTexts


## Testi propri del remake (data/testi), oppure un file nel formato Loc indicato (test). La tabella e' vuota se manca.
static func load_file(path: String = "") -> EventTexts:
	var texts := EventTexts.new()
	if path == "":
		texts.italian = true   # testi propri del remake (data/testi/<lingua>), dal 18/11/2026 in tutte le lingue
		return texts
	texts.table = LocLoader.load_file(path)
	return texts


static func load_text(text: String) -> EventTexts:
	var texts := EventTexts.new()
	texts.table = LocLoader.load_text(text)
	return texts


func _init() -> void:
	table = LocLoader.LocTable.new()


## Numero di eventi storici con un titolo (71 nel file reale).
func historical_count() -> int:
	if italian:
		return ItalianTexts.keys("eventi_titoli").size()
	return table.array(TITLES_LABEL).size()


## Vero se l'indice ha sia il titolo sia il testo.
func has_historical(index: int) -> bool:
	if italian:
		return ItalianTexts.text("eventi_titoli", str(index)) != "" and ItalianTexts.text("eventi_testi", str(index)) != ""
	return index >= 0 and index < table.array(TITLES_LABEL).size() and index < table.array(TEXTS_LABEL).size()


## Titolo dell'evento storico di indice `index` ("" se manca).
func historical_title(index: int) -> String:
	var it := ItalianTexts.text("eventi_titoli", str(index)) if italian else ""
	return it if it != "" else table.array_item(TITLES_LABEL, index, "")


## Testo dell'evento storico di indice `index` ("" se manca).
func historical_text(index: int) -> String:
	var it := ItalianTexts.text("eventi_testi", str(index)) if italian else ""
	return it if it != "" else table.array_item(TEXTS_LABEL, index, "")


## Messaggio del disastro (`kind` = tipo di evento: "inondazione", "carestia", "terremoto", "tempesta", "peste",
## "peste_nera") con il nome della regione al posto di `%s`. Per la peste `variant` sceglie una delle cinque malattie
## (modulo il numero di varianti). "" se il file non lo ha.
func disaster_message(kind: String, region_name: String = "", variant: int = 0) -> String:
	var label := String(DISASTER_MESSAGES.get(kind, ""))
	if label == "":
		return ""
	var message := ""
	var it_variants := ItalianTexts.array("peste", "varianti") if italian and kind == "peste" else PackedStringArray()
	var it_text := ItalianTexts.text("disastri", label) if italian else ""
	if not it_variants.is_empty():
		message = it_variants[posmod(variant, it_variants.size())]
	elif it_text != "":
		message = it_text
	elif table.has_array(label):
		var list := table.array(label)
		if not list.is_empty():
			message = list[posmod(variant, list.size())]
	else:
		message = table.text(label)
	return message.replace("%s", region_name)


## Titolo breve del disastro ("Flood", "Famine"...), "" se il file non lo ha.
func disaster_title(kind: String) -> String:
	var label := String(DISASTER_TITLES.get(kind, ""))
	if label == "":
		return ""
	var it := ItalianTexts.text("disastri", label) if italian else ""
	return it if it != "" else table.text(label)
