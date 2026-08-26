class_name PlayerCombatController
extends Node3D

signal attack_performed(attack_type: String)
signal dodge_performed
signal guard_changed(is_guarding: bool)
signal lock_on_changed(is_locked: bool)

const DEFAULT_LIGHT_DAMAGE := 12.0
const DEFAULT_HEAVY_DAMAGE := 24.0

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
var light_damage := DEFAULT_LIGHT_DAMAGE
var heavy_damage := DEFAULT_HEAVY_DAMAGE
var light_stamina_cost := 8.0
var heavy_stamina_cost := 18.0
var dodge_stamina_cost := 16.0
var light_attack_time := 0.42
var heavy_attack_time := 0.78
var light_active_time := 0.16
var heavy_active_time := 0.26
var light_chain_hits := 1
var heavy_chain_hits := 1
var damage_multiplier := 1.0

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
		_perform_attack("light", light_damage * damage_multiplier, light_stamina_cost, light_attack_time, light_active_time, light_chain_hits)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("heavy_attack"):
		_perform_attack("heavy", heavy_damage * damage_multiplier, heavy_stamina_cost, heavy_attack_time, heavy_active_time, heavy_chain_hits)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge") or _is_ctrl_pressed(event):
		_perform_dodge()
		get_viewport().set_input_as_handled()

func _is_ctrl_pressed(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and (event.keycode == KEY_CTRL or event.physical_keycode == KEY_CTRL)

func set_combat_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	if not value:
		_set_guarding(false)
		is_locked_on = false

func set_lock_target(target: Node3D) -> void:
	lock_target = target

func configure_profile(profile: Dictionary, material_damage_multiplier: float = 1.0) -> void:
	light_damage = float(profile.get("light_damage", DEFAULT_LIGHT_DAMAGE))
	heavy_damage = float(profile.get("heavy_damage", DEFAULT_HEAVY_DAMAGE))
	light_stamina_cost = float(profile.get("light_cost", 8.0))
	heavy_stamina_cost = float(profile.get("heavy_cost", 18.0))
	dodge_stamina_cost = float(profile.get("dodge_cost", 16.0))
	light_attack_time = float(profile.get("light_time", 0.42))
	heavy_attack_time = float(profile.get("heavy_time", 0.78))
	light_active_time = float(profile.get("light_active", 0.16))
	heavy_active_time = float(profile.get("heavy_active", 0.26))
	light_chain_hits = maxi(1, int(profile.get("light_hits", 1)))
	heavy_chain_hits = maxi(1, int(profile.get("heavy_hits", 1)))
	dodge_speed = float(profile.get("dodge_speed", 6.3))
	damage_multiplier = material_damage_multiplier

func can_accept_action() -> bool:
	return enabled and not is_busy and not combatant.is_guarding

func perform_attack(attack_type: String) -> void:
	if not can_accept_action():
		return
	if attack_type == "heavy":
		_perform_attack("heavy", heavy_damage * damage_multiplier, heavy_stamina_cost, heavy_attack_time, heavy_active_time, heavy_chain_hits)
	else:
		_perform_attack("light", light_damage * damage_multiplier, light_stamina_cost, light_attack_time, light_active_time, light_chain_hits)

func _perform_attack(attack_type: String, damage: float, stamina_cost: float, total_time: float, active_time: float, chain_hits: int = 1) -> void:
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
	await get_tree().create_timer(total_time * 0.24).timeout
	for strike in chain_hits:
		hitbox.activate(damage / float(chain_hits), active_time, attack_type == "heavy" or chain_hits > 1)
		if chain_hits > 1:
			visual.rotation.z = -0.32 if strike % 2 == 0 else 0.32
			await get_tree().create_timer(total_time * 0.22).timeout
	visual.rotation.z = 0.0
	await get_tree().create_timer(total_time * 0.54).timeout
	is_busy = false

func _perform_dodge() -> void:
	if player.stamina < dodge_stamina_cost:
		return
	is_busy = true
	player.stamina -= dodge_stamina_cost
	combatant.set_invulnerable(true)
	dodge_performed.emit()
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, player.rotation.y).normalized()
	if direction.is_zero_approx():
		direction = player.global_basis.z
	dodge_direction = direction
	if dodge_speed <= 0.0:
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
