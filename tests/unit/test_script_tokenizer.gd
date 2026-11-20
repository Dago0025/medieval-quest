extends RefCounted
## Test della scomposizione delle righe dei file a comandi.


func test_commento_tolto_fuori_dalle_virgolette(t: TestContext) -> void:
	t.assert_eq(ScriptTokenizer.strip_comment("SetTreasury:: FN_DANISH 99999 // MOD Auror"), "SetTreasury:: FN_DANISH 99999 ")


func test_commento_conservato_dentro_le_virgolette(t: TestContext) -> void:
	var line := "SetAttributes:: ID_X \"Nome // non commento\" 0 // commento vero"
	t.assert_eq(ScriptTokenizer.strip_comment(line), "SetAttributes:: ID_X \"Nome // non commento\" 0 ")


func test_argomenti_con_tabulazioni_multiple(t: TestContext) -> void:
	var args := ScriptTokenizer.split_args("\tID_DENMARK\t\t\tCastle15\t\t")
	t.assert_eq(args, PackedStringArray(["ID_DENMARK", "Castle15"]))


func test_argomento_tra_virgolette_con_spazi(t: TestContext) -> void:
	var args := ScriptTokenizer.split_args("ID_AFRICA\t\"Mesopotamia Castle_xzy\"\tINLAND")
	t.assert_eq(args, PackedStringArray(["ID_AFRICA", "Mesopotamia Castle_xzy", "INLAND"]))


func test_argomento_vuoto_tra_virgolette(t: TestContext) -> void:
	var args := ScriptTokenizer.split_args("A \"\" B")
	t.assert_eq(args, PackedStringArray(["A", "", "B"]))


func test_parse_salta_commenti_e_righe_senza_comando(t: TestContext) -> void:
	var text := "//===\n// SetStartDate:: 900\n\nSetStartDate::\t1000\r\nriga senza comando\nSetPeriod:: EARLY\n"
	var cmds := ScriptTokenizer.parse(text)
	t.assert_eq(cmds.size(), 2)
	t.assert_eq(cmds[0].name, "SetStartDate")
	t.assert_eq(cmds[0].args, PackedStringArray(["1000"]))
	t.assert_eq(cmds[0].line, 4)
	t.assert_eq(cmds[1].name, "SetPeriod")


func test_arg_con_valore_di_ripiego(t: TestContext) -> void:
	var cmd := ScriptTokenizer.Command.new("X", PackedStringArray(["a"]), 1)
	t.assert_eq(cmd.arg(0), "a")
	t.assert_eq(cmd.arg(5, "z"), "z")
