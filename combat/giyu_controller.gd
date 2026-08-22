class_name GiyuController
extends Node3D

signal tutorial_attack_finished(was_avoided: bool, was_guarded: bool)

@onready var actor: Node3D = get_parent()
@onready var combatant: Combatant = $Combatant
@onready var sword: Node3D = actor.get_node("Sword")

var player: ThirdPersonPlayer
var active: bool = false
var preferred_distance: float = 3.0

func _process(delta: float) -> void:
	if not active or not is_instance_valid(player):
		return
	var flat_target := player.global_position
	flat_target.y = actor.global_position.y
	if actor.global_position.distance_squared_to(flat_target) > 0.001:
		actor.look_at(flat_target, Vector3.UP)
	var distance := actor.global_position.distance_to(player.global_position)
	if distance < preferred_distance - 0.5:
		actor.global_position += actor.global_basis.z * 1.4 * delta
	elif distance > preferred_distance + 1.5:
		actor.global_position -= actor.global_basis.z * 0.8 * delta

func configure(target_player: ThirdPersonPlayer) -> void:
	player = target_player
	combatant.set_invulnerable(true)

func set_active(value: bool) -> void:
	active = value
	set_process(value)

func block_player_attack() -> void:
	combatant.set_guarding(true)
	var original_rotation := sword.rotation
	var tween := create_tween()
	tween.tween_property(sword, "rotation", original_rotation + Vector3(0.0, 0.0, 0.45), 0.12)
	tween.tween_property(sword, "rotation", original_rotation, 0.22)
	await tween.finished
	combatant.set_guarding(false)

func perform_telegraphed_attack(target_combatant: Combatant) -> Dictionary:
	var original_rotation := sword.rotation
	var windup := original_rotation + Vector3(-0.7, 0.0, -0.65)
	var tween := create_tween()
	tween.tween_property(sword, "rotation", windup, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	var was_guarded := target_combatant.is_guarding
	var is_in_range := actor.global_position.distance_to(player.global_position) <= 4.6
	var damaged := target_combatant.receive_damage(18.0, true) if is_in_range else false
	var avoided := not damaged
	var strike_tween := create_tween()
	strike_tween.tween_property(sword, "rotation", original_rotation + Vector3(0.65, 0.0, 0.45), 0.12)
	strike_tween.tween_property(sword, "rotation", original_rotation, 0.28)
	await strike_tween.finished
	tutorial_attack_finished.emit(avoided, was_guarded)
	return {"avoided": avoided, "guarded": was_guarded and damaged}

func dodge_sideways() -> void:
	var target_position := actor.global_position + actor.global_basis.x * 2.3
	var tween := create_tween()
	tween.tween_property(actor, "global_position", target_position, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await tween.finished
