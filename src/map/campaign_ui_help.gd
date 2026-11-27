class_name CampaignUiHelp
extends RefCounted
## Finestra «Comandi e tasti» (tasto H; richiesta di Federico del 27/11/2026: piu' chiara, con i tasti in grassetto e le
## voci raggruppate). Ogni sezione: [titolo, [[tasti, cosa fa], ...]]. I testi passano da Lang.t qui, come letterali,
## cosi' tools/testi_lingua.py li vede.


static func sections() -> Array:
	return [
		[Lang.t("Mappa e vista"), [
			[Lang.t("Trascina col tasto sinistro · frecce"), Lang.t("sposta la mappa")],
			[Lang.t("Rotella"), Lang.t("zoom")],
			[Lang.t("P · Pagina su/giù"), Lang.t("prospettiva")],
			[Lang.t("B · R · N"), Lang.t("confini · tinta della religione · nomi delle regioni")],
			[Lang.t("Stemma nella barra in basso"), Lang.t("opzioni della mappa")],
			[Lang.t("Bussola sulla minimappa"), Lang.t("medaglioni di tutti i luoghi leggendari scoperti")],
		]],
		[Lang.t("Selezione"), [
			[Lang.t("Clic sinistro"), Lang.t("sceglie provincia, esercito o agente")],
			[Lang.t("Alt+clic · Alt+riquadro"), Lang.t("sceglie più eserciti insieme; trascinane uno o clic destro: vanno tutti")],
			[Lang.t("Esc"), Lang.t("chiude la finestra o toglie la scelta")],
		]],
		[Lang.t("Eserciti"), [
			[Lang.t("Trascina la pedina su una regione"), Lang.t("muove o attacca; nella sua regione la sposti dove vuoi")],
			[Lang.t("Clic destro con un esercito"), Lang.t("muove o attacca; sulle province cerchiate trasporta via mare")],
			[Lang.t("Trascina su un altro tuo esercito"), Lang.t("si uniscono, subito o all'arrivo")],
			[Lang.t("Trascina su un castello"), Lang.t("tuo: le unità che ci stanno si barricano; nemico: assedio o assalto")],
			[Lang.t("Clic sulle carte nella barra"), Lang.t("sceglie le unità; trascinale sulla mappa per separarle")],
			[Lang.t("Comandi nella barra"), Lang.t("annulla ordini, barricati, assalta, riaddestra, comandante, congeda")],
			[Lang.t("«Congeda»"), Lang.t("le unità scelte lasciano l'esercito senza rimborso e diventano mercenari")],
			[Lang.t("Clic destro sulla carta del comandante"), Lang.t("la sua scheda; da lì anche la scheda della sua unità")],
			[Lang.t("Crociata o jihad senza bersaglio"), Lang.t("il clic destro sceglie il bersaglio")],
		]],
		[Lang.t("Agenti"), [
			[Lang.t("Clic destro con un agente"), Lang.t("muove o sceglie la missione")],
			[Lang.t("Trascina un emissario"), Lang.t("su un re, un esercito o un emissario straniero: alleanza o tregua; su una principessa: nozze")],
		]],
		[Lang.t("Province e castelli"), [
			[Lang.t("Clic sul castello"), Lang.t("le truppe dentro; secondo clic: gli eserciti del castello")],
			[Lang.t("Clic su un edificio"), Lang.t("la sua scheda; le reclute nascono nel castello finché c'è posto")],
			[Lang.t(", e . · frecce della barra"), Lang.t("provincia precedente o successiva (con Maiusc solo quelle con qualcosa in coda)")],
			[Lang.t("Q"), Lang.t("le code di costruzione e addestramento di tutte le province")],
		]],
		[Lang.t("Partita e finestre"), [
			[Lang.t("Invio"), Lang.t("fine anno")],
			[Lang.t("F5 · F9"), Lang.t("salvataggio e caricamento rapidi")],
			[Lang.t("Esc · «Menu»"), Lang.t("salva, carica, menu iniziale, esci dal gioco")],
			[Lang.t("F1 · C · D · G"), Lang.t("economia · corte · diplomazia · classifica")],
			[Lang.t("K · «Regnanti»"), Lang.t("i sovrani in carica di tutte le fazioni")],
			[Lang.t("H"), Lang.t("questo aiuto")],
		]],
	]


## Righe di una sezione in BBCode: il tasto in grassetto e color inchiostro rosso, poi cosa fa.
static func bbcode(rows: Array) -> String:
	var out := PackedStringArray()
	for r in rows:
		var row: Array = r
		out.append("[color=#%s][b]%s[/b][/color]  —  %s" % [UiTheme.INK_TITLE.to_html(false), _escape(str(row[0])), _escape(str(row[1]))])
	return "\n".join(out)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
