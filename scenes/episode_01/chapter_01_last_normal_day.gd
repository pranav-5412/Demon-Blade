extends Node3D

const WOOD_STEP := 0
const DELIVERY_STEP := 1
const RETURN_STEP := 2
const COMPLETE_STEP := 3

const OBJECTIVES := [
	"Go to the wood chopping area.",
	"Deliver the wood down the mountain.",
	"Return home before nightfall.",
	"Chapter 1 prototype complete.",
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

var active_interactable: ChapterInteractable
var is_chopping: bool = false

func _ready() -> void:
	player.interact_pressed.connect(_on_player_interact_pressed)
	objective_tracker.objective_changed.connect(_on_objective_changed)
	wood_area.activated.connect(_on_interactable_activated)
	delivery_area.activated.connect(_on_interactable_activated)
	home_area.activated.connect(_on_interactable_activated)
	_load_chapter_state()
	await get_tree().create_timer(3.0).timeout
	intro_panel.visible = false

func _process(_delta: float) -> void:
	active_interactable = _find_active_interactable()
	interaction_label.visible = active_interactable != null and not is_chopping and objective_tracker.current_step < COMPLETE_STEP
	if active_interactable != null:
		interaction_label.text = active_interactable.prompt_text

func _find_active_interactable() -> ChapterInteractable:
	var candidates: Array[ChapterInteractable] = [wood_area, delivery_area, home_area]
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
			_set_step(COMPLETE_STEP)
			_checkpoint("Chapter 1 prototype complete - checkpoint saved")

func _on_chopping_timer_timeout() -> void:
	is_chopping = false
	_set_step(DELIVERY_STEP)
	_checkpoint("Wood bundle received - checkpoint saved")

func _set_step(step: int) -> void:
	objective_tracker.set_objective(step, OBJECTIVES[step])
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = 1
	data.current_scene = get_tree().current_scene.scene_file_path
	data.story_flags["chapter_01_objective_step"] = step
	data.story_flags["chapter_01_wood_chopped"] = step >= DELIVERY_STEP
	data.story_flags["chapter_01_wood_delivered"] = step >= RETURN_STEP

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

func _on_objective_changed(text: String, _step: int) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
