extends Node3D

signal sound_hook_requested(hook_name: StringName)

enum ProgressState {
	APPROACH_MATERIAL,
	MATERIAL_MENU,
	MATERIAL_CONFIRM,
	APPROACH_ZENITSU,
	ZENITSU_TUTORIAL,
	APPROACH_INOSUKE,
	INOSUKE_TUTORIAL,
	COMPLETE,
}

const SCENE_PATH := "res://scenes/episode_01/post_selection_trio.tscn"
const TRIO_JOURNEY_SCENE := "res://scenes/episode_01/trio_mountain_journey.tscn"
const MATERIALS := [
	{"id": "balanced_ore", "name": "Riverstone Steel", "description": "A dependable alloy with an even temper.", "effect": "Balanced: +3% sword damage with no drawback."},
	{"id": "swift_alloy", "name": "Cloudsilver Alloy", "description": "A light metal that responds quickly to motion.", "effect": "Light: faster attacks, but slightly weaker heavy strikes."},
	{"id": "dense_iron", "name": "Deepforge Iron", "description": "A dense material built for committed blows.", "effect": "Dense: stronger heavy attacks with slower recovery."},
	{"id": "focused_steel", "name": "Tideglass Steel", "description": "A precise blade material that carries controlled breathing.", "effect": "Focused: faster Breath recovery and precise light damage."},
]

@onready var player: ThirdPersonPlayer = $Player
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var combatant: Combatant = $Player/CombatController/Combatant
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var party: PartyCharacterController = $Player/PartyCharacterController
@onready var zenitsu_npc: Node3D = $Characters/ZenitsuNPC
@onready var inosuke_npc: Node3D = $Characters/InosukeNPC
@onready var training_dummy: TrainingDummy = $TrainingDummy
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var ability_label: Label = $HUD/AbilityLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var title_label: Label = $HUD/TitleLabel
@onready var tutorial_label: Label = $HUD/TutorialLabel
@onready var selection_panel: Panel = $HUD/SelectionPanel
@onready var material_name: Label = $HUD/SelectionPanel/MaterialName
@onready var material_description: Label = $HUD/SelectionPanel/MaterialDescription
@onready var material_effect: Label = $HUD/SelectionPanel/MaterialEffect
@onready var confirmation_label: Label = $HUD/SelectionPanel/ConfirmationLabel
@onready var journey_exit: Node3D = $JourneyExit

var state := ProgressState.APPROACH_MATERIAL
var material_index := 0
var material_confirmation_pending := false
var dialogue_locked := false
var tutorial_progress: Dictionary = {}
var last_position := Vector3.ZERO
var feedback_time := 0.0
var party_companions_active := false
var active_character_id := "tanjiro"
var companion_ids: Array[String] = []
var journey_transition_started := false

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_configure_existing_progress()
	_connect_signals()
	_build_environment_details()
	_set_training_dummy_active(false)
	last_position = player.global_position
	_update_material_panel()
	_restore_progress_state()

func _process(delta: float) -> void:
	_update_hud()
	_update_interaction_prompt()
	_update_tutorial_movement()
	_update_party_companions(delta)
	if feedback_time > 0.0:
		feedback_time -= delta
		if feedback_time <= 0.0:
			feedback_label.visible = false
	if player.global_position.y < -3.0:
		_rescue_player()
	if state == ProgressState.COMPLETE and not journey_transition_started and player.global_position.distance_to(journey_exit.global_position) <= 3.0:
		_depart_for_mountain_journey()

func _unhandled_input(event: InputEvent) -> void:
	if state not in [ProgressState.MATERIAL_MENU, ProgressState.MATERIAL_CONFIRM]:
		return
	if event.is_action_pressed("move_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_LEFT):
		_select_previous_material()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_RIGHT):
		_select_next_material()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_confirm_material()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_cancel_material_confirmation()
		get_viewport().set_input_as_handled()

func _configure_existing_progress() -> void:
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = maxi(data.chapter, 8)
	data.current_scene = SCENE_PATH
	data.story_flags["final_selection_completed"] = true
	for form_number in range(1, 8):
		water.set_form_unlocked(form_number, true)
	party.initialize_from_save()
	combat.set_combat_enabled(true)
	combatant.max_health = player.max_health
	combatant.current_health = clampf(player.health, 1.0, player.max_health)

func _connect_signals() -> void:
	player.interact_pressed.connect(_on_interact)
	combat.attack_performed.connect(_on_attack_performed)
	combat.dodge_performed.connect(_on_dodge_performed)
	combatant.health_changed.connect(_on_health_changed)
	party.character_changed.connect(_on_character_changed)
	party.unique_ability_used.connect(_on_unique_ability_used)
	party.unique_ability_finished.connect(_on_unique_ability_finished)
	party.switch_rejected.connect(_show_feedback)
	party.hook_requested.connect(_on_party_hook)
	water.form_activated.connect(_on_water_form_activated)
	$HUD/SelectionPanel/PreviousButton.pressed.connect(_select_previous_material)
	$HUD/SelectionPanel/NextButton.pressed.connect(_select_next_material)
	$HUD/SelectionPanel/ConfirmButton.pressed.connect(_confirm_material)
	$HUD/SelectionPanel/CancelButton.pressed.connect(_cancel_material_confirmation)

func _restore_progress_state() -> void:
	var data := GameManager.save_data
	if bool(data.story_flags.get("character_switching_unlocked", false)):
		_enter_complete_state(false)
	elif bool(data.story_flags.get("inosuke_unlocked", false)):
		if bool(data.story_flags.get("inosuke_tutorial_completed", false)):
			_enter_complete_state(false)
		else:
			_begin_inosuke_tutorial(false)
	elif bool(data.story_flags.get("zenitsu_unlocked", false)):
		if bool(data.story_flags.get("zenitsu_tutorial_completed", false)):
			state = ProgressState.APPROACH_INOSUKE
			party.apply_character("tanjiro", false)
			_set_objective("Meet the fierce swordsman near the training clearing.")
			zenitsu_npc.visible = false
			inosuke_npc.visible = true
		else:
			_begin_zenitsu_tutorial(false)
	elif data.sword_material_selected:
		state = ProgressState.APPROACH_ZENITSU
		_set_objective("Speak with the nervous swordsman by the cedar gate.")
		zenitsu_npc.visible = true
		inosuke_npc.visible = false
	else:
		state = ProgressState.APPROACH_MATERIAL
		_set_objective("Choose your sword material.")
		zenitsu_npc.visible = false
		inosuke_npc.visible = false
	party.set_switching_allowed(state == ProgressState.COMPLETE)
	active_character_id = party.current_character
	journey_exit.visible = state == ProgressState.COMPLETE
	SaveManager.save_checkpoint()

func _on_interact() -> void:
	if dialogue_locked:
		return
	match state:
		ProgressState.APPROACH_MATERIAL:
			if player.global_position.distance_to($MaterialAltar.global_position) <= 3.2:
				_open_material_selection()
		ProgressState.APPROACH_ZENITSU:
			if player.global_position.distance_to(zenitsu_npc.global_position) <= 3.2:
				_introduce_zenitsu()
		ProgressState.APPROACH_INOSUKE:
			if player.global_position.distance_to(inosuke_npc.global_position) <= 3.2:
				_introduce_inosuke()

func _open_material_selection() -> void:
	if GameManager.save_data.sword_material_selected:
		return
	state = ProgressState.MATERIAL_MENU
	material_confirmation_pending = false
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	party.set_switching_allowed(false)
	selection_panel.visible = true
	_update_material_panel()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _select_previous_material() -> void:
	if state not in [ProgressState.MATERIAL_MENU, ProgressState.MATERIAL_CONFIRM]:
		return
	material_index = wrapi(material_index - 1, 0, MATERIALS.size())
	material_confirmation_pending = false
	state = ProgressState.MATERIAL_MENU
	_update_material_panel()

func _select_next_material() -> void:
	if state not in [ProgressState.MATERIAL_MENU, ProgressState.MATERIAL_CONFIRM]:
		return
	material_index = wrapi(material_index + 1, 0, MATERIALS.size())
	material_confirmation_pending = false
	state = ProgressState.MATERIAL_MENU
	_update_material_panel()

func _confirm_material() -> void:
	if GameManager.save_data.sword_material_selected or state not in [ProgressState.MATERIAL_MENU, ProgressState.MATERIAL_CONFIRM]:
		return
	if not material_confirmation_pending:
		material_confirmation_pending = true
		state = ProgressState.MATERIAL_CONFIRM
		confirmation_label.text = "Choose this material? Press Confirm again to lock the decision."
		return
	var choice: Dictionary = MATERIALS[material_index]
	var data := GameManager.save_data
	data.sword_material_selected = true
	data.sword_material = str(choice.id)
	data.story_flags["sword_material_selected"] = true
	data.story_flags["sword_material"] = str(choice.id)
	data.story_flags["post_selection_started"] = true
	data.current_playable_character = "tanjiro"
	party.apply_character("tanjiro", false)
	SaveManager.save_checkpoint()
	selection_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	state = ProgressState.APPROACH_ZENITSU
	zenitsu_npc.visible = true
	_set_objective("Speak with the nervous swordsman by the cedar gate.")
	_show_dialogue("Attendant: Your chosen material will be forged into a blade for the road ahead.", 3.0)
	_show_feedback("%s selected. The choice has been saved permanently." % str(choice.name))

func _cancel_material_confirmation() -> void:
	if state == ProgressState.MATERIAL_CONFIRM:
		material_confirmation_pending = false
		state = ProgressState.MATERIAL_MENU
		confirmation_label.text = "Left/Right or buttons to browse • E/Confirm to choose"
	elif state == ProgressState.MATERIAL_MENU:
		selection_panel.visible = false
		state = ProgressState.APPROACH_MATERIAL
		player.set_controls_enabled(true)
		combat.set_combat_enabled(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _introduce_zenitsu() -> void:
	if bool(GameManager.save_data.story_flags.get("zenitsu_met", false)):
		_begin_zenitsu_tutorial(false)
		return
	dialogue_locked = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	dialogue_label.text = "ZENITSU: I was hoping the road would be quiet. It never is, is it?\nTANJIRO: We can face it together. Show me how you move."
	dialogue_label.visible = true
	await get_tree().create_timer(2.2).timeout
	dialogue_label.visible = false
	GameManager.save_data.story_flags["zenitsu_met"] = true
	GameManager.save_data.story_flags["zenitsu_unlocked"] = true
	party.unlock_character("zenitsu")
	SaveManager.save_checkpoint()
	dialogue_locked = false
	_begin_zenitsu_tutorial(true)

func _begin_zenitsu_tutorial(show_notice: bool = true) -> void:
	state = ProgressState.ZENITSU_TUTORIAL
	zenitsu_npc.visible = false
	inosuke_npc.visible = false
	tutorial_progress = {"move": false, "dodge": false, "light": false, "ability": false}
	party.apply_character("zenitsu", true)
	party.set_switching_allowed(false)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	training_dummy.visible = true
	training_dummy.reset_dummy(180.0)
	_set_training_dummy_active(true)
	training_dummy.global_position = player.global_position - player.global_basis.z * 7.0
	combat.set_lock_target(training_dummy)
	_set_objective("Zenitsu trial: move, dodge, light attack, and use Lightning Step with 1.")
	if show_notice:
		_show_feedback("ZENITSU PLAYABLE — 1: Lightning Step • fast burst attacker")
	_update_tutorial_label()

func _finish_zenitsu_tutorial() -> void:
	if state != ProgressState.ZENITSU_TUTORIAL:
		return
	GameManager.save_data.story_flags["zenitsu_tutorial_completed"] = true
	SaveManager.save_checkpoint()
	state = ProgressState.APPROACH_INOSUKE
	party.apply_character("tanjiro", false)
	_set_training_dummy_active(false)
	combat.set_lock_target(null)
	inosuke_npc.visible = true
	tutorial_label.visible = false
	_set_objective("Meet the fierce swordsman near the training clearing.")
	_show_dialogue("A challenge rings out from the far side of the clearing.", 2.5)

func _introduce_inosuke() -> void:
	if bool(GameManager.save_data.story_flags.get("inosuke_met", false)):
		_begin_inosuke_tutorial(false)
		return
	dialogue_locked = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	dialogue_label.text = "INOSUKE: You two move too carefully. The mountain rewards momentum!\nTANJIRO: Then show us—and try not to destroy the clearing."
	dialogue_label.visible = true
	await get_tree().create_timer(2.2).timeout
	dialogue_label.visible = false
	GameManager.save_data.story_flags["inosuke_met"] = true
	GameManager.save_data.story_flags["inosuke_unlocked"] = true
	party.unlock_character("inosuke")
	SaveManager.save_checkpoint()
	dialogue_locked = false
	_begin_inosuke_tutorial(true)

func _begin_inosuke_tutorial(show_notice: bool = true) -> void:
	state = ProgressState.INOSUKE_TUTORIAL
	zenitsu_npc.visible = false
	inosuke_npc.visible = false
	tutorial_progress = {"light": false, "heavy": false, "dodge": false, "ability": false}
	party.apply_character("inosuke", true)
	party.set_switching_allowed(false)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	training_dummy.visible = true
	training_dummy.reset_dummy(220.0)
	_set_training_dummy_active(true)
	training_dummy.global_position = player.global_position - player.global_basis.z * 6.0
	combat.set_lock_target(training_dummy)
	_set_objective("Inosuke trial: dual light chain, heavy strike, dodge, and Beast Rush with 1.")
	if show_notice:
		_show_feedback("INOSUKE PLAYABLE — 1: Beast Rush • dual-blade pressure fighter")
	_update_tutorial_label()

func _finish_inosuke_tutorial() -> void:
	if state != ProgressState.INOSUKE_TUTORIAL:
		return
	GameManager.save_data.story_flags["inosuke_tutorial_completed"] = true
	SaveManager.save_checkpoint()
	_enter_complete_state(true)

func _enter_complete_state(show_notice: bool = true) -> void:
	state = ProgressState.COMPLETE
	_set_training_dummy_active(false)
	combat.set_lock_target(null)
	zenitsu_npc.visible = true
	inosuke_npc.visible = true
	zenitsu_npc.global_position = player.global_position + Vector3(-2.0, 0.0, 2.2)
	inosuke_npc.global_position = player.global_position + Vector3(2.0, 0.0, 2.2)
	tutorial_label.visible = false
	var data := GameManager.save_data
	data.story_flags["character_switching_unlocked"] = true
	data.story_flags["milestone_10_completed"] = true
	data.story_flags["next_objective"] = "Travel through the mountain with Zenitsu and Inosuke."
	data.chapter = maxi(data.chapter, 9)
	party.switching_unlocked = true
	party.set_switching_allowed(true)
	_set_current_character_if_needed()
	active_character_id = party.current_character
	party_companions_active = true
	journey_exit.visible = true
	_refresh_party_companions()
	_set_objective("Travel through the mountain with Zenitsu and Inosuke.")
	SaveManager.save_checkpoint()
	if show_notice:
		title_label.text = "CHARACTER SWITCHING UNLOCKED\nF1 Tanjiro • F2 Zenitsu • F3 Inosuke • T Cycle"
		title_label.visible = true
		await get_tree().create_timer(3.0).timeout
		title_label.visible = false
		_show_dialogue("The three swordsmen gather at the mountain road. Their journey has not begun yet.", 3.0)

func _set_current_character_if_needed() -> void:
	var requested := GameManager.save_data.current_playable_character.to_lower()
	if requested not in ["tanjiro", "zenitsu", "inosuke"]:
		party.apply_character("tanjiro", false)

func _depart_for_mountain_journey() -> void:
	journey_transition_started = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	title_label.text = "THE MOUNTAIN ROAD\nThe trio sets out together."
	title_label.visible = true
	GameManager.save_data.story_flags["trio_journey_started"] = true
	GameManager.save_data.current_scene = TRIO_JOURNEY_SCENE
	GameManager.save_data.player_position = Vector3(0, 1.2, 12)
	SaveManager.save_checkpoint()
	await get_tree().create_timer(1.8).timeout
	SceneManager.transition_to(TRIO_JOURNEY_SCENE)

func _on_attack_performed(attack_type: String) -> void:
	if state == ProgressState.ZENITSU_TUTORIAL and attack_type == "light":
		tutorial_progress.light = true
	elif state == ProgressState.INOSUKE_TUTORIAL:
		if attack_type == "light":
			tutorial_progress.light = true
		elif attack_type == "heavy":
			tutorial_progress.heavy = true
	_update_tutorial_and_check_completion()

func _on_dodge_performed() -> void:
	if state in [ProgressState.ZENITSU_TUTORIAL, ProgressState.INOSUKE_TUTORIAL]:
		tutorial_progress.dodge = true
		_update_tutorial_and_check_completion()

func _on_unique_ability_used(character_id: String, _ability_name: String) -> void:
	if state == ProgressState.ZENITSU_TUTORIAL and character_id == "zenitsu":
		tutorial_progress.ability = true
	elif state == ProgressState.INOSUKE_TUTORIAL and character_id == "inosuke":
		tutorial_progress.ability = true
	_update_tutorial_label()

func _on_unique_ability_finished(character_id: String, _ability_name: String) -> void:
	if (state == ProgressState.ZENITSU_TUTORIAL and character_id == "zenitsu") or (state == ProgressState.INOSUKE_TUTORIAL and character_id == "inosuke"):
		_update_tutorial_and_check_completion()

func _update_tutorial_movement() -> void:
	if state == ProgressState.ZENITSU_TUTORIAL and player.global_position.distance_to(last_position) > 0.65:
		tutorial_progress.move = true
		last_position = player.global_position
		_update_tutorial_and_check_completion()
	elif state not in [ProgressState.ZENITSU_TUTORIAL, ProgressState.INOSUKE_TUTORIAL]:
		last_position = player.global_position

func _update_tutorial_and_check_completion() -> void:
	_update_tutorial_label()
	for value in tutorial_progress.values():
		if not bool(value):
			return
	if state == ProgressState.ZENITSU_TUTORIAL:
		_finish_zenitsu_tutorial()
	elif state == ProgressState.INOSUKE_TUTORIAL:
		_finish_inosuke_tutorial()

func _update_tutorial_label() -> void:
	if state == ProgressState.ZENITSU_TUTORIAL:
		tutorial_label.text = "ZENITSU QUICK TEST\n%s Move   %s Ctrl Dodge   %s Light Attack   %s 1 Lightning Step" % [_mark("move"), _mark("dodge"), _mark("light"), _mark("ability")]
	elif state == ProgressState.INOSUKE_TUTORIAL:
		tutorial_label.text = "INOSUKE QUICK TEST\n%s Dual Light   %s Heavy Attack   %s Ctrl Dodge   %s 1 Beast Rush" % [_mark("light"), _mark("heavy"), _mark("dodge"), _mark("ability")]
	tutorial_label.visible = state in [ProgressState.ZENITSU_TUTORIAL, ProgressState.INOSUKE_TUTORIAL]

func _mark(key: String) -> String:
	return "[DONE]" if bool(tutorial_progress.get(key, false)) else "[  ]"

func _update_hud() -> void:
	status_label.text = "%s\nHealth: %d / %d\nStamina: %d / %d" % [party.get_display_name(), roundi(player.health), roundi(player.max_health), roundi(player.stamina), roundi(player.max_stamina)]
	if party.current_character == "tanjiro":
		ability_label.text = "WATER BREATHING: %d / %d\n1–7 Water Forms • Ctrl Dodge • Q Guard" % [roundi(breathing.current_breath), roundi(breathing.max_breath)]
	else:
		var remaining := party.get_cooldown_remaining()
		ability_label.text = "%s: %s\nPress 1 • Ctrl Dodge • Q Guard" % [party.get_ability_name().to_upper(), "READY" if remaining <= 0.0 else "%.1fs" % remaining]

func _update_interaction_prompt() -> void:
	interaction_label.visible = false
	if dialogue_locked or state in [ProgressState.MATERIAL_MENU, ProgressState.MATERIAL_CONFIRM]:
		return
	if state == ProgressState.APPROACH_MATERIAL and player.global_position.distance_to($MaterialAltar.global_position) <= 3.2:
		interaction_label.text = "Press E to inspect sword materials"
		interaction_label.visible = true
	elif state == ProgressState.APPROACH_ZENITSU and player.global_position.distance_to(zenitsu_npc.global_position) <= 3.2:
		interaction_label.text = "Press E to speak with Zenitsu"
		interaction_label.visible = true
	elif state == ProgressState.APPROACH_INOSUKE and player.global_position.distance_to(inosuke_npc.global_position) <= 3.2:
		interaction_label.text = "Press E to answer Inosuke's challenge"
		interaction_label.visible = true

func _update_material_panel() -> void:
	var choice: Dictionary = MATERIALS[material_index]
	material_name.text = "%d / %d   %s" % [material_index + 1, MATERIALS.size(), str(choice.name)]
	material_description.text = str(choice.description)
	material_effect.text = str(choice.effect)
	confirmation_label.text = "Choose this material? Press Confirm again to lock the decision." if material_confirmation_pending else "Left/Right or buttons to browse • E/Confirm to choose"

func _on_character_changed(character_id: String, display_name: String) -> void:
	var previous_character := active_character_id
	active_character_id = character_id
	if party_companions_active:
		_refresh_party_companions(previous_character)
	_show_feedback("Active character: %s" % display_name)

func _on_health_changed(current: float, _maximum: float) -> void:
	player.health = current

func _on_water_form_activated(_form_number: int, ability_name: String) -> void:
	_show_feedback("Tanjiro used %s" % ability_name)

func _on_party_hook(_hook_type: StringName, hook_name: StringName) -> void:
	sound_hook_requested.emit(hook_name)

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["post_selection_objective"] = text

func _show_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true
	feedback_time = 3.0

func _show_dialogue(text: String, duration: float) -> void:
	dialogue_label.text = text
	dialogue_label.visible = true
	var expected_text := text
	await get_tree().create_timer(duration).timeout
	if dialogue_label.text == expected_text:
		dialogue_label.visible = false

func _rescue_player() -> void:
	player.global_position = Vector3(0, 1.2, 9)
	player.velocity = Vector3.ZERO
	_show_feedback("Unsafe position corrected — returned to the selection grounds.")

func _set_training_dummy_active(value: bool) -> void:
	training_dummy.visible = value
	var hurtbox := training_dummy.get_node("Hurtbox") as Area3D
	hurtbox.set_deferred("monitorable", value)

func _refresh_party_companions(previous_character: String = "") -> void:
	var inactive_ids: Array[String] = []
	if not previous_character.is_empty() and previous_character != active_character_id:
		inactive_ids.append(previous_character)
	for character_id in ["tanjiro", "zenitsu", "inosuke"]:
		if character_id != active_character_id and character_id not in inactive_ids:
			inactive_ids.append(character_id)
	companion_ids = inactive_ids
	_configure_companion(zenitsu_npc, inactive_ids[0])
	_configure_companion(inosuke_npc, inactive_ids[1])
	zenitsu_npc.visible = true
	inosuke_npc.visible = true
	zenitsu_npc.global_position = _companion_target_position(0)
	inosuke_npc.global_position = _companion_target_position(1)

func _update_party_companions(delta: float) -> void:
	if not party_companions_active:
		return
	for slot_index in 2:
		var companion := zenitsu_npc if slot_index == 0 else inosuke_npc
		var target := _companion_target_position(slot_index)
		companion.global_position = companion.global_position.lerp(target, minf(delta * 7.0, 1.0))
		var face_target := player.global_position
		face_target.y = companion.global_position.y
		if companion.global_position.distance_squared_to(face_target) > 0.05:
			companion.look_at(face_target, Vector3.UP)

func _companion_target_position(slot_index: int) -> Vector3:
	var side := -1.55 if slot_index == 0 else 1.55
	var offset := player.global_basis.x * side + player.global_basis.z * 1.75
	var target := player.global_position + offset
	target.y = _ground_height_at(target)
	return target

func _ground_height_at(position: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3(0.0, 20.0, 0.0), position + Vector3(0.0, -30.0, 0.0))
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.get("position", position).y) if not hit.is_empty() else 0.0

func _configure_companion(companion: Node3D, character_id: String) -> void:
	companion.name = "%sCompanion" % character_id.capitalize()
	var profile: Dictionary = PartyCharacterController.PROFILES[character_id]
	_set_companion_mesh_color(companion.get_node("Body") as MeshInstance3D, profile.color)
	_set_companion_mesh_color(companion.get_node("Head") as MeshInstance3D, profile.head_color)
	var left_blade := _ensure_companion_blade(companion, "BladeLeft", Vector3(-0.42, 0.92, 0), 18.0)
	var right_blade := _ensure_companion_blade(companion, "BladeRight", Vector3(0.42, 0.92, 0), -18.0)
	left_blade.visible = true
	right_blade.visible = character_id == "inosuke"
	_set_companion_mesh_color(left_blade, _companion_blade_color(character_id))
	_set_companion_mesh_color(right_blade, _companion_blade_color(character_id))
	var nameplate := companion.get_node_or_null("Nameplate") as Label3D
	if nameplate == null:
		nameplate = Label3D.new()
		nameplate.name = "Nameplate"
		nameplate.position = Vector3(0, 2.25, 0)
		nameplate.font_size = 36
		nameplate.outline_size = 4
		companion.add_child(nameplate)
	nameplate.text = str(profile.name)

func _ensure_companion_blade(companion: Node3D, blade_name: String, local_position: Vector3, z_rotation: float) -> MeshInstance3D:
	var blade := companion.get_node_or_null(blade_name) as MeshInstance3D
	if blade == null:
		blade = MeshInstance3D.new()
		blade.name = blade_name
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 1.35, 0.1)
		blade.mesh = mesh
		companion.add_child(blade)
	blade.position = local_position
	blade.rotation_degrees = Vector3(0, 0, z_rotation)
	return blade

func _set_companion_mesh_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	mesh_instance.material_override = material

func _companion_blade_color(character_id: String) -> Color:
	match character_id:
		"zenitsu": return Color(1.0, 0.78, 0.16)
		"inosuke": return Color(0.68, 0.72, 0.74)
		_: return Color(0.72, 0.76, 0.82)

func _build_environment_details() -> void:
	for position in [Vector3(-13, 0, 8), Vector3(13, 0, 8), Vector3(-14, 0, -6), Vector3(14, 0, -7), Vector3(-11, 0, -18), Vector3(11, 0, -18)]:
		_add_tree(position)
	for position in [Vector3(-5, 0, 3), Vector3(6, 0, -4), Vector3(-7, 0, -13), Vector3(7, 0, -17)]:
		_add_rock(position)

func _add_tree(position: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = position
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 4.0
	trunk.mesh = trunk_mesh
	trunk.position.y = 2.0
	tree.add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.5
	crown_mesh.height = 4.2
	crown.mesh = crown_mesh
	crown.position.y = 5.0
	tree.add_child(crown)
	$EnvironmentGeometry.add_child(tree)

func _add_rock(position: Vector3) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.1
	rock.mesh = mesh
	rock.scale = Vector3(1.4, 0.8, 1.0)
	rock.position = position + Vector3(0, 0.5, 0)
	$EnvironmentGeometry.add_child(rock)
