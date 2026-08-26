extends Node3D

signal sound_hook_requested(hook_name: StringName)

const SCENE_PATH := "res://scenes/episode_01/drum_house.tscn"
const DEMON_SCRIPT := preload("res://combat/demon_enemy.gd")
const DRUM_DEMON_SCRIPT := preload("res://scenes/episode_01/drum_demon.gd")
const PUZZLE_SEQUENCE := [1, 2, 3]

@onready var player: ThirdPersonPlayer = $Player
@onready var party: PartyCharacterController = $Player/PartyCharacterController
@onready var companions: Node3D = $PartyCompanions
@onready var combat: PlayerCombatController = $Player/CombatController
@onready var player_combatant: Combatant = $Player/CombatController/Combatant
@onready var breathing: BreathingController = $Player/BreathingController
@onready var water: WaterBreathingController = $Player/WaterBreathingController
@onready var puzzle_room: Node3D = $PuzzleRoom
@onready var trap_room: Node3D = $TrapRoom
@onready var objective_label: Label = $HUD/ObjectiveLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var ability_label: Label = $HUD/AbilityLabel
@onready var area_label: Label = $HUD/AreaLabel
@onready var dialogue_label: Label = $HUD/DialogueLabel
@onready var interaction_label: Label = $HUD/InteractionLabel
@onready var feedback_label: Label = $HUD/FeedbackLabel
@onready var boss_panel: Control = $HUD/BossPanel
@onready var boss_health: ProgressBar = $HUD/BossPanel/BossHealth
@onready var boss_phase_label: Label = $HUD/BossPanel/BossPhase

var progress := 0
var puzzle_step := 0
var active_enemies: Array[DemonEnemy] = []
var boss
var sequence_busy := false
var gallery_spawned := false
var trap_started := false
var boss_room_state := 0
var feedback_time := 0.0
var last_checkpoint := Vector3(0, 1.1, 22)

func _ready() -> void:
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_build_house_geometry()
	_build_boss_arena_states()
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
	if player.global_position.y < -8.0:
		_rescue_player()
	if sequence_busy:
		interaction_label.visible = false
		return
	_update_progress_triggers()
	_update_interaction_prompt()

func _configure_party() -> void:
	var data := GameManager.save_data
	data.current_scene = SCENE_PATH
	data.story_flags["drum_house_entered"] = true
	data.story_flags["zenitsu_unlocked"] = true
	data.story_flags["inosuke_unlocked"] = true
	data.story_flags["character_switching_unlocked"] = true
	for form_number in range(1, 8):
		water.set_form_unlocked(form_number, bool(data.story_flags.get("water_form_%d_unlocked" % form_number, true)))
	party.initialize_from_save()
	party.switching_unlocked = true
	party.set_switching_allowed(true)
	combat.set_combat_enabled(true)
	player_combatant.max_health = player.max_health
	player_combatant.current_health = clampf(player.health, 1.0, player.max_health)

func _connect_signals() -> void:
	player.interact_pressed.connect(_on_interact)
	party.character_changed.connect(_on_character_changed)
	party.switch_rejected.connect(_show_feedback)
	player_combatant.health_changed.connect(_on_player_health_changed)
	player_combatant.defeated.connect(_on_player_defeated)
	puzzle_room.rotation_started.connect(_on_rotation_started)
	puzzle_room.rotation_finished.connect(_on_puzzle_rotation_finished)
	trap_room.rotation_started.connect(_on_rotation_started)
	trap_room.rotation_finished.connect(_on_trap_rotation_finished)

func _restore_progress() -> void:
	var data := GameManager.save_data
	progress = clampi(int(data.story_flags.get("drum_house_progress", 0)), 0, 6)
	puzzle_step = clampi(int(data.story_flags.get("drum_puzzle_step", 0)), 0, PUZZLE_SEQUENCE.size())
	var puzzle_complete := bool(data.story_flags.get("drum_house_puzzle_complete", data.story_flags.get("drum_puzzle_complete", false))) or progress >= 2
	puzzle_room.restore_state(int(data.story_flags.get("drum_room_orientation", 0)), puzzle_complete)
	trap_room.restore_state(int(data.story_flags.get("drum_trap_orientation", 0)), progress >= 4)
	trap_room.set_route_open(progress >= 4)
	if progress >= 6 or bool(data.story_flags.get("drum_demon_defeated", false)):
		progress = 6
		player.global_position = Vector3(0, 1.1, -91)
		last_checkpoint = player.global_position
		_show_aftermath_state()
	elif progress == 5:
		player.global_position = Vector3(0, 1.1, -85)
		last_checkpoint = Vector3(0, 1.1, -82)
		boss_room_state = clampi(int(data.story_flags.get("drum_boss_room_state", 0)), 0, 3)
		_apply_boss_room_state(boss_room_state)
		$BossShiftVisual.rotation_degrees.z = float(boss_room_state * 90)
		_set_area("DRUM HEART")
		_set_objective("Defeat the Drum Demon.")
		_spawn_boss(false)
	elif progress >= 4:
		player.global_position = Vector3(0, 1.1, -68)
		last_checkpoint = player.global_position
		_set_area("HEART HALL")
		_set_objective("Enter the heart of the Drum House.")
	elif progress >= 2:
		player.global_position = Vector3(0, 1.1, -31)
		last_checkpoint = player.global_position
		if bool(data.story_flags.get("drum_gallery_cleared", false)):
			progress = 3
			_set_area("SHIFTING GALLERY")
			_set_objective("Cross the shifting room ahead.")
		else:
			_spawn_gallery_enemies()
	else:
		player.global_position = Vector3(0, 1.1, 22)
		_set_area("ENTRY HALL")
		_set_objective("Investigate the strange house.")
	companions.force_catch_up()
	SaveManager.save_checkpoint()

func _update_progress_triggers() -> void:
	if progress == 0 and player.global_position.z < 6.0:
		progress = 1
		_set_area("DRUM CHAMBER")
		_set_objective("Align the chamber seals. Strike the drum with E: I → II → III.")
		_show_dialogue("ZENITSU: The hall moved behind us. Houses should not do that.\nINOSUKE: Then we make it stop.")
		_save_progress(Vector3(0, 1.1, 3))
	elif progress == 2 and player.global_position.z < -27.0 and not gallery_spawned:
		_spawn_gallery_enemies()
	elif progress == 3 and player.global_position.z < -52.0 and not trap_started:
		_begin_trap_rotation()
	elif progress == 4 and player.global_position.z < -76.0:
		_begin_boss_intro()

func _update_interaction_prompt() -> void:
	interaction_label.visible = false
	if progress == 1 and player.global_position.distance_to(Vector3(0, 1.1, -11.5)) <= 4.0:
		interaction_label.text = "Press E to strike the drum — target seal %s" % _roman(PUZZLE_SEQUENCE[puzzle_step])
		interaction_label.visible = true

func _on_interact() -> void:
	if progress != 1 or sequence_busy or player.global_position.distance_to(Vector3(0, 1.1, -11.5)) > 4.0:
		return
	sequence_busy = true
	player.global_position = puzzle_room.get_safe_position()
	player.velocity = Vector3.ZERO
	puzzle_room.rotate_room(1)

func _on_rotation_started(target_state: int) -> void:
	sequence_busy = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	companions.set_follow_enabled(false)
	sound_hook_requested.emit(&"drum_room_rotate")
	_camera_reaction(0.035)
	_show_feedback("The room is turning... orientation %s" % _roman(target_state))

func _on_puzzle_rotation_finished(current_state: int) -> void:
	player.global_position = puzzle_room.get_safe_position()
	player.velocity = Vector3.ZERO
	GameManager.save_data.story_flags["drum_room_orientation"] = current_state
	if progress == 1 and current_state == PUZZLE_SEQUENCE[puzzle_step]:
		puzzle_step += 1
		GameManager.save_data.story_flags["drum_puzzle_step"] = puzzle_step
		_show_feedback("Seal %s aligned. (%d / %d)" % [_roman(current_state), puzzle_step, PUZZLE_SEQUENCE.size()])
		if puzzle_step >= PUZZLE_SEQUENCE.size():
			puzzle_room.set_route_open(true)
			progress = 2
			GameManager.save_data.story_flags["drum_puzzle_complete"] = true
			GameManager.save_data.story_flags["drum_house_puzzle_complete"] = true
			_set_area("SHIFTING GALLERY")
			_set_objective("Cross the opened gallery and defeat the house demons.")
			_save_progress(puzzle_room.get_safe_position())
	elif progress == 1:
		_show_feedback("Seal %s is not next. Rotate toward seal %s." % [_roman(current_state), _roman(PUZZLE_SEQUENCE[puzzle_step])])
	_finish_rotation_lock()

func _begin_trap_rotation() -> void:
	trap_started = true
	player.global_position = trap_room.get_safe_position()
	player.velocity = Vector3.ZERO
	trap_room.rotate_room(2)

func _on_trap_rotation_finished(current_state: int) -> void:
	player.global_position = trap_room.get_safe_position()
	player.velocity = Vector3.ZERO
	trap_room.set_route_open(true)
	progress = 4
	GameManager.save_data.story_flags["drum_trap_complete"] = true
	GameManager.save_data.story_flags["drum_trap_orientation"] = current_state
	_set_area("HEART HALL")
	_set_objective("Enter the heart of the Drum House.")
	_save_progress(player.global_position)
	_finish_rotation_lock()

func _finish_rotation_lock() -> void:
	companions.force_catch_up()
	companions.set_follow_enabled(true)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	sequence_busy = false
	SaveManager.save_checkpoint()

func _spawn_gallery_enemies() -> void:
	if gallery_spawned or bool(GameManager.save_data.story_flags.get("drum_gallery_cleared", false)):
		return
	gallery_spawned = true
	progress = 2
	_set_area("SHIFTING GALLERY")
	for enemy_data in [["standard", Vector3(-4, 0.05, -34)], ["fast", Vector3(4, 0.05, -38)], ["ranged", Vector3(0, 0.05, -43)]]:
		var enemy := DEMON_SCRIPT.new() as DemonEnemy
		$Enemies.add_child(enemy)
		enemy.global_position = enemy_data[1] as Vector3
		enemy.configure(str(enemy_data[0]), player, player_combatant)
		enemy.died.connect(_on_gallery_enemy_died)
		active_enemies.append(enemy)
	_set_objective("Defeat the demons inside the shifting gallery. (3 remaining)")

func _on_gallery_enemy_died(enemy: DemonEnemy, reward: int, _kind: String) -> void:
	active_enemies.erase(enemy)
	GameManager.save_data.wan_currency += reward
	if active_enemies.is_empty():
		progress = 3
		GameManager.save_data.story_flags["drum_gallery_cleared"] = true
		_set_objective("Cross the shifting room ahead.")
		_show_feedback("The gallery is clear. A drum sounds deeper inside.")
		_save_progress(Vector3(0, 1.1, -45))
	else:
		_set_objective("Defeat the demons inside the shifting gallery. (%d remaining)" % active_enemies.size())

func _begin_boss_intro() -> void:
	if sequence_busy or is_instance_valid(boss):
		return
	sequence_busy = true
	progress = 5
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	companions.set_follow_enabled(false)
	_set_area("DRUM HEART")
	_set_objective("Defeat the Drum Demon.")
	dialogue_label.text = "DRUM DEMON: Every beat of this house obeys me.\nTANJIRO: Then we end the rhythm here."
	dialogue_label.visible = true
	GameManager.save_data.story_flags["drum_boss_started"] = true
	GameManager.save_data.story_flags["drum_demon_started"] = true
	_save_progress(Vector3(0, 1.1, -82))
	await get_tree().create_timer(2.4).timeout
	dialogue_label.visible = false
	_spawn_boss(true)
	companions.force_catch_up()
	companions.set_follow_enabled(true)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	sequence_busy = false

func _spawn_boss(fresh: bool) -> void:
	if is_instance_valid(boss):
		return
	boss = DRUM_DEMON_SCRIPT.new()
	$Enemies.add_child(boss)
	boss.global_position = Vector3(0, 0.05, -93)
	boss.configure_drum_boss(player, player_combatant)
	boss.health_updated.connect(_on_boss_health_updated)
	boss.phase_changed.connect(_on_boss_phase_changed)
	boss.attack_telegraphed.connect(_on_boss_attack_telegraphed)
	boss.room_manipulation_requested.connect(_on_boss_room_manipulation)
	boss.died.connect(_on_boss_defeated)
	if not fresh:
		boss.current_phase = clampi(int(GameManager.save_data.story_flags.get("drum_demon_phase", GameManager.save_data.story_flags.get("drum_boss_phase", 1))), 1, 2)
		boss.combatant.current_health = clampf(float(GameManager.save_data.story_flags.get("drum_boss_health", boss.combatant.max_health)), 1.0, boss.combatant.max_health)
	boss_panel.visible = true
	_on_boss_health_updated(boss.combatant.current_health, boss.combatant.max_health)
	_on_boss_phase_changed(boss.current_phase)

func _on_boss_room_manipulation(turns: int) -> void:
	if sequence_busy or not is_instance_valid(boss):
		return
	sequence_busy = true
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	player_combatant.set_invulnerable(true)
	_show_feedback("DRUM SHIFT — brace at the blue center mark!")
	_camera_reaction(0.045)
	var center := Vector3(0, 1.1, -91)
	var target_state := wrapi(boss_room_state + turns, 0, 4)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($BossShiftVisual, "rotation_degrees:z", float(target_state * 90), 0.84)
	await tween.finished
	boss_room_state = target_state
	_apply_boss_room_state(boss_room_state)
	GameManager.save_data.story_flags["drum_boss_room_state"] = boss_room_state
	SaveManager.save_checkpoint()
	if is_instance_valid(boss) and boss.active:
		var boss_positions := [Vector3(0, 0.05, -94), Vector3(-6, 0.05, -94), Vector3(6, 0.05, -94), Vector3(0, 0.05, -87)]
		boss.global_position = boss_positions[boss_room_state]
	if player.global_position.distance_to(center) > 9.5:
		player.global_position = center
		player.velocity = Vector3.ZERO
	companions.force_catch_up()
	player_combatant.set_invulnerable(false)
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	sequence_busy = false

func _on_boss_attack_telegraphed(_enemy: DemonEnemy, attack_name: StringName) -> void:
	var readable := str(attack_name).replace("_", " ").to_upper()
	_show_feedback("DRUM DEMON: %s — dodge with Ctrl or guard with Q" % readable)

func _on_boss_health_updated(current: float, maximum: float) -> void:
	boss_health.max_value = maximum
	boss_health.value = current
	GameManager.save_data.story_flags["drum_boss_health"] = current

func _on_boss_phase_changed(phase_number: int) -> void:
	boss_phase_label.text = "PHASE %d / 2" % phase_number
	GameManager.save_data.story_flags["drum_boss_phase"] = phase_number
	GameManager.save_data.story_flags["drum_demon_phase"] = phase_number
	if phase_number == 2:
		sequence_busy = true
		party.set_switching_allowed(false)
		player.set_controls_enabled(false)
		combat.set_combat_enabled(false)
		if is_instance_valid(boss):
			boss.combatant.set_invulnerable(true)
		_show_feedback("PHASE 2 — the drum rhythm accelerates!")
		SaveManager.save_checkpoint()
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(boss) and boss.active:
			boss.combatant.set_invulnerable(false)
		player.set_controls_enabled(true)
		combat.set_combat_enabled(true)
		party.set_switching_allowed(true)
		sequence_busy = false

func _on_boss_defeated(_enemy: DemonEnemy, reward: int, _kind: String) -> void:
	GameManager.save_data.wan_currency += reward
	progress = 6
	boss_panel.visible = false
	combat.set_lock_target(null)
	GameManager.save_data.story_flags["drum_demon_defeated"] = true
	GameManager.save_data.story_flags["drum_house_completed"] = true
	GameManager.save_data.story_flags["next_objective"] = "Travel to the Wisteria House."
	puzzle_room.stabilize()
	puzzle_room.set_route_open(true)
	trap_room.stabilize()
	trap_room.set_route_open(true)
	boss_room_state = 0
	_apply_boss_room_state(0)
	$BossShiftVisual.rotation_degrees = Vector3.ZERO
	GameManager.save_data.story_flags["drum_boss_room_state"] = 0
	_save_progress(Vector3(0, 1.1, -91))
	_show_feedback("DRUM DEMON DEFEATED — the house is stable.")
	party.set_switching_allowed(false)
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	dialogue_label.text = "ZENITSU: The walls finally stopped moving.\nINOSUKE: I was just getting used to them.\nTANJIRO: We made it out together."
	dialogue_label.visible = true
	await get_tree().create_timer(3.0).timeout
	dialogue_label.visible = false
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	_apply_exhausted_pose()
	_show_aftermath_state()

func _show_aftermath_state() -> void:
	_apply_exhausted_pose()
	_set_area("DRUM HOUSE — CLEARED")
	_set_objective("Travel to the Wisteria House.")
	_show_feedback("Milestone complete. Progress saved.")

func _on_player_defeated() -> void:
	if sequence_busy:
		return
	sequence_busy = true
	player.set_controls_enabled(false)
	combat.set_combat_enabled(false)
	await get_tree().create_timer(1.0).timeout
	player_combatant.restore_full_health()
	player.health = player.max_health
	player.stamina = player.max_stamina
	player.global_position = last_checkpoint
	player.velocity = Vector3.ZERO
	companions.force_catch_up()
	player.set_controls_enabled(true)
	combat.set_combat_enabled(true)
	party.set_switching_allowed(true)
	sequence_busy = false
	_show_feedback("The trio regroups at the last safe room.")

func _on_player_health_changed(current: float, _maximum: float) -> void:
	player.health = current

func _on_character_changed(_character_id: String, display_name: String) -> void:
	_show_feedback("%s takes the lead." % display_name.capitalize())

func _refresh_lock_target() -> void:
	var nearest: DemonEnemy
	var nearest_distance := INF
	for enemy in active_enemies:
		if not is_instance_valid(enemy) or not enemy.active:
			continue
		var distance := player.global_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	if is_instance_valid(boss) and boss.active:
		nearest = boss
	combat.set_lock_target(nearest)

func _update_hud() -> void:
	status_label.text = "%s\nHealth: %d / %d\nStamina: %d / %d\nWAN: %d" % [party.get_display_name(), roundi(player.health), roundi(player.max_health), roundi(player.stamina), roundi(player.max_stamina), GameManager.save_data.wan_currency]
	if party.current_character == "tanjiro":
		ability_label.text = "BREATH: %d / %d\n1–7 Water Forms • Ctrl Dodge • Q Guard • F1/F2/F3 Switch" % [roundi(breathing.current_breath), roundi(breathing.max_breath)]
	else:
		var cooldown := party.get_cooldown_remaining()
		ability_label.text = "%s: %s\n1 Ability • Ctrl Dodge • Q Guard • F1/F2/F3 Switch" % [party.get_ability_name().to_upper(), "READY" if cooldown <= 0.0 else "%.1fs" % cooldown]

func _rescue_player() -> void:
	player.global_position = last_checkpoint
	player.velocity = Vector3.ZERO
	companions.force_catch_up()
	_show_feedback("Returned to the last safe room.")

func _save_progress(checkpoint: Vector3) -> void:
	last_checkpoint = checkpoint
	var data := GameManager.save_data
	data.current_scene = SCENE_PATH
	data.player_position = checkpoint
	data.story_flags["drum_house_progress"] = progress
	SaveManager.save_checkpoint()

func _set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE\n%s" % text
	GameManager.save_data.story_flags["drum_house_objective"] = text

func _set_area(text: String) -> void:
	area_label.text = text

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

func _apply_exhausted_pose() -> void:
	(player.get_node("Visual") as Node3D).rotation.z = -0.08
	for slot in companions.get_children():
		if slot is Node3D:
			(slot as Node3D).rotation.z = 0.08 if slot.get_index() % 2 == 0 else -0.08

func _camera_reaction(amount: float) -> void:
	var pivot := player.camera_pivot
	var original := pivot.rotation.z
	var reaction := create_tween()
	reaction.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reaction.tween_property(pivot, "rotation:z", original + amount, 0.18)
	reaction.tween_property(pivot, "rotation:z", original - amount * 0.45, 0.12)
	reaction.tween_property(pivot, "rotation:z", original, 0.16)

func _roman(value: int) -> String:
	return ["0", "I", "II", "III"][clampi(value, 0, 3)]

func _build_house_geometry() -> void:
	_add_room("EntryFoyer", Vector3(18, 0.8, 20), Vector3(0, -0.4, 18), Color(0.24, 0.16, 0.12))
	_add_room("EntryHall", Vector3(7, 0.8, 13), Vector3(0, -0.4, 2.5), Color(0.21, 0.13, 0.1))
	_add_room("Gallery", Vector3(18, 0.8, 22), Vector3(0, -0.4, -35), Color(0.25, 0.17, 0.12))
	_add_room("SleepingRoom", Vector3(14, 0.8, 12), Vector3(-16, -0.4, -35), Color(0.2, 0.14, 0.12))
	_add_room("StorageRoom", Vector3(14, 0.8, 12), Vector3(16, -0.4, -35), Color(0.18, 0.13, 0.1))
	_add_room("GalleryHall", Vector3(7, 0.8, 10), Vector3(0, -0.4, -50), Color(0.2, 0.12, 0.09))
	_add_room("HeartHall", Vector3(7, 0.8, 14), Vector3(0, -0.4, -69), Color(0.19, 0.1, 0.08))
	_add_room("BossArena", Vector3(27, 0.8, 28), Vector3(0, -0.4, -90), Color(0.23, 0.11, 0.09), $BossArenaVisual)
	for room_data in [[18.0, 18.0, 20.0], [-90.0, 27.0, 28.0]]:
		_add_room_walls(float(room_data[0]), float(room_data[1]), float(room_data[2]))
	_add_gallery_branch_walls()
	_add_corridor_walls(2.5, 13.0, 7.0)
	_add_corridor_walls(-50.0, 10.0, 7.0)
	_add_corridor_walls(-69.0, 14.0, 7.0)
	_add_drum_marker(Vector3(0, 0.2, -11.5))
	_add_drum_marker(Vector3(0, 0.2, -58.0))
	_add_door_frame(-24.5, 7.0)
	_add_door_frame(-46.0, 7.0)
	_add_door_frame(-76.0, 7.0)
	_build_house_dressing()

func _build_house_dressing() -> void:
	# A real front facade frames the entrance instead of leaving the arrival side open.
	_add_solid_box($EnvironmentGeometry, "FrontFacadeLeft", Vector3(6.0, 5.5, 0.8), Vector3(-6.0, 2.75, 28.8), Color(0.16, 0.075, 0.05))
	_add_solid_box($EnvironmentGeometry, "FrontFacadeRight", Vector3(6.0, 5.5, 0.8), Vector3(6.0, 2.75, 28.8), Color(0.16, 0.075, 0.05))
	_add_solid_box($EnvironmentGeometry, "FrontFacadeLintel", Vector3(6.8, 1.1, 0.8), Vector3(0, 5.25, 28.8), Color(0.22, 0.09, 0.055))
	_add_visual_box($EnvironmentGeometry, "Roof", Vector3(22.0, 0.8, 25.0), Vector3(0, 6.35, 18.0), Color(0.07, 0.035, 0.03), Vector3(0, 0, deg_to_rad(-2.0)))
	_add_visual_box($EnvironmentGeometry, "EntryRug", Vector3(5.5, 0.05, 8.0), Vector3(0, 0.04, 18.0), Color(0.42, 0.08, 0.045))
	_add_visual_box($EnvironmentGeometry, "EntryPath", Vector3(3.2, 0.07, 15.0), Vector3(0, 0.08, 9.5), Color(0.72, 0.24, 0.07))
	_add_visual_box($EnvironmentGeometry, "EntryThresholdGlow", Vector3(5.4, 0.12, 0.18), Vector3(0, 0.16, 10.0), Color(1.0, 0.5, 0.08))
	_add_room_label("ENTRY HALL", Vector3(0, 4.6, 25.8), Color(1.0, 0.72, 0.35))
	_add_room_label("FOLLOW THE LIT PATH", Vector3(0, 3.4, 14.5), Color(1.0, 0.9, 0.45))
	_add_room_label("ROTATING DRUM CHAMBER", Vector3(0, 5.0, -11.5), Color(1.0, 0.34, 0.18))
	_add_room_label("SLEEPING WING", Vector3(-16, 4.2, -35), Color(0.65, 0.78, 0.9))
	_add_room_label("STORAGE WING", Vector3(16, 4.2, -35), Color(0.8, 0.62, 0.35))
	_add_room_label("SHIFTING GALLERY", Vector3(0, 4.8, -35), Color(1.0, 0.55, 0.22))
	_add_room_label("DRUM HEART", Vector3(0, 5.0, -90), Color(1.0, 0.18, 0.1))
	_add_drum_prop(Vector3(0, 0.85, -11.5))
	_add_drum_prop(Vector3(0, 0.85, -58.0))
	_add_drum_prop(Vector3(0, 0.85, -90.0))
	_add_gallery_props()
	_add_room_light(Vector3(0, 4.5, 18), Color(1.0, 0.5, 0.22), 2.2, 18.0)
	_add_room_light(Vector3(0, 4.5, -11.5), Color(1.0, 0.18, 0.08), 3.0, 17.0)
	_add_room_light(Vector3(-16, 3.8, -35), Color(0.25, 0.45, 1.0), 1.8, 13.0)
	_add_room_light(Vector3(16, 3.8, -35), Color(1.0, 0.42, 0.12), 1.8, 13.0)
	_add_room_light(Vector3(0, 4.5, -58), Color(0.85, 0.1, 0.04), 2.6, 15.0)
	_add_room_light(Vector3(0, 5.0, -90), Color(1.0, 0.08, 0.02), 3.5, 24.0)

func _add_gallery_props() -> void:
	for z_position in [-39.0, -34.0, -29.0]:
		_add_visual_box($EnvironmentGeometry, "GalleryBeam", Vector3(1.0, 3.8, 1.0), Vector3(-7.0, 1.9, z_position), Color(0.11, 0.05, 0.035))
		_add_visual_box($EnvironmentGeometry, "GalleryBeam", Vector3(1.0, 3.8, 1.0), Vector3(7.0, 1.9, z_position), Color(0.11, 0.05, 0.035))
	for side in [-1.0, 1.0]:
		for index in 3:
			_add_visual_box($EnvironmentGeometry, "StorageCrate", Vector3(1.6, 1.1, 1.4), Vector3(side * (15.5 + index * 1.8), 0.55, -38.0 + index * 2.5), Color(0.36, 0.2, 0.08))
	_add_visual_box($EnvironmentGeometry, "SleepingMat", Vector3(4.0, 0.1, 1.7), Vector3(-16, 0.08, -35), Color(0.18, 0.34, 0.48))
	_add_visual_box($EnvironmentGeometry, "SleepingMat", Vector3(4.0, 0.1, 1.7), Vector3(-16, 0.08, -38), Color(0.18, 0.34, 0.48))

func _add_drum_prop(position: Vector3) -> void:
	var drum := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.95
	mesh.bottom_radius = 0.95
	mesh.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.035, 0.018)
	material.emission_enabled = true
	material.emission = Color(0.22, 0.008, 0.002)
	mesh.material = material
	drum.mesh = mesh
	drum.position = position
	drum.rotation_degrees.x = 90.0
	$EnvironmentGeometry.add_child(drum)
	_add_visual_box($EnvironmentGeometry, "DrumStand", Vector3(2.3, 0.18, 1.1), position + Vector3(0, -0.5, 0), Color(0.12, 0.045, 0.025))

func _add_room_label(text_value: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = position
	label.font_size = 32
	label.outline_size = 8
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	$EnvironmentGeometry.add_child(label)

func _add_room_light(position: Vector3, color: Color, energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = true
	$EnvironmentGeometry.add_child(light)

func _add_visual_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.emission_enabled = true
	material.emission = color * 0.65
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	parent.add_child(visual)
	return visual

func _build_boss_arena_states() -> void:
	var layouts := [
		[Vector3(-7, 1, -88), Vector3(7, 1, -94)],
		[Vector3(-4, 1, -90), Vector3(4, 1, -90)],
		[Vector3(0, 1, -86), Vector3(-7, 1, -95), Vector3(7, 1, -95)],
		[Vector3(0, 1, -96), Vector3(-7, 1, -87), Vector3(7, 1, -87)],
	]
	for state in 4:
		var state_root := Node3D.new()
		state_root.name = "ArenaState%d" % state
		$BossArenaStates.add_child(state_root)
		for obstacle_position: Vector3 in layouts[state]:
			_add_solid_box(state_root, "ShiftedObstacle", Vector3(2.2, 2.0, 2.2), obstacle_position, Color(0.34, 0.12 + state * 0.025, 0.08))
		var marker := MeshInstance3D.new()
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(10.0, 0.08, 0.35)
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = Color(0.72, 0.08, 0.04)
		marker_material.emission_enabled = true
		marker_material.emission = Color(0.38, 0.02, 0.01)
		marker_mesh.material = marker_material
		marker.mesh = marker_mesh
		marker.position = Vector3(0, 0.08, -91)
		marker.rotation_degrees.y = float(state * 45)
		$BossShiftVisual.add_child(marker)
	_apply_boss_room_state(0)

func _apply_boss_room_state(state: int) -> void:
	boss_room_state = clampi(state, 0, 3)
	for index in $BossArenaStates.get_child_count():
		var state_root := $BossArenaStates.get_child(index) as Node3D
		var active := index == boss_room_state
		state_root.visible = active
		for collision_node in state_root.find_children("*", "CollisionShape3D", true, false):
			(collision_node as CollisionShape3D).disabled = not active

func _add_room(label: String, size: Vector3, position: Vector3, color: Color, parent: Node = $EnvironmentGeometry) -> void:
	_add_solid_box(parent, label, size, position, color)

func _add_room_walls(center_z: float, width: float, length: float) -> void:
	_add_solid_box($EnvironmentGeometry, "Wall", Vector3(0.6, 6.0, length), Vector3(-width * 0.5, 3.0, center_z), Color(0.13, 0.075, 0.06))
	_add_solid_box($EnvironmentGeometry, "Wall", Vector3(0.6, 6.0, length), Vector3(width * 0.5, 3.0, center_z), Color(0.13, 0.075, 0.06))

func _add_corridor_walls(center_z: float, length: float, width: float) -> void:
	_add_solid_box($EnvironmentGeometry, "HallWall", Vector3(0.5, 5.0, length), Vector3(-width * 0.5, 2.5, center_z), Color(0.12, 0.07, 0.055))
	_add_solid_box($EnvironmentGeometry, "HallWall", Vector3(0.5, 5.0, length), Vector3(width * 0.5, 2.5, center_z), Color(0.12, 0.07, 0.055))

func _add_gallery_branch_walls() -> void:
	for side in [-1.0, 1.0]:
		for segment_z in [-42.5, -27.5]:
			_add_solid_box($EnvironmentGeometry, "GalleryWall", Vector3(0.6, 6.0, 7.0), Vector3(side * 9.0, 3.0, segment_z), Color(0.13, 0.075, 0.06))
		_add_solid_box($EnvironmentGeometry, "BranchOuterWall", Vector3(0.6, 5.0, 12.0), Vector3(side * 23.0, 2.5, -35.0), Color(0.11, 0.065, 0.052))
		_add_solid_box($EnvironmentGeometry, "BranchEndWall", Vector3(14.0, 5.0, 0.6), Vector3(side * 16.0, 2.5, -41.0), Color(0.11, 0.065, 0.052))
		_add_solid_box($EnvironmentGeometry, "BranchEndWall", Vector3(14.0, 5.0, 0.6), Vector3(side * 16.0, 2.5, -29.0), Color(0.11, 0.065, 0.052))

func _add_door_frame(z_position: float, width: float) -> void:
	var frame_color := Color(0.29, 0.12, 0.07)
	_add_solid_box($EnvironmentGeometry, "DoorPost", Vector3(0.45, 4.2, 0.55), Vector3(-width * 0.5, 2.1, z_position), frame_color)
	_add_solid_box($EnvironmentGeometry, "DoorPost", Vector3(0.45, 4.2, 0.55), Vector3(width * 0.5, 2.1, z_position), frame_color)
	_add_solid_box($EnvironmentGeometry, "DoorLintel", Vector3(width + 0.8, 0.5, 0.55), Vector3(0, 4.4, z_position), frame_color)

func _add_solid_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.emission_enabled = true
	material.emission = color * 0.55
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sBody" % label
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _add_drum_marker(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.7
	mesh.height = 0.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.65, 0.08, 0.04)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.025, 0.01)
	mesh.material = material
	marker.mesh = mesh
	marker.position = position
	$EnvironmentGeometry.add_child(marker)
