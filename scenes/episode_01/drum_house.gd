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
	_configure_indoor_navigation()
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

func _configure_indoor_navigation() -> void:
	player.camera_distance = 3.0
	player.spring_arm.spring_length = 3.0
	player.spring_arm.margin = 0.28
	player.spring_arm.collision_mask = 1
	player.camera_pivot.position.y = 0.78
	companions.set("follow_distance", 3.8)
	companions.set("side_spacing", 0.82)
	companions.set("catch_up_distance", 8.0)
	for slot in companions.get("slots"):
		var nameplate := (slot as Node3D).get_node_or_null("Nameplate") as Label3D
		if nameplate != null:
			nameplate.visible = false

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
		_set_objective("Investigate the strange house. Explore the open rooms, then follow the lanterns to the drum.")
		_show_feedback("Turn left or right to enter a furnished room. The main route continues ahead.")
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
	if progress == 0:
		interaction_label.text = "Explore the open rooms on both sides • Follow the lantern corridor to the drum"
		interaction_label.visible = true
	elif progress == 1 and player.global_position.distance_to(Vector3(0, 1.1, -11.5)) <= 4.0:
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
	_add_house_room("EntryVestibule", Vector3(0, 0, 28.5), Vector2(6, 3), {"north": true}, Color(0.3, 0.19, 0.12))
	_add_house_room("EntranceHall", Vector3(0, 0, 22), Vector2(10, 10), {"north": true, "south": true, "east": true, "west": true}, Color(0.36, 0.23, 0.14))
	_add_house_room("TeaRoom", Vector3(-8, 0, 22), Vector2(6, 8), {"east": true}, Color(0.34, 0.3, 0.18))
	_add_house_room("FamilyRoom", Vector3(8, 0, 22), Vector2(6, 8), {"west": true}, Color(0.32, 0.26, 0.18))
	_add_house_room("MainCorridor", Vector3(0, 0, 14.5), Vector2(4.5, 5), {"north": true, "south": true}, Color(0.3, 0.19, 0.12))
	_add_house_room("TatamiRoom", Vector3(0, 0, 9.5), Vector2(8, 5), {"north": true, "south": true, "east": true, "west": true}, Color(0.34, 0.22, 0.14))
	_add_house_room("SideRoomA", Vector3(-7, 0, 9.5), Vector2(6, 7), {"east": true}, Color(0.3, 0.24, 0.17))
	_add_house_room("SideRoomB", Vector3(7, 0, 9.5), Vector2(6, 7), {"west": true}, Color(0.29, 0.2, 0.15))
	_add_house_room("PuzzleApproach", Vector3(0, 0, 2.0), Vector2(4.5, 10), {"north": true, "south": true}, Color(0.27, 0.17, 0.11))
	_add_house_room("DrumThreshold", Vector3(0, 0, -4.75), Vector2(4.5, 3.5), {"north": true, "south": true}, Color(0.28, 0.17, 0.11))
	_add_house_room("AlteredCorridor", Vector3(0, 0, -22), Vector2(4.5, 8), {"north": true, "south": true}, Color(0.27, 0.16, 0.11))
	_add_house_room("GalleryThreshold", Vector3(0, 0, -27), Vector2(4.5, 2), {"north": true, "south": true}, Color(0.29, 0.18, 0.11))
	_add_house_room("DemonCombatRoom", Vector3(0, 0, -35), Vector2(14, 14), {"north": true, "south": true, "east": true, "west": true}, Color(0.34, 0.22, 0.14))
	_add_house_room("DamagedRoom", Vector3(-11, 0, -35), Vector2(7, 9), {"east": true}, Color(0.26, 0.18, 0.14))
	_add_house_room("StorageRoom", Vector3(11, 0, -35), Vector2(7, 9), {"west": true}, Color(0.28, 0.19, 0.12))
	_add_house_room("GalleryHall", Vector3(0, 0, -47), Vector2(4.5, 10), {"north": true, "south": true}, Color(0.28, 0.17, 0.11))
	_add_house_room("TrapThreshold", Vector3(0, 0, -52.5), Vector2(4.5, 1), {"north": true, "south": true}, Color(0.28, 0.17, 0.11))
	_add_house_room("PuzzleRoom", Vector3(0, 0, -69), Vector2(8, 12), {"north": true, "south": true, "east": true, "west": true}, Color(0.3, 0.2, 0.13))
	_add_house_room("PuzzleNicheWest", Vector3(-7, 0, -69), Vector2(6, 6), {"east": true}, Color(0.25, 0.17, 0.12))
	_add_house_room("PuzzleNicheEast", Vector3(7, 0, -69), Vector2(6, 6), {"west": true}, Color(0.25, 0.17, 0.12))
	_add_house_room("BossApproach", Vector3(0, 0, -77), Vector2(8, 5), {"north": true, "south": true}, Color(0.31, 0.16, 0.12))
	_add_house_room("BossChamber", Vector3(0, 0, -91), Vector2(20, 23), {"south": true}, Color(0.38, 0.17, 0.12), $BossArenaVisual)
	_add_drum_marker(Vector3(0, 0.2, -11.5))
	_add_drum_marker(Vector3(0, 0.2, -58.0))
	_build_house_dressing()

func _build_house_dressing() -> void:
	_add_visual_box($EnvironmentGeometry, "EntryRunner", Vector3(2.2, 0.05, 8.0), Vector3(0, 0.06, 22), Color(0.48, 0.12, 0.055))
	_add_table(Vector3(-3.1, 0, 20.5), false)
	_add_visual_box($EnvironmentGeometry, "ShoeBench", Vector3(2.4, 0.55, 0.65), Vector3(3.1, 0.3, 24.8), Color(0.3, 0.16, 0.08))
	_add_visual_box($EnvironmentGeometry, "AbandonedSandals", Vector3(0.55, 0.08, 0.85), Vector3(2.6, 0.11, 23.5), Color(0.16, 0.1, 0.06), Vector3(0, 0.22, 0))
	_add_visual_box($EnvironmentGeometry, "AbandonedSandals", Vector3(0.55, 0.08, 0.85), Vector3(3.35, 0.11, 23.2), Color(0.16, 0.1, 0.06), Vector3(0, -0.18, 0))
	_add_open_sliding_door(Vector3(-5.02, 0, 22), true)
	_add_open_sliding_door(Vector3(5.02, 0, 22), true)
	_add_room_sign("TEA ROOM", Vector3(-4.82, 3.25, 22), Color(1.0, 0.8, 0.42), Vector3(0, 90, 0))
	_add_room_sign("FAMILY ROOM", Vector3(4.82, 3.25, 22), Color(1.0, 0.8, 0.42), Vector3(0, -90, 0))
	_add_room_sign("ENTRANCE HALL", Vector3(0, 3.25, 17.2), Color(1.0, 0.78, 0.4))
	_add_room_sign("DRUM CHAMBER", Vector3(0, 3.2, -5.9), Color(1.0, 0.42, 0.22))
	_add_room_sign("SHIFTING GALLERY", Vector3(0, 3.2, -28.2), Color(1.0, 0.58, 0.28))
	_add_room_sign("DRUM HEART", Vector3(0, 3.3, -80.1), Color(1.0, 0.28, 0.16))
	_add_drum_prop(Vector3(0, 0.85, -11.5))
	_add_drum_prop(Vector3(0, 0.85, -58.0))
	_add_drum_prop(Vector3(0, 0.85, -90.0))
	_add_side_room_props()
	_add_entrance_room_props()
	_add_tatami_room_props()
	_add_puzzle_room_props()
	_add_combat_room_props()
	_add_storage_props()
	_add_boss_room_props()
	for lantern_position in [Vector3(-3.7, 3.25, 22), Vector3(3.7, 3.25, 22), Vector3(0, 3.2, 14.5), Vector3(0, 3.2, 2), Vector3(0, 3.2, -22), Vector3(-5.8, 3.35, -35), Vector3(5.8, 3.35, -35), Vector3(0, 3.2, -47), Vector3(0, 3.2, -69), Vector3(0, 3.3, -77)]:
		_add_lantern(lantern_position, Color(1.0, 0.52, 0.22), 1.8, 7.5)
	_add_lantern(Vector3(-7.5, 4.0, -91), Color(1.0, 0.22, 0.08), 2.6, 12.0)
	_add_lantern(Vector3(7.5, 4.0, -91), Color(1.0, 0.22, 0.08), 2.6, 12.0)

func _add_side_room_props() -> void:
	for z_position in [8.0, 10.5]:
		_add_visual_box($EnvironmentGeometry, "TatamiMat", Vector3(2.35, 0.08, 1.8), Vector3(-7, 0.08, z_position), Color(0.5, 0.48, 0.28))
	_add_visual_box($EnvironmentGeometry, "AbandonedBedding", Vector3(3.6, 0.18, 1.5), Vector3(-7, 0.15, 11.7), Color(0.24, 0.36, 0.45))
	_add_table(Vector3(7, 0, 9.5), true)
	_add_visual_box($EnvironmentGeometry, "FallenStool", Vector3(0.85, 0.75, 0.85), Vector3(8.4, 0.42, 11.2), Color(0.3, 0.15, 0.07), Vector3(0, 0, 0.65))
	_add_visual_box($EnvironmentGeometry, "DamagedPanel", Vector3(2.5, 2.8, 0.16), Vector3(5.8, 1.55, 12.7), Color(0.55, 0.46, 0.33), Vector3(0, 0.2, 0.08))

func _add_tatami_room_props() -> void:
	for x_position in [-2.2, 0.2, 2.2]:
		_add_visual_box($EnvironmentGeometry, "CentralTatami", Vector3(2.0, 0.08, 1.85), Vector3(x_position, 0.07, 9.5), Color(0.57, 0.54, 0.3))
	_add_table(Vector3(0, 0, 9.5), false)
	_add_visual_box($EnvironmentGeometry, "FloorCushion", Vector3(0.8, 0.16, 0.8), Vector3(-2.65, 0.13, 8.4), Color(0.42, 0.18, 0.12))
	_add_visual_box($EnvironmentGeometry, "FloorCushion", Vector3(0.8, 0.16, 0.8), Vector3(2.65, 0.13, 10.6), Color(0.42, 0.18, 0.12))

func _add_puzzle_room_props() -> void:
	_add_visual_box($EnvironmentGeometry, "PuzzlePedestal", Vector3(1.4, 1.0, 1.4), Vector3(0, 0.5, -69), Color(0.32, 0.12, 0.055))
	_add_visual_box($EnvironmentGeometry, "PuzzleSeal", Vector3(0.9, 0.12, 0.9), Vector3(0, 1.06, -69), Color(0.7, 0.12, 0.05))
	for side in [-1.0, 1.0]:
		_add_visual_box($EnvironmentGeometry, "PuzzleWallDrum", Vector3(0.16, 1.5, 1.5), Vector3(side * 3.82, 2.2, -69), Color(0.44, 0.06, 0.025))
	_add_visual_box($EnvironmentGeometry, "PuzzleNicheCrate", Vector3(1.1, 1.1, 1.1), Vector3(-7, 0.55, -70), Color(0.38, 0.2, 0.08))
	_add_visual_box($EnvironmentGeometry, "PuzzleNicheShelf", Vector3(1.8, 2.3, 0.55), Vector3(7.5, 1.15, -68), Color(0.28, 0.13, 0.06))

func _add_entrance_room_props() -> void:
	for x_position in [-8.9, -7.1]:
		for z_position in [20.3, 22.3, 24.3]:
			_add_visual_box($EnvironmentGeometry, "TeaRoomTatami", Vector3(1.55, 0.08, 1.75), Vector3(x_position, 0.07, z_position), Color(0.58, 0.55, 0.3))
	_add_table(Vector3(-8, 0, 22.2), false)
	_add_visual_box($EnvironmentGeometry, "TeaCup", Vector3(0.22, 0.18, 0.22), Vector3(-8.35, 0.9, 22.2), Color(0.62, 0.52, 0.38))
	_add_visual_box($EnvironmentGeometry, "TeaCup", Vector3(0.22, 0.18, 0.22), Vector3(-7.65, 0.9, 22.2), Color(0.62, 0.52, 0.38))
	_add_visual_box($EnvironmentGeometry, "WallScroll", Vector3(2.1, 2.3, 0.08), Vector3(-8, 2.5, 18.12), Color(0.7, 0.61, 0.43))
	_add_visual_box($EnvironmentGeometry, "ScrollMark", Vector3(0.18, 1.35, 0.04), Vector3(-8, 2.5, 18.05), Color(0.25, 0.08, 0.045), Vector3(0, 0, 0.35))
	_add_visual_box($EnvironmentGeometry, "FamilyBedding", Vector3(3.8, 0.18, 1.55), Vector3(8, 0.13, 20.2), Color(0.3, 0.4, 0.52))
	_add_visual_box($EnvironmentGeometry, "FamilyBedding", Vector3(3.8, 0.18, 1.55), Vector3(8, 0.13, 23.0), Color(0.42, 0.28, 0.38))
	_add_visual_box($EnvironmentGeometry, "ClothingChest", Vector3(2.0, 1.15, 1.1), Vector3(9.4, 0.58, 24.8), Color(0.38, 0.19, 0.08))
	_add_visual_box($EnvironmentGeometry, "ChestBand", Vector3(2.05, 0.12, 1.15), Vector3(9.4, 0.78, 24.8), Color(0.18, 0.06, 0.03))
	_add_visual_box($EnvironmentGeometry, "AbandonedBundle", Vector3(1.25, 0.8, 1.0), Vector3(6.8, 0.42, 24.7), Color(0.34, 0.16, 0.22), Vector3(0.1, 0.25, 0.12))
	_add_lantern(Vector3(-8, 3.35, 22), Color(1.0, 0.55, 0.22), 2.0, 7.0)
	_add_lantern(Vector3(8, 3.35, 22), Color(1.0, 0.48, 0.2), 2.0, 7.0)

func _add_open_sliding_door(position: Vector3, along_z: bool) -> void:
	var panel_size := Vector3(0.12, 2.8, 1.25) if along_z else Vector3(1.25, 2.8, 0.12)
	var first_offset := Vector3(0, 1.4, -1.75) if along_z else Vector3(-1.75, 1.4, 0)
	var second_offset := Vector3(0, 1.4, 1.75) if along_z else Vector3(1.75, 1.4, 0)
	for offset in [first_offset, second_offset]:
		_add_visual_box($EnvironmentGeometry, "OpenSlidingPanel", panel_size, position + offset, Color(0.62, 0.54, 0.4))
		var crossbar_size := Vector3(0.14, 0.1, 1.28) if along_z else Vector3(1.28, 0.1, 0.14)
		for height in [0.65, 1.35, 2.05]:
			_add_visual_box($EnvironmentGeometry, "SlidingPanelBar", crossbar_size, position + offset + Vector3(0, height - 1.4, 0), Color(0.22, 0.08, 0.035))

func _add_combat_room_props() -> void:
	for x_position in [-5.7, 5.7]:
		for z_position in [-39.8, -30.2]:
			_add_visual_box($EnvironmentGeometry, "CombatPillar", Vector3(0.55, 4.2, 0.55), Vector3(x_position, 2.1, z_position), Color(0.24, 0.1, 0.055))
	_add_visual_box($EnvironmentGeometry, "FallenBeam", Vector3(6.5, 0.42, 0.45), Vector3(-2.0, 0.35, -39.8), Color(0.3, 0.12, 0.055), Vector3(0, 0.28, 0.12))
	for scratch_index in 4:
		_add_visual_box($EnvironmentGeometry, "ClawScratch", Vector3(0.08, 1.3, 0.035), Vector3(-6.68 + scratch_index * 0.14, 2.2 + scratch_index * 0.08, -35), Color(0.65, 0.12, 0.06), Vector3(0, 0, -0.22))

func _add_storage_props() -> void:
	for shelf_z in [-38.0, -34.8, -31.6]:
		_add_visual_box($EnvironmentGeometry, "StorageShelf", Vector3(0.65, 2.6, 2.2), Vector3(12.8, 1.3, shelf_z), Color(0.27, 0.14, 0.065))
	for crate_data in [[9.8, -38.0, 0.85], [10.3, -35.8, 1.15], [9.5, -33.4, 0.7], [11.2, -31.8, 0.95]]:
		var crate_size := float(crate_data[2])
		_add_visual_box($EnvironmentGeometry, "StorageCrate", Vector3(crate_size, crate_size, crate_size), Vector3(float(crate_data[0]), crate_size * 0.5, float(crate_data[1])), Color(0.42, 0.23, 0.09))
	_add_visual_box($EnvironmentGeometry, "BrokenTableTop", Vector3(3.2, 0.18, 1.6), Vector3(-11, 0.55, -35), Color(0.32, 0.15, 0.07), Vector3(0.12, 0.25, 0.35))
	_add_visual_box($EnvironmentGeometry, "BrokenTableLeg", Vector3(0.22, 1.2, 0.22), Vector3(-12, 0.6, -34.4), Color(0.25, 0.11, 0.05), Vector3(0.35, 0, 0.25))

func _add_boss_room_props() -> void:
	for x_position in [-8.4, 8.4]:
		for z_position in [-98.5, -90.5, -82.5]:
			_add_visual_box($BossArenaVisual, "BossTimber", Vector3(0.75, 4.8, 0.75), Vector3(x_position, 2.4, z_position), Color(0.28, 0.075, 0.04))
	for x_position in [-5.5, 0.0, 5.5]:
		_add_visual_box($BossArenaVisual, "CeilingBeam", Vector3(0.45, 0.45, 19.0), Vector3(x_position, 4.25, -91), Color(0.24, 0.065, 0.035))
	for motif_x in [-6.0, -3.0, 3.0, 6.0]:
		_add_drum_wall_motif(Vector3(motif_x, 2.4, -101.9))
	_add_visual_box($BossArenaVisual, "BossDais", Vector3(7.0, 0.22, 4.0), Vector3(0, 0.12, -96), Color(0.42, 0.12, 0.055))

func _add_table(position: Vector3, damaged: bool) -> void:
	var tilt := Vector3(0.12, 0, 0.18) if damaged else Vector3.ZERO
	_add_visual_box($EnvironmentGeometry, "LowTable", Vector3(2.6, 0.18, 1.5), position + Vector3(0, 0.72, 0), Color(0.33, 0.16, 0.07), tilt)
	for leg_offset in [Vector3(-0.9, 0.35, -0.45), Vector3(0.9, 0.35, -0.45), Vector3(-0.9, 0.35, 0.45), Vector3(0.9, 0.35, 0.45)]:
		_add_visual_box($EnvironmentGeometry, "TableLeg", Vector3(0.16, 0.7, 0.16), position + leg_offset, Color(0.25, 0.11, 0.045), tilt)

func _add_lantern(position: Vector3, color: Color, energy: float, range_value: float) -> void:
	_add_visual_box($EnvironmentGeometry, "LanternGlow", Vector3(0.32, 0.48, 0.32), position, Color(1.0, 0.62, 0.25))
	var frame_color := Color(0.3, 0.09, 0.035)
	_add_visual_box($EnvironmentGeometry, "LanternTop", Vector3(0.55, 0.08, 0.55), position + Vector3(0, 0.32, 0), frame_color)
	_add_visual_box($EnvironmentGeometry, "LanternBottom", Vector3(0.55, 0.08, 0.55), position + Vector3(0, -0.32, 0), frame_color)
	for corner in [Vector3(-0.24, 0, -0.24), Vector3(0.24, 0, -0.24), Vector3(-0.24, 0, 0.24), Vector3(0.24, 0, 0.24)]:
		_add_visual_box($EnvironmentGeometry, "LanternPost", Vector3(0.06, 0.65, 0.06), position + corner, frame_color)
	_add_room_light(position, color, energy, range_value)

func _add_drum_wall_motif(position: Vector3) -> void:
	var motif := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 0.75
	mesh.height = 0.18
	mesh.material = _make_material(Color(0.48, 0.055, 0.025), 0.8)
	motif.name = "DrumWallMotif"
	motif.mesh = mesh
	motif.position = position
	motif.rotation_degrees.x = 90.0
	$BossArenaVisual.add_child(motif)

func _add_drum_prop(position: Vector3) -> void:
	var drum := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.95
	mesh.bottom_radius = 0.95
	mesh.height = 0.7
	mesh.material = _make_material(Color(0.48, 0.055, 0.025), 0.72)
	drum.mesh = mesh
	drum.position = position
	drum.rotation_degrees.x = 90.0
	$EnvironmentGeometry.add_child(drum)
	_add_visual_box($EnvironmentGeometry, "DrumStand", Vector3(2.3, 0.18, 1.1), position + Vector3(0, -0.5, 0), Color(0.12, 0.045, 0.025))

func _add_room_sign(text_value: String, position: Vector3, color: Color, rotation_degrees: Vector3 = Vector3.ZERO) -> void:
	var board_rotation := Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))
	_add_visual_box($EnvironmentGeometry, "%sSignBoard" % text_value.replace(" ", ""), Vector3(2.4, 0.5, 0.12), position + Vector3(0, 0, 0.08), Color(0.34, 0.16, 0.065), board_rotation)
	var label := Label3D.new()
	label.text = text_value
	label.position = position + Vector3(0, 0, 0.18)
	label.font_size = 14
	label.outline_size = 3
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.rotation_degrees = rotation_degrees
	$EnvironmentGeometry.add_child(label)

func _add_room_light(position: Vector3, color: Color, energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = false
	$EnvironmentGeometry.add_child(light)

func _add_visual_box(parent: Node, label: String, size: Vector3, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_material(color, 0.28)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.position = position
	visual.rotation = rotation
	parent.add_child(visual, true)
	return visual

func _make_material(color: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = color * emission_strength
	return material

func _add_house_room(label: String, center: Vector3, footprint: Vector2, openings: Dictionary, floor_color: Color, parent: Node = $EnvironmentGeometry) -> void:
	var room := Node3D.new()
	room.name = label
	room.position = center
	room.set_meta("house_space", true)
	room.set_meta("footprint", footprint)
	parent.add_child(room)
	var width := footprint.x
	var length := footprint.y
	var wall_color := Color(0.49, 0.41, 0.3)
	var timber_color := Color(0.2, 0.085, 0.045)
	_add_solid_box(room, "WoodenFloor", Vector3(width, 0.4, length), Vector3(0, -0.2, 0), floor_color)
	_add_visual_box(room, "PlasterCeiling", Vector3(width, 0.25, length), Vector3(0, 4.5, 0), Color(0.32, 0.27, 0.22))
	_add_wall_z(room, "NorthWall", width, -length * 0.5, bool(openings.get("north", false)), wall_color, timber_color)
	_add_wall_z(room, "SouthWall", width, length * 0.5, bool(openings.get("south", false)), wall_color, timber_color)
	_add_wall_x(room, "WestWall", length, -width * 0.5, bool(openings.get("west", false)), wall_color, timber_color)
	_add_wall_x(room, "EastWall", length, width * 0.5, bool(openings.get("east", false)), wall_color, timber_color)
	for corner in [Vector3(-width * 0.5 + 0.18, 2.25, -length * 0.5 + 0.18), Vector3(width * 0.5 - 0.18, 2.25, -length * 0.5 + 0.18), Vector3(-width * 0.5 + 0.18, 2.25, length * 0.5 - 0.18), Vector3(width * 0.5 - 0.18, 2.25, length * 0.5 - 0.18)]:
		_add_visual_box(room, "TimberPost", Vector3(0.32, 4.5, 0.32), corner, timber_color)
	_add_visual_box(room, "CeilingBeam", Vector3(width, 0.3, 0.35), Vector3(0, 4.28, 0), timber_color)
	for board_index in range(1, int(length)):
		_add_visual_box(room, "FloorBoardSeam", Vector3(width - 0.3, 0.012, 0.025), Vector3(0, 0.012, -length * 0.5 + float(board_index)), Color(0.12, 0.07, 0.04))

func _add_wall_z(parent: Node, label: String, width: float, z_position: float, has_door: bool, wall_color: Color, timber_color: Color) -> void:
	var door_width := minf(2.5, width * 0.55)
	if has_door:
		var segment_width := (width - door_width) * 0.5
		_add_solid_box(parent, "%sLeft" % label, Vector3(segment_width, 4.5, 0.3), Vector3(-(door_width + segment_width) * 0.5, 2.25, z_position), wall_color)
		_add_solid_box(parent, "%sRight" % label, Vector3(segment_width, 4.5, 0.3), Vector3((door_width + segment_width) * 0.5, 2.25, z_position), wall_color)
		_add_visual_box(parent, "%sLintel" % label, Vector3(door_width + 0.35, 0.32, 0.42), Vector3(0, 3.35, z_position), timber_color)
		_add_visual_box(parent, "%sPost" % label, Vector3(0.24, 3.4, 0.42), Vector3(-door_width * 0.5, 1.7, z_position), timber_color)
		_add_visual_box(parent, "%sPost" % label, Vector3(0.24, 3.4, 0.42), Vector3(door_width * 0.5, 1.7, z_position), timber_color)
	else:
		_add_solid_box(parent, label, Vector3(width, 4.5, 0.3), Vector3(0, 2.25, z_position), wall_color)

func _add_wall_x(parent: Node, label: String, length: float, x_position: float, has_door: bool, wall_color: Color, timber_color: Color) -> void:
	var door_width := minf(2.5, length * 0.55)
	if has_door:
		var segment_length := (length - door_width) * 0.5
		_add_solid_box(parent, "%sFront" % label, Vector3(0.3, 4.5, segment_length), Vector3(x_position, 2.25, -(door_width + segment_length) * 0.5), wall_color)
		_add_solid_box(parent, "%sBack" % label, Vector3(0.3, 4.5, segment_length), Vector3(x_position, 2.25, (door_width + segment_length) * 0.5), wall_color)
		_add_visual_box(parent, "%sLintel" % label, Vector3(0.42, 0.32, door_width + 0.35), Vector3(x_position, 3.35, 0), timber_color)
		_add_visual_box(parent, "%sPost" % label, Vector3(0.42, 3.4, 0.24), Vector3(x_position, 1.7, -door_width * 0.5), timber_color)
		_add_visual_box(parent, "%sPost" % label, Vector3(0.42, 3.4, 0.24), Vector3(x_position, 1.7, door_width * 0.5), timber_color)
	else:
		_add_solid_box(parent, label, Vector3(0.3, 4.5, length), Vector3(x_position, 2.25, 0), wall_color)

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
			_add_solid_box(state_root, "ShiftedWallPanel", Vector3(3.2, 1.4, 0.65), obstacle_position, Color(0.46, 0.34 + state * 0.015, 0.23))
	_add_boss_floor_emblem()
	_apply_boss_room_state(0)

func _add_boss_floor_emblem() -> void:
	var emblem := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.2
	mesh.bottom_radius = 2.2
	mesh.height = 0.045
	mesh.material = _make_material(Color(0.34, 0.075, 0.035), 0.22)
	emblem.name = "BossDrumFloorEmblem"
	emblem.mesh = mesh
	emblem.position = Vector3(0, 0.045, -91)
	$BossShiftVisual.add_child(emblem)

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
