class_name ObjectiveTracker
extends Node

signal objective_changed(text: String, step: int)

var current_step: int = 0
var current_text: String = ""

func set_objective(step: int, text: String) -> void:
	current_step = step
	current_text = text
	objective_changed.emit(current_text, current_step)
