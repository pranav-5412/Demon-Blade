class_name GiyuEncounter
extends Node3D

signal encounter_completed

enum TutorialPhase { INACTIVE, MOVEMENT, LOCK_ON, LIGHT_ATTACK, DODGE, GUARD, HEAVY_ATTACK, SPECIAL, COMPLETE }

@onready var player: ThirdPersonPlayer = $"../Player"
@onready var player_combat: PlayerCombatController = $"../Player/CombatController"
@onready var player_combatant: Combatant = $"../Player/CombatController/Combatant"
@onready var carried_nezuko: Node3D = $"../Player/CarriedNezuko"
@onready var player_camera: Camera3D = $"../Player/CameraPivot/SpringArm3D/Camera3D"
@onready var cinematic_camera: Camera3D = $"../CinematicCamera"
@onready var dialogue_label: Label = %DialogueLabel
@onready var tutorial_label: Label = %TutorialLabel
@onready var lock_on_label: Label = %LockOnLabel
@onready var milestone_label: Label = %MilestoneLabel
@onready var health_label: Label = $"../HUD/Health"
@onready var stamina_label: Label = $"../HUD/Stamina"
@onready var giyu: Node3D = $Giyu
@onready var giyu_controller: GiyuController = $Giyu/Controller
@onready var safe_nezuko: Node3D = $SafeNezuko
@onready var axe: Node3D = $Axe
@onready var rock: Node3D = $Rock
@onready var near_miss_vfx: MeshInstance3D = $NearMissVFX
@onready var route_marker: Node3D = $ShizuRouteMarker

var phase: TutorialPhase = TutorialPhase.INACTIVE
var started: bool = false
var movement_origin: Vector3
var lock_on_registered: bool = false
var light_attack_attempted: bool = false
var dodge_attempted: bool = false
var guard_registered: bool = false
var heavy_attack_attempted: bool = false
var special_action_pressed: bool = false

func _ready() -> void:
	giyu_controller.configure(player)
	player_combat.set_lock_target(giyu)
	player_combat.attack_performed.connect(_on_attack_performed)
	player_combat.dodge_performed.connect(_on_dodge_performed)
	player_combat.guard_changed.connect(_on_guard_changed)
	player_combat.lock_on_changed.connect(_on_lock_on_changed)
	player_combatant.health_changed.connect(_on_player_health_changed)
	player_combatant.defeated.connect(_on_player_defeated)
	player.interact_pressed.connect(_on_player_interact_pressed)
	player_combatant.max_health = player.max_health
	player_combatant.current_health = clampf(player.health, 0.0, player.max_health)
	set_process(true)
	_apply_loaded_state()

func _process(_delta: float) -> void:
	health_label.text = "Health: %d / %d" % [roundi(player_combatant.current_health), roundi(player_combatant.max_health)]
	stamina_label.text = "Stamina: %d" % roundi(player.stamina)
	lock_on_label.visible = started and player_combat.is_locked_on and phase < TutorialPhase.SPECIAL
	if phase == TutorialPhase.MOVEMENT and player.global_position.distance_to(movement_origin) >= 1.4:
		phase = TutorialPhase.LOCK_ON

func _apply_loaded_state() -> void:
	var flags := GameManager.save_data.story_flags
	if bool(flags.get("shizu_location_received", false)):
		route_marker.visible = true
		giyu.visible = false
		safe_nezuko.visible = false

func start_encounter() -> void:
	var data := GameManager.save_data
	var flags := data.story_flags
	if started or bool(flags.get("shizu_location_received", false)):
		return
	started = true
	data.story_flags["giyu_encounter_started"] = true
	SaveManager.save_checkpoint()
	player.set_controls_enabled(false)
	player_combat.set_combat_enabled(false)
	carried_nezuko.visible = false
	player.carrying_companion = false
	safe_nezuko.visible = true
	giyu.visible = true
	giyu_controller.set_active(false)
	if bool(flags.get("combat_tutorial_completed", false)):
		if bool(flags.get("axe_rock_sequence_completed", false)):
			cinematic_camera.current = true
			_focus_camera(giyu.global_position + Vector3(2.8, 1.8, 2.6), giyu.global_position + Vector3(0.0, 0.9, 0.0))
			await _show_dialogue("Giyu: Your strategy showed patience and instinct.", 2.4)
			await _show_dialogue("Giyu: Seek Shizu beyond the northern ridge. Proper training may save you both.", 3.2)
			await _finish_encounter()
		else:
			player_camera.current = true
			player.set_controls_enabled(true)
			await _run_axe_rock_sequence()
		return
	tutorial_label.text = "GIYU ENCOUNTER\nWatch his stance. A combat lesson is about to begin."
	tutorial_label.visible = true
	cinematic_camera.current = true
	_focus_camera(Vector3(4.5, 3.0, -46.0), giyu.global_position + Vector3(0.0, 1.0, 0.0))
	await _show_dialogue("Someone is waiting on the path ahead.", 2.0)
	await _move_camera(Vector3(2.7, 2.25, -51.5), giyu.global_position + Vector3(0.0, 0.9, 0.0), 1.8)
	await _show_dialogue("Giyu: Step away. The girl you carry may be dangerous.", 2.8)
	await _show_dialogue("Tanjiro: She is my family. I will not abandon her.", 2.8)
	player_camera.current = true
	player.stamina = player.max_stamina
	player.set_controls_enabled(true)
	player_combat.set_combat_enabled(true)
	giyu_controller.set_active(true)
	await _run_tutorial()

func _run_tutorial() -> void:
	phase = TutorialPhase.MOVEMENT
	movement_origin = player.global_position
	tutorial_label.text = "Move to avoid Giyu."
	tutorial_label.visible = true
	while phase == TutorialPhase.MOVEMENT:
		await get_tree().process_frame

	tutorial_label.text = "Lock on — Middle Mouse."
	lock_on_registered = false
	while not lock_on_registered:
		await get_tree().process_frame

	phase = TutorialPhase.LIGHT_ATTACK
	light_attack_attempted = false
	tutorial_label.text = "Light attack — Left Mouse."
	while not light_attack_attempted:
		await get_tree().process_frame

	phase = TutorialPhase.DODGE
	dodge_attempted = false
	tutorial_label.text = "Dodge Giyu's telegraphed attack — Ctrl."
	var dodge_succeeded := false
	while not dodge_succeeded:
		var dodge_result: Dictionary = await giyu_controller.perform_telegraphed_attack(player_combatant)
		dodge_succeeded = dodge_attempted and bool(dodge_result.get("avoided", false))
		if not dodge_succeeded:
			tutorial_label.text = "Watch the wind-up, then dodge — Ctrl."
			player_combatant.restore_full_health()
			dodge_attempted = false
	phase = TutorialPhase.GUARD

	guard_registered = false
	tutorial_label.text = "Hold guard against the next attack — Q."
	while not guard_registered:
		var guard_result: Dictionary = await giyu_controller.perform_telegraphed_attack(player_combatant)
		guard_registered = bool(guard_result.get("guarded", false))
		if not guard_registered:
			tutorial_label.text = "Hold guard before the sword lands."
			player_combatant.restore_full_health()

	phase = TutorialPhase.HEAVY_ATTACK
	heavy_attack_attempted = false
	tutorial_label.text = "Heavy attack — Right Mouse.\nGiyu cannot be defeated by ordinary attacks."
	while not heavy_attack_attempted:
		await get_tree().process_frame

	var data := GameManager.save_data
	data.story_flags["combat_tutorial_completed"] = true
	SaveManager.save_checkpoint()
	await _run_axe_rock_sequence()

func _run_axe_rock_sequence() -> void:
	phase = TutorialPhase.SPECIAL
	player_combat.set_combat_enabled(false)
	giyu_controller.set_active(false)
	tutorial_label.text = "Press E to use the axe and rock strategy."
	tutorial_label.visible = true
	special_action_pressed = false
	while not special_action_pressed:
		await get_tree().process_frame
	tutorial_label.visible = false
	player.set_controls_enabled(false)
	var retreat_target := giyu.global_position + Vector3(0.0, 0.0, 5.2)
	var retreat := create_tween()
	retreat.tween_property(player, "global_position", retreat_target, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await retreat.finished

	cinematic_camera.current = true
	_focus_camera(player.global_position + Vector3(3.8, 2.5, 3.5), giyu.global_position + Vector3(0.0, 0.8, 0.0))
	axe.global_position = player.global_position + Vector3(0.0, 1.0, -0.5)
	axe.visible = true
	rock.global_position = player.global_position + Vector3(0.35, 0.8, -0.2)
	rock.visible = true
	var old_giyu_position := giyu.global_position
	var axe_pass_position := old_giyu_position + (old_giyu_position - player.global_position).normalized() * 4.0 + Vector3(0.0, 1.0, 0.0)
	var axe_tween := create_tween()
	axe_tween.set_parallel(true)
	axe_tween.tween_property(axe, "global_position", axe_pass_position, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	axe_tween.tween_property(axe, "rotation", axe.rotation + Vector3(0.0, 0.0, TAU * 3.0), 0.9)
	await get_tree().create_timer(0.28).timeout
	var rush_target := old_giyu_position + Vector3(0.0, 0.0, 1.25)
	var rush := create_tween()
	rush.set_parallel(true)
	rush.tween_property(player, "global_position", rush_target, 0.58).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	rush.tween_property(rock, "global_position", rush_target + Vector3(0.25, 0.75, -0.15), 0.58).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.38).timeout
	Engine.time_scale = 0.35
	near_miss_vfx.global_position = old_giyu_position + Vector3(0.0, 1.0, 0.0)
	near_miss_vfx.visible = true
	giyu_controller.dodge_sideways()
	await get_tree().create_timer(0.55, true, false, true).timeout
	Engine.time_scale = 1.0
	if axe_tween.is_running():
		await axe_tween.finished
	if rush.is_running():
		await rush.finished
	_shake_camera()
	await get_tree().create_timer(0.25).timeout
	near_miss_vfx.visible = false
	axe.visible = false
	rock.visible = false

	var data := GameManager.save_data
	data.story_flags["axe_rock_sequence_completed"] = true
	SaveManager.save_checkpoint()
	await _move_camera(giyu.global_position + Vector3(2.8, 1.8, 2.6), giyu.global_position + Vector3(0.0, 0.9, 0.0), 0.8)
	await _show_dialogue("Giyu: That was no reckless charge. You planned the second strike.", 2.8)
	await _show_dialogue("Giyu: Seek Shizu beyond the northern ridge. Proper training may save you both.", 3.2)
	await _finish_encounter()

func _finish_encounter() -> void:
	phase = TutorialPhase.COMPLETE
	var data := GameManager.save_data
	data.chapter = 3
	data.story_flags["giyu_impressed"] = true
	data.story_flags["shizu_location_received"] = true
	SaveManager.save_checkpoint()
	var leave_tween := create_tween()
	leave_tween.tween_property(giyu, "global_position", giyu.global_position + Vector3(-5.0, 0.0, -5.0), 1.0)
	await leave_tween.finished
	giyu.visible = false
	safe_nezuko.visible = false
	carried_nezuko.visible = true
	player.carrying_companion = true
	route_marker.visible = true
	player_camera.current = true
	player.set_controls_enabled(true)
	milestone_label.text = "GIYU ENCOUNTER COMPLETE"
	milestone_label.visible = true
	encounter_completed.emit()
	await get_tree().create_timer(3.0).timeout
	milestone_label.visible = false

func _on_attack_performed(attack_type: String) -> void:
	if phase == TutorialPhase.LIGHT_ATTACK and attack_type == "light":
		giyu_controller.block_player_attack()
		light_attack_attempted = true
	elif phase == TutorialPhase.HEAVY_ATTACK and attack_type == "heavy":
		giyu_controller.block_player_attack()
		heavy_attack_attempted = true

func _on_dodge_performed() -> void:
	if phase == TutorialPhase.DODGE:
		dodge_attempted = true

func _on_guard_changed(is_guarding: bool) -> void:
	if phase == TutorialPhase.GUARD and not is_guarding:
		tutorial_label.text = "Keep holding Q until the sword lands."

func _on_lock_on_changed(is_locked: bool) -> void:
	if phase == TutorialPhase.LOCK_ON and is_locked:
		lock_on_registered = true

func _on_player_interact_pressed() -> void:
	if phase == TutorialPhase.SPECIAL:
		special_action_pressed = true

func _on_player_health_changed(current_health: float, _max_health: float) -> void:
	player.health = current_health

func _on_player_defeated() -> void:
	player_combatant.restore_full_health()
	player.global_position = movement_origin
	tutorial_label.text = "Recover and try this tutorial step again."

func _show_dialogue(line: String, duration: float) -> void:
	dialogue_label.text = line
	dialogue_label.visible = true
	await get_tree().create_timer(duration).timeout
	dialogue_label.visible = false

func _focus_camera(camera_position: Vector3, focus_position: Vector3) -> void:
	cinematic_camera.global_position = camera_position
	cinematic_camera.look_at(focus_position, Vector3.UP)

func _move_camera(camera_position: Vector3, focus_position: Vector3, duration: float) -> void:
	var target_transform := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus_position, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(cinematic_camera, "global_transform", target_transform, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _shake_camera() -> void:
	var origin := cinematic_camera.position
	var tween := create_tween()
	tween.tween_property(cinematic_camera, "position", origin + Vector3(0.07, 0.03, 0.0), 0.05)
	tween.tween_property(cinematic_camera, "position", origin - Vector3(0.05, 0.02, 0.0), 0.05)
	tween.tween_property(cinematic_camera, "position", origin, 0.08)
