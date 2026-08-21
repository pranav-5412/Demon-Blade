extends Node3D

const WOOD_STEP := 0
const DELIVERY_STEP := 1
const RETURN_STEP := 2
const CARRY_STEP := 3
const COMPLETE_STEP := 4

const OBJECTIVES := [
	"Go to the wood chopping area.",
	"Deliver the wood down the mountain.",
	"Return home before nightfall.",
	"Carry Nezuko down the mountain to find help.",
	"Chapter 2 prototype complete.",
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

var active_interactable: ChapterInteractable
var is_chopping: bool = false
var is_cinematic: bool = false

func _ready() -> void:
	player.interact_pressed.connect(_on_player_interact_pressed)
	objective_tracker.objective_changed.connect(_on_objective_changed)
	wood_area.activated.connect(_on_interactable_activated)
	delivery_area.activated.connect(_on_interactable_activated)
	home_area.activated.connect(_on_interactable_activated)
	descent_area.activated.connect(_on_interactable_activated)
	_load_chapter_state()
	await get_tree().create_timer(3.0).timeout
	intro_panel.visible = false

func _process(_delta: float) -> void:
	active_interactable = _find_active_interactable()
	interaction_label.visible = active_interactable != null and not is_chopping and not is_cinematic and objective_tracker.current_step < COMPLETE_STEP
	if active_interactable != null:
		interaction_label.text = active_interactable.prompt_text

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
		"descent" when objective_tracker.current_step == CARRY_STEP:
			_set_step(COMPLETE_STEP)
			_checkpoint("Chapter 2 prototype complete - checkpoint saved")

func _on_chopping_timer_timeout() -> void:
	is_chopping = false
	_set_step(DELIVERY_STEP)
	_checkpoint("Wood bundle received - checkpoint saved")

func _set_step(step: int) -> void:
	objective_tracker.set_objective(step, OBJECTIVES[step])
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 2 if step >= CARRY_STEP else 1
	data.current_scene = get_tree().current_scene.scene_file_path
	data.story_flags["chapter_01_objective_step"] = step
	data.story_flags["chapter_01_wood_chopped"] = step >= DELIVERY_STEP
	data.story_flags["chapter_01_wood_delivered"] = step >= RETURN_STEP
	data.story_flags["chapter_02_checkpoint_reached"] = step >= COMPLETE_STEP

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
	_set_step(step)
	if bool(data.story_flags.get("family_tragedy_seen", false)):
		_apply_tragedy_atmosphere()
	if step >= CARRY_STEP:
		carried_nezuko.visible = true
		player.carrying_companion = true
		nezuko_at_house.visible = false

func _begin_tragedy_sequence() -> void:
	if is_cinematic:
		return
	is_cinematic = true
	player.set_controls_enabled(false)
	_apply_tragedy_atmosphere()
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 2
	data.story_flags["family_tragedy_seen"] = true
	_checkpoint("Checkpoint saved")
	cinematic_camera.global_position = Vector3(-0.5, 3.8, 14.0)
	cinematic_camera.look_at($House.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)
	cinematic_camera.current = true
	await _show_dialogue("The air feels wrong. The house is silent.", 2.5)
	await _show_dialogue("Something terrible has happened here.", 2.5)
	nezuko_at_house.visible = true
	await _show_dialogue("One person is still breathing. I have to get her help.", 3.0)
	nezuko_at_house.visible = false
	carried_nezuko.visible = true
	player.carrying_companion = true
	data.story_flags["nezuko_found"] = true
	data.story_flags["carrying_nezuko"] = true
	_set_step(CARRY_STEP)
	_checkpoint("Nezuko found - checkpoint saved")
	player_camera.current = true
	player.set_controls_enabled(true)
	is_cinematic = false

func _show_dialogue(line: String, duration: float) -> void:
	dialogue_label.text = line
	dialogue_label.visible = true
	await get_tree().create_timer(duration).timeout
	dialogue_label.visible = false

func _apply_tragedy_atmosphere() -> void:
	world_environment.environment.background_color = Color(0.035, 0.06, 0.12, 1.0)
	world_environment.environment.ambient_light_color = Color(0.22, 0.3, 0.48, 1.0)
	world_environment.environment.fog_light_color = Color(0.18, 0.24, 0.38, 1.0)

func _on_objective_changed(text: String, _step: int) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
