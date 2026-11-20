extends RefCounted
## Fortezza bianca degli Auror (ADR-076): solo nella regione natia degli Auror (la Norvegia) e solo in modalita' Auror;
## sulla mappa al posto del castello e piu' grande, nella barra e nelle finestre come icona del castello costruito.


func test_solo_nella_regione_natia_e_solo_in_modalita_auror(t: TestContext) -> void:
	Scenario.set_auror(true)
	t.assert_true(FortressArt.is_fortress("ID_ATLANTIS"))
	t.assert_true(FortressArt.is_fortress("id_atlantis "), "senza distinguere maiuscole e spazi")
	t.assert_false(FortressArt.is_fortress("ID_DENMARK"), "la Danimarca non e' piu' la regione natia")
	t.assert_false(FortressArt.is_fortress(""))
	Scenario.set_auror(false)
	t.assert_false(FortressArt.is_fortress("ID_ATLANTIS"), "scenario storico: nessuna fortezza")
	t.assert_eq(FortressArt.map_original("ID_ATLANTIS"), "")
	t.assert_true(FortressArt.icon("ID_ATLANTIS") == null)
	Scenario.set_auror(true)


func test_immagini_solo_se_pronte(t: TestContext) -> void:
	Scenario.set_auror(true)
	var ready := AssetLibrary.is_remade(FortressArt.MAP_ORIGINAL)
	t.assert_eq(FortressArt.map_original("ID_ATLANTIS"), FortressArt.MAP_ORIGINAL if ready else "")
	t.assert_eq(FortressArt.map_original("ID_DENMARK"), "")
	t.assert_true(FortressArt.icon("ID_DENMARK") == null)
	t.assert_eq(FortressArt.icon("ID_ATLANTIS") != null, AssetLibrary.is_remade(FortressArt.ICON_ORIGINAL))
	t.assert_true(FortressArt.MAP_SCALE > 1.0, "piu' grande degli altri castelli")


func test_pedina_della_fortezza_diversa_dal_castello_del_grado(t: TestContext) -> void:
	Scenario.set_auror(true)
	if not AssetLibrary.is_available() or not AssetLibrary.is_remade(FortressArt.MAP_ORIGINAL):
		t.skip("immagine della fortezza non ancora preparata")
		return
	var data := Scenario.load_startpos()
	var normal := PieceArt.castle_piece(data, "FN_DANISH", 4, 1.0)
	var fortress := PieceArt.castle_piece(data, "FN_DANISH", 4, 1.0, FortressArt.MAP_ORIGINAL)
	t.assert_true(normal != null and fortress != null)
	t.assert_true(fortress != normal, "pedina propria")
	t.assert_true(fortress.get_height() >= normal.get_height())
