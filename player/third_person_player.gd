class_name ThirdPersonPlayer
extends CharacterBody3D

signal interact_pressed

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var acceleration: float = 18.0
@export var deceleration: float = 22.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.003
@export var camera_distance: float = 4.5
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 35.0

@export var max_health: float = 200.0
@export var health: float = 200.0
@export var health_regeneration_per_second: float = 1.5
@export var health_regeneration_delay: float = 5.0
@export var max_stamina: float = 100.0
@export var stamina: float = 100.0
@export var stamina_drain_per_second: float = 18.0
@export var stamina_recovery_per_second: float = 13.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var visual: Node3D = $Visual
@onready var health_combatant: Combatant = get_node_or_null("CombatController/Combatant") as Combatant

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var controls_enabled: bool = true
var carrying_companion: bool = false
var seconds_since_health_damage := 0.0

func _ready() -> void:
	spring_arm.spring_length = camera_distance
	_restore_saved_position()
	_configure_health_system()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_mouse_capture()
		return
	if not controls_enabled:
		return
	if event.is_action_pressed("interact"):
		if interact_pressed.get_connections().is_empty():
			SaveManager.save_checkpoint()
		else:
			interact_pressed.emit()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

func _physics_process(delta: float) -> void:
	_update_vertical_velocity(delta)
	_update_horizontal_velocity(delta)
	_update_health_regeneration(delta)
	_update_save_data()
	move_and_slide()

func _configure_health_system() -> void:
	if not is_instance_valid(health_combatant):
		return
	health_combatant.max_health = max_health
	health_combatant.current_health = clampf(health, 0.0, max_health)
	if not health_combatant.health_changed.is_connected(_on_health_changed):
		health_combatant.health_changed.connect(_on_health_changed)
	if not health_combatant.damaged.is_connected(_on_health_damaged):
		health_combatant.damaged.connect(_on_health_damaged)

func _update_health_regeneration(delta: float) -> void:
	if not is_instance_valid(health_combatant) or health_combatant.current_health <= 0.0 or health_combatant.current_health >= health_combatant.max_health:
		return
	seconds_since_health_damage += delta
	if seconds_since_health_damage >= health_regeneration_delay:
		health_combatant.heal(health_regeneration_per_second * delta)

func _on_health_damaged(_amount: float, _was_guarded: bool) -> void:
	seconds_since_health_damage = 0.0

func _on_health_changed(current: float, maximum: float) -> void:
	max_health = maximum
	health = current

func _update_vertical_velocity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		try_jump()
	else:
		velocity.y = -0.1

func _update_horizontal_velocity(delta: float) -> void:
	if not controls_enabled:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, rotation.y).normalized()
	var is_sprinting := Input.is_action_pressed("sprint") and input_vector.length_squared() > 0.0 and stamina > 0.0
	var target_speed := sprint_speed if is_sprinting else walk_speed
	if carrying_companion:
		target_speed *= 0.8
	if is_sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_recovery_per_second * delta)
	var target_velocity := move_direction * target_speed
	var rate := acceleration if input_vector.length_squared() > 0.0 else deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, rate * delta)
	if move_direction.length_squared() > 0.0:
		var visual_target_yaw := atan2(-input_vector.x, -input_vector.y)
		visual.rotation.y = lerp_angle(visual.rotation.y, visual_target_yaw, minf(12.0 * delta, 1.0))

func _update_save_data() -> void:
	if GameManager.save_data == null:
		return
	GameManager.save_data.current_scene = get_tree().current_scene.scene_file_path
	GameManager.save_data.player_position = global_position
	GameManager.save_data.player_health = health
	GameManager.save_data.player_stamina = stamina

func _restore_saved_position() -> void:
	if SaveManager.has_save():
		SaveManager.load_save()
	var data := GameManager.save_data
	if data != null and data.current_scene == get_tree().current_scene.scene_file_path and data.player_position.y > 0.0:
		global_position = data.player_position
		health = clampf(data.player_health, 0.0, max_health)
		stamina = clampf(data.player_stamina, 0.0, max_stamina)

func _has_jump_floor() -> bool:
	if is_on_floor():
		return true
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.1, 0.0), global_position + Vector3(0.0, -1.2, 0.0), collision_mask)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var floor_normal: Vector3 = hit["normal"]
	return floor_normal.angle_to(Vector3.UP) <= floor_max_angle

func try_jump() -> bool:
	if not controls_enabled or not _has_jump_floor():
		return false
	velocity.y = jump_velocity
	return true

func _toggle_mouse_capture() -> void:
	var next_mode := Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(next_mode)

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
