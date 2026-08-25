class_name PlayerCombatController
extends Node3D

signal attack_performed(attack_type: String)
signal dodge_performed
signal guard_changed(is_guarding: bool)
signal lock_on_changed(is_locked: bool)

const LIGHT_STAMINA_COST := 8.0
const HEAVY_STAMINA_COST := 18.0
const DODGE_STAMINA_COST := 16.0

@onready var player: ThirdPersonPlayer = get_parent()
@onready var combatant: Combatant = $Combatant
@onready var hitbox: CombatHitbox = $Hitbox
@onready var visual: Node3D = player.get_node("Visual")

var enabled: bool = false
var is_busy: bool = false
var is_locked_on: bool = false
var lock_target: Node3D
var is_dodge_moving: bool = false
var dodge_direction: Vector3
var dodge_speed: float = 0.0

func _ready() -> void:
	hitbox.source_combatant = combatant
	set_process(false)

func _process(_delta: float) -> void:
	if enabled and is_locked_on and is_instance_valid(lock_target):
		var flat_target := lock_target.global_position
		flat_target.y = player.global_position.y
		if player.global_position.distance_squared_to(flat_target) > 0.001:
			player.look_at(flat_target, Vector3.UP)

func _physics_process(delta: float) -> void:
	if is_dodge_moving:
		player.move_and_collide(dodge_direction * dodge_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("lock_on"):
		is_locked_on = not is_locked_on and is_instance_valid(lock_target)
		lock_on_changed.emit(is_locked_on)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("block"):
		_set_guarding(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("block"):
		_set_guarding(false)
		get_viewport().set_input_as_handled()
		return
	if is_busy or combatant.is_guarding:
		return
	if event.is_action_pressed("attack"):
		_perform_attack("light", 12.0, LIGHT_STAMINA_COST, 0.42, 0.16)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("heavy_attack"):
		_perform_attack("heavy", 24.0, HEAVY_STAMINA_COST, 0.78, 0.26)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge"):
		_perform_dodge()
		get_viewport().set_input_as_handled()

func set_combat_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	if not value:
		_set_guarding(false)
		is_locked_on = false

func set_lock_target(target: Node3D) -> void:
	lock_target = target

func _perform_attack(attack_type: String, damage: float, stamina_cost: float, total_time: float, active_time: float) -> void:
	if player.stamina < stamina_cost:
		return
	is_busy = true
	player.stamina -= stamina_cost
	attack_performed.emit(attack_type)
	var original_rotation := visual.rotation
	var windup_rotation := original_rotation + Vector3(0.0, 0.0, -0.28 if attack_type == "light" else -0.58)
	var tween := create_tween()
	tween.tween_property(visual, "rotation", windup_rotation, total_time * 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, "rotation", original_rotation, total_time * 0.65).set_trans(Tween.TRANS_BACK)
	await get_tree().create_timer(total_time * 0.28).timeout
	hitbox.activate(damage, active_time, attack_type == "heavy")
	await get_tree().create_timer(total_time * 0.72).timeout
	is_busy = false

func _perform_dodge() -> void:
	if player.stamina < DODGE_STAMINA_COST:
		return
	is_busy = true
	player.stamina -= DODGE_STAMINA_COST
	combatant.set_invulnerable(true)
	dodge_performed.emit()
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, player.rotation.y).normalized()
	if direction.is_zero_approx():
		direction = player.global_basis.z
	dodge_direction = direction
	dodge_speed = 6.3
	is_dodge_moving = true
	player.set_controls_enabled(false)
	var original_rotation := visual.rotation
	var original_scale := visual.scale
	var dodge_rotation := original_rotation + Vector3(0.62, 0.0, -0.48)
	var dodge_scale := original_scale * Vector3(1.12, 0.82, 1.12)
	var dodge_animation := create_tween()
	dodge_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	dodge_animation.tween_property(visual, "rotation", dodge_rotation, 0.12)
	dodge_animation.parallel().tween_property(visual, "scale", dodge_scale, 0.12)
	dodge_animation.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dodge_animation.tween_property(visual, "rotation", original_rotation, 0.26)
	dodge_animation.parallel().tween_property(visual, "scale", original_scale, 0.26)
	await get_tree().create_timer(0.38).timeout
	is_dodge_moving = false
	await get_tree().create_timer(0.47).timeout
	combatant.set_invulnerable(false)
	player.set_controls_enabled(true)
	await get_tree().create_timer(0.18).timeout
	is_busy = false

func _set_guarding(value: bool) -> void:
	if combatant.is_guarding == value:
		return
	combatant.set_guarding(value)
	guard_changed.emit(value)
