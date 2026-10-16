extends Node3D

const TRAINING_SCENE := "res://scenes/episode_01/shizu_training.tscn"
const FINAL_TRAINING_SCENE := "res://scenes/episode_01/final_training_challenge.tscn"
const FINAL_OBJECTIVE := "Face Shizu's final challenge."
const DUMMY_SCENE := preload("res://combat/training_dummy.tscn")

const STAGE_OBJECTIVES := {
	1: "Endurance: reach every mountain-course marker.",
	2: "Reaction: dodge three clearly telegraphed log swings.",
	3: "Sword control: use light, heavy, guard, then break three targets.",
	4: "Breathing control: focus at the three blue breathing markers.",
	5: "Combat drill: light, heavy, guard, dodge, then press 1 for Water Form 1.",
	6: "Form mastery: demonstrate the highlighted Water Form.",
	7: "Final course: traverse, dodge, use three forms, and break the final target.",
}

@onready var player: ThirdPersonPlayer = $Player
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var breathing_label: Label = $HUD/BreathingLabel
@onready var form_label: Label = $HUD/FormLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var cinematic_camera: Camera3D = $CinematicCamera
@onready var player_camera: Camera3D = $Player/CameraPivot/SpringArm3D/Camera3D
@onready var hazard_log: Node3D = $TrainingFeatures/SwingingLog

var training_stage := 1
var checkpoint_index := 0
var active_checkpoints: Array[Area3D] = []
var dummies: Array[TrainingDummy] = []
var dodge_count := 0
var light_used := false
var heavy_used := false
var guard_used := false
var form_hits := 0
var final_forms_used: Dictionary = {}
var current_mastery_form := 1
var mastery_hits := 0
var mastery_completion_pending := false
var hazard_phase := 0.0
var stage_transitioning := false

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_build_training_ground()
	_build_checkpoint_sets()
	_build_dummies()
	combat.set_combat_enabled(true)
	combat.attack_performed.connect(_on_basic_attack)
	combat.dodge_performed.connect(_on_dodge)
	combat.guard_changed.connect(_on_guard_changed)
	water.form_activated.connect(_on_form_activated)
	water.form_hit.connect(_on_form_hit)
	water.form_failed.connect(_show_feedback)
	breathing.breath_changed.connect(_on_breath_changed)
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 4
	data.current_scene = TRAINING_SCENE
	if data.player_position.y <= 0.0:
		data.player_position = player.global_position
	data.story_flags["training_started"] = true
	training_stage = clampi(int(data.story_flags.get("training_stage", 1)), 1, 7)
	current_mastery_form = clampi(int(data.story_flags.get("water_mastery_form", 1)), 1, 7)
	_load_unlocks()
	if bool(data.story_flags.get("training_completed", false)):
		data.current_scene = FINAL_TRAINING_SCENE
		SaveManager.save_checkpoint()
		call_deferred("_continue_to_final_training")
		return
	if Engine.has_meta("skip_shizu_training_intro"):
		_configure_stage(training_stage)
	elif not bool(data.story_flags.get("training_intro_seen", false)):
		_run_training_intro()
	else:
		_configure_stage(training_stage)

func _process(delta: float) -> void:
	status_label.text = "TANJIRO\nHealth: %d / %d\nStamina: %d" % [roundi(player.health), roundi(player.max_health), roundi(player.stamina)]
	breathing_label.text = "BREATH: %d / %d" % [roundi(breathing.current_breath), roundi(breathing.max_breath)] if breathing.enabled and training_stage >= 4 else "BREATH: LOCKED"
	if training_stage in [2, 7] or (training_stage == 6 and current_mastery_form == 5):
		_update_hazard(delta)
	if training_stage in [1, 4, 7] and checkpoint_index < active_checkpoints.size():
		if active_checkpoints[checkpoint_index].overlaps_body(player):
			_reach_checkpoint()

func _run_training_intro() -> void:
	stage_transitioning = true
	player.set_controls_enabled(false)
	cinematic_camera.current = true
	cinematic_camera.global_position = Vector3(8, 5, 12)
	cinematic_camera.look_at($Shizu.global_position + Vector3(0, 1, 0))
	await _show_dialogue("Shizu: Reaching this mountain proved your resolve, not your readiness.", 3.5)
	await _show_dialogue("Shizu: I will train your body, your judgment, and the rhythm of your breathing.", 3.7)
	await _show_dialogue("Shizu: Complete each drill. Rushing ahead will only teach you how to fail faster.", 3.7)
	GameManager.save_data.story_flags["training_intro_seen"] = true
	GameManager.save_data.story_flags["training_stage"] = 1
	GameManager.save_data.story_flags["training_checkpoint_stage"] = 1
	GameManager.save_data.story_flags["training_checkpoint_index"] = 0
	SaveManager.save_checkpoint()
	player_camera.current = true
	player.set_controls_enabled(true)
	stage_transitioning = false
	_configure_stage(1)

func _configure_stage(stage: int) -> void:
	training_stage = stage
	combat.set_combat_enabled(stage >= 2)
	checkpoint_index = 0
	dodge_count = 0
	light_used = false
	heavy_used = false
	guard_used = false
	form_hits = 0
	final_forms_used.clear()
	for checkpoint_set in $CheckpointSets.get_children():
		for area in checkpoint_set.get_children():
			area.visible = false
			area.monitoring = false
	for dummy in dummies:
		dummy.visible = false
		dummy.hurtbox.monitorable = false
	hazard_log.visible = stage in [2, 7]
	$TrainingFeatures/HazardTelegraph.visible = false
	match stage:
		1:
			active_checkpoints = _areas_in($CheckpointSets/Endurance)
			_show_checkpoint_set(active_checkpoints)
			player.global_position = Vector3(0, 1, 14)
		2:
			player.global_position = Vector3(0, 1, 1)
		3:
			player.global_position = Vector3(0, 1, 1)
			_reset_dummies(3, 45.0, [Vector3(-3, 0, -7), Vector3(0, 0, -9), Vector3(3, 0, -7)])
		4:
			player.global_position = Vector3(0, 1, 5)
			breathing.set_unlocked(true)
			GameManager.save_data.story_flags["breathing_system_unlocked"] = true
			active_checkpoints = _areas_in($CheckpointSets/Breathing)
			_show_checkpoint_set(active_checkpoints)
		5:
			player.global_position = Vector3(0, 1, 1)
			_unlock_forms_through(1)
			GameManager.save_data.story_flags["water_form_1_unlocked"] = true
			GameManager.save_data.story_flags["water_form_1_tutorial_seen"] = true
			SaveManager.save_checkpoint()
			_reset_dummies(1, 180.0, [Vector3(0, 0, -8)])
		6:
			player.global_position = Vector3(0, 1, 1)
			_prepare_mastery_test()
		7:
			player.global_position = Vector3(0, 1, 12)
			_unlock_forms_through(7)
			active_checkpoints = _areas_in($CheckpointSets/FinalCourse)
			_show_checkpoint_set(active_checkpoints)
			_reset_dummies(1, 240.0, [Vector3(0, 0, -23)])
	_restore_stage_checkpoint(stage)
	_set_objective(STAGE_OBJECTIVES[stage])
	_update_form_hud()
	if stage == 5:
		SaveManager.save_checkpoint()
	if stage == 7:
		_show_feedback("Space jumps • Ctrl dodges • Follow the blue markers from the low end of each slope.")
	else:
		_show_feedback("Training Stage %d / 7" % stage)

func _areas_in(parent: Node) -> Array[Area3D]:
	var result: Array[Area3D] = []
	for child in parent.get_children():
		result.append(child as Area3D)
	return result

func _show_checkpoint_set(areas: Array[Area3D]) -> void:
	for area in areas:
		area.visible = true
		area.monitoring = true
	_update_checkpoint_markers()

func _update_checkpoint_markers() -> void:
	for index in active_checkpoints.size():
		var marker := active_checkpoints[index].get_node("Marker") as MeshInstance3D
		marker.visible = index == checkpoint_index

func _restore_stage_checkpoint(stage: int) -> void:
	var data := GameManager.save_data
	if int(data.story_flags.get("training_checkpoint_stage", -1)) != stage:
		return
	checkpoint_index = clampi(int(data.story_flags.get("training_checkpoint_index", 0)), 0, active_checkpoints.size())
	if checkpoint_index > 0 and data.player_position.y > 0.0:
		player.global_position = data.player_position
	_update_checkpoint_markers()

func _reach_checkpoint() -> void:
	if training_stage == 4:
		breathing.refill(24.0)
	checkpoint_index += 1
	_show_feedback("Course marker %d / %d" % [checkpoint_index, active_checkpoints.size()])
	_update_checkpoint_markers()
	var data := GameManager.save_data
	data.story_flags["training_checkpoint_stage"] = training_stage
	data.story_flags["training_checkpoint_index"] = checkpoint_index
	data.player_position = player.global_position
	SaveManager.save_checkpoint()
	if checkpoint_index >= active_checkpoints.size():
		if training_stage == 7:
			_check_final_course()
		else:
			_complete_stage()

func _update_hazard(delta: float) -> void:
	hazard_phase += delta
	hazard_log.rotation.z = sin(hazard_phase * 2.1) * 1.05
	var warning_window := absf(sin(hazard_phase * 2.1)) < 0.25
	$TrainingFeatures/HazardTelegraph.visible = warning_window

func _on_dodge() -> void:
	if training_stage == 2:
		if player.global_position.distance_to(hazard_log.global_position) > 6.0 or not $TrainingFeatures/HazardTelegraph.visible:
			_show_feedback("Watch the red telegraph and dodge as the log crosses the center.")
			return
		dodge_count += 1
		_show_feedback("Clean dodge %d / 3" % mini(dodge_count, 3))
		if dodge_count >= 3:
			_complete_stage()
	elif training_stage == 5:
		dodge_count += 1
		_check_combat_drill()
	elif training_stage == 7:
		dodge_count += 1
		_check_final_course()

func _on_basic_attack(attack_type: String) -> void:
	light_used = light_used or attack_type == "light"
	heavy_used = heavy_used or attack_type == "heavy"
	if training_stage == 3:
		_check_sword_control()
	elif training_stage == 5:
		_check_combat_drill()

func _on_guard_changed(is_guarding: bool) -> void:
	guard_used = guard_used or is_guarding
	if training_stage == 3:
		_check_sword_control()
	elif training_stage == 5:
		_check_combat_drill()

func _on_dummy_defeated(_dummy: TrainingDummy) -> void:
	if training_stage == 3:
		_check_sword_control()
	elif training_stage == 5:
		_check_combat_drill()
	elif training_stage == 7:
		_check_final_course()

func _on_form_activated(form_number: int, ability_name: String) -> void:
	form_label.text = "ACTIVE FORM: %d — %s" % [form_number, ability_name]
	if training_stage == 6 and form_number == current_mastery_form and form_number == 5:
		if player.global_position.distance_to(hazard_log.global_position) <= 6.0 and $TrainingFeatures/HazardTelegraph.visible:
			_complete_mastery_form()
		else:
			_show_feedback("Form 5 must be timed as the red log telegraph crosses the center.")
	elif training_stage == 7:
		final_forms_used[form_number] = true
		_check_final_course()

func _on_form_hit(form_number: int, _target: CombatHurtbox) -> void:
	form_hits += 1
	if training_stage == 5:
		_check_combat_drill()
	elif training_stage == 6 and form_number == current_mastery_form and current_mastery_form != 5:
		mastery_hits += 1
		var required := {1: 1, 2: 2, 3: 3, 4: 2, 5: 0, 6: 4, 7: 1}[current_mastery_form] as int
		_show_feedback("Form %d hits: %d / %d" % [current_mastery_form, mini(mastery_hits, required), required])
		if mastery_hits >= required and not mastery_completion_pending:
			mastery_completion_pending = true
			call_deferred("_complete_mastery_form")

func _check_combat_drill() -> void:
	if dummies[0].combatant.current_health <= 0.0 and light_used and heavy_used and guard_used and dodge_count > 0 and form_hits > 0:
		_complete_stage()

func _check_sword_control() -> void:
	var defeated := 0
	for dummy in dummies.slice(0, 3):
		if dummy.combatant.current_health <= 0.0:
			defeated += 1
	if defeated == 3 and light_used and heavy_used and guard_used:
		_complete_stage()
	elif defeated == 3:
		_show_feedback("Targets broken. Demonstrate light, heavy, and guard to finish.")

func _prepare_mastery_test() -> void:
	mastery_hits = 0
	mastery_completion_pending = false
	_unlock_forms_through(current_mastery_form)
	player.global_position = Vector3(0, 1, 1)
	var positions := [Vector3(0, 0, -1.4), Vector3(-1.4, 0, -1.4), Vector3(1.4, 0, -1.4), Vector3(0, 0, -2.2), Vector3(-2.5, 0, -1.8)]
	if current_mastery_form == 1:
		positions[0] = Vector3(0, 0, -4.8)
	elif current_mastery_form == 7:
		positions[0] = Vector3(0, 0, -3.5)
	var count := 3 if current_mastery_form in [2, 4] else (1 if current_mastery_form in [1, 5, 7] else 2)
	_reset_dummies(count, 500.0, positions)
	if current_mastery_form == 5:
		hazard_log.visible = true
		_set_objective("Master Water Form 5: press 5 during the red log telegraph.")
	else:
		hazard_log.visible = false
		$TrainingFeatures/HazardTelegraph.visible = false
		_set_objective("Master Water Form %d: press %d and strike the training target%s." % [current_mastery_form, current_mastery_form, "s" if count > 1 else ""])
	_update_form_hud()
	_show_feedback("Water Form %d unlocked" % current_mastery_form)

func _complete_mastery_form() -> void:
	GameManager.save_data.story_flags["water_form_%d_unlocked" % current_mastery_form] = true
	if current_mastery_form >= 7:
		current_mastery_form = 7
		GameManager.save_data.story_flags["water_mastery_form"] = 7
		SaveManager.save_checkpoint()
		_complete_stage()
		return
	current_mastery_form += 1
	GameManager.save_data.story_flags["water_mastery_form"] = current_mastery_form
	SaveManager.save_checkpoint()
	_prepare_mastery_test()

func _check_final_course() -> void:
	if checkpoint_index < active_checkpoints.size():
		return
	if dodge_count < 1:
		_show_feedback("Course complete: dodge one hazard before finishing.")
		return
	if final_forms_used.size() < 3:
		_show_feedback("Use three different Water Forms in the final drill.")
		return
	if dummies[0].combatant.current_health > 0.0:
		_show_feedback("Break the final training target.")
		return
	_finish_training()

func _complete_stage() -> void:
	if stage_transitioning:
		return
	stage_transitioning = true
	var completed_stage := training_stage
	GameManager.save_data.story_flags["training_stage_%d_completed" % completed_stage] = true
	if completed_stage >= 7:
		_finish_training()
		return
	training_stage += 1
	GameManager.save_data.story_flags["training_stage"] = training_stage
	GameManager.save_data.story_flags["training_checkpoint_stage"] = training_stage
	GameManager.save_data.story_flags["training_checkpoint_index"] = 0
	SaveManager.save_checkpoint()
	_show_feedback("Stage %d complete — checkpoint saved" % completed_stage)
	await get_tree().create_timer(1.4).timeout
	stage_transitioning = false
	_configure_stage(training_stage)

func _finish_training() -> void:
	if bool(GameManager.save_data.story_flags.get("training_completed", false)):
		return
	stage_transitioning = true
	player.set_controls_enabled(false)
	GameManager.save_data.story_flags["training_completed"] = true
	GameManager.save_data.story_flags["training_stage"] = 7
	GameManager.save_data.chapter = 5
	SaveManager.save_checkpoint()
	_set_objective(FINAL_OBJECTIVE)
	await _show_dialogue("Shizu: Your movements finally follow your breathing instead of fighting it.", 3.5)
	await _show_dialogue("Shizu: You have learned the seven forms. One final challenge remains.", 3.5)
	feedback_label.text = "Shizu Training Complete"
	feedback_label.visible = true
	GameManager.save_data.current_scene = FINAL_TRAINING_SCENE
	SaveManager.save_checkpoint()
	await get_tree().create_timer(1.2).timeout
	SceneManager.transition_to(FINAL_TRAINING_SCENE)

func _continue_to_final_training() -> void:
	SceneManager.transition_to(FINAL_TRAINING_SCENE)

func _unlock_forms_through(max_form: int) -> void:
	breathing.set_unlocked(true)
	GameManager.save_data.story_flags["breathing_system_unlocked"] = true
	water.set_enabled(true)
	for form_number in range(1, 8):
		var unlocked := form_number <= max_form or bool(GameManager.save_data.story_flags.get("water_form_%d_unlocked" % form_number, false))
		water.set_form_unlocked(form_number, unlocked)
		if form_number <= max_form:
			GameManager.save_data.story_flags["water_form_%d_unlocked" % form_number] = true

func _update_form_hud() -> void:
	if training_stage < 5:
		form_label.text = "WATER FORMS: LOCKED"
		return
	if training_stage == 5:
		form_label.text = "WATER FORM 1 UNLOCKED\nPress 1 to use First Form: Current Step"
		return
	var unlocked: PackedStringArray = []
	for form_number in range(1, 8):
		if water.is_form_unlocked(form_number):
			unlocked.append(str(form_number))
	var unlocked_text := ", ".join(unlocked)
	form_label.text = "WATER FORMS UNLOCKED: %s\nPress the matching number key to activate a form." % unlocked_text

func _load_unlocks() -> void:
	var breathing_unlocked := bool(GameManager.save_data.story_flags.get("breathing_system_unlocked", false))
	breathing.set_unlocked(breathing_unlocked)
	water.set_enabled(breathing_unlocked)
	for form_number in range(1, 8):
		water.set_form_unlocked(form_number, bool(GameManager.save_data.story_flags.get("water_form_%d_unlocked" % form_number, false)))

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["training_objective"] = text

func _show_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true

func _on_breath_changed(_current: float, _maximum: float) -> void:
	pass

func _show_dialogue(line: String, duration: float) -> void:
	dialogue_label.text = line
	dialogue_label.visible = true
	await get_tree().create_timer(duration).timeout
	dialogue_label.visible = false

func _reset_dummies(count: int, health: float, positions: Array) -> void:
	for index in dummies.size():
		var dummy := dummies[index]
		if index < count:
			dummy.position = positions[index]
			dummy.reset_dummy(health)
		else:
			dummy.visible = false
			dummy.hurtbox.set_deferred("monitorable", false)

func _build_dummies() -> void:
	for index in 5:
		var dummy := DUMMY_SCENE.instantiate() as TrainingDummy
		dummy.name = "TrainingDummy%d" % (index + 1)
		$TrainingFeatures/Dummies.add_child(dummy)
		dummy.dummy_defeated.connect(_on_dummy_defeated)
		dummies.append(dummy)

func _build_checkpoint_sets() -> void:
	_create_checkpoint_set($CheckpointSets/Endurance, [Vector3(-10, 1, 7), Vector3(-12, 2.4, -7), Vector3(0, 4.2, -18), Vector3(12, 2.2, -8), Vector3(8, 1, 7)])
	_create_checkpoint_set($CheckpointSets/Breathing, [Vector3(-7, 1, -4), Vector3(0, 1, -11), Vector3(7, 1, -4)])
	_create_checkpoint_set($CheckpointSets/FinalCourse, [Vector3(-10, 1, 9.2), Vector3(-8, 2.5, -9), Vector3(8, 5.3, -18), Vector3(10, 1, -23)])

func _create_checkpoint_set(parent: Node3D, positions: Array) -> void:
	for index in positions.size():
		var area := Area3D.new()
		area.name = "Checkpoint%d" % (index + 1)
		area.position = positions[index]
		area.collision_layer = 0
		area.collision_mask = 1
		var shape_node := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.5
		shape_node.shape = shape
		area.add_child(shape_node)
		var marker_mesh := CylinderMesh.new()
		marker_mesh.top_radius = 0.18
		marker_mesh.bottom_radius = 0.18
		marker_mesh.height = 1.3
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.72, 0.95, 0.8)
		material.emission_enabled = true
		material.emission = Color(0.0, 0.25, 0.65, 1)
		marker_mesh.material = material
		var marker := MeshInstance3D.new()
		marker.name = "Marker"
		marker.mesh = marker_mesh
		marker.position.y = 0.8
		area.add_child(marker)
		parent.add_child(area)

func _build_training_ground() -> void:
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.18, 0.28, 0.17, 1)
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(42, 1, 52)
	ground_mesh.material = ground_material
	$TrainingGround/Ground.mesh = ground_mesh
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(42, 1, 52)
	$TrainingGround/GroundBody/CollisionShape3D.shape = ground_shape
	_add_course_box("LowerSlope", Vector3(6, 0.35, 16), Vector3(-11, 1.1, 0), Vector3(8, 0, 0))
	_add_course_box("LowerRest", Vector3(15, 0.35, 5), Vector3(-5, 2.2, -9), Vector3.ZERO)
	_add_course_box("UpperSlope", Vector3(6, 0.35, 12), Vector3(0, 3.2, -14), Vector3(10, 0, 0))
	_add_course_box("HighRidge", Vector3(16, 0.35, 5), Vector3(7, 4.2, -19), Vector3.ZERO)
	_add_course_box("ControlledDescent", Vector3(6, 0.35, 12), Vector3(12, 3.2, -13), Vector3(10, 0, 0))
	_add_course_box("ReturnSlope", Vector3(6, 0.35, 17), Vector3(9, 1.4, 0), Vector3(5, 0, 0))

func _add_course_box(label: String, size: Vector3, position: Vector3, rotation_degrees_value: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.25, 0.15, 1.0)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation_degrees = rotation_degrees_value
	$TrainingGround.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sBody" % label
	body.position = position
	body.rotation_degrees = rotation_degrees_value
	$TrainingGround.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
