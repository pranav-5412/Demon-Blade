class_name PartyCharacterController
extends Node

signal character_changed(character_id: String, display_name: String)
signal unique_ability_used(character_id: String, ability_name: String)
signal unique_ability_finished(character_id: String, ability_name: String)
signal switch_rejected(message: String)
signal hook_requested(hook_type: StringName, hook_name: StringName)

const CHARACTER_ORDER := ["tanjiro", "zenitsu", "inosuke"]
const PROFILES := {
	"tanjiro": {
		"name": "TANJIRO", "max_health": 200.0, "walk_speed": 4.5, "sprint_speed": 7.5,
		"color": Color(0.04, 0.34, 0.27), "head_color": Color(0.62, 0.24, 0.18),
		"light_damage": 12.0, "heavy_damage": 24.0, "light_cost": 8.0, "heavy_cost": 18.0,
		"light_time": 0.42, "heavy_time": 0.78, "light_hits": 1, "heavy_hits": 1, "dodge_speed": 6.3,
	},
	"zenitsu": {
		"name": "ZENITSU", "max_health": 200.0, "walk_speed": 5.4, "sprint_speed": 9.2,
		"color": Color(0.92, 0.58, 0.08), "head_color": Color(0.98, 0.72, 0.3),
		"light_damage": 11.0, "heavy_damage": 28.0, "light_cost": 6.0, "heavy_cost": 20.0,
		"light_time": 0.28, "heavy_time": 0.62, "light_hits": 1, "heavy_hits": 1, "dodge_speed": 8.1,
	},
	"inosuke": {
		"name": "INOSUKE", "max_health": 200.0, "walk_speed": 5.0, "sprint_speed": 8.0,
		"color": Color(0.18, 0.48, 0.56), "head_color": Color(0.32, 0.36, 0.4),
		"light_damage": 20.0, "heavy_damage": 36.0, "light_cost": 9.0, "heavy_cost": 22.0,
		"light_time": 0.46, "heavy_time": 0.72, "light_hits": 2, "heavy_hits": 2, "dodge_speed": 7.2,
	},
}
const ABILITY_DATA := {
	"zenitsu": {"name": "Lightning Step", "cost": 30.0, "cooldown": 4.5, "damage": 48.0},
	"inosuke": {"name": "Beast Rush", "cost": 28.0, "cooldown": 5.0, "damage": 52.0},
}

@onready var player: ThirdPersonPlayer = get_parent()
@onready var combat: PlayerCombatController = player.get_node("CombatController")
@onready var combatant: Combatant = player.get_node("CombatController/Combatant")
@onready var hitbox: CombatHitbox = player.get_node("CombatController/Hitbox")
@onready var breathing: BreathingController = player.get_node("BreathingController")
@onready var water: WaterBreathingController = player.get_node("WaterBreathingController")
@onready var visual: Node3D = player.get_node("Visual")

var current_character := "tanjiro"
var switching_unlocked := false
var switching_allowed := false
var ability_busy := false
var cooldown_ends: Dictionary = {}

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	_store_active_vitals()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var requested := ""
		match event.physical_keycode:
			KEY_F1: requested = "tanjiro"
			KEY_F2: requested = "zenitsu"
			KEY_F3: requested = "inosuke"
		if not requested.is_empty():
			switch_to(requested)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("switch_character"):
		cycle_character()
		get_viewport().set_input_as_handled()
		return
	if current_character != "tanjiro" and event.is_action_pressed("ability_1"):
		activate_unique_ability()
		get_viewport().set_input_as_handled()

func initialize_from_save() -> void:
	var data := GameManager.save_data
	switching_unlocked = bool(data.story_flags.get("character_switching_unlocked", false))
	var restored := data.current_playable_character.to_lower()
	if restored.is_empty() or not PROFILES.has(restored) or not is_character_unlocked(restored):
		restored = "tanjiro"
	apply_character(restored, false, false)

func set_switching_allowed(value: bool) -> void:
	switching_allowed = value

func unlock_character(character_id: String) -> void:
	if character_id == "tanjiro":
		return
	GameManager.save_data.story_flags["%s_unlocked" % character_id] = true

func is_character_unlocked(character_id: String) -> bool:
	return character_id == "tanjiro" or bool(GameManager.save_data.story_flags.get("%s_unlocked" % character_id, false))

func switch_to(character_id: String) -> bool:
	character_id = character_id.to_lower()
	if character_id == current_character:
		return true
	if not switching_unlocked or not switching_allowed:
		switch_rejected.emit("Character switching is unavailable during this moment.")
		return false
	if not is_character_unlocked(character_id):
		switch_rejected.emit("That character has not joined the party yet.")
		return false
	if ability_busy or combat.is_busy or combatant.current_health <= 0.0:
		switch_rejected.emit("Finish the current action before switching.")
		return false
	apply_character(character_id, true)
	return true

func cycle_character() -> bool:
	var start := CHARACTER_ORDER.find(current_character)
	for offset in range(1, CHARACTER_ORDER.size() + 1):
		var candidate: String = CHARACTER_ORDER[(start + offset) % CHARACTER_ORDER.size()]
		if is_character_unlocked(candidate):
			return switch_to(candidate)
	return false

func apply_character(character_id: String, save_after: bool = true, store_previous: bool = true) -> void:
	if not PROFILES.has(character_id):
		character_id = "tanjiro"
	if store_previous:
		_store_active_vitals()
	current_character = character_id
	var profile: Dictionary = (PROFILES[character_id] as Dictionary).duplicate(true)
	if character_id == "tanjiro":
		_apply_sword_material_stats(profile)
	player.walk_speed = float(profile.walk_speed)
	player.sprint_speed = float(profile.sprint_speed)
	player.max_health = float(profile.max_health)
	combatant.max_health = player.max_health
	var saved_stats: Dictionary = GameManager.save_data.story_flags.get("character_stats", {})
	var character_stats: Dictionary = saved_stats.get(character_id, {})
	player.health = clampf(float(character_stats.get("health", player.max_health)), 1.0, player.max_health)
	player.stamina = clampf(float(character_stats.get("stamina", player.max_stamina)), 0.0, player.max_stamina)
	combatant.current_health = player.health
	combat.configure_profile(profile, _material_damage_multiplier() if character_id == "tanjiro" else 1.0)
	breathing.regeneration_per_second = 11.5 if character_id == "tanjiro" and GameManager.save_data.sword_material == "focused_steel" else 9.0
	breathing.set_unlocked(character_id == "tanjiro")
	water.set_enabled(character_id == "tanjiro")
	_apply_visual_profile(profile)
	GameManager.save_data.current_playable_character = character_id
	_store_active_vitals()
	character_changed.emit(character_id, str(profile.name))
	if save_after:
		SaveManager.save_checkpoint()

func get_display_name() -> String:
	return str(PROFILES[current_character].name)

func get_ability_name() -> String:
	if current_character == "tanjiro":
		return "Water Breathing Forms 1–7"
	return str(ABILITY_DATA[current_character].name)

func get_cooldown_remaining(character_id: String = "") -> float:
	var id := current_character if character_id.is_empty() else character_id
	return maxf(0.0, float(cooldown_ends.get(id, 0.0)) - Time.get_ticks_msec() / 1000.0)

func activate_unique_ability() -> bool:
	if current_character == "tanjiro" or not ABILITY_DATA.has(current_character):
		return false
	if ability_busy or not combat.enabled or get_cooldown_remaining() > 0.0:
		return false
	var ability: Dictionary = ABILITY_DATA[current_character]
	if player.stamina < float(ability.cost):
		return false
	ability_busy = true
	player.stamina -= float(ability.cost)
	cooldown_ends[current_character] = Time.get_ticks_msec() / 1000.0 + float(ability.cooldown)
	var ability_character := current_character
	var ability_name := str(ability.name)
	unique_ability_used.emit(ability_character, ability_name)
	hook_requested.emit(&"sfx", &"lightning_burst" if current_character == "zenitsu" else &"beast_rush")
	hook_requested.emit(&"camera", &"precision_impact" if current_character == "zenitsu" else &"rapid_stagger")
	combat.set_combat_enabled(false)
	player.set_controls_enabled(false)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if current_character == "zenitsu":
		await _lightning_step(float(ability.damage))
	else:
		await _beast_rush(float(ability.damage))
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	ability_busy = false
	unique_ability_finished.emit(ability_character, ability_name)
	return true

func _lightning_step(damage: float) -> void:
	_spawn_motion_trail(Color(1.0, 0.82, 0.12, 0.72), 4)
	var original_scale := visual.scale
	visual.scale = original_scale * Vector3(0.78, 0.92, 1.35)
	await get_tree().create_timer(0.16).timeout
	hitbox.scale = Vector3.ONE * 1.3
	hitbox.activate(damage, 0.5, true)
	var swept_targets: Array[CombatHurtbox] = []
	for step in 6:
		player.move_and_collide(-player.global_basis.z * 1.08)
		await get_tree().physics_frame
		_damage_hurtboxes_near_player(damage, 1.55, swept_targets)
	_camera_kick(-0.065)
	await get_tree().create_timer(0.36).timeout
	visual.scale = original_scale
	hitbox.scale = Vector3.ONE

func _beast_rush(damage: float) -> void:
	var original_rotation := visual.rotation
	_spawn_motion_trail(Color(0.25, 0.86, 0.76, 0.62), 3)
	for strike in 4:
		player.move_and_collide(-player.global_basis.z * 1.05)
		visual.rotation.z = -0.52 if strike % 2 == 0 else 0.52
		hitbox.activate(damage / 4.0, 0.15, true)
		await get_tree().create_timer(0.18).timeout
	visual.rotation = original_rotation
	_camera_kick(0.055)
	await get_tree().create_timer(0.24).timeout

func _store_active_vitals() -> void:
	if GameManager.save_data == null or current_character.is_empty():
		return
	var stats: Dictionary = GameManager.save_data.story_flags.get("character_stats", {})
	stats[current_character] = {"health": player.health, "stamina": player.stamina}
	GameManager.save_data.story_flags["character_stats"] = stats

func _damage_hurtboxes_near_player(damage: float, radius: float, already_hit: Array[CombatHurtbox]) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0.0, 0.55, 0.0))
	query.collision_mask = 4
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var hurtbox := result.get("collider") as CombatHurtbox
		if not is_instance_valid(hurtbox) or hurtbox in already_hit or hurtbox.combatant == combatant:
			continue
		hitbox.damage = damage
		hitbox.can_stagger = true
		if hurtbox.receive_hit(hitbox):
			already_hit.append(hurtbox)
			hitbox.hit_landed.emit(hurtbox)

func _material_damage_multiplier() -> float:
	return 1.03 if GameManager.save_data.sword_material == "balanced_ore" else 1.0

func _apply_sword_material_stats(profile: Dictionary) -> void:
	match GameManager.save_data.sword_material:
		"swift_alloy":
			profile.light_time = float(profile.light_time) * 0.84
			profile.heavy_time = float(profile.heavy_time) * 0.9
			profile.heavy_damage = float(profile.heavy_damage) * 0.9
		"dense_iron":
			profile.heavy_damage = float(profile.heavy_damage) * 1.18
			profile.heavy_time = float(profile.heavy_time) * 1.16
		"focused_steel":
			profile.light_damage = float(profile.light_damage) * 1.04

func _apply_visual_profile(profile: Dictionary) -> void:
	_set_mesh_color(visual.get_node_or_null("Body") as MeshInstance3D, profile.color)
	_set_mesh_color(visual.get_node_or_null("Head") as MeshInstance3D, profile.head_color)
	var sword := visual.get_node_or_null("Sword") as MeshInstance3D
	var offhand := visual.get_node_or_null("OffhandSword") as MeshInstance3D
	if is_instance_valid(sword):
		sword.visible = true
		sword.scale = Vector3(0.82, 0.9, 0.82) if current_character == "zenitsu" else Vector3.ONE
		_set_mesh_color(sword, _weapon_color())
	if is_instance_valid(offhand):
		offhand.visible = current_character == "inosuke"
		_set_mesh_color(offhand, Color(0.68, 0.72, 0.74))

func _weapon_color() -> Color:
	if current_character == "zenitsu":
		return Color(1.0, 0.78, 0.16)
	if current_character == "inosuke":
		return Color(0.68, 0.72, 0.74)
	match GameManager.save_data.sword_material:
		"swift_alloy": return Color(0.55, 0.86, 0.95)
		"dense_iron": return Color(0.28, 0.31, 0.36)
		"focused_steel": return Color(0.28, 0.72, 0.92)
		_: return Color(0.72, 0.76, 0.82)

func _set_mesh_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	mesh_instance.material_override = material

func _spawn_motion_trail(color: Color, count: int) -> void:
	for index in count:
		var ghost := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.34
		mesh.height = 1.25
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = material
		ghost.mesh = mesh
		get_tree().current_scene.add_child(ghost)
		ghost.global_position = player.global_position + player.global_basis.z * float(index) * 0.65 + Vector3(0, 0.15, 0)
		var fade := ghost.create_tween()
		fade.parallel().tween_property(material, "albedo_color:a", 0.0, 0.38)
		fade.parallel().tween_property(ghost, "scale", Vector3(0.7, 1.0, 0.7), 0.38)
		fade.tween_callback(ghost.queue_free)

func _camera_kick(amount: float) -> void:
	var pivot := player.get_node("CameraPivot") as Node3D
	var original := pivot.rotation.z
	var kick := pivot.create_tween()
	kick.tween_property(pivot, "rotation:z", original + amount, 0.06)
	kick.tween_property(pivot, "rotation:z", original, 0.14)
