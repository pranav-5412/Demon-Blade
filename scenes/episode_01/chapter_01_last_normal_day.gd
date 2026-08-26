extends Node3D

const WOOD_STEP := 0
const DELIVERY_STEP := 1
const RETURN_STEP := 2
const CARRY_STEP := 3
const GIYU_STEP := 4
const FIND_SHIZU_STEP := 5
const COMPLETE_STEP := FIND_SHIZU_STEP
const JOURNEY_SCENE := "res://scenes/episode_01/journey_to_shizu.tscn"
const TRAINING_SCENE := "res://scenes/episode_01/shizu_training.tscn"
const FINAL_TRAINING_SCENE := "res://scenes/episode_01/final_training_challenge.tscn"
const FINAL_SELECTION_SCENE := "res://scenes/episode_01/final_selection.tscn"
const POST_SELECTION_SCENE := "res://scenes/episode_01/post_selection_trio.tscn"
const TRIO_JOURNEY_SCENE := "res://scenes/episode_01/trio_mountain_journey.tscn"
const DRUM_HOUSE_SCENE := "res://scenes/episode_01/drum_house.tscn"

const OBJECTIVES := [
	"Go to the wood chopping area.",
	"Deliver the wood down the mountain.",
	"Return home before nightfall.",
	"Carry Nezuko down the mountain to find help.",
	"Face the swordsman on the mountain path.",
	"Find Shizu.",
]

@onready var player: ThirdPersonPlayer = $Player
@onready var objective_tracker: ObjectiveTracker = $ObjectiveTracker
@onready var objective_label: Label = %ObjectiveLabel
@onready var interaction_label: Label = %InteractionLabel
@onready var checkpoint_label: Label = %CheckpointLabel
@onready var intro_panel: Control = %IntroPanel
@onready var chopping_timer: Timer = $ChoppingTimer
@onready var wood_area: ChapterInteractable = $WoodChoppingArea
@onready var delivery_area: ChapterInteractable = $DeliveryPoint
@onready var home_area: ChapterInteractable = $HouseReturnPoint
@onready var descent_area: ChapterInteractable = $MountainDescentCheckpoint
@onready var player_camera: Camera3D = $Player/CameraPivot/SpringArm3D/Camera3D
@onready var cinematic_camera: Camera3D = $CinematicCamera
@onready var dialogue_label: Label = %DialogueLabel
@onready var nezuko_at_house: Node3D = $NezukoAtHouse
@onready var carried_nezuko: Node3D = $Player/CarriedNezuko
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var family_scene: Node3D = $FamilyScene
@onready var cinematic_shade: ColorRect = %CinematicShade
@onready var giyu_encounter: GiyuEncounter = $GiyuEncounter
@onready var shizu_route_area: Area3D = $GiyuEncounter/ShizuRouteMarker/RouteArea

var active_interactable: ChapterInteractable
var is_chopping: bool = false
var is_cinematic: bool = false
var journey_transition_started: bool = false

func _ready() -> void:
	if SaveManager.load_save() and GameManager.save_data.current_scene in [JOURNEY_SCENE, TRAINING_SCENE, FINAL_TRAINING_SCENE, FINAL_SELECTION_SCENE, POST_SELECTION_SCENE, TRIO_JOURNEY_SCENE, DRUM_HOUSE_SCENE]:
		call_deferred("_resume_saved_scene", GameManager.save_data.current_scene)
		return
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	player.interact_pressed.connect(_on_player_interact_pressed)
	objective_tracker.objective_changed.connect(_on_objective_changed)
	wood_area.activated.connect(_on_interactable_activated)
	delivery_area.activated.connect(_on_interactable_activated)
	home_area.activated.connect(_on_interactable_activated)
	descent_area.activated.connect(_on_interactable_activated)
	giyu_encounter.encounter_completed.connect(_on_giyu_encounter_completed)
	_load_chapter_state()
	await get_tree().create_timer(3.0).timeout
	intro_panel.visible = false

func _resume_saved_scene(scene_path: String) -> void:
	SceneManager.transition_to(scene_path)

func _process(_delta: float) -> void:
	active_interactable = _find_active_interactable()
	interaction_label.visible = active_interactable != null and not is_chopping and not is_cinematic and objective_tracker.current_step < COMPLETE_STEP
	if active_interactable != null:
		interaction_label.text = active_interactable.prompt_text
	if objective_tracker.current_step in [CARRY_STEP, GIYU_STEP] and descent_area.is_player_nearby(player) and not giyu_encounter.started:
		_begin_giyu_encounter()
	if objective_tracker.current_step == FIND_SHIZU_STEP and shizu_route_area.overlaps_body(player) and not journey_transition_started:
		_begin_journey_to_shizu()

func _find_active_interactable() -> ChapterInteractable:
	var candidates: Array[ChapterInteractable] = [wood_area, delivery_area, home_area, descent_area]
	var closest: ChapterInteractable
	var closest_distance := INF
	for candidate in candidates:
		if candidate.is_player_nearby(player):
			var distance := candidate.global_position.distance_squared_to(player.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest

func _on_player_interact_pressed() -> void:
	if active_interactable != null:
		active_interactable.activate()

func _on_interactable_activated(interactable_id: String) -> void:
	match interactable_id:
		"wood_chopping" when objective_tracker.current_step == WOOD_STEP and not is_chopping:
			is_chopping = true
			interaction_label.visible = false
			checkpoint_label.text = "Chopping wood..."
			checkpoint_label.visible = true
			chopping_timer.start()
		"delivery" when objective_tracker.current_step == DELIVERY_STEP:
			_set_step(RETURN_STEP)
			_checkpoint("Wood delivered - checkpoint saved")
		"home" when objective_tracker.current_step == RETURN_STEP:
			_begin_tragedy_sequence()
		"descent" when objective_tracker.current_step in [CARRY_STEP, GIYU_STEP]:
			_begin_giyu_encounter()

func _on_chopping_timer_timeout() -> void:
	is_chopping = false
	_set_step(DELIVERY_STEP)
	_checkpoint("Wood bundle received - checkpoint saved")

func _set_step(step: int) -> void:
	objective_tracker.set_objective(step, OBJECTIVES[step])
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 3 if step >= FIND_SHIZU_STEP else (2 if step >= CARRY_STEP else 1)
	data.current_scene = get_tree().current_scene.scene_file_path
	data.story_flags["chapter_01_objective_step"] = step
	data.story_flags["chapter_01_wood_chopped"] = step >= DELIVERY_STEP
	data.story_flags["chapter_01_wood_delivered"] = step >= RETURN_STEP
	data.story_flags["chapter_02_checkpoint_reached"] = step >= COMPLETE_STEP
	data.story_flags["giyu_encounter_objective_reached"] = step >= GIYU_STEP

func _checkpoint(message: String) -> void:
	SaveManager.save_checkpoint()
	checkpoint_label.text = message
	checkpoint_label.visible = true
	await get_tree().create_timer(2.5).timeout
	checkpoint_label.visible = false

func _load_chapter_state() -> void:
	var data := GameManager.save_data
	var step := WOOD_STEP
	if data.current_scene == get_tree().current_scene.scene_file_path:
		step = clampi(int(data.story_flags.get("chapter_01_objective_step", WOOD_STEP)), WOOD_STEP, COMPLETE_STEP)
	if bool(data.story_flags.get("shizu_location_received", false)):
		step = FIND_SHIZU_STEP
	_set_step(step)
	if bool(data.story_flags.get("family_tragedy_seen", false)):
		_apply_tragedy_atmosphere()
		family_scene.visible = true
	if step >= CARRY_STEP:
		carried_nezuko.visible = true
		player.carrying_companion = true
		nezuko_at_house.visible = false
	if step >= FIND_SHIZU_STEP:
		$GiyuEncounter/ShizuRouteMarker.visible = true
	elif step == GIYU_STEP and bool(data.story_flags.get("giyu_encounter_started", false)):
		call_deferred("_begin_giyu_encounter")

func _begin_tragedy_sequence() -> void:
	if is_cinematic:
		return
	is_cinematic = true
	player.set_controls_enabled(false)
	_apply_tragedy_atmosphere()
	family_scene.visible = true
	cinematic_shade.visible = true
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 2
	data.story_flags["family_tragedy_seen"] = true
	_checkpoint("Checkpoint saved")
	cinematic_camera.current = true
	_focus_cinematic(Vector3(-2.0, 3.3, 15.0), $House.global_position + Vector3(0.0, 1.1, 0.0))
	await _show_dialogue("The house is silent. Something is terribly wrong.", 3.0)
	await _move_cinematic(Vector3(-6.0, 2.4, 13.5), $House.global_position + Vector3(0.0, 0.9, 2.4), 2.5)
	await _move_cinematic(Vector3(-7.0, 1.85, 10.65), family_scene.global_position + Vector3(0.0, 0.35, 0.35), 1.5)
	await _move_cinematic(Vector3(-6.2, 1.6, 9.15), family_scene.global_position + Vector3(0.0, 0.25, 0.15), 1.4)
	await _show_dialogue("No... what happened here? Please, someone answer me.", 3.5)
	nezuko_at_house.visible = true
	await _move_cinematic(Vector3(-6.15, 1.25, 8.7), nezuko_at_house.global_position + Vector3(0.0, 0.1, 0.0), 1.6)
	await _show_dialogue("Nezuko? Wait... she is still breathing.", 3.0)
	await _show_dialogue("Hold on. I will carry you down the mountain and find help.", 3.5)
	nezuko_at_house.visible = false
	carried_nezuko.visible = true
	player.carrying_companion = true
	data.story_flags["nezuko_found"] = true
	data.story_flags["carrying_nezuko"] = true
	_set_step(CARRY_STEP)
	_checkpoint("Nezuko found - checkpoint saved")
	cinematic_shade.visible = false
	player_camera.current = true
	player.set_controls_enabled(true)
	is_cinematic = false

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

func _apply_tragedy_atmosphere() -> void:
	world_environment.environment.background_color = Color(0.035, 0.06, 0.12, 1.0)
	world_environment.environment.ambient_light_color = Color(0.22, 0.3, 0.48, 1.0)
	world_environment.environment.fog_light_color = Color(0.18, 0.24, 0.38, 1.0)
	$TragedyLight.visible = true

func _begin_giyu_encounter() -> void:
	if giyu_encounter.started or objective_tracker.current_step >= FIND_SHIZU_STEP:
		return
	is_cinematic = true
	_set_step(GIYU_STEP)
	giyu_encounter.start_encounter()

func _on_giyu_encounter_completed() -> void:
	_set_step(FIND_SHIZU_STEP)
	is_cinematic = false
	_checkpoint("Giyu encounter complete - checkpoint saved")

func _begin_journey_to_shizu() -> void:
	journey_transition_started = true
	var data := GameManager.save_data
	data.story_flags["journey_to_shizu_started"] = true
	data.current_scene = "res://scenes/episode_01/journey_to_shizu.tscn"
	data.player_position = Vector3(0.0, 1.0, 20.0)
	_checkpoint("Mountain route found - checkpoint saved")
	SceneManager.transition_to("res://scenes/episode_01/journey_to_shizu.tscn")

func _on_objective_changed(text: String, _step: int) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
