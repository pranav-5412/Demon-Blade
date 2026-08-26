extends Node3D

signal sound_hook_requested(hook_name: StringName)

const FINAL_SELECTION_SCENE := "res://scenes/episode_01/final_selection.tscn"
const POST_SELECTION_SCENE := "res://scenes/episode_01/post_selection_trio.tscn"
const DEMON_SCRIPT := preload("res://combat/demon_enemy.gd")
const TOTAL_DAYS := 5
const HEALTH_REGEN_DELAY := 5.0
const HEALTH_REGEN_PER_SECOND := 1.5

const DAY_CONFIG := {
	1: {"kills": 2, "marker": Vector3(0, 1, 0), "objective": "Learn the forest routes and defeat two nearby demons.", "enemies": ["standard", "standard"]},
	2: {"kills": 3, "marker": Vector3(0, 3, -28), "objective": "Cross the rocky pass and clear its ambush.", "enemies": ["standard", "standard", "fast"]},
	3: {"kills": 4, "marker": Vector3(-20, 5, -53), "objective": "Enter the deep forest and survive the fast hunters.", "enemies": ["fast", "fast", "standard", "ranged"]},
	4: {"kills": 5, "marker": Vector3(22, 2, -103), "objective": "Descend through the valley, investigate the abandoned camp, and defeat the elite.", "enemies": ["elite", "ranged", "brute", "fast", "standard"]},
	5: {"kills": 0, "marker": Vector3(0, 4, -158), "objective": "Cross the high ridge, enter the sealed region, and defeat the mountain demon.", "enemies": []},
}

const DAY_SPAWNS := {
	1: [Vector3(-7, 1, 4), Vector3(8, 1, -1)],
	2: [Vector3(-6, 3, -22), Vector3(6, 3, -29), Vector3(0, 3, -35)],
	3: [Vector3(-27, 5, -46), Vector3(-14, 5, -50), Vector3(-24, 5, -59), Vector3(-10, 5, -58)],
	4: [Vector3(-9, 1, -74), Vector3(10, 1, -82), Vector3(17, 2, -96), Vector3(27, 2, -103), Vector3(20, 2, -110)],
}

const DAY_CHECKPOINTS := {
	1: Vector3(0, 1, 22), 2: Vector3(0, 3, -16), 3: Vector3(-20, 5, -42),
	4: Vector3(0, 1, -68), 5: Vector3(0, 4, -146),
}

@onready var player: ThirdPersonPlayer = $Player
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var player_combatant: Combatant = $Player/CombatController/Combatant
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var environment: Environment = $WorldEnvironment.environment
@onready var enemies: Node3D = $Enemies
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var day_label: Label = $HUD/DayLabel
@onready var form_label: Label = $HUD/FormLabel
@onready var wan_label: Label = $HUD/WanLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var title_label: Label = $HUD/TitleLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var boss_panel: Control = $HUD/BossPanel
@onready var boss_bar: ProgressBar = $HUD/BossPanel/BossHealth
@onready var boss_name: Label = $HUD/BossPanel/BossName

var current_day := 1
var kills_this_day := 0
var marker_reached := false
var day_transitioning := false
var recovery_used_today := false
var active_enemies: Array[Node3D] = []
var boss: Node3D
var lock_refresh := 0.0
var active_marker: MeshInstance3D
var boss_started := false
var rescue_in_progress := false
var seconds_since_damage := HEALTH_REGEN_DELAY

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_build_region()
	_configure_player()
	_connect_player()
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = maxi(data.chapter, 7)
	data.current_scene = FINAL_SELECTION_SCENE
	data.story_flags["final_selection_started"] = true
	current_day = clampi(int(data.story_flags.get("final_selection_day", 1)), 1, TOTAL_DAYS)
	if bool(data.story_flags.get("final_selection_completed", false)):
		_show_completed_state()
		return
	_start_day(current_day, true)
	if not bool(data.story_flags.get("final_selection_intro_seen", false)):
		call_deferred("_play_intro")

func _process(delta: float) -> void:
	_update_health_regeneration(delta)
	status_label.text = "TANJIRO\nHealth: %d\nStamina: %d\nBreath: %d / %d" % [roundi(player.health), roundi(player.stamina), roundi(breathing.current_breath), roundi(breathing.max_breath)]
	wan_label.text = "WAN  %d" % GameManager.save_data.wan_currency
	if player.global_position.y < -2.0 and not rescue_in_progress:
		_rescue_from_void()
		return
	if day_transitioning or bool(GameManager.save_data.story_flags.get("final_selection_completed", false)):
		return
	lock_refresh -= delta
	if lock_refresh <= 0.0:
		lock_refresh = 0.45
		_refresh_lock_target()
	if not marker_reached and player.global_position.distance_to(DAY_CONFIG[current_day].marker) <= 5.0:
		marker_reached = true
		_show_feedback("Area reached. Secure the remaining threats.")
		_update_objective()
	if current_day < TOTAL_DAYS:
		_check_day_complete()
	elif marker_reached and not boss_started:
		_spawn_boss()
	interaction_label.visible = current_day in [3, 4] and not recovery_used_today and player.global_position.distance_to(_camp_position_for_day()) <= 3.5

func _configure_player() -> void:
	combat.set_combat_enabled(true)
	player_combatant.max_health = player.max_health
	player_combatant.current_health = maxf(1.0, clampf(player.health, 0.0, player.max_health))
	breathing.set_unlocked(true)
	breathing.refill(breathing.max_breath)
	water.set_enabled(true)
	for form_number in range(1, 8):
		water.set_form_unlocked(form_number, true)
		GameManager.save_data.story_flags["water_form_%d_unlocked" % form_number] = true

func _connect_player() -> void:
	player_combatant.health_changed.connect(_on_player_health_changed)
	player_combatant.defeated.connect(_on_player_defeated)
	player.interact_pressed.connect(_on_player_interact)
	water.form_activated.connect(_on_form_activated)
	water.hook_requested.connect(_on_water_hook)

func _play_intro() -> void:
	day_transitioning = true
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	title_label.text = "FINAL SELECTION\nSurvive for 5 days."
	title_label.visible = true
	await get_tree().create_timer(2.6).timeout
	title_label.visible = false
	GameManager.save_data.story_flags["final_selection_intro_seen"] = true
	SaveManager.save_checkpoint()
	combat.set_combat_enabled(true)
	player.set_controls_enabled(true)
	day_transitioning = false

func _start_day(day: int, restoring: bool = false) -> void:
	current_day = day
	kills_this_day = 0
	marker_reached = false
	recovery_used_today = false
	boss_started = false
	_clear_enemies()
	_apply_day_atmosphere(day)
	day_label.text = "DAY %d / %d" % [day, TOTAL_DAYS]
	_create_objective_marker(DAY_CONFIG[day].marker)
	if restoring:
		player.global_position = _saved_or_checkpoint_position(day)
	else:
		player.global_position = DAY_CHECKPOINTS[day]
	player.velocity = Vector3.ZERO
	if day < TOTAL_DAYS:
		_spawn_day_enemies(day)
	else:
		_show_feedback("The boss region has opened. Follow the crimson path.")
	_update_objective()
	_checkpoint_day()

func _spawn_day_enemies(day: int) -> void:
	var kinds: Array = DAY_CONFIG[day].enemies
	var positions: Array = DAY_SPAWNS[day]
	for index in mini(kinds.size(), 6):
		_spawn_enemy(str(kinds[index]), positions[index])

func _spawn_enemy(kind: String, position: Vector3) -> Node3D:
	var enemy := DEMON_SCRIPT.new() as Node3D
	enemy.name = "%sDemon_%d" % [kind.capitalize(), active_enemies.size()]
	enemies.add_child(enemy)
	enemy.global_position = position
	enemy.configure(kind, player, player_combatant)
	enemy.died.connect(_on_enemy_died)
	enemy.attack_telegraphed.connect(_on_enemy_telegraphed)
	enemy.attack_landed.connect(_on_enemy_attack_landed)
	active_enemies.append(enemy)
	return enemy

func _spawn_boss() -> void:
	boss_started = true
	if is_instance_valid(active_marker):
		active_marker.visible = false
	boss = _spawn_enemy("boss", Vector3(0, 4, -168))
	boss.name = "HollowPeakDemon"
	boss.health_updated.connect(_on_boss_health)
	boss.phase_changed.connect(_on_boss_phase_changed)
	boss_panel.visible = true
	boss_name.text = "HOLLOW PEAK DEMON — PHASE 1"
	boss_bar.max_value = boss.combatant.max_health
	boss_bar.value = boss.combatant.current_health
	objective_label.text = "OBJECTIVE\nDefeat the Hollow Peak Demon."
	GameManager.save_data.story_flags["final_selection_boss_started"] = true
	GameManager.save_data.player_position = DAY_CHECKPOINTS[TOTAL_DAYS]
	SaveManager.save_checkpoint()
	_show_feedback("Its slam, sweep, charge, and shockwave all have red telegraphs.")

func _on_enemy_died(enemy: Node3D, reward: int, kind: String) -> void:
	active_enemies.erase(enemy)
	GameManager.save_data.wan_currency += reward
	SaveManager.save_checkpoint()
	if kind == "boss":
		_complete_final_selection()
		return
	kills_this_day += 1
	_update_objective()
	_check_day_complete()

func _on_enemy_telegraphed(_enemy: Node3D, attack_name: StringName) -> void:
	sound_hook_requested.emit(&"demon_attack_telegraph")
	_show_feedback("Red telegraph: %s — guard with Q or dodge with Ctrl." % str(attack_name).replace("_", " ").capitalize())

func _on_enemy_attack_landed(_enemy: Node3D) -> void:
	sound_hook_requested.emit(&"demon_attack_hit")

func _check_day_complete() -> void:
	if day_transitioning or current_day >= TOTAL_DAYS:
		return
	var required := int(DAY_CONFIG[current_day].kills)
	if marker_reached and kills_this_day >= required:
		_advance_day()

func _advance_day() -> void:
	day_transitioning = true
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	GameManager.save_data.story_flags["final_selection_day_%d_completed" % current_day] = true
	GameManager.save_data.story_flags["final_selection_day"] = current_day + 1
	GameManager.save_data.player_position = DAY_CHECKPOINTS[current_day + 1]
	SaveManager.save_checkpoint()
	title_label.text = "DAWN\nDAY %d SURVIVED" % current_day
	title_label.visible = true
	await get_tree().create_timer(1.8).timeout
	title_label.visible = false
	current_day += 1
	_start_day(current_day, false)
	combat.set_combat_enabled(true)
	player.set_controls_enabled(true)
	day_transitioning = false

func _on_player_defeated() -> void:
	if day_transitioning:
		return
	day_transitioning = true
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	title_label.text = "THE NIGHT CLAIMED YOU\nReturning to Day %d checkpoint" % current_day
	title_label.visible = true
	await get_tree().create_timer(1.5).timeout
	player_combatant.restore_full_health()
	player.health = player.max_health
	player.stamina = player.max_stamina
	breathing.refill(breathing.max_breath)
	GameManager.save_data.player_health = player.max_health
	GameManager.save_data.player_stamina = player.max_stamina
	title_label.visible = false
	_start_day(current_day, false)
	combat.set_combat_enabled(true)
	player.set_controls_enabled(true)
	day_transitioning = false

func _on_player_interact() -> void:
	if interaction_label.visible and not recovery_used_today:
		recovery_used_today = true
		player_combatant.restore_full_health()
		player.health = player.max_health
		breathing.refill(breathing.max_breath)
		player.stamina = player.max_stamina
		_show_feedback("Medicinal herbs used. This recovery point is now empty.")

func _complete_final_selection() -> void:
	day_transitioning = true
	boss_panel.visible = false
	combat.set_combat_enabled(false)
	player.set_controls_enabled(false)
	GameManager.save_data.story_flags["final_selection_boss_defeated"] = true
	GameManager.save_data.story_flags["final_selection_completed"] = true
	GameManager.save_data.story_flags["final_selection_day"] = TOTAL_DAYS
	GameManager.save_data.story_flags["final_selection_objective"] = "Choose your sword material."
	GameManager.save_data.chapter = 8
	SaveManager.save_checkpoint()
	sound_hook_requested.emit(&"boss_defeat")
	title_label.text = "FINAL SELECTION COMPLETE"
	title_label.visible = true
	objective_label.text = "OBJECTIVE\nChoose your sword material."
	await get_tree().create_timer(2.4).timeout
	title_label.visible = false
	_continue_to_post_selection()

func _show_completed_state() -> void:
	current_day = TOTAL_DAYS
	day_label.text = "DAY %d / %d" % [TOTAL_DAYS, TOTAL_DAYS]
	objective_label.text = "OBJECTIVE\nChoose your sword material."
	feedback_label.text = "FINAL SELECTION COMPLETE\nSword material selection has not begun."
	feedback_label.visible = true
	boss_panel.visible = false
	player.global_position = DAY_CHECKPOINTS[TOTAL_DAYS]
	combat.set_combat_enabled(false)
	call_deferred("_continue_to_post_selection")

func _continue_to_post_selection() -> void:
	if SceneManager.is_transitioning:
		return
	GameManager.save_data.current_scene = POST_SELECTION_SCENE
	GameManager.save_data.player_position = Vector3(0, 1.0, 10)
	SaveManager.save_checkpoint()
	SceneManager.transition_to(POST_SELECTION_SCENE)

func _update_objective() -> void:
	var config: Dictionary = DAY_CONFIG[current_day]
	var progress := ""
	if current_day < TOTAL_DAYS:
		progress = "\nDemons defeated: %d / %d • Destination: %s" % [mini(kills_this_day, int(config.kills)), int(config.kills), "reached" if marker_reached else "follow the blue beacon"]
	else:
		progress = "\nBoss region: %s" % ("entered" if marker_reached else "follow the crimson beacon")
	objective_label.text = "OBJECTIVE\n%s%s" % [config.objective, progress]
	GameManager.save_data.story_flags["final_selection_objective"] = config.objective

func _create_objective_marker(position: Vector3) -> void:
	if is_instance_valid(active_marker):
		active_marker.queue_free()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.5
	mesh.height = 5.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.08, 0.04) if current_day == TOTAL_DAYS else Color(0.05, 0.68, 1.0)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	active_marker = MeshInstance3D.new()
	active_marker.name = "DayObjectiveBeacon"
	active_marker.mesh = mesh
	add_child(active_marker)
	active_marker.global_position = position + Vector3(0, 4.0, 0)

func _refresh_lock_target() -> void:
	var nearest: Node3D
	var nearest_distance := INF
	for enemy in active_enemies:
		if not is_instance_valid(enemy) or int(enemy.get("state")) == 5:
			continue
		var distance := player.global_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	combat.set_lock_target(nearest)

func _on_boss_health(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

func _on_boss_phase_changed(phase_number: int) -> void:
	boss_name.text = "HOLLOW PEAK DEMON — PHASE %d" % phase_number
	sound_hook_requested.emit(&"boss_phase_transition")
	_show_feedback("Phase 2: faster recovery, shockwaves, and a three-hit combo.")

func _on_player_health_changed(current: float, _maximum: float) -> void:
	if current < player.health:
		seconds_since_damage = 0.0
	player.health = current

func _update_health_regeneration(delta: float) -> void:
	if player_combatant.current_health <= 0.0 or player_combatant.current_health >= player_combatant.max_health:
		return
	seconds_since_damage += delta
	if seconds_since_damage >= HEALTH_REGEN_DELAY:
		player_combatant.heal(HEALTH_REGEN_PER_SECOND * delta)

func _on_form_activated(form_number: int, ability_name: String) -> void:
	form_label.text = "ACTIVE FORM: %d — %s\n1–7 Water Forms • Ctrl Dodge • Q Guard" % [form_number, ability_name]

func _on_water_hook(_hook_type: StringName, _hook_name: StringName) -> void:
	sound_hook_requested.emit(&"water_form_impact")

func _show_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true

func _checkpoint_day() -> void:
	var data := GameManager.save_data
	data.current_scene = FINAL_SELECTION_SCENE
	data.story_flags["final_selection_started"] = true
	data.story_flags["final_selection_day"] = current_day
	data.story_flags["final_selection_checkpoint"] = "day_%d_start" % current_day
	data.player_position = player.global_position
	data.player_health = player.health
	data.player_stamina = player.stamina
	SaveManager.save_checkpoint()

func _saved_or_checkpoint_position(day: int) -> Vector3:
	var data := GameManager.save_data
	var saved_position_is_safe := data.player_position.y > -1.0 and data.player_position.y < 20.0 and data.player_position.distance_to(DAY_CHECKPOINTS[day]) <= 45.0
	if data.current_scene == FINAL_SELECTION_SCENE and int(data.story_flags.get("final_selection_day", 1)) == day and saved_position_is_safe:
		return data.player_position
	return DAY_CHECKPOINTS[day]

func _rescue_from_void() -> void:
	rescue_in_progress = true
	player.global_position = DAY_CHECKPOINTS[current_day]
	player.velocity = Vector3.ZERO
	GameManager.save_data.player_position = player.global_position
	SaveManager.save_checkpoint()
	_show_feedback("Unsafe position corrected — returned to the Day %d checkpoint." % current_day)
	await get_tree().physics_frame
	rescue_in_progress = false

func _clear_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
	boss = null
	boss_panel.visible = false

func _camp_position_for_day() -> Vector3:
	return {3: Vector3(-18, 5, -56), 4: Vector3(22, 2, -102)}.get(current_day, Vector3(999, 999, 999))

func _apply_day_atmosphere(day: int) -> void:
	var darkness := clampf(0.12 + day * 0.045, 0.15, 0.46)
	environment.background_color = Color(0.04 + darkness * 0.18, 0.07 + darkness * 0.18, 0.12 + darkness * 0.2)
	environment.ambient_light_energy = maxf(0.28, 0.72 - day * 0.055)
	environment.fog_density = 0.008 + day * 0.002
	sound_hook_requested.emit(&"night_ambience")

func _build_region() -> void:
	_add_ground("SafetyFoundation", Vector3(110, 1, 230), Vector3(0, -4.5, -75), Color(0.035, 0.055, 0.05))
	_add_ground("EntryForest", Vector3(42, 1, 42), Vector3(0, -0.5, 10), Color(0.12, 0.25, 0.13))
	_add_ground("EntryToPass", Vector3(16, 1, 20), Vector3(0, 0.7, -12), Color(0.2, 0.18, 0.12), Vector3(-7, 0, 0))
	_add_ground("RockyPass", Vector3(30, 1, 28), Vector3(0, 1.5, -28), Color(0.26, 0.25, 0.22))
	_add_ground("PassToDeep", Vector3(18, 1, 25), Vector3(-10, 2.8, -43), Color(0.18, 0.2, 0.14), Vector3(-5, 0, -20))
	_add_ground("DeepForest", Vector3(38, 1, 34), Vector3(-20, 3.5, -55), Color(0.08, 0.18, 0.1))
	_add_ground("ForestDescent", Vector3(18, 1, 28), Vector3(-10, 1.8, -68), Color(0.14, 0.19, 0.13), Vector3(10, 0, 18))
	_add_ground("RiverValley", Vector3(44, 1, 32), Vector3(0, -0.5, -82), Color(0.12, 0.22, 0.18))
	_add_ground("ValleyToRuins", Vector3(18, 1, 28), Vector3(11, 0.1, -94), Color(0.2, 0.19, 0.14), Vector3(-4, 0, -22))
	_add_ground("RuinedCamp", Vector3(34, 1, 30), Vector3(22, 0.5, -104), Color(0.21, 0.2, 0.15))
	_add_ground("RidgeAscent", Vector3(18, 1, 34), Vector3(10, 3.0, -118), Color(0.24, 0.23, 0.2), Vector3(-13, 0, 20))
	_add_ground("HighRidge", Vector3(34, 1, 30), Vector3(0, 5.5, -132), Color(0.25, 0.26, 0.24))
	_add_ground("BossApproach", Vector3(18, 1, 28), Vector3(0, 4.3, -146), Color(0.19, 0.14, 0.12), Vector3(6, 0, 0))
	_add_ground("BossRegion", Vector3(50, 1, 40), Vector3(0, 2.5, -165), Color(0.22, 0.16, 0.13))
	for position in [Vector3(-15, 0, 20), Vector3(14, 0, 16), Vector3(-12, 0, 4), Vector3(15, 0, -2), Vector3(-29, 4, -48), Vector3(-12, 4, -48), Vector3(-30, 4, -62), Vector3(-11, 4, -64), Vector3(-15, 0, -78), Vector3(16, 0, -86), Vector3(13, 1, -99), Vector3(31, 1, -110)]:
		_add_tree(position)
	for position in [Vector3(-9, 2, -24), Vector3(9, 2, -31), Vector3(-6, 0, -75), Vector3(8, 0, -88), Vector3(14, 6, -128), Vector3(-13, 6, -135), Vector3(-18, 3, -160), Vector3(18, 3, -170)]:
		_add_rock(position)
	_add_camp(Vector3(22, 1, -102))
	_add_camp(Vector3(-18, 4, -56))
	_add_camp(Vector3(0, 6, -126))
	for side in [-1.0, 1.0]:
		_add_ground("BossBoundary%d" % int(side), Vector3(5, 7, 42), Vector3(25 * side, 3.5, -165), Color(0.11, 0.1, 0.1))

func _add_ground(label: String, size: Vector3, position: Vector3, color: Color, rotation := Vector3.ZERO) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation_degrees = rotation
	$EnvironmentGeometry.add_child(visual)
	var body := StaticBody3D.new()
	body.position = position
	body.rotation_degrees = rotation
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	$EnvironmentGeometry.add_child(body)

func _add_tree(position: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = position
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 4.0
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.12, 0.07, 0.035)
	trunk_mesh.material = trunk_material
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.position.y = 2.0
	tree.add_child(trunk)
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.5
	crown_mesh.height = 4.5
	var crown_material := StandardMaterial3D.new()
	crown_material.albedo_color = Color(0.035, 0.13, 0.07)
	crown_mesh.material = crown_material
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.position.y = 5.0
	tree.add_child(crown)
	$EnvironmentGeometry.add_child(tree)

func _add_rock(position: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 1.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.24, 0.24)
	mesh.material = material
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.position = position + Vector3(0, 0.7, 0)
	rock.scale = Vector3(1.7, 1.1, 1.4)
	$EnvironmentGeometry.add_child(rock)

func _add_camp(position: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.8, 0.28)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.45, 0.1)
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.material = material
	var herb := MeshInstance3D.new()
	herb.mesh = mesh
	herb.position = position + Vector3(0, 0.6, 0)
	$EnvironmentGeometry.add_child(herb)
