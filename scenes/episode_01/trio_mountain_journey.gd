extends Node3D

signal sound_hook_requested(hook_name: StringName)

const SCENE_PATH := "res://scenes/episode_01/trio_mountain_journey.tscn"
const DRUM_HOUSE_SCENE := "res://scenes/episode_01/drum_house.tscn"
const DEMON_SCRIPT := preload("res://combat/demon_enemy.gd")
const SECTION_NAMES := ["FOREST TRAIL", "STEEP ASCENT", "WIND RIDGE", "FOREST DESCENT", "DANGER ZONE", "STRANGE HOUSE APPROACH"]
const SECTION_OBJECTIVES := [
	"Follow the forest trail with Zenitsu and Inosuke.",
	"Climb the winding rock shelves.",
	"Cross the exposed mountain ridge.",
	"Descend into the dark cedar valley.",
	"Clear the demons blocking the narrow pass.",
	"Approach the strange house through the fog.",
]
const SECTION_DIALOGUE := [
	"ZENITSU: This path is too quiet. Quiet paths always hide something.\nINOSUKE: Good. I was getting bored.",
	"INOSUKE: The mountain is finally putting up a fight!\nTANJIRO: Save some strength for whatever waits ahead.",
	"ZENITSU: The view is beautiful. I still vote for turning back.\nINOSUKE: Denied.",
	"TANJIRO: The forest changed. Stay close.\nZENITSU: I was already planning to.",
	"INOSUKE: Demons ahead. Now this road makes sense!",
	"TANJIRO: That house feels wrong. We investigate together.",
]
const ROUTE_POINTS := [
	Vector3(0, 0, 14), Vector3(-10, 1, 0), Vector3(-18, 2, -16), Vector3(-8, 3, -31), Vector3(8, 4, -44),
	Vector3(20, 7, -57), Vector3(9, 11, -70), Vector3(-8, 15, -82), Vector3(-22, 19, -96),
	Vector3(-8, 22, -111), Vector3(12, 24, -126), Vector3(25, 23, -141), Vector3(10, 21, -156),
	Vector3(-8, 18, -170), Vector3(-23, 14, -185), Vector3(-12, 10, -201), Vector3(6, 7, -217),
	Vector3(22, 6, -232), Vector3(12, 5, -248), Vector3(-8, 5, -262), Vector3(-22, 6, -276),
	Vector3(-10, 7, -292), Vector3(8, 8, -308), Vector3(18, 9, -325), Vector3(4, 10, -344),
]
const SECTION_POINT_INDICES := [4, 8, 12, 16, 20, 24]
const ROUTE_HORIZONTAL_SCALE := 1.65
const ROUTE_DEPTH_SCALE := 2.45
const HOUSE_ENTRY_PROMPT := "E — Enter Strange House"
const HOUSE_ENTRY_HALF_EXTENTS := Vector3(3.5, 3.0, 3.0)

@onready var player: ThirdPersonPlayer = $Player
@onready var party: PartyCharacterController = $Player/PartyCharacterController
@onready var companions: Node3D = $PartyCompanions
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var combatant: Combatant = $Player/CombatController/Combatant
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var ability_label: Label = $HUD/AbilityLabel
@onready var section_label: Label = $HUD/SectionLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var environment: Environment = $WorldEnvironment.environment

var current_section := 0
var route_points: Array[Vector3] = []
var last_checkpoint := Vector3(0, 1.2, 14)
var path_segment_count := 0
var route_length := 0.0
var active_enemies: Array[DemonEnemy] = []
var danger_spawned := false
var strange_house_found := false
var transition_active := false
var feedback_time := 0.0
var house_entry_zone: Area3D
var house_entry_position := Vector3.ZERO

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_prepare_route_points()
	_build_mountain_route()
	_build_house_exterior()
	_configure_party()
	_connect_signals()
	_restore_progress()

func _process(delta: float) -> void:
	_update_hud()
	_refresh_lock_target()
	if feedback_time > 0.0:
		feedback_time -= delta
		if feedback_time <= 0.0:
			feedback_label.visible = false
	if player.global_position.y < -12.0:
		_rescue_player()
	if transition_active:
		return
	if strange_house_found:
		interaction_label.text = HOUSE_ENTRY_PROMPT
		interaction_label.visible = _is_player_at_house_entry()
		return
	interaction_label.visible = false
	_check_section_progress()

func _configure_party() -> void:
	var data := GameManager.save_data
	data.current_scene = SCENE_PATH
	data.story_flags["trio_journey_started"] = true
	data.story_flags["zenitsu_unlocked"] = true
	data.story_flags["inosuke_unlocked"] = true
	data.story_flags["character_switching_unlocked"] = true
	for form_number in range(1, 8):
		water.set_form_unlocked(form_number, bool(data.story_flags.get("water_form_%d_unlocked" % form_number, true)))
	party.initialize_from_save()
	party.switching_unlocked = true
	party.set_switching_allowed(true)
	combat.set_combat_enabled(true)
	combatant.max_health = player.max_health
	combatant.current_health = clampf(player.health, 1.0, player.max_health)

func _connect_signals() -> void:
	player.interact_pressed.connect(_on_interact)
	party.character_changed.connect(_on_character_changed)
	combatant.health_changed.connect(_on_health_changed)

func _restore_progress() -> void:
	var data := GameManager.save_data
	current_section = clampi(int(data.story_flags.get("trio_journey_section", 0)), 0, SECTION_NAMES.size() - 1)
	strange_house_found = bool(data.story_flags.get("strange_house_found", false))
	danger_spawned = bool(data.story_flags.get("trio_danger_cleared", false))
	last_checkpoint = route_points[SECTION_POINT_INDICES[maxi(0, current_section - 1)]] + Vector3(0, 1.2, 0) if current_section > 0 else route_points[0] + Vector3(0, 1.2, 0)
	if strange_house_found:
		last_checkpoint = _get_house_approach_checkpoint()
		player.global_position = last_checkpoint
		data.current_scene = SCENE_PATH
		data.player_position = last_checkpoint
		_show_house_arrival_state()
	else:
		_set_section(current_section, false)
	SaveManager.save_checkpoint()

func _check_section_progress() -> void:
	var target: Vector3 = route_points[SECTION_POINT_INDICES[current_section]] + Vector3(0, 1.0, 0)
	if player.global_position.distance_to(target) > 8.0:
		return
	if current_section == 4:
		if not danger_spawned:
			_spawn_danger_encounter()
			return
		if not active_enemies.is_empty():
			_set_objective("Defeat the demons controlling the narrow pass. (%d remaining)" % active_enemies.size())
			return
	if current_section < SECTION_NAMES.size() - 1:
		current_section += 1
		_set_section(current_section, true)
	else:
		_arrive_at_strange_house()

func _set_section(section: int, show_dialogue: bool) -> void:
	current_section = section
	section_label.text = "MOUNTAIN JOURNEY — %s" % SECTION_NAMES[section]
	_set_objective(SECTION_OBJECTIVES[section])
	var checkpoint_index: int = 0 if section == 0 else SECTION_POINT_INDICES[section - 1]
	last_checkpoint = route_points[checkpoint_index] + Vector3(0, 1.2, 0)
	var data := GameManager.save_data
	data.story_flags["trio_journey_section"] = current_section
	data.story_flags["trio_journey_checkpoint"] = SECTION_NAMES[section].to_lower().replace(" ", "_")
	data.player_position = player.global_position
	SaveManager.save_checkpoint()
	_apply_section_atmosphere(section)
	if show_dialogue:
		_show_dialogue(SECTION_DIALOGUE[section])

func _spawn_danger_encounter() -> void:
	danger_spawned = true
	var base := route_points[20]
	for data in [["fast", Vector3(-3, 0.05, -2)], ["brute", Vector3(3, 0.05, 2)]]:
		var enemy := DEMON_SCRIPT.new() as DemonEnemy
		$Enemies.add_child(enemy)
		enemy.global_position = base + (data[1] as Vector3)
		enemy.configure(str(data[0]), player, combatant)
		enemy.died.connect(_on_enemy_died)
		active_enemies.append(enemy)
	_set_objective("Defeat the demons controlling the narrow pass. (2 remaining)")
	_show_feedback("The path is blocked. Stay together and clear the pass.")

func _on_enemy_died(enemy: DemonEnemy, reward: int, _kind: String) -> void:
	active_enemies.erase(enemy)
	GameManager.save_data.wan_currency += reward
	if active_enemies.is_empty():
		GameManager.save_data.story_flags["trio_danger_cleared"] = true
		SaveManager.save_checkpoint()
		_show_feedback("The pass is clear. Continue toward the fog.")
		current_section += 1
		_set_section(current_section, true)

func _arrive_at_strange_house() -> void:
	if strange_house_found:
		return
	strange_house_found = true
	var data := GameManager.save_data
	data.story_flags["strange_house_found"] = true
	data.story_flags["trio_journey_completed"] = true
	data.story_flags["trio_journey_section"] = 5
	data.story_flags["trio_journey_checkpoint"] = "strange_house_approach"
	last_checkpoint = _get_house_approach_checkpoint()
	data.current_scene = SCENE_PATH
	data.player_position = last_checkpoint
	SaveManager.save_checkpoint()
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	section_label.text = "THE STRANGE HOUSE"
	dialogue_label.text = "ZENITSU: The inside sounds bigger than the outside.\nTANJIRO: We go in carefully—and together."
	dialogue_label.visible = true
	await get_tree().create_timer(2.2).timeout
	dialogue_label.visible = false
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	_show_house_arrival_state()

func _show_house_arrival_state() -> void:
	section_label.text = "THE STRANGE HOUSE"
	_set_objective("Investigate the strange house.")
	interaction_label.text = HOUSE_ENTRY_PROMPT
	interaction_label.visible = false

func _on_interact() -> void:
	if not strange_house_found or transition_active:
		return
	if not _is_player_at_house_entry():
		return
	transition_active = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	var data := GameManager.save_data
	data.story_flags["drum_house_entered"] = true
	data.story_flags["drum_house_progress"] = 0
	data.current_scene = DRUM_HOUSE_SCENE
	data.player_position = Vector3(0, 1.1, 22)
	SaveManager.save_checkpoint()
	SceneManager.transition_to(DRUM_HOUSE_SCENE)

func _is_player_at_house_entry() -> bool:
	return is_instance_valid(house_entry_zone) and house_entry_zone.overlaps_body(player)

func _get_house_approach_checkpoint() -> Vector3:
	# This is on the exterior foundation, facing the visible doorway and within a short walk of it.
	return route_points[-1] + Vector3(0, 1.2, -8.0)

func _on_character_changed(_character_id: String, display_name: String) -> void:
	_show_feedback("%s takes the lead." % display_name.capitalize())

func _on_health_changed(current: float, _maximum: float) -> void:
	player.health = current

func _update_hud() -> void:
	status_label.text = "%s\nHealth: %d / %d\nStamina: %d / %d\nWAN: %d" % [party.get_display_name(), roundi(player.health), roundi(player.max_health), roundi(player.stamina), roundi(player.max_stamina), GameManager.save_data.wan_currency]
	if party.current_character == "tanjiro":
		ability_label.text = "WATER BREATHING: %d / %d\n1–7 Forms • Ctrl Dodge • Q Guard • F1/F2/F3 Switch" % [roundi(breathing.current_breath), roundi(breathing.max_breath)]
	else:
		var cooldown := party.get_cooldown_remaining()
		ability_label.text = "%s: %s\n1 Ability • Ctrl Dodge • F1/F2/F3 Switch" % [party.get_ability_name().to_upper(), "READY" if cooldown <= 0.0 else "%.1fs" % cooldown]

func _refresh_lock_target() -> void:
	var nearest: DemonEnemy
	var distance := INF
	for enemy in active_enemies:
		if not is_instance_valid(enemy) or not enemy.active:
			continue
		var candidate := player.global_position.distance_squared_to(enemy.global_position)
		if candidate < distance:
			distance = candidate
			nearest = enemy
	combat.set_lock_target(nearest)

func _rescue_player() -> void:
	player.global_position = last_checkpoint
	player.velocity = Vector3.ZERO
	companions.force_catch_up()
	GameManager.save_data.player_position = last_checkpoint
	SaveManager.save_checkpoint()
	_show_feedback("Returned to the last safe mountain checkpoint.")

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["trio_journey_objective"] = text

func _show_dialogue(text: String) -> void:
	dialogue_label.text = text
	dialogue_label.visible = true
	var expected := text
	await get_tree().create_timer(3.0).timeout
	if dialogue_label.text == expected:
		dialogue_label.visible = false

func _show_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true
	feedback_time = 3.0

func _apply_section_atmosphere(section: int) -> void:
	environment.fog_density = 0.003 + section * 0.0018
	environment.ambient_light_energy = 0.85 - section * 0.07

func _prepare_route_points() -> void:
	route_points.clear()
	var origin: Vector3 = ROUTE_POINTS[0]
	for point: Vector3 in ROUTE_POINTS:
		route_points.append(Vector3(point.x * ROUTE_HORIZONTAL_SCALE, point.y * 2.15, origin.z + (point.z - origin.z) * ROUTE_DEPTH_SCALE))

func _build_mountain_route() -> void:
	for index in route_points.size() - 1:
		var width := 15.0 if index in [0, 3, 8, 12, 16, 20, 23] else (8.0 if index in [6, 10, 14, 18, 21] else 11.0)
		_add_path_between(route_points[index], route_points[index + 1], width, index)
		path_segment_count += 1
		route_length += route_points[index].distance_to(route_points[index + 1])
		if index % 2 == 0:
			_add_tree(route_points[index] + Vector3(width * 0.65, 0.2, 0))
			_add_tree(route_points[index] - Vector3(width * 0.65, -0.2, 0))
		if index % 3 == 1:
			_add_rock(route_points[index] + Vector3(width * 0.42, 0.1, -1.5))
	for point_index in SECTION_POINT_INDICES:
		_add_beacon(route_points[point_index] + Vector3(0, 3.0, 0), point_index == SECTION_POINT_INDICES[-1])

func _add_path_between(start: Vector3, finish: Vector3, width: float, index: int) -> void:
	var delta := finish - start
	var horizontal_length := Vector2(delta.x, delta.z).length()
	var size := Vector3(width, 0.9, horizontal_length + 2.2)
	var center := (start + finish) * 0.5 - Vector3(0, 0.45, 0)
	var yaw := atan2(delta.x, delta.z)
	var pitch := -atan2(delta.y, horizontal_length)
	var rotation := Vector3(pitch, yaw, 0)
	var color := Color(0.16, 0.28, 0.16) if index < 5 or index in range(13, 18) else Color(0.3, 0.27, 0.22)
	_add_ground_box("MountainPath%02d" % index, size, center, rotation, color)

func _add_ground_box(label: String, size: Vector3, position: Vector3, rotation: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	$EnvironmentGeometry.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sBody" % label
	body.position = position
	body.rotation = rotation
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	$EnvironmentGeometry.add_child(body)

func _add_tree(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 4.5
	trunk.mesh = trunk_mesh
	trunk.position.y = 2.25
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.6
	crown_mesh.height = 4.5
	crown.mesh = crown_mesh
	crown.position.y = 5.2
	root.add_child(crown)
	$EnvironmentGeometry.add_child(root)

func _add_rock(position: Vector3) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.3
	rock.mesh = mesh
	rock.position = position + Vector3(0, 0.6, 0)
	rock.scale = Vector3(1.5, 0.9, 1.1)
	$EnvironmentGeometry.add_child(rock)

func _add_beacon(position: Vector3, crimson: bool) -> void:
	var beacon := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.14
	mesh.bottom_radius = 0.42
	mesh.height = 5.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.08, 0.05) if crimson else Color(0.08, 0.65, 1.0)
	material.emission_enabled = true
	material.emission = material.albedo_color
	mesh.material = material
	beacon.mesh = mesh
	beacon.position = position
	$EnvironmentGeometry.add_child(beacon)

func _build_house_exterior() -> void:
	var base := route_points[-1] + Vector3(0, 2.5, -10)
	_add_ground_box("HouseFoundation", Vector3(26, 1, 22), base - Vector3(0, 2.5, 0), Vector3.ZERO, Color(0.12, 0.1, 0.09))
	# The front wall is deliberately split around a real, walk-up doorway.
	for wall_data in [[Vector3(10.25, 8, 1), Vector3(-7.875, 1.5, -10)], [Vector3(10.25, 8, 1), Vector3(7.875, 1.5, -10)], [Vector3(1, 8, 22), Vector3(-13, 1.5, 0)], [Vector3(1, 8, 22), Vector3(13, 1.5, 0)]]:
		_add_ground_box("HouseWall", wall_data[0] as Vector3, base + (wall_data[1] as Vector3), Vector3.ZERO, Color(0.22, 0.13, 0.1))
	_add_ground_box("HouseRoof", Vector3(30, 1, 26), base + Vector3(0, 6.5, 0), Vector3(0, 0, deg_to_rad(4)), Color(0.08, 0.07, 0.07))
	_build_house_entry(base)

func _build_house_entry(base: Vector3) -> void:
	var entry_root := Node3D.new()
	entry_root.name = "StrangeHouseEntrance"
	entry_root.position = base + Vector3(0, 0, -10.7)
	$EnvironmentGeometry.add_child(entry_root)

	# A simple frame, steps, and lanterns make the interactive doorway visible from the path.
	_add_house_entry_piece(entry_root, "DoorFrameLeft", Vector3(0.45, 5.8, 0.7), Vector3(-2.75, 2.9, 0), Color(0.3, 0.18, 0.1))
	_add_house_entry_piece(entry_root, "DoorFrameRight", Vector3(0.45, 5.8, 0.7), Vector3(2.75, 2.9, 0), Color(0.3, 0.18, 0.1))
	_add_house_entry_piece(entry_root, "DoorLintel", Vector3(5.95, 0.55, 0.75), Vector3(0, 5.55, 0), Color(0.36, 0.22, 0.12))
	_add_house_entry_piece(entry_root, "DoorThreshold", Vector3(5.8, 0.32, 1.25), Vector3(0, 0.16, 0.75), Color(0.22, 0.15, 0.1))
	_add_ground_box("HouseEntryLowerStep", Vector3(7.0, 0.45, 2.2), base + Vector3(0, -2.25, -12.9), Vector3.ZERO, Color(0.18, 0.14, 0.1))
	_add_ground_box("HouseEntryUpperStep", Vector3(6.4, 0.45, 1.5), base + Vector3(0, -1.72, -11.55), Vector3.ZERO, Color(0.22, 0.16, 0.1))
	_add_house_entry_lantern(entry_root, Vector3(-3.65, 2.8, 0.25))
	_add_house_entry_lantern(entry_root, Vector3(3.65, 2.8, 0.25))

	house_entry_position = entry_root.global_position
	house_entry_zone = Area3D.new()
	house_entry_zone.name = "StrangeHouseEntryZone"
	house_entry_zone.position = house_entry_position
	house_entry_zone.collision_layer = 0
	house_entry_zone.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = HOUSE_ENTRY_HALF_EXTENTS * 2.0
	collision.shape = shape
	house_entry_zone.add_child(collision)
	$EnvironmentGeometry.add_child(house_entry_zone)

func _add_house_entry_piece(parent: Node3D, label: String, size: Vector3, local_position: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	visual.mesh = mesh
	visual.position = local_position
	parent.add_child(visual)

func _add_house_entry_lantern(parent: Node3D, local_position: Vector3) -> void:
	var lantern := MeshInstance3D.new()
	lantern.name = "EntryLantern"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.8, 0.35)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.48, 0.12)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.03)
	material.emission_energy_multiplier = 2.5
	mesh.material = material
	lantern.mesh = mesh
	lantern.position = local_position
	parent.add_child(lantern)
	var light := OmniLight3D.new()
	light.name = "EntryLanternLight"
	light.light_color = Color(1.0, 0.45, 0.16)
	light.light_energy = 1.4
	light.omni_range = 7.0
	light.position = local_position
	parent.add_child(light)
