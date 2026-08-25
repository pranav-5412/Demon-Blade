extends Node3D

signal final_slash_confirmed
signal sound_hook_requested(hook_name: StringName)

const FINAL_SCENE := "res://scenes/episode_01/final_training_challenge.tscn"

enum Phase { APPROACH, FAILED_ATTEMPT, TRIAL_A, TRIAL_B, RETURN_TO_BOULDER, FINAL_CUT, COMPLETE }

@onready var player: ThirdPersonPlayer = $Player
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var player_combatant: Combatant = $Player/CombatController/Combatant
@onready var player_hitbox: CombatHitbox = $Player/CombatController/Hitbox
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var player_camera: Camera3D = $Player/CameraPivot/SpringArm3D/Camera3D
@onready var cinematic_camera: Camera3D = $CinematicCamera
@onready var approach_area: Area3D = $Triggers/BoulderApproach
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var breathing_label: Label = $HUD/BreathingLabel
@onready var form_label: Label = $HUD/FormLabel
@onready var trial_label: Label = $HUD/TrialLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var milestone_label: Label = $HUD/MilestoneLabel

var phase := Phase.APPROACH
var sequence_busy := false
var awaiting_final_slash := false
var companion_a: TrainingMemoryCompanion
var companion_b: TrainingMemoryCompanion
var intact_collision: CollisionShape3D
var split_collisions: Array[CollisionShape3D] = []
var split_left: Node3D
var split_right: Node3D
var a_defense_complete := false
var a_precision_complete := false
var a_water_complete := false
var a_dodge_during_telegraph := false
var b_dodge_during_telegraph := false
var b_counter_ready := false
var b_counters := 0

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_build_environment()
	_build_boulder()
	_build_companions()
	_connect_combat()
	var data := GameManager.save_data
	data.episode = 1
	data.chapter = maxi(data.chapter, 5)
	data.current_scene = FINAL_SCENE
	data.story_flags["training_completed"] = true
	var repaired_unlocks := _configure_player_systems()
	_apply_saved_progress()
	if repaired_unlocks:
		_checkpoint()
	set_process(true)

func _process(_delta: float) -> void:
	status_label.text = "TANJIRO\nHealth: %d\nStamina: %d" % [roundi(player.health), roundi(player.stamina)]
	breathing_label.text = "BREATH: %d / %d" % [roundi(breathing.current_breath), roundi(breathing.max_breath)]
	if phase == Phase.APPROACH and not sequence_busy and approach_area.overlaps_body(player):
		_run_failed_attempt()
	interaction_label.visible = phase == Phase.RETURN_TO_BOULDER and not sequence_busy and approach_area.overlaps_body(player)

func _unhandled_input(event: InputEvent) -> void:
	if awaiting_final_slash and event.is_action_pressed("ability_7"):
		awaiting_final_slash = false
		final_slash_confirmed.emit()
		get_viewport().set_input_as_handled()

func _connect_combat() -> void:
	combat.dodge_performed.connect(_on_player_dodge)
	player_hitbox.hit_landed.connect(_on_basic_hit_landed)
	water.form_activated.connect(_on_form_activated)
	water.form_hit.connect(_on_water_hit)
	water.form_failed.connect(_show_trial_message)
	player_combatant.health_changed.connect(_on_player_health_changed)
	player_combatant.defeated.connect(_on_player_defeated)
	player.interact_pressed.connect(_on_player_interact_pressed)

func _configure_player_systems() -> bool:
	combat.set_combat_enabled(true)
	player_combatant.max_health = player.max_health
	player_combatant.current_health = maxf(1.0, clampf(player.health, 0.0, player.max_health))
	player.health = player_combatant.current_health
	breathing.set_unlocked(true)
	breathing.refill(breathing.max_breath)
	water.set_enabled(true)
	var completed_training := bool(GameManager.save_data.story_flags.get("training_completed", false))
	var repaired_unlocks := false
	for form_number in range(1, 8):
		var flag := "water_form_%d_unlocked" % form_number
		var unlocked := completed_training or bool(GameManager.save_data.story_flags.get(flag, false))
		water.set_form_unlocked(form_number, unlocked)
		if completed_training and not bool(GameManager.save_data.story_flags.get(flag, false)):
			GameManager.save_data.story_flags[flag] = true
			repaired_unlocks = true
	form_label.text = "ACTIVE WATER FORM: NONE\nPress 1–7 to activate an unlocked form."
	return repaired_unlocks

func _apply_saved_progress() -> void:
	var flags := GameManager.save_data.story_flags
	if bool(flags.get("boulder_cut", false)):
		phase = Phase.COMPLETE
		_show_split_state()
		companion_a.set_manifested(false)
		companion_b.set_manifested(false)
		_set_objective("Prepare for Final Selection.")
		milestone_label.text = "Training Complete"
		milestone_label.visible = true
		trial_label.text = "The boulder remains split. Final Selection has not begun."
		return
	_show_intact_state()
	if bool(flags.get("companion_b_trial_complete", false)):
		phase = Phase.RETURN_TO_BOULDER
		companion_a.set_manifested(true)
		companion_b.set_manifested(true)
		companion_a.position = Vector3(-7, 1, 5)
		companion_b.position = Vector3(7, 1, 5)
		_set_objective("Cut the boulder.")
		trial_label.text = "Return to the boulder and press E to begin the final attempt."
	elif bool(flags.get("companion_a_trial_complete", false)):
		phase = Phase.TRIAL_B
		companion_a.set_manifested(true)
		companion_b.set_manifested(true)
		companion_a.position = Vector3(-7, 1, 5)
		companion_b.position = Vector3(0, 1, -3)
		call_deferred("_start_trial_b", true)
	elif bool(flags.get("boulder_challenge_started", false)):
		phase = Phase.TRIAL_A
		companion_a.set_manifested(true)
		companion_b.set_manifested(true)
		companion_a.position = Vector3(0, 1, -4)
		companion_b.position = Vector3(7, 1, 5)
		call_deferred("_start_trial_a", true)
	else:
		phase = Phase.APPROACH
		companion_a.set_manifested(false)
		companion_b.set_manifested(false)
		_set_objective("Approach the final boulder.")
		trial_label.text = "Shizu's last challenge waits across the clearing."
		if not bool(flags.get("final_training_intro_seen", false)):
			call_deferred("_run_shizu_challenge_intro")

func _run_shizu_challenge_intro() -> void:
	if sequence_busy or phase != Phase.APPROACH:
		return
	sequence_busy = true
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	await _start_cinematic(Vector3(11, 4.8, 15), $Shizu.global_position + Vector3(0, 0.8, 0), 0.8)
	await _show_dialogue("Shizu: The drills are finished. One task remains before I can send you onward.", 3.2)
	await _show_dialogue("Shizu: Cross the clearing and cut the boulder. Do not expect stone to yield to effort alone.", 3.6)
	GameManager.save_data.story_flags["final_training_intro_seen"] = true
	_checkpoint()
	_end_cinematic()
	combat.set_combat_enabled(true)
	player.set_controls_enabled(true)
	sequence_busy = false

func _run_failed_attempt() -> void:
	if sequence_busy or phase != Phase.APPROACH:
		return
	sequence_busy = true
	phase = Phase.FAILED_ATTEMPT
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	interaction_label.visible = false
	_set_cinematic_hud(true)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 1, -14.2)
	player.look_at($Boulder.global_position + Vector3(0, 1.8, 0), Vector3.UP)
	await _start_cinematic(Vector3(9.5, 4.8, -9.5), Vector3(0, 2.3, -21), 1.0)
	await _show_dialogue("Tanjiro: This is the last wall between me and the next trial.", 2.7)
	await _move_camera(Vector3(3.8, 2.4, -12.0), player.global_position + Vector3(0, 0.7, 0), 0.75)
	var original_rotation := player.visual.rotation
	var attempt := create_tween()
	attempt.tween_property(player.visual, "rotation:z", -0.72, 0.55).set_trans(Tween.TRANS_SINE)
	attempt.tween_property(player.visual, "rotation:z", 0.48, 0.16).set_trans(Tween.TRANS_EXPO)
	attempt.tween_property(player.visual, "rotation", original_rotation, 0.28)
	await attempt.finished
	sound_hook_requested.emit(&"boulder_failed_impact")
	await _subtle_camera_shake(0.13)
	await _move_camera(Vector3(-7.5, 4.2, -13.0), Vector3(0, 2.3, -22), 0.65)
	await _show_dialogue("Tanjiro: Not even a mark... Strength alone is not enough.", 3.0)
	GameManager.save_data.story_flags["boulder_challenge_started"] = true
	_set_objective("Find a way to overcome the final challenge.")
	_checkpoint()
	await _reveal_companions()
	_set_cinematic_hud(false)
	_end_cinematic()
	combat.set_combat_enabled(true)
	player.set_controls_enabled(true)
	sequence_busy = false
	_start_trial_a(false)

func _reveal_companions() -> void:
	$MemoryLight.light_energy = 0.0
	var environment: Environment = $WorldEnvironment.environment
	var original_density: float = environment.fog_density
	var fog_tween := create_tween()
	fog_tween.parallel().tween_property($MemoryLight, "light_energy", 3.2, 0.8)
	fog_tween.parallel().tween_property(environment, "fog_density", 0.024, 0.8)
	companion_a.position = Vector3(-3.2, 1, -5)
	companion_b.position = Vector3(4.8, 1, -2)
	companion_a.manifest()
	await get_tree().create_timer(0.35).timeout
	companion_b.manifest()
	await get_tree().create_timer(0.8).timeout
	await _show_dialogue("Tanjiro: Who are you? Are you truly standing here?", 2.7)
	await _show_dialogue("Still Echo: Names will not move the stone. Show me the instant your breathing becomes action.", 3.4)
	environment.fog_density = original_density

func _start_trial_a(resuming: bool = false) -> void:
	if phase == Phase.COMPLETE or bool(GameManager.save_data.story_flags.get("companion_a_trial_complete", false)):
		return
	phase = Phase.TRIAL_A
	a_defense_complete = false
	a_precision_complete = false
	a_water_complete = false
	a_dodge_during_telegraph = false
	companion_a.position = Vector3(0, 1, -4)
	companion_a.set_manifested(true)
	companion_b.position = Vector3(7, 1, 5)
	companion_b.set_manifested(true)
	combat.set_lock_target(companion_a)
	_set_objective("Precision trial: defend, counter during the blue opening, and land a Water Form.")
	trial_label.text = "COMPANION A — PRECISION\nDefense 0/1  Timed counter 0/1  Water Form 0/1"
	if resuming:
		_show_trial_message("Checkpoint restored: watch the red telegraph, then answer during the blue opening.")
	companion_a.start_trial()

func _on_a_telegraph(_duration: float) -> void:
	a_dodge_during_telegraph = false
	_show_trial_message("Red telegraph — hold Q to guard or press Ctrl/Space to dodge.")

func _on_a_attack_resolved(avoided: bool, guarded: bool) -> void:
	if phase != Phase.TRIAL_A:
		return
	if guarded or (avoided and a_dodge_during_telegraph):
		a_defense_complete = true
		_show_trial_message("Defense accepted. Blue opening — strike with precise timing.")
	else:
		_show_trial_message("That was not a deliberate defense. Read the red telegraph and guard or dodge.")
	_update_trial_a_hud()
	_check_trial_a_complete()

func _update_trial_a_hud() -> void:
	trial_label.text = "COMPANION A — PRECISION\nDefense %d/1  Timed counter %d/1  Water Form %d/1" % [int(a_defense_complete), int(a_precision_complete), int(a_water_complete)]

func _check_trial_a_complete() -> void:
	if a_defense_complete and a_precision_complete and a_water_complete and not sequence_busy:
		sequence_busy = true
		call_deferred("_finish_trial_a")

func _finish_trial_a() -> void:
	companion_a.stop_trial()
	GameManager.save_data.story_flags["companion_a_trial_complete"] = true
	_checkpoint()
	_show_trial_message("Companion A trial complete — checkpoint saved")
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	await _show_dialogue("Still Echo: Precision is restraint. You moved only when the opening was real.", 3.0)
	await _show_dialogue("Swift Echo: Then let us see whether that focus survives motion.", 2.7)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	sequence_busy = false
	_start_trial_b(false)

func _start_trial_b(resuming: bool = false) -> void:
	if phase == Phase.COMPLETE or bool(GameManager.save_data.story_flags.get("companion_b_trial_complete", false)):
		return
	phase = Phase.TRIAL_B
	b_dodge_during_telegraph = false
	b_counter_ready = false
	b_counters = 0
	companion_a.position = Vector3(-7, 1, 5)
	companion_a.set_manifested(true)
	companion_b.set_manifested(true)
	combat.set_lock_target(companion_b)
	_set_objective("Reaction trial: dodge each fast strike, reposition, and counter during the blue opening.")
	trial_label.text = "COMPANION B — SPEED / REACTION\nDodge-and-counter sequences: 0 / 3"
	if resuming:
		_show_trial_message("Checkpoint restored: chase the moving target and dodge during each red telegraph.")
	companion_b.start_trial()

func _on_b_telegraph(_duration: float) -> void:
	b_dodge_during_telegraph = false
	b_counter_ready = false
	_show_trial_message("Fast red telegraph — dodge now, then close the distance for the blue opening.")

func _on_b_attack_resolved(avoided: bool, _guarded: bool) -> void:
	if phase != Phase.TRIAL_B:
		return
	b_counter_ready = avoided and b_dodge_during_telegraph
	if b_counter_ready:
		_show_trial_message("Clean dodge. Counter before the blue opening closes.")
	else:
		_show_trial_message("Only a timed dodge creates a valid counter in this trial.")

func _complete_b_counter() -> void:
	if not b_counter_ready or not companion_b.accepts_counter():
		_show_trial_message("Wait for a clean dodge and the blue counter opening.")
		return
	b_counter_ready = false
	b_counters += 1
	companion_b.accept_counter()
	trial_label.text = "COMPANION B — SPEED / REACTION\nDodge-and-counter sequences: %d / 3" % mini(b_counters, 3)
	_show_trial_message("Reaction sequence %d / 3" % mini(b_counters, 3))
	if b_counters >= 3 and not sequence_busy:
		sequence_busy = true
		call_deferred("_finish_trial_b")

func _finish_trial_b() -> void:
	companion_b.stop_trial()
	GameManager.save_data.story_flags["companion_b_trial_complete"] = true
	_checkpoint()
	_show_trial_message("Companion B trial complete — checkpoint saved")
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	await _show_dialogue("Swift Echo: Speed without awareness is only panic. You chose where to be.", 3.0)
	await _show_dialogue("Still Echo: Breath, timing, technique, focus. Commit them to one cut.", 3.1)
	await _show_dialogue("Tanjiro: I understand. The stone is not asking for more force. It is asking for everything at once.", 3.4)
	phase = Phase.RETURN_TO_BOULDER
	companion_a.position = Vector3(-7, 1, 5)
	companion_b.position = Vector3(7, 1, 5)
	combat.set_lock_target(null)
	_set_objective("Cut the boulder.")
	trial_label.text = "Return to the boulder. Press E when you are ready."
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	sequence_busy = false

func _on_player_dodge() -> void:
	if phase == Phase.TRIAL_A and companion_a.telegraph_active:
		a_dodge_during_telegraph = true
	elif phase == Phase.TRIAL_B and companion_b.telegraph_active:
		b_dodge_during_telegraph = true

func _on_basic_hit_landed(target: CombatHurtbox) -> void:
	if phase == Phase.TRIAL_A and target == companion_a.hurtbox and companion_a.accepts_counter():
		a_precision_complete = true
		companion_a.accept_counter()
		_show_trial_message("Precise counter accepted.")
		_update_trial_a_hud()
		_check_trial_a_complete()
	elif phase == Phase.TRIAL_B and target == companion_b.hurtbox:
		_complete_b_counter()

func _on_water_hit(_form_number: int, target: CombatHurtbox) -> void:
	if phase == Phase.TRIAL_A and target == companion_a.hurtbox and companion_a.accepts_counter():
		a_water_complete = true
		companion_a.accept_counter()
		_show_trial_message("Water Form landed inside the timing window.")
		_update_trial_a_hud()
		_check_trial_a_complete()
	elif phase == Phase.TRIAL_B and target == companion_b.hurtbox:
		_complete_b_counter()

func _on_form_activated(form_number: int, ability_name: String) -> void:
	form_label.text = "ACTIVE WATER FORM: %d — %s\nPress 1–7 to activate an unlocked form." % [form_number, ability_name]

func _on_player_interact_pressed() -> void:
	if phase == Phase.RETURN_TO_BOULDER and not sequence_busy and approach_area.overlaps_body(player):
		_run_final_cut()

func _run_final_cut() -> void:
	if sequence_busy or phase != Phase.RETURN_TO_BOULDER:
		return
	sequence_busy = true
	phase = Phase.FINAL_CUT
	interaction_label.visible = false
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	companion_a.stop_trial()
	companion_b.stop_trial()
	_set_cinematic_hud(true)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 1, -14.2)
	player.look_at($Boulder.global_position + Vector3(0, 1.8, 0), Vector3.UP)
	await _start_cinematic(Vector3(10.5, 5.6, -10.5), Vector3(0, 2.2, -21.5), 1.0)
	await _move_camera(Vector3(3.2, 2.5, -12.2), player.global_position + Vector3(0, 0.65, 0), 0.8)
	var stance := create_tween()
	stance.tween_property(player.visual, "rotation:z", -0.48, 0.65).set_trans(Tween.TRANS_SINE)
	await stance.finished
	breathing.refill(breathing.max_breath)
	player.stamina = player.max_stamina
	water.cooldown_ends[7] = 0.0
	water.set_enabled(false)
	trial_label.text = "FINAL CUT\nPress 7 to commit Seventh Form: Piercing Drop"
	trial_label.visible = true
	awaiting_final_slash = true
	await final_slash_confirmed
	trial_label.text = "Breath • Timing • Technique • Focus"
	water.set_enabled(true)
	sound_hook_requested.emit(&"final_breath_focus")
	Engine.time_scale = 0.38
	var activated := await water.activate_form(7)
	Engine.time_scale = 1.0
	if not activated:
		breathing.refill(breathing.max_breath)
		player.stamina = player.max_stamina
		water.cooldown_ends[7] = 0.0
		water.set_form_unlocked(7, true)
		activated = await water.activate_form(7)
	if not activated:
		phase = Phase.RETURN_TO_BOULDER
		_set_objective("Cut the boulder.")
		_set_cinematic_hud(false)
		_end_cinematic()
		combat.set_combat_enabled(true)
		player.set_controls_enabled(true)
		sequence_busy = false
		_show_trial_message("The final Water Form did not activate. Return to the boulder and press E to retry.")
		return
	await _move_camera(Vector3(-5.8, 3.2, -18.0), Vector3(0, 2.4, -22), 0.38)
	await get_tree().create_timer(0.28).timeout
	sound_hook_requested.emit(&"boulder_crack")
	await _split_boulder()
	GameManager.save_data.story_flags["final_training_complete"] = true
	GameManager.save_data.story_flags["boulder_cut"] = true
	GameManager.save_data.chapter = 6
	_checkpoint()
	await _subtle_camera_shake(0.22)
	await _move_camera(Vector3(11.5, 6.0, -8.5), Vector3(0, 2.0, -22), 0.9)
	await _show_dialogue("Tanjiro: The cut happened before doubt could interrupt it.", 2.8)
	await _show_dialogue("Shizu: Now your strength has direction. Your training is complete.", 3.0)
	await _show_dialogue("Shizu: The next test is Final Selection. Prepare yourself before you leave this mountain.", 3.4)
	phase = Phase.COMPLETE
	_set_objective("Prepare for Final Selection.")
	_checkpoint()
	_set_cinematic_hud(false)
	_end_cinematic()
	trial_label.text = "The final challenge is complete. Final Selection has not begun."
	milestone_label.text = "Training Complete"
	milestone_label.visible = true
	combat.set_combat_enabled(false)
	player.set_controls_enabled(true)
	sequence_busy = false

func _split_boulder() -> void:
	$Boulder/Intact.visible = false
	intact_collision.set_deferred("disabled", true)
	$Boulder/SplitHalves.visible = true
	for collision in split_collisions:
		collision.set_deferred("disabled", false)
	_spawn_dust_and_debris()
	var left_target := split_left.position + Vector3(-1.15, -0.12, 0.15)
	var right_target := split_right.position + Vector3(1.15, -0.12, -0.12)
	var split_tween := create_tween()
	split_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	split_tween.parallel().tween_property(split_left, "position", left_target, 0.85)
	split_tween.parallel().tween_property(split_right, "position", right_target, 0.85)
	split_tween.parallel().tween_property(split_left, "rotation:z", 0.16, 0.85)
	split_tween.parallel().tween_property(split_right, "rotation:z", -0.16, 0.85)
	await split_tween.finished

func _show_intact_state() -> void:
	$Boulder/Intact.visible = true
	$Boulder/SplitHalves.visible = false
	intact_collision.set_deferred("disabled", false)
	for collision in split_collisions:
		collision.set_deferred("disabled", true)

func _show_split_state() -> void:
	$Boulder/Intact.visible = false
	$Boulder/SplitHalves.visible = true
	intact_collision.set_deferred("disabled", true)
	for collision in split_collisions:
		collision.set_deferred("disabled", false)
	if is_instance_valid(split_left):
		split_left.position = Vector3(-2.15, 2.7, 0.15)
		split_left.rotation.z = 0.16
	if is_instance_valid(split_right):
		split_right.position = Vector3(2.15, 2.7, -0.12)
		split_right.rotation.z = -0.16

func _checkpoint() -> void:
	var data := GameManager.save_data
	data.current_scene = FINAL_SCENE
	data.player_position = player.global_position
	data.player_health = player.health
	data.player_stamina = player.stamina
	SaveManager.save_checkpoint()

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["final_training_objective"] = text

func _show_trial_message(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true

func _on_player_health_changed(current_health: float, _maximum: float) -> void:
	player.health = current_health

func _on_player_defeated() -> void:
	player_combatant.restore_full_health()
	player.stamina = player.max_stamina
	player.global_position = Vector3(0, 1, 6)
	_show_trial_message("You recovered at the edge of the clearing. The current trial continues.")

func _set_cinematic_hud(value: bool) -> void:
	status_label.visible = not value
	objective_label.visible = not value
	breathing_label.visible = not value
	form_label.visible = not value
	feedback_label.visible = not value
	interaction_label.visible = false
	if value:
		trial_label.text = ""

func _show_dialogue(line: String, duration: float) -> void:
	dialogue_label.text = line
	dialogue_label.visible = true
	await get_tree().create_timer(duration).timeout
	dialogue_label.visible = false

func _start_cinematic(position: Vector3, target: Vector3, duration: float) -> void:
	var start_transform := player_camera.global_transform
	cinematic_camera.global_transform = start_transform
	cinematic_camera.current = true
	await _move_camera(position, target, duration)

func _move_camera(position: Vector3, target: Vector3, duration: float) -> void:
	var target_transform := Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cinematic_camera, "global_transform", target_transform, duration)
	await tween.finished

func _end_cinematic() -> void:
	player_camera.current = true

func _subtle_camera_shake(strength: float) -> void:
	var origin := cinematic_camera.position
	var tween := create_tween()
	tween.tween_property(cinematic_camera, "position", origin + Vector3(strength, 0.04, 0), 0.045)
	tween.tween_property(cinematic_camera, "position", origin + Vector3(-strength * 0.7, -0.03, 0), 0.055)
	tween.tween_property(cinematic_camera, "position", origin, 0.07)
	await tween.finished

func _build_companions() -> void:
	companion_a = TrainingMemoryCompanion.new()
	companion_a.name = "CompanionAStillEcho"
	$Companions.add_child(companion_a)
	companion_a.configure(player, player_combatant, "precision", [])
	companion_a.telegraph_started.connect(_on_a_telegraph)
	companion_a.attack_resolved.connect(_on_a_attack_resolved)
	companion_b = TrainingMemoryCompanion.new()
	companion_b.name = "CompanionBSwiftEcho"
	$Companions.add_child(companion_b)
	var speed_positions: Array[Vector3] = [Vector3(-7, 1, -2), Vector3(7, 1, -5), Vector3(0, 1, -10), Vector3(-5, 1, -12), Vector3(6, 1, 0)]
	companion_b.configure(player, player_combatant, "speed", speed_positions)
	companion_b.telegraph_started.connect(_on_b_telegraph)
	companion_b.attack_resolved.connect(_on_b_attack_resolved)

func _build_environment() -> void:
	_add_static_box("ClearingGround", Vector3(42, 0.8, 48), Vector3(0, -0.4, -4), Color(0.16, 0.23, 0.15, 1), Vector3.ZERO)
	_add_static_box("NorthRockShelf", Vector3(42, 3.5, 5), Vector3(0, 1.1, -29), Color(0.19, 0.22, 0.23, 1), Vector3(2, 0, 0))
	_add_static_box("WestRidge", Vector3(5, 4.5, 42), Vector3(-22, 1.7, -5), Color(0.16, 0.2, 0.22, 1), Vector3(0, 0, -6))
	_add_static_box("EastRidge", Vector3(5, 6.0, 42), Vector3(22, 2.4, -5), Color(0.16, 0.2, 0.22, 1), Vector3(0, 0, 7))
	_add_static_box("EntryRise", Vector3(12, 0.5, 8), Vector3(0, 0.25, 14), Color(0.25, 0.2, 0.13, 1), Vector3(-4, 0, 0))
	for position in [Vector3(-14, 0, 10), Vector3(14, 0, 8), Vector3(-16, 0, -8), Vector3(16, 0, -13), Vector3(-12, 0, -22), Vector3(12, 0, -24)]:
		_add_tree(position, 0.9 + absf(position.x) * 0.015)
	for position in [Vector3(-9, 0.5, -17), Vector3(10, 0.4, -16), Vector3(-13, 0.6, 2), Vector3(13, 0.7, -1), Vector3(-7, 0.3, 12)]:
		_add_rock(position, Vector3(1.2, 0.8, 1.0))

func _build_boulder() -> void:
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.22, 0.25, 0.27, 1.0)
	rock_material.roughness = 0.96
	for lump in [
		{"position": Vector3(0, 2.75, 0), "scale": Vector3(3.5, 2.8, 2.65), "rotation": Vector3(0, 0, 7)},
		{"position": Vector3(-1.6, 2.2, 0.2), "scale": Vector3(1.8, 2.0, 2.25), "rotation": Vector3(0, 18, -9)},
		{"position": Vector3(1.7, 2.05, -0.2), "scale": Vector3(1.65, 1.8, 2.15), "rotation": Vector3(0, -16, 11)},
	]:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 20
		mesh.rings = 10
		mesh.material = rock_material
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.position = lump.position
		visual.scale = lump.scale
		visual.rotation_degrees = lump.rotation
		$Boulder/Intact.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "IntactCollisionBody"
	body.position = Vector3(0, 2.65, 0)
	intact_collision = CollisionShape3D.new()
	var intact_shape := BoxShape3D.new()
	intact_shape.size = Vector3(7.0, 5.5, 5.2)
	intact_collision.shape = intact_shape
	body.add_child(intact_collision)
	$Boulder/Intact.add_child(body)
	split_left = _create_boulder_half("LeftHalf", Vector3(-1.0, 2.7, 0), Vector3(1.75, 2.7, 2.5), rock_material)
	split_right = _create_boulder_half("RightHalf", Vector3(1.0, 2.7, 0), Vector3(1.75, 2.7, 2.5), rock_material)

func _create_boulder_half(label: String, position: Vector3, half_scale: Vector3, material: StandardMaterial3D) -> Node3D:
	var half := Node3D.new()
	half.name = label
	half.position = position
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = half_scale
	half.add_child(visual)
	var crack_material := StandardMaterial3D.new()
	crack_material.albedo_color = Color(0.055, 0.065, 0.07, 1.0)
	var crack_mesh := BoxMesh.new()
	crack_mesh.size = Vector3(0.08, 4.8, 4.2)
	crack_mesh.material = crack_material
	var crack_face := MeshInstance3D.new()
	crack_face.mesh = crack_mesh
	crack_face.position.x = 1.72 if label == "LeftHalf" else -1.72
	half.add_child(crack_face)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4, 5.2, 4.8)
	collision.shape = shape
	collision.disabled = true
	body.add_child(collision)
	half.add_child(body)
	split_collisions.append(collision)
	$Boulder/SplitHalves.add_child(half)
	return half

func _spawn_dust_and_debris() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "BoulderDust"
	dust.position = Vector3(0, 2.3, 0.2)
	dust.amount = 56
	dust.lifetime = 1.6
	dust.one_shot = true
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(1.4, 2.0, 1.2)
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 78.0
	process_material.initial_velocity_min = 1.8
	process_material.initial_velocity_max = 4.8
	process_material.gravity = Vector3(0, -5.5, 0)
	dust.process_material = process_material
	var dust_material := StandardMaterial3D.new()
	dust_material.albedo_color = Color(0.5, 0.46, 0.4, 0.78)
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.11
	dust_mesh.height = 0.22
	dust_mesh.material = dust_material
	dust.draw_pass_1 = dust_mesh
	$Boulder/Effects.add_child(dust)
	dust.emitting = true
	for index in 8:
		var debris_mesh := BoxMesh.new()
		debris_mesh.size = Vector3.ONE * (0.16 + index * 0.025)
		debris_mesh.material = dust_material
		var debris := MeshInstance3D.new()
		debris.mesh = debris_mesh
		debris.position = Vector3(0, 2.5 + index * 0.12, 0)
		$Boulder/Effects.add_child(debris)
		var side := -1.0 if index % 2 == 0 else 1.0
		var target := debris.position + Vector3(side * (1.4 + index * 0.22), -1.8, (index % 3 - 1) * 0.7)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(debris, "position", target, 0.8 + index * 0.03)
		tween.parallel().tween_property(debris, "rotation", Vector3(index, index * 0.7, index * 0.4), 0.8)
		tween.tween_callback(debris.queue_free)

func _add_static_box(label: String, size: Vector3, position: Vector3, color: Color, rotation_degrees_value: Vector3) -> void:
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
	visual.rotation_degrees = rotation_degrees_value
	$EnvironmentGeometry.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sBody" % label
	body.position = position
	body.rotation_degrees = rotation_degrees_value
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	$EnvironmentGeometry.add_child(body)

func _add_tree(position: Vector3, scale_factor: float) -> void:
	var tree := Node3D.new()
	tree.position = position
	tree.scale = Vector3.ONE * scale_factor
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.16, 0.09, 0.04, 1)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 3.4
	trunk_mesh.material = trunk_material
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.7
	tree.add_child(trunk)
	var crown_material := StandardMaterial3D.new()
	crown_material.albedo_color = Color(0.055, 0.16, 0.13, 1)
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.35
	crown_mesh.height = 3.8
	crown_mesh.material = crown_material
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.position.y = 4.0
	tree.add_child(crown)
	$EnvironmentGeometry.add_child(tree)

func _add_rock(position: Vector3, rock_scale: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.23, 0.24, 1)
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.material = material
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.position = position
	rock.scale = rock_scale
	rock.rotation_degrees = Vector3(0, position.x * 3.0, position.z * 2.0)
	$EnvironmentGeometry.add_child(rock)
