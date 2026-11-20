class_name CampaignUiReport
extends RefCounted
## Resoconto di fine anno impaginato per la finestra degli avvenimenti (richiesta di Federico dell'11/11/2026: in testo
## semplice era troppo denso e si leggeva a fatica). Prende i blocchi di CampaignUiText.year_report_sections e li rende in
## BBCode per un RichTextLabel: intestazione di sezione nel carattere dei titoli con il numero di avvenimenti e un filo
## sotto; un avvenimento per riga con il pallino e il rientro sospeso (le righe a capo restano allineate al testo); nomi
## di fazioni, province e personaggi in grassetto (la fazione del giocatore nel colore dei titoli, le altre in blu); la
## frase dell'originale tra «» staccata sotto, in corsivo e più tenue; avvisi ed errori in rosso in fondo.

const BULLET := "•"
const QUOTE_SIZE := 15            ## misura della frase dell'originale tra «»
const HEADER_SIZE := 20           ## misura dell'intestazione di sezione
const COUNT_SIZE := 15            ## misura del numero di avvenimenti accanto all'intestazione
const GAP_SIZE := 9               ## misura della riga vuota tra due sezioni
const MIN_NAME := 3               ## nomi più corti non si evidenziano (sigle, iniziali)


## Numero di avvenimenti del resoconto (esclusi avvisi ed errori).
static func event_count(sections: Array[Dictionary]) -> int:
	var n := 0
	for sec in sections:
		var kind := str(sec["tipo"])
		if kind == CampaignUiText.REPORT_SECTION or kind == CampaignUiText.REPORT_OTHERS:
			var lines: PackedStringArray = sec["righe"]
			n += lines.size()
	return n


## Riga sotto il titolo della finestra: «Ora è il 1022 · 7 avvenimenti».
static func subtitle(new_year: int, sections: Array[Dictionary]) -> String:
	var n := event_count(sections)
	var count := Lang.t("nessun avvenimento") if n == 0 else (Lang.t("1 avvenimento") if n == 1 else Lang.t("%d avvenimenti") % n)
	return Lang.t("Ora è il %d · %s") % [new_year, count]


## BBCode del resoconto. `closing` (facoltativa) è una riga finale in grassetto, per esempio la fine della campagna.
static func bbcode(state: GameState, sections: Array[Dictionary], player_id: String, closing: String = "") -> String:
	var names := name_table(state, player_id)
	var pattern := name_pattern(names)
	var parts := PackedStringArray()
	for sec in sections:
		var kind := str(sec["tipo"])
		var lines: PackedStringArray = sec["righe"]
		var title := str(sec["titolo"])
		var bad := kind == CampaignUiText.REPORT_WARNINGS or kind == CampaignUiText.REPORT_ERRORS
		if kind == CampaignUiText.REPORT_WARNINGS:
			title = Lang.t("Avvisi")
		elif kind == CampaignUiText.REPORT_ERRORS:
			title = Lang.t("Errori nei dati")
		var block := ""
		if title != "":
			block += _header(title, lines.size() if not bad else 0, UiTheme.INK_BAD if bad else UiTheme.INK_TITLE)
		block += _items(lines, names, pattern, UiTheme.INK_BAD if bad else UiTheme.INK_TITLE)
		parts.append(block)
	if closing != "":
		parts.append("[b]%s[/b]" % highlight(closing, names, pattern))
	return ("\n[font_size=%d] [/font_size]\n" % GAP_SIZE).join(parts)


## Testo di un avvenimento con i nomi in grassetto; le parentesi quadre del testo non diventano BBCode.
static func highlight(text: String, names: Dictionary, pattern: RegEx) -> String:
	if pattern == null:
		return escape(text)
	var out := ""
	var last := 0
	for m in pattern.search_all(text):
		out += escape(text.substr(last, m.get_start() - last))
		var name := m.get_string()
		var color: Variant = names.get(name)
		if color is Color:
			out += "[b][color=#%s]%s[/color][/b]" % [(color as Color).to_html(false), escape(name)]
		else:
			out += "[b]%s[/b]" % escape(name)
		last = m.get_end()
	out += escape(text.substr(last))
	return out


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Nomi da evidenziare -> colore (Color) o null (grassetto nel colore del testo): fazioni (quella del giocatore nel colore
## dei titoli, le altre in blu), province e mari, personaggi (nome completo, con il numerale per i re).
static func name_table(state: GameState, player_id: String) -> Dictionary:
	var out := {}
	if state == null:
		return out
	for c in state.characters:
		var n := c.full_name().strip_edges()
		if n.length() >= MIN_NAME:
			out[n] = null
	if state.campaign != null:
		for r in state.campaign.regions:
			var n := CampaignUiText.region_name(state, r.id)
			if n.length() >= MIN_NAME:
				out[n] = null
	var player := SimUtil.norm(player_id)
	for f in state.factions:
		var n := CampaignUiText.faction_name(f.id)
		if n.length() >= MIN_NAME:
			out[n] = UiTheme.INK_TITLE if f.id == player else UiTheme.INK_BLUE
	return out


## Espressione che trova i nomi della tabella come parole intere, preferendo i più lunghi («Mar Baltico» prima di «Baltico»).
static func name_pattern(names: Dictionary) -> RegEx:
	if names.is_empty():
		return null
	var keys: Array = names.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a).length() > str(b).length())
	var alts := PackedStringArray()
	for k in keys:
		alts.append(_regex_escape(str(k)))
	var re := RegEx.new()
	if re.compile("(?<![\\p{L}\\p{N}])(?:%s)(?![\\p{L}\\p{N}])" % "|".join(alts)) != OK:
		return null
	return re


## Divide un avvenimento nel testo e nella frase dell'originale tra «» in fondo: ["testo", "frase"] ("" se non c'è).
static func split_quote(line: String) -> PackedStringArray:
	var re := RegEx.new()
	re.compile("^(.*?)\\s*«([^«»]+)»\\s*$")
	var m := re.search(line)
	if m == null or m.get_string(1).strip_edges() == "":
		return PackedStringArray([line, ""])
	return PackedStringArray([m.get_string(1), m.get_string(2)])


# --- interni -----------------------------------------------------------------------------------------------------------

static func _header(title: String, count: int, color: Color) -> String:
	var t := "[font=%s][font_size=%d][color=#%s]%s[/color][/font_size][/font]" % [
		UiTheme.FONT_TITLE, HEADER_SIZE, color.to_html(false), escape(title)]
	if count > 0:
		t += "  [font_size=%d][color=#%s]%d[/color][/font_size]" % [COUNT_SIZE, UiTheme.INK_FAINT.to_html(false), count]
	t += "\n[hr color=#%s height=1 width=100%% align=left]" % Color(UiTheme.LEATHER, 0.45).to_html(true)
	return t


## Righe di una sezione in una tabella a due colonne: pallino e testo, così chi va a capo resta allineato al testo.
static func _items(lines: PackedStringArray, names: Dictionary, pattern: RegEx, bullet_color: Color) -> String:
	var t := "[table=2]"
	for line in lines:
		var parts := split_quote(line)
		var body := highlight(parts[0], names, pattern)
		if parts[1] != "":
			body += "\n[font_size=%d][i][color=#%s]«%s»[/color][/i][/font_size]" % [
				QUOTE_SIZE, UiTheme.INK_FAINT.to_html(false), escape(parts[1])]
		t += "[cell padding=2,3,10,5][color=#%s]%s[/color][/cell][cell expand=1 padding=0,3,4,5]%s[/cell]" % [
			bullet_color.to_html(false), BULLET, body]
	t += "[/table]"
	return t


static func _regex_escape(text: String) -> String:
	var out := ""
	for ch in text:
		if "\\^$.|?*+()[]{}/".contains(ch):
			out += "\\" + ch
		else:
			out += ch
	return out
