class_name Combatant
extends Node

signal health_changed(current_health: float, max_health: float)
signal damaged(amount: float, was_guarded: bool)
signal staggered
signal defeated

@export var max_health: float = 100.0
@export_range(0.0, 1.0) var guard_damage_multiplier: float = 0.2

var current_health: float
var is_guarding: bool = false
var is_invulnerable: bool = false

func _ready() -> void:
	current_health = max_health

func receive_damage(amount: float, can_stagger: bool = true) -> bool:
	if is_invulnerable or current_health <= 0.0:
		return false
	var was_guarded := is_guarding
	var applied_damage := amount * guard_damage_multiplier if was_guarded else amount
	current_health = maxf(0.0, current_health - applied_damage)
	damaged.emit(applied_damage, was_guarded)
	health_changed.emit(current_health, max_health)
	if can_stagger and not was_guarded:
		staggered.emit()
	if current_health <= 0.0:
		defeated.emit()
	return true

func restore_full_health() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

func heal(amount: float) -> float:
	if amount <= 0.0 or current_health <= 0.0 or current_health >= max_health:
		return 0.0
	var previous_health := current_health
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)
	return current_health - previous_health

func set_guarding(guarding: bool) -> void:
	is_guarding = guarding

func set_invulnerable(invulnerable: bool) -> void:
	is_invulnerable = invulnerable
