extends RefCounted
## Test della logica pura dell'interfaccia della fase 5c (Papato, scomunica, crociate e jihad): generi e distintivi,
## indicatore di scomunica e avviso del Papa nella barra, riga del Papato e colonna della scomunica nella diplomazia,
## righe del pannello dell'esercito crociato, scelta del bersaglio (clic destro, elenco dall'anteprima, messaggi),
## voci di reclutamento di Crusade e Jihad, lealtà con la voce «scomunica», testi degli eventi e resoconto di fine anno.
## Mondo di prova: tests/unit/papacy_world.gd (ALPHA, GAMMA e DELTA cattoliche, BETA musulmana, il Papato a ROMA,
## ribelli in RIBELLE); ALPHA è il giocatore. Nomi delle regioni: Roma, Nord1, Nord2, Nord3, Est, Delta1, Sud1, Sud2,
## Ribelle; nomi delle fazioni: Alpha, Beta, Gamma, Delta, Papist.

const W := preload("res://tests/unit/papacy_world.gd")
const ArmyLayerScript := preload("res://scenes/army_layer.gd")
const CRUSADE := PapacyProcessor.KIND_CRUSADE
const JIHAD := PapacyProcessor.KIND_JIHAD


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	return s


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


func _text(s: GameState, kind: String, data: Dictionary) -> String:
	return CampaignUiText.format_event(s, _ev(kind, data))


func _no_raw_ids(t: TestContext, text: String) -> void:
	t.assert_false(text.contains("ID_"), text)
	t.assert_false(text.contains("FN_"), text)


# --- generi e distintivi ----------------------------------------------------------------------------------------


func test_nomi_dei_generi(t: TestContext) -> void:
	t.assert_eq(CampaignUiPapacy.kind_name(CRUSADE), "crociata")
	t.assert_eq(CampaignUiPapacy.kind_name(JIHAD), "jihad")
	t.assert_eq(CampaignUiPapacy.kind_name(""), "crociata", "senza genere: crociata")
	t.assert_eq(CampaignUiPapacy.kind_noun(CRUSADE), "La crociata")
	t.assert_eq(CampaignUiPapacy.kind_noun(JIHAD), "Il jihad")
	t.assert_eq(CampaignUiPapacy.kind_label(CRUSADE), "Crociata")
	t.assert_eq(CampaignUiPapacy.kind_label(JIHAD), "Jihad")
	t.assert_eq(CampaignUiPapacy.kind_tag(CRUSADE), "[Crociata]")
	t.assert_eq(CampaignUiPapacy.kind_tag(JIHAD), "[Jihad]")


func test_distintivo_dell_esercito_crociato(t: TestContext) -> void:
	var s := _world()
	var crusade := W.add_crusade(s, W.A, W.NORD1)
	var jihad := W.add_crusade(s, W.B, W.SUD2, JIHAD)
	var plain := W.land_army(s, W.G, W.EST)
	t.assert_eq(CampaignUiPapacy.badge_of(crusade), CampaignUiPapacy.BADGE_CROSS)
	t.assert_eq(CampaignUiPapacy.badge_of(jihad), CampaignUiPapacy.BADGE_CRESCENT)
	t.assert_eq(CampaignUiPapacy.badge_of(plain), "", "l'esercito normale non ha distintivo")
	t.assert_eq(CampaignUiPapacy.badge_of(null), "")
	var fleet := s.create_army(W.A, W.NORD1, true)
	t.assert_eq(CampaignUiPapacy.badge_of(fleet), "", "le flotte non hanno distintivo")


func test_il_livello_dei_segnalini_porta_il_distintivo(t: TestContext) -> void:
	var layer: ArmyLayerScript = ArmyLayerScript.new()
	layer.set_view(Vector2(100.0, 100.0), 1.0, Vector2(1280.0, 720.0))
	layer.add_marker(1, Vector2(100.0, 100.0), Vector2(-28.0, 0.0), Color.RED, "4", false, true, false, CampaignUiPapacy.BADGE_CROSS)
	layer.add_marker(2, Vector2(100.0, 100.0), Vector2(28.0, 0.0), Color.BLUE, "2", false, false, false)
	layer.add_marker(3, Vector2(100.0, 100.0), Vector2(0.0, 28.0), Color.GREEN, "4", false, false, false, CampaignUiPapacy.BADGE_CRESCENT)
	t.assert_eq(layer.marker_count(), 3)
	t.assert_eq(layer.marker_badge(0), CampaignUiPapacy.BADGE_CROSS)
	t.assert_eq(layer.marker_badge(1), "", "senza distintivo come prima")
	t.assert_eq(layer.marker_badge(2), CampaignUiPapacy.BADGE_CRESCENT)
	t.assert_eq(layer.marker_badge(9), "", "fuori intervallo")
	var center := Vector2(640.0, 360.0)
	t.assert_eq(layer.army_at(center + Vector2(-28.0, 0.0)), 1, "il segnalino con il distintivo si trova come gli altri")
	t.assert_eq(layer.army_at(center + Vector2(28.0, 0.0)), 2)
	# il distintivo sta sopra il segnalino
	var badge := ArmyLayerScript.badge_center(Vector2(100.0, 100.0))
	t.assert_eq(badge.x, 100.0)
	t.assert_true(badge.y < 100.0 - ArmyLayerScript.HALF, "sopra il bordo alto del segnalino")
	# ADR-072: la pedina di crociata e jihad e' piu' grande delle altre
	t.assert_eq(layer.marker_height(layer._markers[0]), layer.marker_height(layer._markers[1]) * ArmyLayerScript.CRUSADE_PIECE_SCALE)
	t.assert_eq(layer.marker_height(layer._markers[2]), layer.marker_height(layer._markers[0]))
	t.assert_true(ArmyLayerScript.CRUSADE_PIECE_SCALE > 1.0)
	layer.clear_all()
	t.assert_eq(layer.marker_badge(0), "")


# --- barra in alto ----------------------------------------------------------------------------------------------


func test_testo_della_scomunica(t: TestContext) -> void:
	t.assert_eq(CampaignUiPapacy.excommunication_text(1150), "Scomunicati dal 1150")
	t.assert_eq(CampaignUiPapacy.excommunication_text(1150, false), "Scomunicata dal 1150")
	t.assert_eq(CampaignUiPapacy.excommunication_text(0), "Scomunicati", "anno sconosciuto")


func test_indicatore_di_scomunica_nella_barra(t: TestContext) -> void:
	var s := _world()
	var free := CampaignUiPapacy.excommunication_info(s, W.A)
	t.assert_false(bool(free["scomunicata"]))
	t.assert_eq(free["testo"], "")
	t.assert_eq(free["tooltip"], "")
	t.assert_true(PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_PAPACY, W.ROMA))
	var info := CampaignUiPapacy.excommunication_info(s, W.A)
	t.assert_true(bool(info["scomunicata"]))
	t.assert_eq(info["testo"], "Scomunicati dal 1000")
	var tip := str(info["tooltip"])
	t.assert_true(tip.contains("influenza del capo cala di %d" % s.rules.papacy.excommunication_influence), tip)
	t.assert_true(tip.contains("fino a %d" % s.rules.papacy.excommunication_loyalty), tip)
	t.assert_true(tip.contains("alleanze"), tip)
	t.assert_true(tip.contains("crociate"), tip)
	t.assert_true(tip.contains("morte del Papa"), tip)
	t.assert_false(bool(CampaignUiPapacy.excommunication_info(s, W.G)["scomunicata"]), "solo la fazione scomunicata")
	t.assert_false(bool(CampaignUiPapacy.excommunication_info(s, "FN_NESSUNA")["scomunicata"]), "fazione sconosciuta")
	PapacyProcessor.lift_excommunication(s, W.A, "morte_del_papa")
	t.assert_false(bool(CampaignUiPapacy.excommunication_info(s, W.A)["scomunicata"]), "revocata")


func test_avviso_del_papa_nella_barra(t: TestContext) -> void:
	var s := _world()
	var none := CampaignUiPapacy.warning_info(s, W.A)
	t.assert_false(bool(none["visibile"]))
	t.assert_eq(none["testo"], "")
	# la piu' grande tra due cattoliche che attacca viene ammonita (regola della simulazione)
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.G, W.EST), GameState.EV_PAPAL_WARNING)
	var one := CampaignUiPapacy.warning_info(s, W.A)
	t.assert_true(bool(one["visibile"]))
	t.assert_eq(one["testo"], "Il Papa vi ammonisce: non attaccate Gamma fino al 1002.")
	t.assert_true(str(one["tooltip"]).contains("scomunicati"), str(one["tooltip"]))
	t.assert_true(str(one["tooltip"]).contains("tregua di 10 anni"), str(one["tooltip"]))
	t.assert_false(bool(CampaignUiPapacy.warning_info(s, W.G)["visibile"]), "l'avviso e' di chi e' ammonito")
	var lines := CampaignUiPapacy.warnings_of(s, W.A)
	t.assert_eq(lines.size(), 1)
	t.assert_eq(lines[0]["contro"], W.G)
	t.assert_eq(lines[0]["scadenza"], 1002)
	# due avvertimenti: tutte e due le fazioni con la loro scadenza
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.D, W.DELTA1), GameState.EV_PAPAL_WARNING)
	var two := CampaignUiPapacy.warning_info(s, W.A)
	t.assert_eq(two["testo"], "Il Papa vi ammonisce: non attaccate Delta (fino al 1002) e Gamma (fino al 1002).")
	# la scomunica toglie gli avvertimenti
	PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_WARNING)
	t.assert_false(bool(CampaignUiPapacy.warning_info(s, W.A)["visibile"]))


# --- pannello della diplomazia ----------------------------------------------------------------------------------


func test_colonna_della_scomunica_nella_diplomazia(t: TestContext) -> void:
	var s := _world()
	PapacyProcessor.excommunicate(s, W.G, PapacyProcessor.REASON_PAPACY)
	var headers := CampaignUiPapacy.diplomacy_headers()
	t.assert_eq(headers.size(), 6)
	t.assert_eq(headers[5], "Scomunica")
	t.assert_eq(CampaignUiAgents.diplomacy_headers().size(), 5, "le colonne della 5a non cambiano")
	var rows := CampaignUiPapacy.diplomacy_rows(s, W.A)
	var seen := {}
	for row in rows:
		seen[str(row["fazione"])] = str(row["testo_scomunica"])
		t.assert_eq(CampaignUiPapacy.diplomacy_cells(row).size(), 6)
		t.assert_eq(CampaignUiPapacy.diplomacy_cells(row)[5], str(row["testo_scomunica"]))
		t.assert_eq(bool(row["scomunicata"]), str(row["fazione"]) == W.G)
	t.assert_eq(seen[W.G], "Scomunicata dal 1000")
	t.assert_eq(seen[W.A], "-")
	t.assert_eq(seen[W.B], "-")
	t.assert_eq(seen[W.P], "Papa", "il Papato e' tra le fazioni vive")
	t.assert_eq(rows[0]["fazione"], W.A, "il giocatore resta in cima")


func test_riga_del_papato(t: TestContext) -> void:
	var s := _world()
	var pope := s.leader_of(W.P)
	t.assert_true(pope != null)
	t.assert_eq(CampaignUiPapacy.papacy_line(s), "Papato: vivo · Papa %s" % pope.full_name())
	s.faction(W.P).alive = false
	t.assert_eq(CampaignUiPapacy.papacy_line(s), "Papato: distrutto · ricompare con un'armata tra 15 e 30 anni nelle sue terre")


# --- esercito crociato ------------------------------------------------------------------------------------------


func test_righe_del_pannello_della_crociata(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var lines := CampaignUiPapacy.crusade_lines(s, army)
	t.assert_eq(lines, PackedStringArray([
		"Crociata · zelo 80 su 100",
		"Bersaglio: nessuno (senza bersaglio lo zelo cala di altri 10 all'anno)",
		"Province già reclutate: nessuna",
	]))
	army.crusade["bersaglio"] = W.SUD1
	army.crusade["reclutate"] = [W.NORD2, W.NORD3]
	lines = CampaignUiPapacy.crusade_lines(s, army)
	t.assert_eq(lines[1], "Bersaglio: Sud1 (Beta)")
	t.assert_eq(lines[2], "Province già reclutate: Nord2, Nord3")
	t.assert_eq(lines.size(), 3)
	army.crusade["bersaglio"] = W.RIBELLE
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, army)[1], "Bersaglio: Ribelle (ribelli)")
	var jihad := W.add_crusade(s, W.B, W.SUD2, JIHAD)
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, jihad)[0], "Jihad · zelo 80 su 100")
	t.assert_true(CampaignUiPapacy.crusade_lines(s, W.land_army(s, W.G, W.EST)).is_empty(), "l'esercito normale non ha righe")
	t.assert_true(CampaignUiPapacy.crusade_lines(s, null).is_empty())


func test_avvisi_di_zelo_basso(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1, CRUSADE, W.SUD1)
	army.crusade["zelo"] = 40
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, army).size(), 3, "40: ancora nessun avviso (soglia: sotto 40)")
	army.crusade["zelo"] = 39
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, army)[3], "Zelo basso: a fine anno si perde un'armata.")
	army.crusade["zelo"] = 29
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, army)[3], "Zelo molto basso: a fine anno 2 armate disertano.")
	army.crusade["zelo"] = 20
	t.assert_eq(CampaignUiPapacy.crusade_lines(s, army)[3], "Zelo esaurito: l'esercito si scioglie a fine anno.")


func test_descrizione_dell_esercito_crociato(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var text := CampaignUiPapacy.army_text(s, army)
	t.assert_true(text.begins_with(CampaignUiText.describe_army(s, army)), "prima la descrizione di sempre")
	t.assert_true(text.contains("Crociata · zelo 80 su 100"), text)
	var plain := W.land_army(s, W.G, W.EST)
	t.assert_eq(CampaignUiPapacy.army_text(s, plain), CampaignUiText.describe_army(s, plain), "gli altri eserciti non cambiano")


# --- scelta del bersaglio ---------------------------------------------------------------------------------------


func test_azione_del_clic_destro(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	t.assert_eq(CampaignUiPapacy.right_click_action(army, W.SUD1), CampaignUiPapacy.CLICK_TARGET, "senza bersaglio: lo sceglie")
	t.assert_eq(CampaignUiPapacy.right_click_action(army, W.NORD1), CampaignUiPapacy.CLICK_MOVE, "sulla propria regione: annulla il movimento")
	army.crusade["bersaglio"] = W.SUD1
	t.assert_eq(CampaignUiPapacy.right_click_action(army, W.NORD2), CampaignUiPapacy.CLICK_MOVE, "con il bersaglio: movimento come ora")
	var plain := W.land_army(s, W.G, W.EST)
	t.assert_eq(CampaignUiPapacy.right_click_action(plain, W.NORD1), CampaignUiPapacy.CLICK_MOVE)
	t.assert_eq(CampaignUiPapacy.right_click_action(null, W.NORD1), CampaignUiPapacy.CLICK_MOVE)
	var fleet := s.create_army(W.A, W.NORD1, true)
	t.assert_eq(CampaignUiPapacy.right_click_action(fleet, W.NORD2), CampaignUiPapacy.CLICK_MOVE)


func test_motivi_dei_bersagli(t: TestContext) -> void:
	t.assert_eq(CampaignUiPapacy.target_reason_text("scomunicato"), "proprietario scomunicato")
	t.assert_eq(CampaignUiPapacy.target_reason_text("ribelle"), "in mano ai ribelli")
	t.assert_eq(CampaignUiPapacy.target_reason_text("non_cattolico"), "proprietario non cattolico")
	t.assert_eq(CampaignUiPapacy.target_reason_text("eretici"), "maggioranza eretica")
	t.assert_eq(CampaignUiPapacy.target_reason_text("musulmana"), "terra un tempo musulmana")
	t.assert_eq(CampaignUiPapacy.target_reason_text("altro_motivo"), "altro motivo", "sconosciuto: leggibile comunque")


func test_elenco_dei_bersagli_dall_anteprima(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var menu := CampaignUiPapacy.target_menu(s, W.A, army.id)
	t.assert_true(bool(menu["ok"]), str(menu["errore"]))
	t.assert_eq(menu["titolo"], "Crociata %d: scegli il bersaglio (zelo 80)" % army.id)
	t.assert_eq(menu["bersaglio"], "")
	var entries: Array = menu["voci"]
	t.assert_eq(entries.size(), 3)
	# ordine alfabetico del nome
	t.assert_eq(entries[0]["regione"], W.RIBELLE)
	t.assert_eq(entries[0]["testo"], "Ribelle · di ribelli · in mano ai ribelli")
	t.assert_eq(entries[1]["regione"], W.SUD1)
	t.assert_eq(entries[1]["testo"], "Sud1 · di Beta · proprietario non cattolico")
	t.assert_eq(entries[2]["regione"], W.SUD2)
	for entry in entries:
		t.assert_false(bool(entry["attuale"]))
	# uno scomunicato diventa un bersaglio e il bersaglio attuale e' segnato
	PapacyProcessor.excommunicate(s, W.G, PapacyProcessor.REASON_PAPACY)
	var set_result := GameCommands.set_crusade_target(s, W.A, army.id, W.EST)
	t.assert_true(bool(set_result["ok"]), str(set_result["errore"]))
	menu = CampaignUiPapacy.target_menu(s, W.A, army.id)
	entries = menu["voci"]
	t.assert_eq(entries.size(), 4)
	t.assert_eq(entries[0]["regione"], W.EST)
	t.assert_eq(entries[0]["testo"], "Est · di Gamma · proprietario scomunicato")
	t.assert_true(bool(entries[0]["attuale"]))
	t.assert_eq(menu["bersaglio"], W.EST)
	# eretici
	s.province(W.DELTA1).religions = ProvinceState.normalize_religions({"HERETIC": 100.0})
	var heretic := CampaignUiPapacy.target_menu(s, W.A, army.id)["voci"] as Array
	var found := false
	for entry in heretic:
		if entry["regione"] == W.DELTA1:
			found = true
			t.assert_eq(entry["testo"], "Delta1 · di Delta · maggioranza eretica")
	t.assert_true(found, "la provincia a maggioranza eretica e' un bersaglio")


func test_elenco_dei_bersagli_del_jihad(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.B, W.SUD2, JIHAD)
	t.assert_eq((CampaignUiPapacy.target_menu(s, W.B, army.id)["voci"] as Array).size(), 0, "nessuna terra un tempo musulmana")
	s.province(W.NORD2).former_owner = W.B
	var menu := CampaignUiPapacy.target_menu(s, W.B, army.id)
	t.assert_eq(menu["titolo"], "Jihad %d: scegli il bersaglio (zelo 80)" % army.id)
	var entries: Array = menu["voci"]
	t.assert_eq(entries.size(), 1)
	t.assert_eq(entries[0]["testo"], "Nord2 · di Alpha · terra un tempo musulmana")


func test_elenco_dei_bersagli_con_errori(t: TestContext) -> void:
	var s := _world()
	var plain := W.land_army(s, W.A, W.NORD1)
	var army := W.add_crusade(s, W.A, W.NORD1)
	var foreign := CampaignUiPapacy.target_menu(s, W.B, army.id)
	t.assert_false(bool(foreign["ok"]), "non e' un esercito di BETA")
	t.assert_true(str(foreign["errore"]) != "")
	t.assert_true((foreign["voci"] as Array).is_empty())
	var not_crusade := CampaignUiPapacy.target_menu(s, W.A, plain.id)
	t.assert_false(bool(not_crusade["ok"]), "non e' un esercito crociato")
	t.assert_false(bool(CampaignUiPapacy.target_menu(s, W.A, 9999)["ok"]), "esercito sconosciuto")


func test_messaggio_del_bersaglio_scelto(t: TestContext) -> void:
	var s := _world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var r := GameCommands.set_crusade_target(s, W.A, army.id, W.SUD1)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var text := CampaignUiPapacy.target_result_text(s, r)
	t.assert_true(text.begins_with("Crociata %d: bersaglio Sud1 (Beta)." % army.id), text)
	t.assert_true(text.contains("Percorso: "), text)
	t.assert_true(text.contains("Sud1"), text)
	t.assert_true(text.ends_with("La guerra a Beta si dichiara all'ingresso."), text)
	_no_raw_ids(t, text)
	# un bersaglio dei ribelli: nessuna guerra da dichiarare
	var rebels := W.add_crusade(s, W.A, W.EST)
	var rr := GameCommands.set_crusade_target(s, W.A, rebels.id, W.RIBELLE)
	t.assert_true(bool(rr["ok"]), str(rr["errore"]))
	var rebel_text := CampaignUiPapacy.target_result_text(s, rr)
	t.assert_true(rebel_text.begins_with("Crociata %d: bersaglio Ribelle (ribelli)." % rebels.id), rebel_text)
	t.assert_false(rebel_text.contains("La guerra"), rebel_text)
	# bersaglio tolto
	var cleared := GameCommands.set_crusade_target(s, W.A, army.id, "")
	t.assert_eq(CampaignUiPapacy.target_result_text(s, cleared), "Crociata %d: bersaglio tolto." % army.id)
	# bersaglio con un ordine di movimento gia' dato: il percorso resta
	var again := GameCommands.set_crusade_target(s, W.A, army.id, W.SUD2)
	t.assert_true(bool(again["ok"]), str(again["errore"]))
	var kept := CampaignUiPapacy.target_result_text(s, again)
	t.assert_true(kept.contains("prosegue sul percorso già ordinato"), kept)
	# bersaglio non valido: l'errore della simulazione, senza id grezzi
	var bad := GameCommands.set_crusade_target(s, W.A, army.id, W.NORD2)
	t.assert_false(bool(bad["ok"]), "NORD2 e' di ALPHA")
	var bad_text := CampaignUiPapacy.target_result_text(s, bad)
	t.assert_true(bad_text != "", bad_text)
	_no_raw_ids(t, bad_text)
	var sea_only := {"ok": false, "errore": "Il bersaglio deve essere una provincia di terra (ID_NORD1 e' mare)"}
	t.assert_eq(CampaignUiPapacy.target_result_text(s, sea_only), "Il bersaglio deve essere una provincia di terra (Nord1 e' mare)")


# --- reclutamento -----------------------------------------------------------------------------------------------


func test_genere_e_visibilita_delle_voci_di_reclutamento(t: TestContext) -> void:
	var s := _world()
	var crusade_unit := s.units.get_unit("Crusade")
	var jihad_unit := s.units.get_unit("Jihad")
	var spears := s.units.get_unit("Spearmen")
	t.assert_true(crusade_unit != null and jihad_unit != null and spears != null)
	t.assert_eq(CampaignUiPapacy.unit_kind(crusade_unit), CRUSADE)
	t.assert_eq(CampaignUiPapacy.unit_kind(jihad_unit), JIHAD)
	t.assert_eq(CampaignUiPapacy.unit_kind(spears), "")
	t.assert_true(CampaignUiPapacy.recruit_visible(s, W.A, CRUSADE))
	t.assert_false(CampaignUiPapacy.recruit_visible(s, W.B, CRUSADE), "i musulmani non vedono la crociata")
	t.assert_true(CampaignUiPapacy.recruit_visible(s, W.B, JIHAD))
	t.assert_false(CampaignUiPapacy.recruit_visible(s, W.A, JIHAD), "i cattolici non vedono il jihad")
	t.assert_false(CampaignUiPapacy.recruit_visible(s, W.A, ""))


func test_etichetta_della_voce_di_reclutamento(t: TestContext) -> void:
	var s := _world()
	var crusade_unit := s.units.get_unit("Crusade")
	var check := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_true(bool(check["ok"]), str(check["errore"]))
	var text := CampaignUiPapacy.recruit_text(crusade_unit, CRUSADE, int(check["costo"]), int(check["anni"]))
	t.assert_eq(text, "[Crociata] Crociata · 1000 fiorini, 4 anni")
	var jihad_unit := s.units.get_unit("Jihad")
	var jihad_check := GameCommands.can_queue_unit(s, W.B, W.SUD1, "Jihad")
	t.assert_true(bool(jihad_check["ok"]), str(jihad_check["errore"]))
	t.assert_eq(CampaignUiPapacy.recruit_text(jihad_unit, JIHAD, int(jihad_check["costo"]), int(jihad_check["anni"])), "[Jihad] Jihad · 500 fiorini, 2 anni")
	t.assert_true(CampaignUiPapacy.recruit_tip(CRUSADE, "Costo.").begins_with("Costo.\n"))
	t.assert_true(CampaignUiPapacy.recruit_tip(CRUSADE, "Costo.").contains("Una alla volta"))
	t.assert_true(CampaignUiPapacy.recruit_tip(JIHAD, "Costo.").contains("musulmane"))


func test_motivo_dell_indisponibilita_dall_errore_vero(t: TestContext) -> void:
	var s := _world()
	var unit := s.units.get_unit("Crusade")
	# scomunica
	PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_PAPACY)
	var banned := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(banned["ok"]))
	t.assert_eq(CampaignUiPapacy.unavailable_reason(str(banned["errore"])), "scomunica")
	t.assert_eq(CampaignUiPapacy.recruit_text(unit, CRUSADE, 1000, 4, str(banned["errore"])), "[Crociata] Crociata · 1000 fiorini, 4 anni (scomunica)")
	PapacyProcessor.lift_excommunication(s, W.A, "morte_del_papa")
	# crociata in coda
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	var queued := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(queued["ok"]))
	t.assert_eq(CampaignUiPapacy.unavailable_reason(str(queued["errore"])), "crociata già in coda")
	GameCommands.cancel_queue_item(s, W.A, W.NORD1, GameCommands.QUEUE_UNIT, 0)
	# crociata attiva
	W.add_crusade(s, W.A, W.NORD2)
	var active := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(active["ok"]))
	t.assert_eq(CampaignUiPapacy.unavailable_reason(str(active["errore"])), "crociata già attiva")
	t.assert_true(CampaignUiPapacy.recruit_text(unit, CRUSADE, 1000, 4, str(active["errore"])).ends_with("(crociata già attiva)"))
	# altri errori: nessun motivo papale (requisiti, tesoro)
	var other := GameCommands.can_queue_unit(s, W.G, W.EST, "Crusade")
	t.assert_false(bool(other["ok"]), "manca la Chapter House")
	t.assert_eq(CampaignUiPapacy.unavailable_reason(str(other["errore"])), "")
	t.assert_eq(CampaignUiPapacy.recruit_text(unit, CRUSADE, 1000, 4, str(other["errore"])), "[Crociata] Crociata · 1000 fiorini, 4 anni")
	t.assert_eq(CampaignUiPapacy.unavailable_reason(""), "")


func test_etichetta_della_coda_di_reclutamento(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiPapacy.queue_label(s, "Crusade"), "[Crociata] Crociata")
	t.assert_eq(CampaignUiPapacy.queue_label(s, "Jihad"), "[Jihad] Jihad")
	t.assert_eq(CampaignUiPapacy.queue_label(s, "Spearmen"), CampaignUiAgents.queue_label(s, "Spearmen"), "le truppe come prima")
	t.assert_eq(CampaignUiPapacy.queue_label(s, "Sconosciuta"), CampaignUiAgents.queue_label(s, "Sconosciuta"))


# --- lealtà -----------------------------------------------------------------------------------------------------


func test_voce_scomunica_nella_lealta(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.term_label("scomunica"), "Scomunica")
	var pairs := CampaignUiText.loyalty_detail_pairs({"base": 100, "tassa": 0, "scomunica": -15, "somma": 85})
	var keys := PackedStringArray()
	for pair in pairs:
		keys.append(str(pair[0]))
	t.assert_eq(keys, PackedStringArray(["base", "scomunica"]), "la voce compare solo se diversa da zero")
	var quiet := CampaignUiText.loyalty_detail_pairs({"base": 100, "scomunica": 0})
	t.assert_eq(quiet.size(), 1)
	# dalla simulazione vera
	var s := _world()
	PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_PAPACY)
	var province := s.province(W.NORD1)
	var terms := ProvinceProcessor.loyalty_terms(s, province)
	t.assert_true(int(terms["scomunica"]) < 0, "i cattolici di una fazione scomunicata sono meno leali")
	province.last_loyalty = terms
	var text := "\n".join(CampaignUiText.loyalty_lines(province))
	t.assert_true(text.contains("Scomunica:"), text)


# --- resoconto di fine anno -------------------------------------------------------------------------------------


func test_sezione_del_resoconto_della_fase_5c(t: TestContext) -> void:
	var sections := CampaignUiText.phase5c_sections()
	t.assert_eq(sections.size(), 1)
	t.assert_eq(sections[0]["titolo"], "Papato e crociate")
	var kinds: PackedStringArray = sections[0]["tipi"]
	for kind in [GameState.EV_PAPAL_WARNING, GameState.EV_PAPAL_TRUCE, GameState.EV_EXCOMMUNICATION, GameState.EV_EXCOMMUNICATION_LIFTED,
			GameState.EV_PAPAL_GIFT, GameState.EV_PAPACY_REEMERGED, GameState.EV_CRUSADE_LAUNCHED, GameState.EV_CRUSADE_TARGET,
			GameState.EV_CRUSADE_RECRUITED, GameState.EV_CRUSADE_DESERTION, GameState.EV_CRUSADE_SUCCEEDED, GameState.EV_CRUSADE_FAILED]:
		t.assert_true(kinds.has(kind), "nel resoconto: %s" % kind)
	t.assert_eq(kinds.size(), 12)
	var every := CampaignUiText.all_report_sections()
	t.assert_eq(every.size(), CampaignUiText.report_sections().size() + CampaignUiText.phase5a_sections().size() + CampaignUiText.phase5b_sections().size() + 1 + CampaignUiText.phase6_sections().size())
	t.assert_eq(every[every.size() - 2]["titolo"], "Papato e crociate", "dopo la 5b e prima della fase 6")
	t.assert_eq(every[every.size() - 3]["titolo"], "Religione")
	t.assert_eq(every[every.size() - 1]["titolo"], "Eventi e storia", "in fondo, la fase 6")
	t.assert_true(CampaignUiText.always_reported_kinds().has(GameState.EV_PAPACY_REEMERGED), "la riemersione del Papato riguarda tutti")


func test_testi_degli_avvertimenti_e_delle_scomuniche(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_PAPAL_WARNING, {"fazione": W.A, "contro": W.G, "regione": W.EST, "fino_al": 1002}),
		"Il Papa ammonisce Alpha: non attacchi Gamma fino al 1002, o sarà scomunicata.")
	t.assert_eq(_text(s, GameState.EV_PAPAL_TRUCE, {"fazione": W.A, "con": W.G, "fino_al": 1012}),
		"Il Papa impone una tregua tra Alpha e Gamma fino al 1012.")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION, {"fazione": W.A, "motivo": "attacco_al_papato", "influenza_persa": 2, "alleanze_rotte": [W.G], "rimborso": 1000}),
		"Alpha è scomunicata dal Papa (ha attaccato il Papato). L'influenza del suo capo scende di 2. Alleanze rotte con Gamma. Le crociate in coda sono annullate: rimborsati 1000 fiorini.")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION, {"fazione": W.A, "motivo": "attacco_durante_avvertimento", "influenza_persa": 0, "alleanze_rotte": [], "rimborso": 0}),
		"Alpha è scomunicata dal Papa (ha ignorato l'avvertimento del Papa).")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION_LIFTED, {"fazione": W.A, "motivo": "morte_del_papa"}),
		"La scomunica di Alpha è revocata per la morte del Papa.")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION_LIFTED, {"fazione": W.A, "motivo": "morte_del_capo"}),
		"La scomunica di Alpha è revocata per la morte del suo capo.")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION_LIFTED, {"fazione": W.A, "motivo": "papato_distrutto"}),
		"La scomunica di Alpha è revocata perché il Papato è distrutto.")
	t.assert_eq(_text(s, GameState.EV_EXCOMMUNICATION_LIFTED, {"fazione": W.A, "motivo": ""}),
		"La scomunica di Alpha è revocata.")
	t.assert_eq(_text(s, GameState.EV_PAPAL_GIFT, {"fazione": W.A, "importo": 1000, "religiosi": 3}),
		"Dono del Papa per Alpha: 1000 fiorini (3 religiosi).")
	t.assert_eq(_text(s, GameState.EV_PAPACY_REEMERGED, {"fazione": W.P, "provincia": W.ROMA, "regione": W.ROMA, "pile": 4, "riemersioni": 1}),
		"Il Papato riemerge a Roma con 4 armate (riemersione 1).")
	t.assert_eq(_text(s, GameState.EV_ALLIANCE_BROKEN, {"fazione": W.A, "con": W.G, "motivo": "scomunica", "influenza_persa": 0}),
		"L'alleanza tra Alpha e Gamma cade per la scomunica.")


func test_testi_di_crociata_e_jihad_secondo_il_genere(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_CRUSADE_LAUNCHED, {"fazione": W.A, "genere": CRUSADE, "provincia": W.NORD1, "esercito": 7, "pile": 4, "zelo": 80}),
		"La crociata di Alpha parte da Nord1 con 4 armate (zelo 80).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_LAUNCHED, {"fazione": W.B, "genere": JIHAD, "provincia": W.SUD1, "esercito": 8, "pile": 4, "zelo": 80}),
		"Il jihad di Beta parte da Sud1 con 4 armate (zelo 80).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_TARGET, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "bersaglio": W.SUD1, "proprietario": W.B}),
		"La crociata di Alpha (esercito 7) ha come bersaglio Sud1 (Beta).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_TARGET, {"fazione": W.B, "genere": JIHAD, "esercito": 8, "bersaglio": W.NORD2, "proprietario": W.A}),
		"Il jihad di Beta (esercito 8) ha come bersaglio Nord2 (Alpha).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_TARGET, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "bersaglio": "", "proprietario": W.B}),
		"La crociata di Alpha (esercito 7) non ha più un bersaglio.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_TARGET, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "bersaglio": "", "motivo": "ID_SUD1 non e' piu' valido"}),
		"La crociata di Alpha (esercito 7) non ha più un bersaglio: Sud1 non e' piu' valido.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_RECRUITED, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "provincia": W.NORD2, "pile": 2, "zelo_provincia": 70}),
		"La crociata di Alpha recluta 2 armate a Nord2 (zelo della provincia 70).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_DESERTION, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "pile": 2, "zelo": 25, "motivo": "diserzione"}),
		"La crociata di Alpha perde 2 armate per diserzione (zelo 25).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_DESERTION, {"fazione": W.B, "genere": JIHAD, "esercito": 8, "pile": 1, "zelo": 35, "motivo": "perdite"}),
		"Il jihad di Beta perde 1 armata per le perdite (zelo 35).")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_SUCCEEDED, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "bersaglio": W.SUD1, "influenza": 1, "pile_ordine": 2, "unita_ordine": "TEMPLARS"}),
		"La crociata di Alpha conquista Sud1. L'influenza del suo capo sale di 1. Ricompensa: 2 armate di Templars.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_SUCCEEDED, {"fazione": W.B, "genere": JIHAD, "esercito": 8, "bersaglio": W.NORD2, "influenza": 1, "pile_ordine": 0, "unita_ordine": ""}),
		"Il jihad di Beta conquista Nord2. L'influenza del suo capo sale di 1.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_FAILED, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "motivo": "scioglimento", "influenza": -1}),
		"La crociata di Alpha fallisce: lo zelo è esaurito e l'esercito si scioglie. L'influenza del suo capo scende di 1.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_FAILED, {"fazione": W.B, "genere": JIHAD, "esercito": 8, "motivo": "distrutto", "influenza": -2}),
		"Il jihad di Beta fallisce: l'esercito è distrutto. L'influenza del suo capo scende di 2.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_FAILED, {"fazione": W.A, "genere": CRUSADE, "esercito": 7, "motivo": "scomunica", "influenza": 0}),
		"La crociata di Alpha fallisce: la fazione è scomunicata.")
	t.assert_eq(_text(s, GameState.EV_CRUSADE_FAILED, {"fazione": W.A, "esercito": 7, "motivo": "senza_pile", "influenza": 0}),
		"La crociata di Alpha fallisce: l'esercito non ha più pile.", "senza genere: crociata")


func test_testi_senza_i_campi_essenziali_ripiegano_sul_testo(t: TestContext) -> void:
	var s := _world()
	for kind in [GameState.EV_PAPAL_WARNING, GameState.EV_PAPAL_TRUCE, GameState.EV_EXCOMMUNICATION, GameState.EV_EXCOMMUNICATION_LIFTED,
			GameState.EV_PAPAL_GIFT, GameState.EV_PAPACY_REEMERGED, GameState.EV_CRUSADE_LAUNCHED, GameState.EV_CRUSADE_TARGET,
			GameState.EV_CRUSADE_RECRUITED, GameState.EV_CRUSADE_DESERTION, GameState.EV_CRUSADE_SUCCEEDED, GameState.EV_CRUSADE_FAILED]:
		t.assert_eq(_text(s, kind, {"testo": "testo della simulazione"}), "testo della simulazione", str(kind))
	t.assert_eq(CampaignUiPapacy.format_event(s, "altro_evento", {"fazione": W.A}), "", "i tipi altrui non sono suoi")


func test_resoconto_con_papato_e_crociate(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append(_ev(GameState.EV_PAPAL_WARNING, {"fazione": W.A, "contro": W.G, "regione": W.EST, "fino_al": 1002}))
	# la crociata di GAMMA non riguarda ALPHA ...
	s.events.append(_ev(GameState.EV_CRUSADE_LAUNCHED, {"fazione": W.G, "genere": CRUSADE, "provincia": W.EST, "esercito": 9, "pile": 4, "zelo": 80}))
	# ... ma il suo bersaglio in una provincia di ALPHA si
	s.events.append(_ev(GameState.EV_CRUSADE_TARGET, {"fazione": W.D, "genere": CRUSADE, "esercito": 10, "bersaglio": W.NORD1, "proprietario": W.A}))
	s.events.append(_ev(GameState.EV_CRUSADE_LAUNCHED, {"fazione": W.A, "genere": CRUSADE, "provincia": W.NORD1, "esercito": 11, "pile": 4, "zelo": 80}))
	s.events.append(_ev(GameState.EV_PAPACY_REEMERGED, {"fazione": W.P, "provincia": W.ROMA, "regione": W.ROMA, "pile": 4, "riemersioni": 1}))
	var lines := CampaignUiText.year_report(s, W.A, {"ok": true, "avvisi": [], "errori": []})
	t.assert_eq(lines, PackedStringArray([
		"— Papato e crociate —",
		"  Il Papa ammonisce Alpha: non attacchi Gamma fino al 1002, o sarà scomunicata.",
		"  La crociata di Delta (esercito 10) ha come bersaglio Nord1 (Alpha).",
		"  La crociata di Alpha parte da Nord1 con 4 armate (zelo 80).",
		"  Il Papato riemerge a Roma con 4 armate (riemersione 1).",
		"— Notizie dalle altre fazioni —",
		"  La crociata di Gamma parte da Est con 4 armate (zelo 80).",
	]), "la crociata di GAMMA arriva tra le notizie (2026-11-13)")
	for line in lines:
		_no_raw_ids(t, line)


func test_eventi_veri_di_papato_e_crociata_hanno_testo_leggibile(t: TestContext) -> void:
	var s := _world()
	var all_events: Array[Dictionary] = []   # il fine anno svuota il registro: li raccolgo anno per anno
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	for i in 4:
		var step := TurnProcessor.end_year(s)
		t.assert_true(bool(step["ok"]))
		all_events.append_array(s.events)
	var army: Army = null
	for a in s.armies_of(W.A):
		if a.is_crusade():
			army = a
	t.assert_true(army != null, "la crociata e' partita")
	if army == null:
		return
	var r := GameCommands.set_crusade_target(s, W.A, army.id, W.RIBELLE)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	TurnProcessor.end_year(s)
	all_events.append_array(s.events)
	PapacyProcessor.on_attack(s, W.A, W.G, W.EST)
	PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_PAPACY, W.ROMA)
	all_events.append_array(s.events)
	var wanted := PackedStringArray()
	for sec in CampaignUiText.phase5c_sections():
		wanted.append_array(sec["tipi"])
	var seen := PackedStringArray()
	for e in all_events:
		var kind := str(e["tipo"])
		if not wanted.has(kind):
			continue
		seen.append(kind)
		var text := CampaignUiText.format_event(s, e)
		t.assert_true(text != "" and text != kind, "riga grezza per %s" % kind)
		_no_raw_ids(t, text)
	t.assert_true(seen.has(GameState.EV_CRUSADE_LAUNCHED), "la partenza e' nel registro")
	t.assert_true(seen.has(GameState.EV_CRUSADE_TARGET), "il bersaglio e' annunciato")
	t.assert_true(seen.has(GameState.EV_EXCOMMUNICATION), "la scomunica e' nel registro")
	t.assert_true(seen.has(GameState.EV_CRUSADE_FAILED), "la crociata cade con la scomunica")
	t.assert_true(seen.has(GameState.EV_PAPAL_WARNING), "l'avvertimento e' nel registro")
