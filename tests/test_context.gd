class_name TestContext
extends RefCounted
## Raccoglie l'esito di un singolo test. Ogni metodo `test_*` riceve un TestContext.

var failed := false
var skipped := false
var messages := PackedStringArray()


func assert_true(condition: bool, message: String = "condizione falsa") -> void:
	if not condition:
		_fail(message)


func assert_false(condition: bool, message: String = "condizione vera") -> void:
	if condition:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("%s atteso <%s>, ottenuto <%s>" % [message, str(expected), str(actual)])


## Segna il test come saltato (per esempio se manca l'installazione del gioco).
func skip(reason: String) -> void:
	skipped = true
	messages.append(reason)


func _fail(message: String) -> void:
	failed = true
	messages.append(message)
