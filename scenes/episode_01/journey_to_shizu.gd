extends Node3D

const JOURNEY_SCENE := "res://scenes/episode_01/journey_to_shizu.tscn"
const JOURNEY_OBJECTIVE := "Find Shizu."
const TRAINING_OBJECTIVE := "Begin training with Shizu."

@onready var player: ThirdPersonPlayer = $Player
@onready var player_camera: Camera3D = $Player/CameraPivot/SpringArm3D/Camera3D
@onready var cinematic_camera: Camera3D = $CinematicCamera
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var checkpoint_label: Label = $HUD/CheckpointLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var milestone_label: Label = $HUD/MilestoneLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var obstacle_area: Area3D = $JourneyTriggers/DetourCheckpoint
@onready var arrival_area: Area3D = $JourneyTriggers/ShizuArrival
@onready var training_start_area: Area3D = $Shizu/TrainingStartArea

var obstacle_complete := false
var intro_running := false
var safe_checkpoint_position := Vector3(0.0, 1.0, 20.0)

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_build_journey_environment()
	var data := GameManager.save_data
	if data.current_scene == JOURNEY_SCENE and data.player_position != Vector3.ZERO:
		player.global_position = data.player_position
	player.floor_max_angle = deg_to_rad(50.0)
	player.floor_snap_length = 0.35
	safe_checkpoint_position = player.global_position if player.global_position.y > 0.0 else Vector3(0.0, 1.0, 20.0)
	player.interact_pressed.connect(_on_player_interact_pressed)
	player.carrying_companion = true
	$Player/CarriedNezuko.visible = true
	data.episode = 1
	data.chapter = 3
	data.current_scene = JOURNEY_SCENE
	data.player_position = player.global_position
	data.story_flags["shizu_location_received"] = true
	if not bool(data.story_flags.get("journey_to_shizu_started", false)):
		data.story_flags["journey_to_shizu_started"] = true
		_checkpoint("Journey begun - checkpoint saved")
	obstacle_complete = bool(data.story_flags.get("mountain_obstacle_completed", false))
	if bool(data.story_flags.get("shizu_intro_seen", false)):
		_set_objective(TRAINING_OBJECTIVE)
		milestone_label.text = "Journey to Shizu Complete"
		milestone_label.visible = true
	else:
		_set_objective(JOURNEY_OBJECTIVE)

func _process(_delta: float) -> void:
	status_label.text = "TANJIRO\nHealth: %d / %d\nStamina: %d" % [roundi(player.health), roundi(player.max_health), roundi(player.stamina)]
	if player.is_on_floor() and player.global_position.y > -0.1:
		safe_checkpoint_position = player.global_position
	if player.global_position.y < -8.0:
		_restore_fall_checkpoint()
	if not obstacle_complete and obstacle_area.overlaps_body(player):
		_complete_obstacle()
	if not intro_running and not bool(GameManager.save_data.story_flags.get("shizu_intro_seen", false)) and arrival_area.overlaps_body(player):
		_begin_shizu_intro()
	interaction_label.visible = bool(GameManager.save_data.story_flags.get("shizu_intro_seen", false)) and _is_training_start_nearby() and not intro_running

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["journey_to_shizu_objective"] = text

func _complete_obstacle() -> void:
	obstacle_complete = true
	safe_checkpoint_position = player.global_position
	GameManager.save_data.story_flags["mountain_obstacle_completed"] = true
	_checkpoint("Fallen tree bypassed - checkpoint saved")
	_show_dialogue("The trunk blocks the old trail. The narrow path to the right is clear.", 3.2)

func _begin_shizu_intro() -> void:
	intro_running = true
	player.set_controls_enabled(false)
	GameManager.save_data.story_flags["shizu_reached"] = true
	_checkpoint("Shizu's clearing reached - checkpoint saved")
	await get_tree().create_timer(0.2).timeout
	cinematic_camera.current = true
	_focus_cinematic(Vector3(11.0, 17.0, -666.0), $Shizu.global_position + Vector3(0.0, 0.75, 0.0))
	await _show_dialogue("Tanjiro: Giyu told me to find you.", 2.8)
	await _move_cinematic(Vector3(10.0, 15.5, -681.0), $Shizu.global_position + Vector3(0.0, 0.75, 0.0), 2.0)
	await _show_dialogue("Shizu: So he sent you through the mountain after all.", 3.0)
	await _show_dialogue("Shizu: Determination brought you here. It will not be enough for what follows.", 3.8)
	await _show_dialogue("Shizu: Rest for a moment. Then I will see whether you are ready to train.", 3.8)
	var data := GameManager.save_data
	data.story_flags["shizu_intro_seen"] = true
	data.chapter = 4
	_set_objective(TRAINING_OBJECTIVE)
	_checkpoint("Shizu introduction complete - checkpoint saved")
	milestone_label.text = "Journey to Shizu Complete"
	milestone_label.visible = true
	player_camera.current = true
	player.set_controls_enabled(true)
	intro_running = false

func _on_player_interact_pressed() -> void:
	if intro_running or not bool(GameManager.save_data.story_flags.get("shizu_intro_seen", false)) or not _is_training_start_nearby():
		return
	intro_running = true
	var data := GameManager.save_data
	data.story_flags["training_started"] = true
	data.story_flags["training_stage"] = maxi(1, int(data.story_flags.get("training_stage", 1)))
	data.current_scene = "res://scenes/episode_01/shizu_training.tscn"
	data.player_position = Vector3(0, 1, 14)
	SaveManager.save_checkpoint()
	SceneManager.transition_to("res://scenes/episode_01/shizu_training.tscn")

func _is_training_start_nearby() -> bool:
	return training_start_area.overlaps_body(player) or player.global_position.distance_to($Shizu.global_position) <= 5.0

func _checkpoint(message: String) -> void:
	SaveManager.save_checkpoint()
	checkpoint_label.text = message
	checkpoint_label.visible = true
	await get_tree().create_timer(2.5).timeout
	checkpoint_label.visible = false

func _restore_fall_checkpoint() -> void:
	player.global_position = safe_checkpoint_position
	player.velocity = Vector3.ZERO
	SaveManager.save_checkpoint()
	_checkpoint("Recovered at the last safe mountain surface")

func _show_dialogue(line: String, duration: float) -> void:
	dialogue_label.text = line
	dialogue_label.visible = true
	await get_tree().create_timer(duration).timeout
	dialogue_label.visible = false

func _focus_cinematic(camera_position: Vector3, focus_position: Vector3) -> void:
	cinematic_camera.global_position = camera_position
	cinematic_camera.look_at(focus_position, Vector3.UP)

func _move_cinematic(camera_position: Vector3, focus_position: Vector3, duration: float) -> void:
	var target_transform := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus_position, Vector3.UP)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cinematic_camera, "global_transform", target_transform, duration)
	await tween.finished

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _add_box(parent: Node3D, label: String, size: Vector3, position: Vector3, color: Color, collision := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_material(color)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	parent.add_child(visual)
	if collision:
		var body := StaticBody3D.new()
		body.name = "%sCollision" % label
		parent.add_child(body)
		body.position = position
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
	return visual

func _add_slope(parent: Node3D, label: String, size: Vector3, position: Vector3, angle_degrees: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_material(color)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation_degrees.x = angle_degrees
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sCollision" % label
	body.position = position
	body.rotation_degrees.x = angle_degrees
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return visual

func _add_slope_edges(parent: Node3D, center: Vector3, length: float, angle_degrees: float, color: Color) -> void:
	for side in [-1.0, 1.0]:
		_add_slope(parent, "CliffEdge", Vector3(1.8, 4.5, length), center + Vector3(side * 3.5, 1.8, 0), angle_degrees, color)

func _add_tree(parent: Node3D, position: Vector3, scale_factor := 1.0) -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16 * scale_factor
	trunk_mesh.bottom_radius = 0.26 * scale_factor
	trunk_mesh.height = 3.2 * scale_factor
	trunk_mesh.material = _make_material(Color(0.22, 0.11, 0.045, 1.0))
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.position = position + Vector3(0, 1.6 * scale_factor, 0)
	parent.add_child(trunk)
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.08 * scale_factor
	crown_mesh.bottom_radius = 1.05 * scale_factor
	crown_mesh.height = 5.4 * scale_factor
	crown_mesh.material = _make_material(Color(0.055, 0.19, 0.10, 1.0))
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.position = position + Vector3(0, 5.2 * scale_factor, 0)
	parent.add_child(crown)

func _add_rock(parent: Node3D, position: Vector3, scale_factor := 1.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.75 * scale_factor
	mesh.height = 1.15 * scale_factor
	mesh.material = _make_material(Color(0.25, 0.28, 0.29, 1.0))
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.position = position + Vector3(0, 0.4 * scale_factor, 0)
	rock.scale = Vector3(1.25, 0.75, 0.9)
	parent.add_child(rock)

func _build_journey_environment() -> void:
	var world := $JourneyWorld
	_add_box(world, "SafeMountainGround", Vector3(100, 1, 760), Vector3(0, -0.5, -340), Color(0.13, 0.23, 0.15, 1.0), true)
	var forest := Node3D.new()
	forest.name = "ForestPath"
	world.add_child(forest)
	_add_box(forest, "ForestTrail", Vector3(5.4, 0.14, 62), Vector3(0, 0.05, -10), Color(0.32, 0.24, 0.14, 1.0), true)
	for position in [Vector3(-4, 0, 14), Vector3(4, 0, 11), Vector3(-5, 0, 3), Vector3(5, 0, -3), Vector3(-4, 0, -11), Vector3(4, 0, -18), Vector3(-5, 0, -28), Vector3(5, 0, -36), Vector3(-4, 0, -44)]:
		_add_tree(forest, position, 0.9)
	for position in [Vector3(-2.8, 0, 8), Vector3(2.7, 0, -9), Vector3(-2.6, 0, -22), Vector3(2.9, 0, -38)]:
		_add_rock(forest, position, 0.8)
	var ascent := Node3D.new()
	ascent.name = "SteepMountainAscent"
	world.add_child(ascent)
	_add_box(ascent, "AscentTrailA", Vector3(5.2, 0.18, 28), Vector3(1.8, 0.12, -54), Color(0.34, 0.25, 0.15, 1.0), true)
	_add_box(ascent, "SwitchbackTrail", Vector3(20, 0.18, 5), Vector3(8.5, 0.18, -69), Color(0.34, 0.25, 0.15, 1.0), true)
	_add_box(ascent, "AscentTrailB", Vector3(5.2, 0.18, 36), Vector3(14.5, 0.12, -87), Color(0.34, 0.25, 0.15, 1.0), true)
	for position in [Vector3(-3, 0, -53), Vector3(5, 0, -63), Vector3(16, 0, -72), Vector3(10, 0, -84), Vector3(18, 0, -97)]:
		_add_rock(ascent, position, 1.7)
	var obstacle := Node3D.new()
	obstacle.name = "BrokenPathObstacle"
	world.add_child(obstacle)
	var log := _add_box(obstacle, "FallenTree", Vector3(12, 0.9, 0.9), Vector3(14.5, 0.65, -106), Color(0.24, 0.105, 0.035, 1.0), true)
	log.rotation_degrees.z = 7.0
	_add_box(obstacle, "RockslideBarrierLeft", Vector3(70, 2.8, 1.2), Vector3(-14.5, 1.35, -106), Color(0.22, 0.25, 0.26, 1.0), true)
	_add_box(obstacle, "RockslideBarrierRight", Vector3(28, 2.8, 1.2), Vector3(36.0, 1.35, -106), Color(0.22, 0.25, 0.26, 1.0), true)
	_add_box(obstacle, "DetourTrail", Vector3(5, 0.18, 25), Vector3(21.0, 0.1, -115), Color(0.36, 0.27, 0.16, 1.0), true)
	for position in [Vector3(8, 0, -105), Vector3(11, 0, -111), Vector3(17, 0, -119), Vector3(25, 0, -108)]:
		_add_rock(obstacle, position, 1.25)
	var high_trail := Node3D.new()
	high_trail.name = "HighMountainTrail"
	world.add_child(high_trail)
	_add_box(high_trail, "HighTrail", Vector3(5.0, 0.18, 58), Vector3(21.0, 0.12, -155), Color(0.31, 0.23, 0.15, 1.0), true)
	_add_box(high_trail, "LookoutStone", Vector3(8, 1.0, 7), Vector3(15.0, 0.5, -149), Color(0.27, 0.29, 0.31, 1.0))
	for position in [Vector3(13, 0, -131), Vector3(28, 0, -142), Vector3(14, 0, -161), Vector3(28, 0, -173)]:
		_add_rock(high_trail, position, 1.9)
	_build_long_mountain(world)
	var hut := $Shizu/Hut
	_add_box(hut, "HutWalls", Vector3(7, 3.4, 5), Vector3(8, 1.7, -7), Color(0.24, 0.14, 0.075, 1.0), true)
	var roof := _add_box(hut, "HutRoof", Vector3(8, 0.7, 6), Vector3(8, 3.7, -7), Color(0.09, 0.11, 0.12, 1.0))
	roof.rotation_degrees.z = 8.0
	_add_box($Shizu, "TrainingYard", Vector3(14, 0.12, 13), Vector3(0, 0.08, 0), Color(0.38, 0.29, 0.18, 1.0), true)
	for position in [Vector3(-6, 0, 6), Vector3(15, 0, 3), Vector3(-6, 0, -9), Vector3(15, 0, -11)]:
		_add_tree($Shizu, position, 0.85)

func _build_long_mountain(world: Node3D) -> void:
	var journey := Node3D.new()
	journey.name = "ExtendedMountainJourney"
	world.add_child(journey)
	var trail_color := Color(0.31, 0.23, 0.15, 1.0)
	var cliff_color := Color(0.22, 0.25, 0.26, 1.0)
	var forest_color := Color(0.07, 0.22, 0.12, 1.0)

	# Section 3: a long climb out of the first forest and onto a high ridge.
	_add_slope(journey, "RidgeClimb", Vector3(5.4, 0.22, 92), Vector3(21, 4.6, -235), 5.7, trail_color)
	_add_slope_edges(journey, Vector3(21, 4.0, -235), 92, 5.7, cliff_color)
	_add_box(journey, "RidgeRest", Vector3(15, 0.22, 22), Vector3(18, 9.1, -292), trail_color, true)
	_add_box(journey, "RidgeViewpoint", Vector3(4, 0.45, 4), Vector3(27, 9.3, -292), cliff_color)
	for position in [Vector3(13, 0, -220), Vector3(28, 0, -248), Vector3(13, 0, -270), Vector3(28, 0, -312)]:
		_add_rock(journey, position, 2.2)
	# The broad ridge crossing turns the route instead of pointing straight at Shizu.
	_add_box(journey, "RidgeTransition", Vector3(15, 0.22, 10), Vector3(12, 9.1, -307), trail_color, true)
	_add_box(journey, "RidgeSwitchback", Vector3(28, 0.22, 5.2), Vector3(7, 9.1, -314), trail_color, true)
	_add_box(journey, "RidgeWall", Vector3(1.6, 3.5, 14), Vector3(-8, 10.5, -320), cliff_color, true)

	# Section 4: descend through exposed rock toward a second, lower forest.
	_add_slope(journey, "RockyDescent", Vector3(5.4, 0.22, 92), Vector3(-7, 5.2, -365), -4.4, trail_color)
	_add_slope_edges(journey, Vector3(-7, 4.6, -365), 92, -4.4, cliff_color)
	for position in [Vector3(-12, 0, -335), Vector3(-2, 0, -350), Vector3(-12, 0, -375), Vector3(-2, 0, -398)]:
		_add_rock(journey, position, 2.0)

	# Section 5: a quiet valley with a wider rest area and optional side trail.
	_add_box(journey, "ValleyFloor", Vector3(8, 0.22, 66), Vector3(-7, 2.0, -435), trail_color, true)
	_add_box(journey, "ValleyRestArea", Vector3(18, 0.22, 15), Vector3(-7, 2.1, -472), Color(0.36, 0.29, 0.19, 1.0), true)
	_add_box(journey, "ValleyBranch", Vector3(20, 0.18, 3.5), Vector3(-19, 2.0, -457), trail_color, true)
	for position in [Vector3(-14, 0, -414), Vector3(0, 0, -426), Vector3(-14, 0, -449), Vector3(0, 0, -483)]:
		_add_tree(journey, position, 0.95)
	for position in [Vector3(-12, 0, -430), Vector3(-2, 0, -446), Vector3(-13, 0, -480), Vector3(1, 0, -490)]:
		_add_rock(journey, position, 1.25)

	# Section 6: final ascent, another switchback, and a narrow approach to Shizu.
	_add_slope(journey, "FinalAscentLower", Vector3(5.4, 0.22, 92), Vector3(-7, 4.7, -525), 3.4, trail_color)
	_add_slope_edges(journey, Vector3(-7, 4.0, -525), 92, 3.4, cliff_color)
	_add_box(journey, "FinalAscentTransition", Vector3(20, 0.22, 10), Vector3(0, 8.1, -575), trail_color, true)
	_add_box(journey, "FinalSwitchback", Vector3(27, 0.22, 5.2), Vector3(5, 8.1, -579), trail_color, true)
	_add_slope(journey, "FinalAscentUpper", Vector3(4.8, 0.22, 112), Vector3(14, 11.0, -635), 3.5, trail_color)
	# End the cliff walls before the clearing so they cannot seal off Shizu's yard.
	_add_slope_edges(journey, Vector3(14, 10.3, -635), 94, 3.5, cliff_color)
	for position in [Vector3(-13, 0, -520), Vector3(-1, 0, -548), Vector3(11, 0, -605), Vector3(20, 0, -647)]:
		_add_rock(journey, position, 1.8)
	for position in [Vector3(9, 0, -540), Vector3(1, 0, -570), Vector3(20, 0, -600), Vector3(8, 0, -658)]:
		_add_tree(journey, position, 0.82)
	_add_box(journey, "ShizuApproach", Vector3(12, 0.22, 38), Vector3(14, 13.0, -690), trail_color, true)
