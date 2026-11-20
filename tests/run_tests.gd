extends SceneTree
## Esegue tutti i test in res://tests/unit (file test_*.gd, metodi test_*).
##
## Uso (dalla cartella del progetto):
##   godot --headless --import                       (solo la prima volta)
##   godot --headless --script res://tests/run_tests.gd
##   godot --headless --script res://tests/run_tests.gd -- sim_events ui_   (solo i file che contengono uno dei testi)
## Codice d'uscita 0 se tutto passa, 1 se almeno un test fallisce. Per ogni file stampa il tempo impiegato.

const TEST_DIR := "res://tests/unit"


func _initialize() -> void:
	var total := 0
	var failures := 0
	var skips := 0
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	var filters := OS.get_cmdline_user_args()
	for file_name in files:
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		if not filters.is_empty():
			var wanted := false
			for f in filters:
				if file_name.contains(f):
					wanted = true
			if not wanted:
				continue
		var started := Time.get_ticks_msec()
		var test_script := load(TEST_DIR.path_join(file_name)) as GDScript
		if test_script == null or not test_script.can_instantiate():
			# Script con errori di analisi: lo segnalo e passo al successivo invece di bloccarmi.
			total += 1
			failures += 1
			print("FALLITO  %s :: script non caricabile (vedi gli errori sopra)" % file_name)
			continue
		var suite: Object = test_script.new()
		for method in test_script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			var ctx := TestContext.new()
			suite.call(method_name, ctx)
			if ctx.failed:
				failures += 1
				print("FALLITO  %s :: %s" % [file_name, method_name])
				for m in ctx.messages:
					print("         %s" % m)
			elif ctx.skipped:
				skips += 1
				print("saltato  %s :: %s (%s)" % [file_name, method_name, ", ".join(ctx.messages)])
			else:
				print("ok       %s :: %s" % [file_name, method_name])
		print("tempo    %s: %d ms" % [file_name, Time.get_ticks_msec() - started])
	print("")
	print("Test: %d · falliti: %d · saltati: %d" % [total, failures, skips])
	quit(1 if failures > 0 else 0)
