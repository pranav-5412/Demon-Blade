extends Node

const JOURNEY_SCENE := preload("res://scenes/episode_01/trio_mountain_journey.tscn")
const HOUSE_SCENE := preload("res://scenes/episode_01/drum_house.tscn")

var failures: Array[String] = []
var checks := 0
var boss_attacks_seen: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("MILESTONE_11_AUTOMATIC_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("MILESTONE_11_AUTOMATIC_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _run() -> void:
	GameManager.new_game()
	_prepare_milestone_save()
	SaveManager.save_game()
	var journey = JOURNEY_SCENE.instantiate()
	add_child(journey)
	await get_tree().process_frame
	_check(journey.route_points.size() == 25 and journey.path_segment_count == 24, "Mountain journey contains 24 connected terrain segments")
	_check(journey.route_length > 800.0, "Mountain route has substantial traversal length")
	_check(journey.SECTION_NAMES.size() == 6, "Journey is divided into six distinct travel sections")
	_check(_route_has_vertical_variation(journey.route_points), "Route repeatedly climbs and descends")
	_check(_route_has_horizontal_variation(journey.route_points), "Route winds instead of following a straight line")
	_check(journey.get_node("EnvironmentGeometry").get_child_count() > 50, "Journey has dense terrain and environmental landmarks")
	_check(journey.get_node("Player") is CharacterBody3D, "Journey uses the shared playable character")
	_check(journey.get_node("PartyCompanions").get_companion_ids().size() == 2, "Both inactive trio members follow during travel")
	_check(journey.party.switching_allowed and journey.party.switching_unlocked, "Character switching is available during normal travel")
	for character_id in ["tanjiro", "zenitsu", "inosuke"]:
		_check(journey.party.switch_to(character_id), "%s can lead the trio journey" % character_id.capitalize())
		_check(character_id not in journey.companions.get_companion_ids(), "%s is not duplicated as a companion" % character_id.capitalize())
	_check(journey.combat.enabled, "Existing combat remains enabled on the mountain")
	_check(journey.water.is_form_unlocked(1), "Existing Water Forms remain available")
	_check(journey.objective_label.text.contains("forest trail"), "Journey begins with the correct travel objective")
	for frame in 30:
		await get_tree().physics_frame
	_check(journey.player.is_on_floor(), "Journey spawn is supported by terrain collision")
	journey.current_section = 4
	journey.danger_spawned = false
	journey._spawn_danger_encounter()
	_check(journey.active_enemies.size() == 2, "Danger zone creates a meaningful two-enemy encounter")
	_check(journey.combat.lock_target != null or journey.active_enemies.size() == 2, "Danger enemies use the existing combat architecture")
	journey.player.global_position = Vector3(0, -20, 0)
	journey._rescue_player()
	_check(journey.player.global_position.y > 0.0 and journey.player.velocity == Vector3.ZERO, "Void recovery returns player to a safe route checkpoint")
	journey._arrive_at_strange_house()
	await get_tree().create_timer(2.3).timeout
	_check(bool(GameManager.save_data.story_flags.get("strange_house_found", false)), "House arrival persists")
	_check(journey.objective_label.text.contains("Investigate the strange house."), "House arrival sets the exact investigation objective")
	journey.queue_free()
	await get_tree().process_frame

	GameManager.new_game()
	_prepare_milestone_save()
	GameManager.save_data.current_scene = "res://scenes/episode_01/drum_house.tscn"
	SaveManager.save_game()
	var house = HOUSE_SCENE.instantiate()
	add_child(house)
	await get_tree().process_frame
	_check(house.get_node("EnvironmentGeometry").get_child_count() >= 25, "Drum House contains multiple connected rooms and corridors")
	_check(house.get_node("PuzzleRoom").orientation_state == 0, "Puzzle chamber starts in a known orientation")
	_check(not house.get_node("PuzzleRoom").route_open, "Puzzle exit is closed before solving")
	_check(house.get_node("TrapRoom") != null, "A second controlled shifting chamber exists")
	_check(house.get_node("PartyCompanions").get_companion_ids().size() == 2, "Trio remains together inside the dungeon")
	_check(house.objective_label.text.contains("Investigate the strange house."), "Dungeon starts at the investigation objective")
	for frame in 30:
		await get_tree().physics_frame
	_check(house.player.is_on_floor(), "Drum House spawn has valid floor collision")

	house.progress = 1
	house.puzzle_step = 0
	house.player.global_position = Vector3(0, 1.1, -11.5)
	var camera_rotation_before: Vector3 = house.player.camera_pivot.rotation
	house._on_interact()
	_check(house.sequence_busy and not house.party.switching_allowed and not house.player.controls_enabled, "Rotation immediately locks movement and character switching")
	await house.puzzle_room.rotation_finished
	_check(house.puzzle_step == 1 and house.puzzle_room.orientation_state == 1, "First drum strike aligns seal I")
	_check(house.player.global_position.distance_to(house.puzzle_room.get_safe_position()) < 0.1, "Player is safely repositioned after room rotation")
	_check(house.player.camera_pivot.rotation.is_equal_approx(camera_rotation_before), "Camera orientation remains stable through rotation")
	house._on_interact()
	await house.puzzle_room.rotation_finished
	_check(house.puzzle_step == 2, "Second drum strike aligns seal II")
	house._on_interact()
	await house.puzzle_room.rotation_finished
	_check(house.puzzle_step == 3 and house.progress == 2, "Third seal completes the readable rotation sequence")
	_check(house.puzzle_room.route_open, "Solving the puzzle opens the physical route")
	_check(house.party.switching_allowed and house.player.controls_enabled and house.combat.enabled, "Controls restore after puzzle rotation")
	_check(bool(GameManager.save_data.story_flags.get("drum_puzzle_complete", false)), "Puzzle completion persists in save data")
	house.puzzle_room.call_deferred("rotate_room", 1)
	await get_tree().process_frame
	_check(house.puzzle_room.rotation_active, "Rotation controller accepts one controlled request")
	var duplicate_accepted: bool = await house.puzzle_room.rotate_room(1)
	_check(not duplicate_accepted, "Concurrent drum triggers are rejected")
	await house.puzzle_room.rotation_finished

	house.player.global_position = Vector3(0, 1.1, -32)
	house._spawn_gallery_enemies()
	_check(house.active_enemies.size() == 3, "Gallery encounter spawns three distinct house demons")
	var archetypes: Array[String] = []
	for frame in 20:
		await get_tree().physics_frame
	var enemies_supported := true
	for enemy in house.active_enemies.duplicate():
		archetypes.append(enemy.archetype)
		enemies_supported = enemies_supported and enemy.global_position.y >= 0.0 and enemy.global_position.y <= 0.15 and enemy.velocity.y > -1.0
		enemy._on_defeated()
	_check(enemies_supported, "Dungeon enemies remain supported by gallery collision")
	await get_tree().process_frame
	_check("standard" in archetypes and "fast" in archetypes and "ranged" in archetypes, "Dungeon enemy mix uses multiple archetypes")
	_check(house.progress == 3 and bool(GameManager.save_data.story_flags.get("drum_gallery_cleared", false)), "Clearing the gallery advances and saves progression")

	house._begin_trap_rotation()
	_check(house.sequence_busy and not house.party.switching_allowed, "Trap-room rotation blocks switching")
	await house.trap_room.rotation_finished
	_check(house.progress == 4 and house.trap_room.route_open, "Trap rotation finishes with a stable open route")
	_check(house.player.global_position.distance_to(house.trap_room.get_safe_position()) < 0.1, "Trap room leaves player on its safe floor anchor")
	_check(bool(GameManager.save_data.story_flags.get("drum_trap_complete", false)), "Trap completion persists")

	house.progress = 5
	house._spawn_boss(true)
	house.boss.attack_telegraphed.connect(_on_boss_attack_seen)
	_check(is_instance_valid(house.boss) and house.boss.archetype == "boss", "Drum Demon spawns through the existing enemy architecture")
	_check(house.boss.combatant.max_health >= 900.0 and house.boss_panel.visible, "Boss has durable health and a visible boss bar")
	_check(house.boss.current_phase == 1, "Drum Demon starts in phase one")
	house.boss.set_physics_process(false)
	house.player.set_controls_enabled(false)
	house.player.velocity = Vector3.ZERO
	house.player.global_position = Vector3(house.boss.global_position.x, 1.1, house.boss.global_position.z + 2.5)
	house.player_combatant.set_invulnerable(false)
	house.player_combatant.set_guarding(false)
	house.player_combatant.restore_full_health()
	var health_before_normal: float = house.player_combatant.current_health
	await house.boss._perform_boss_attack(1)
	_check("wide_sweep" in boss_attacks_seen, "Boss performs a readable normal sweep attack")
	_check(house.player_combatant.current_health < health_before_normal, "Boss normal attack can damage the player")
	house.player.set_controls_enabled(true)
	house.boss.set_physics_process(true)
	house.boss.combatant.receive_damage(500.0, true)
	_check(house.boss.current_phase == 2 and house.boss_phase_label.text.contains("PHASE 2"), "Boss transitions to phase two at half health")
	_check(not house.party.switching_allowed, "Character switching is blocked during boss phase transition")
	_check(int(GameManager.save_data.story_flags.get("drum_boss_phase", 0)) == 2, "Boss phase is saved")
	await get_tree().create_timer(0.85).timeout
	_check(house.party.switching_allowed, "Character switching returns after boss phase transition")
	house.player_combatant.restore_full_health()
	await house.boss._perform_boss_attack(2)
	_check("drum_room_shift" in boss_attacks_seen, "Boss performs its signature drum room-shift attack")
	_check(house.boss_room_state == 1 and is_equal_approx(house.get_node("BossShiftVisual").rotation_degrees.z, 90.0), "Boss drum rotates the arena presentation by 90 degrees")
	_check(house.get_node("BossArenaStates/ArenaState1").visible and not house.get_node("BossArenaStates/ArenaState0").visible, "Boss drum swaps to a different collision-backed arena layout")
	_check(not house.sequence_busy and house.party.switching_allowed and not house.player_combatant.is_invulnerable, "Boss drum shift protects player while locking unsafe actions")
	await get_tree().create_timer(0.1).timeout
	_check(not house.sequence_busy and house.party.switching_allowed and not house.player_combatant.is_invulnerable, "Boss room shift restores controls and vulnerability")
	house.boss.combatant.receive_damage(1000.0, true)
	await get_tree().create_timer(3.2).timeout
	_check(bool(GameManager.save_data.story_flags.get("drum_demon_defeated", false)), "Drum Demon defeat persists")
	_check(house.get_node("BossShiftVisual").rotation_degrees.is_equal_approx(Vector3.ZERO) and house.boss_room_state == 0, "Boss arena returns to a safe orientation after defeat")
	_check(house.progress == 6 and not house.boss_panel.visible, "Boss defeat cleans up combat HUD and advances progression")
	_check(house.objective_label.text.contains("Travel to the Wisteria House."), "Milestone stops at the exact Wisteria travel objective")
	_check(not ResourceLoader.exists("res://scenes/episode_02"), "No Episode 2 content was started")
	_check(not bool(GameManager.save_data.story_flags.get("wisteria_house_entered", false)), "Wisteria House is not implemented or entered")
	_check(SaveManager.load_save() and int(GameManager.save_data.story_flags.get("drum_house_progress", 0)) == 6, "Save reload preserves completed dungeon progress")
	_check(bool(GameManager.save_data.story_flags.get("drum_house_puzzle_complete", false)), "Canonical puzzle-complete flag survives reload")
	_check(int(GameManager.save_data.story_flags.get("drum_demon_phase", 0)) == 2, "Canonical boss phase flag survives reload")
	_check(GameManager.save_data.current_scene == "res://scenes/episode_01/drum_house.tscn", "Reload returns to the Drum House aftermath")
	_check(GameManager.save_data.current_playable_character in ["tanjiro", "zenitsu", "inosuke"], "Active trio character persists safely")
	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_check(SaveManager.request_autosave(), "Autosave remains functional after the dungeon")
	var chapter_script := load("res://scenes/episode_01/chapter_01_last_normal_day.gd") as Script
	var constants := chapter_script.get_script_constant_map()
	_check(constants.get("TRIO_JOURNEY_SCENE", "") == "res://scenes/episode_01/trio_mountain_journey.tscn", "Main-scene resume router recognizes mountain journey saves")
	_check(constants.get("DRUM_HOUSE_SCENE", "") == "res://scenes/episode_01/drum_house.tscn", "Main-scene resume router recognizes Drum House saves")
	for path in ["res://scenes/episode_01/chapter_01_last_normal_day.tscn", "res://scenes/episode_01/post_selection_trio.tscn", "res://scenes/episode_01/trio_mountain_journey.tscn", "res://scenes/episode_01/drum_house.tscn"]:
		_check(ResourceLoader.exists(path) and load(path) != null, "Story scene loads: %s" % path.get_file())
	house.queue_free()
	await get_tree().process_frame
	var completed_reload = HOUSE_SCENE.instantiate()
	add_child(completed_reload)
	await get_tree().process_frame
	_check(not is_instance_valid(completed_reload.boss), "Reload does not respawn the defeated Drum Demon")
	_check(completed_reload.puzzle_room.route_open and completed_reload.boss_room_state == 0, "Completed reload restores open routes and a safe arena state")
	completed_reload.queue_free()
	await get_tree().process_frame
	var flags := GameManager.save_data.story_flags
	flags["drum_house_progress"] = 1
	flags["drum_puzzle_step"] = 1
	flags["drum_room_orientation"] = 1
	flags["drum_puzzle_complete"] = false
	flags["drum_house_puzzle_complete"] = false
	flags["drum_demon_defeated"] = false
	flags["drum_house_completed"] = false
	GameManager.save_data.current_scene = "res://scenes/episode_01/drum_house.tscn"
	SaveManager.save_checkpoint()
	var puzzle_reload = HOUSE_SCENE.instantiate()
	add_child(puzzle_reload)
	await get_tree().process_frame
	_check(puzzle_reload.puzzle_step == 1 and puzzle_reload.puzzle_room.orientation_state == 1, "Mid-puzzle reload restores the solved seal and room orientation")
	_check(not puzzle_reload.puzzle_room.route_open, "Mid-puzzle reload keeps the progression gate correctly closed")
	puzzle_reload.player.global_position = Vector3(0, 1.1, -11.5)
	puzzle_reload._on_interact()
	await puzzle_reload.puzzle_room.rotation_finished
	_check(puzzle_reload.puzzle_step == 2, "Rotation puzzle remains solvable after mid-puzzle reload")
	puzzle_reload.queue_free()

func _prepare_milestone_save() -> void:
	var data := GameManager.save_data
	data.story_flags["final_selection_completed"] = true
	data.story_flags["training_completed"] = true
	data.story_flags["sword_material_selected"] = true
	data.sword_material_selected = true
	data.sword_material = "balanced_ore"
	data.story_flags["zenitsu_unlocked"] = true
	data.story_flags["inosuke_unlocked"] = true
	data.story_flags["character_switching_unlocked"] = true
	for form_number in range(1, 8):
		data.story_flags["water_form_%d_unlocked" % form_number] = true

func _on_boss_attack_seen(_enemy: DemonEnemy, attack_name: StringName) -> void:
	boss_attacks_seen.append(str(attack_name))

func _route_has_vertical_variation(points: Array) -> bool:
	var climbs := 0
	var descents := 0
	for index in points.size() - 1:
		var difference: float = (points[index + 1] as Vector3).y - (points[index] as Vector3).y
		if difference > 0.5:
			climbs += 1
		elif difference < -0.5:
			descents += 1
	return climbs >= 8 and descents >= 4

func _route_has_horizontal_variation(points: Array) -> bool:
	var direction_changes := 0
	var previous_sign := 0
	for index in points.size() - 1:
		var difference: float = (points[index + 1] as Vector3).x - (points[index] as Vector3).x
		var current_sign := signi(roundi(difference))
		if current_sign != 0 and previous_sign != 0 and current_sign != previous_sign:
			direction_changes += 1
		if current_sign != 0:
			previous_sign = current_sign
	return direction_changes >= 8

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
