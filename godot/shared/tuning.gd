extends Node
## Autoload "Tuning": every gameplay number lives in res://tuning.json.
## Press F5 in game to reload it without restarting.

const PATH := "res://tuning.json"

signal reloaded

var data: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Tuning: cannot open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Tuning: %s is not a valid JSON object, keeping old values" % PATH)
		return
	data = parsed
	reloaded.emit()


func section(name: String) -> Dictionary:
	return data.get(name, {})
