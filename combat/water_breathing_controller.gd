class_name WaterBreathingController
extends Node3D

signal form_activated(form_number: int, ability_name: String)
signal form_hit(form_number: int, target: CombatHurtbox)
signal form_failed(message: String)
signal hook_requested(hook_type: StringName, hook_name: StringName)

@export var forms: Array[WaterFormData] = []
@export var hitbox_path: NodePath
@export var breathing_path: NodePath
@export var combatant_path: NodePath

@onready var player: ThirdPersonPlayer = get_parent()
@onready var hitbox: CombatHitbox = get_node(hitbox_path)
@onready var breathing: BreathingController = get_node(breathing_path)
@onready var combatant: Combatant = get_node(combatant_path)
@onready var visual: Node3D = player.get_node("Visual")

var enabled := false
var busy := false
var unlocked_forms: Dictionary = {}
var cooldown_ends: Dictionary = {}
var active_form_number := 0

func _ready() -> void:
	hitbox.source_combatant = combatant
	hitbox.hit_landed.connect(_on_hit_landed)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or busy:
		return
	for form in forms:
		if event.is_action_pressed(form.input_action):
			activate_form(form.form_number)
			get_viewport().set_input_as_handled()
			return

func set_enabled(value: bool) -> void:
	enabled = value

func set_form_unlocked(form_number: int, value: bool) -> void:
	unlocked_forms[form_number] = value

func is_form_unlocked(form_number: int) -> bool:
	return bool(unlocked_forms.get(form_number, false))

func get_form(form_number: int) -> WaterFormData:
	for form in forms:
		if form.form_number == form_number:
			return form
	return null

func get_cooldown_remaining(form_number: int) -> float:
	return maxf(0.0, float(cooldown_ends.get(form_number, 0.0)) - Time.get_ticks_msec() / 1000.0)

func activate_form(form_number: int) -> bool:
	var form := get_form(form_number)
	if form == null or not is_form_unlocked(form_number):
		form_failed.emit("That Water Form is still locked.")
		return false
	if get_cooldown_remaining(form_number) > 0.0:
		form_failed.emit("%s is cooling down." % form.ability_name)
		return false
	if player.stamina < form.stamina_cost:
		form_failed.emit("Not enough stamina.")
		return false
	if not breathing.spend(form.breath_cost):
		form_failed.emit("Not enough breath.")
		return false
	player.stamina -= form.stamina_cost
	cooldown_ends[form_number] = Time.get_ticks_msec() / 1000.0 + form.cooldown
	active_form_number = form_number
	busy = true
	form_activated.emit(form_number, form.ability_name)
	hook_requested.emit(&"sfx", form.sfx_hook)
	hook_requested.emit(&"animation", form.animation_hook)
	hook_requested.emit(&"camera", form.camera_feedback_hook)
	_play_water_vfx(form)
	match form.gameplay_role:
		"dash": await _dash_slash(form)
		"spin": await _spinning_defense(form)
		"combo": await _flowing_combo(form)
		"arc": await _wave_arc(form)
		"counter": await _calm_counter(form)
		"rapid": await _rapid_flow(form)
		"thrust": await _precision_thrust(form)
	busy = false
	active_form_number = 0
	return true

func _activate_hitbox(form: WaterFormData, duration_override := -1.0) -> void:
	hitbox.scale = Vector3.ONE
	var collision := hitbox.get_node("CollisionShape3D") as CollisionShape3D
	if collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		box.size = Vector3(1.4, 1.5, 1.8) * form.hitbox_scale
	hitbox.activate(form.damage, form.active_time if duration_override < 0.0 else duration_override, true)

func _dash_slash(form: WaterFormData) -> void:
	player.set_controls_enabled(false)
	player.move_and_collide(-player.global_basis.z * form.movement_distance)
	_activate_hitbox(form)
	await get_tree().create_timer(0.42).timeout
	player.set_controls_enabled(true)

func _spinning_defense(form: WaterFormData) -> void:
	var original := visual.rotation
	var tween := create_tween()
	tween.tween_property(visual, "rotation:y", original.y + TAU, 0.55)
	_activate_hitbox(form, 0.48)
	await tween.finished
	visual.rotation = original

func _flowing_combo(form: WaterFormData) -> void:
	for strike in 3:
		player.move_and_collide(-player.global_basis.z * 0.7)
		_activate_hitbox(form)
		await get_tree().create_timer(0.23).timeout

func _wave_arc(form: WaterFormData) -> void:
	var original := visual.scale
	visual.scale = Vector3(1.25, 0.9, 1.25)
	_activate_hitbox(form, 0.34)
	await get_tree().create_timer(0.45).timeout
	visual.scale = original

func _calm_counter(form: WaterFormData) -> void:
	combatant.set_invulnerable(true)
	visual.scale = Vector3(0.92, 1.05, 0.92)
	await get_tree().create_timer(0.75).timeout
	_activate_hitbox(form, 0.28)
	combatant.set_invulnerable(false)
	visual.scale = Vector3.ONE
	await get_tree().create_timer(0.25).timeout

func _rapid_flow(form: WaterFormData) -> void:
	for strike in 5:
		visual.rotation.z = -0.35 if strike % 2 == 0 else 0.35
		_activate_hitbox(form)
		await get_tree().create_timer(0.16).timeout
	visual.rotation.z = 0.0

func _precision_thrust(form: WaterFormData) -> void:
	player.set_controls_enabled(false)
	player.move_and_collide(-player.global_basis.z * form.movement_distance)
	visual.scale = Vector3(0.8, 1.0, 1.35)
	_activate_hitbox(form, 0.18)
	await get_tree().create_timer(0.38).timeout
	visual.scale = Vector3.ONE
	player.set_controls_enabled(true)

func _play_water_vfx(form: WaterFormData) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.55
	mesh.outer_radius = 0.72 + form.form_number * 0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.62, 0.95, 0.78)
	material.emission_enabled = true
	material.emission = Color(0.0, 0.35, 0.85, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	effect.rotation_degrees.x = 90.0 if form.form_number != 2 else 0.0
	add_child(effect)
	hook_requested.emit(&"vfx", form.vfx_hook)
	var tween := create_tween()
	tween.parallel().tween_property(effect, "scale", Vector3.ONE * (1.2 + form.form_number * 0.14), 0.45)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.45)
	tween.tween_callback(effect.queue_free)

func _on_hit_landed(target: CombatHurtbox) -> void:
	if active_form_number > 0:
		form_hit.emit(active_form_number, target)
