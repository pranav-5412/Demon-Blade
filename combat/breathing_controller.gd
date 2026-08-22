class_name BreathingController
extends Node

signal breath_changed(current: float, maximum: float)
signal unlocked

@export var max_breath: float = 100.0
@export var regeneration_per_second: float = 9.0

var current_breath: float = 0.0
var enabled: bool = false

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if enabled and current_breath < max_breath:
		current_breath = minf(max_breath, current_breath + regeneration_per_second * delta)
		breath_changed.emit(current_breath, max_breath)

func set_unlocked(value: bool) -> void:
	enabled = value
	if value:
		current_breath = maxf(current_breath, 35.0)
		unlocked.emit()
		breath_changed.emit(current_breath, max_breath)

func refill(amount: float) -> void:
	current_breath = minf(max_breath, current_breath + amount)
	breath_changed.emit(current_breath, max_breath)

func spend(amount: float) -> bool:
	if not enabled or current_breath < amount:
		return false
	current_breath -= amount
	breath_changed.emit(current_breath, max_breath)
	return true
