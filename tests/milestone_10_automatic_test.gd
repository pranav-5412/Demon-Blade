extends Node

const SCENE := preload("res://scenes/episode_01/post_selection_trio.tscn")

var failures: Array[String] = []
var checks := 0
var attacks_seen: Array[String] = []
var abilities_seen: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("MILESTONE_10_AUTOMATIC_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("MILESTONE_10_AUTOMATIC_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _run() -> void:
	GameManager.new_game()
	GameManager.save_data.story_flags["final_selection_completed"] = true
	GameManager.save_data.story_flags["final_selection_boss_defeated"] = true
	GameManager.save_data.story_flags["final_selection_day"] = 5
	GameManager.save_data.story_flags["training_completed"] = true
	for form_number in range(1, 8):
		GameManager.save_data.story_flags["water_form_%d_unlocked" % form_number] = true
	var scene = SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	_check(scene.state == scene.ProgressState.APPROACH_MATERIAL, "Post-selection starts at physical material objective")
	_check(scene.objective_label.text.contains("Choose your sword material."), "Sword material objective is exact")
	_check(scene.MATERIALS.size() == 4, "Four material choices are available")
	var material_ids: Array[String] = []
	for index in scene.MATERIALS.size():
		scene.material_index = index
		scene._update_material_panel()
		var option: Dictionary = scene.MATERIALS[index]
		material_ids.append(str(option.id))
		_check(not scene.material_name.text.is_empty() and not scene.material_effect.text.is_empty(), "Material option %d shows name, description, and gameplay effect" % (index + 1))
	_check(material_ids.duplicate().size() == 4 and material_ids[0] != material_ids[1] and material_ids[1] != material_ids[2] and material_ids[2] != material_ids[3], "All material options have distinct saved IDs")
	_check(scene.get_node("Player") is CharacterBody3D, "Shared playable CharacterBody3D exists")
	_check(scene.get_node("Player/CameraPivot/SpringArm3D/Camera3D").current, "Existing third-person camera is active")
	await get_tree().physics_frame
	_check(not scene.training_dummy.visible and not scene.training_dummy.get_node("Hurtbox").monitorable, "Hidden tutorial target has no active damage area")
	for frame in 30:
		await get_tree().physics_frame
	_check(scene.player.is_on_floor(), "Player is supported in post-selection area")

	scene.player.global_position = scene.get_node("MaterialAltar").global_position + Vector3(0, 0.6, 2.0)
	scene._open_material_selection()
	_check(scene.selection_panel.visible and not scene.player.controls_enabled, "Material menu opens without movement leak")
	var original_index: int = scene.material_index
	scene._select_next_material()
	_check(scene.material_index != original_index, "Material browsing changes selection")
	scene._cancel_material_confirmation()
	_check(not scene.selection_panel.visible and scene.state == scene.ProgressState.APPROACH_MATERIAL, "Material menu can be backed out without trapping player")
	scene._open_material_selection()
	scene.material_index = 2
	scene._confirm_material()
	_check(scene.material_confirmation_pending and not GameManager.save_data.sword_material_selected, "First confirmation asks Choose this material")
	scene._confirm_material()
	_check(GameManager.save_data.sword_material_selected, "Material choice locks only after confirmation")
	_check(GameManager.save_data.sword_material == "dense_iron", "Chosen material ID is stored")
	_check(scene.combat.heavy_damage > 24.0 and scene.combat.heavy_attack_time > 0.78, "Dense material applies stronger, slower heavy attacks")
	GameManager.save_data.sword_material = "balanced_ore"
	scene.party.apply_character("tanjiro", false)
	_check(scene.combat.damage_multiplier > 1.0, "Balanced material applies its even damage bonus")
	GameManager.save_data.sword_material = "swift_alloy"
	scene.party.apply_character("tanjiro", false)
	_check(scene.combat.light_attack_time < 0.42 and scene.combat.heavy_damage < 24.0, "Light material applies faster attacks and weaker heavy power")
	GameManager.save_data.sword_material = "focused_steel"
	scene.party.apply_character("tanjiro", false)
	_check(scene.breathing.regeneration_per_second > 9.0, "Focused material improves breathing efficiency")
	GameManager.save_data.sword_material = "dense_iron"
	scene.party.apply_character("tanjiro", false)
	_check(bool(GameManager.save_data.story_flags.get("sword_material_selected", false)), "Material selection flag is stored")
	_check(scene.state == scene.ProgressState.APPROACH_ZENITSU and not scene.selection_panel.visible, "Story proceeds after selection")
	var chosen_before := GameManager.save_data.sword_material
	scene._confirm_material()
	_check(GameManager.save_data.sword_material == chosen_before, "Material selection cannot be confirmed twice")
	_check(SaveManager.load_save() and GameManager.save_data.sword_material_selected and GameManager.save_data.sword_material == "dense_iron", "Reload preserves material choice")

	scene.player.global_position = scene.zenitsu_npc.global_position + Vector3(0, 0.6, 2.0)
	await scene._introduce_zenitsu()
	_check(bool(GameManager.save_data.story_flags.get("zenitsu_met", false)), "Zenitsu introduction saves")
	_check(bool(GameManager.save_data.story_flags.get("zenitsu_unlocked", false)), "Zenitsu unlock saves")
	_check(scene.party.current_character == "zenitsu", "Zenitsu becomes the active playable character")
	_check(scene.player.sprint_speed >= 9.0 and scene.player.max_health < 100.0, "Zenitsu has high mobility and lower durability")
	_check(not scene.water.enabled, "Zenitsu cannot use Water Breathing")
	scene._update_hud()
	_check(scene.ability_label.text.contains("LIGHTNING STEP") and not scene.ability_label.text.contains("WATER BREATHING"), "HUD adapts to Zenitsu ability")
	_check(not scene.get_node("Player/Visual/OffhandSword").visible, "Zenitsu uses a single distinct weapon silhouette")
	Input.action_press("move_forward")
	scene.player._update_horizontal_velocity(0.2)
	Input.action_release("move_forward")
	_check(Vector2(scene.player.velocity.x, scene.player.velocity.z).length() > 0.1, "Zenitsu movement uses the shared controller")
	attacks_seen.clear()
	if not scene.combat.attack_performed.is_connected(_on_attack_seen):
		scene.combat.attack_performed.connect(_on_attack_seen)
	scene.player.stamina = scene.player.max_stamina
	scene.combat.perform_attack("light")
	await get_tree().create_timer(0.5).timeout
	_check("light" in attacks_seen, "Zenitsu light attack executes")
	_check(scene.combat.light_attack_time < 0.35, "Zenitsu basic attack timing is distinctly fast")
	scene.player.stamina = scene.player.max_stamina
	scene.combat._perform_dodge()
	await get_tree().create_timer(1.1).timeout
	_check(scene.combat.dodge_speed > 8.0 and not scene.combat.is_busy, "Zenitsu fast dodge completes safely")
	scene.training_dummy.reset_dummy(180.0)
	scene.training_dummy.global_position = scene.player.global_position - scene.player.global_basis.z * 7.4
	var zenitsu_health_before: float = scene.training_dummy.combatant.current_health
	scene.player.stamina = scene.player.max_stamina
	abilities_seen.clear()
	if not scene.party.unique_ability_used.is_connected(_on_ability_seen):
		scene.party.unique_ability_used.connect(_on_ability_seen)
	await scene.party.activate_unique_ability()
	await get_tree().physics_frame
	_check("zenitsu" in abilities_seen, "Lightning Step activates")
	_check(scene.training_dummy.combatant.current_health < zenitsu_health_before, "Lightning Step damages a target")
	_check(scene.party.get_cooldown_remaining("zenitsu") > 0.0, "Lightning Step applies cooldown")
	_check(scene.player.controls_enabled and scene.combat.enabled, "Zenitsu ability restores controls")
	scene.tutorial_progress = {"move": true, "dodge": true, "light": true, "ability": true}
	scene._update_tutorial_and_check_completion()
	await get_tree().process_frame
	_check(scene.state == scene.ProgressState.APPROACH_INOSUKE, "Zenitsu short tutorial completes")
	await get_tree().physics_frame
	_check(not scene.training_dummy.get_node("Hurtbox").monitorable, "Zenitsu target disables after tutorial")

	scene.player.global_position = scene.inosuke_npc.global_position + Vector3(0, 0.6, 2.0)
	await scene._introduce_inosuke()
	_check(bool(GameManager.save_data.story_flags.get("inosuke_met", false)), "Inosuke introduction saves")
	_check(bool(GameManager.save_data.story_flags.get("inosuke_unlocked", false)), "Inosuke unlock saves")
	_check(scene.party.current_character == "inosuke", "Inosuke becomes the active playable character")
	_check(scene.player.max_health > 120.0 and scene.combat.light_chain_hits == 2, "Inosuke has durable dual-strike profile")
	_check(scene.get_node("Player/Visual/OffhandSword").visible, "Inosuke visibly uses two blades")
	_check(not scene.water.enabled, "Inosuke cannot use Water Breathing")
	scene._update_hud()
	_check(scene.ability_label.text.contains("BEAST RUSH") and not scene.ability_label.text.contains("WATER BREATHING"), "HUD adapts to Inosuke ability")
	attacks_seen.clear()
	scene.player.stamina = scene.player.max_stamina
	scene.combat.perform_attack("light")
	await get_tree().create_timer(0.8).timeout
	scene.player.stamina = scene.player.max_stamina
	scene.combat.perform_attack("heavy")
	await get_tree().create_timer(1.0).timeout
	_check("light" in attacks_seen, "Inosuke dual-blade light chain executes")
	_check("heavy" in attacks_seen and scene.combat.heavy_chain_hits == 2, "Inosuke heavy dual strike executes")
	scene.player.stamina = scene.player.max_stamina
	scene.combat._perform_dodge()
	await get_tree().create_timer(1.1).timeout
	_check(not scene.combat.is_busy and scene.combat.dodge_speed > 7.0, "Inosuke dodge completes safely")
	scene.training_dummy.reset_dummy(220.0)
	scene.training_dummy.global_position = scene.player.global_position - scene.player.global_basis.z * 5.2
	var inosuke_health_before: float = scene.training_dummy.combatant.current_health
	scene.player.stamina = scene.player.max_stamina
	await scene.party.activate_unique_ability()
	await get_tree().physics_frame
	_check("inosuke" in abilities_seen, "Beast Rush activates")
	_check(scene.training_dummy.combatant.current_health < inosuke_health_before, "Beast Rush damages a target")
	_check(scene.party.get_cooldown_remaining("inosuke") > 0.0, "Beast Rush applies cooldown")
	scene.tutorial_progress = {"light": true, "heavy": true, "dodge": true, "ability": true}
	scene._update_tutorial_and_check_completion()
	await get_tree().process_frame
	_check(scene.state == scene.ProgressState.COMPLETE, "Inosuke short tutorial completes")
	await get_tree().physics_frame
	_check(not scene.training_dummy.get_node("Hurtbox").monitorable, "Inosuke target disables after tutorial")
	_check(bool(GameManager.save_data.story_flags.get("character_switching_unlocked", false)), "Character switching unlock saves")
	_check(scene.objective_label.text.contains("Travel through the mountain with Zenitsu and Inosuke."), "Milestone stops at exact trio journey objective")
	_check(not bool(GameManager.save_data.story_flags.get("drum_house_started", false)), "Drum House does not begin")

	var shared_player: ThirdPersonPlayer = scene.player
	var position_before: Vector3 = shared_player.global_position
	var facing_before: Vector3 = shared_player.rotation
	var camera_before: Vector3 = shared_player.camera_pivot.rotation
	_check(scene.party.switch_to("tanjiro"), "Inosuke to Tanjiro switch works")
	_check(scene.player == shared_player and scene.player.global_position.is_equal_approx(position_before), "Switch preserves one body and world position")
	_check(scene.player.rotation.is_equal_approx(facing_before) and scene.player.camera_pivot.rotation.is_equal_approx(camera_before), "Switch preserves facing and camera orientation")
	_check(scene.water.enabled and scene.get_node("Player/Visual/OffhandSword").visible == false, "Tanjiro Water Forms and sword restore")
	scene._update_hud()
	_check(scene.ability_label.text.contains("WATER BREATHING"), "HUD restores Tanjiro Water Forms")
	scene.breathing.refill(scene.breathing.max_breath)
	var tanjiro_breath_before: float = scene.breathing.current_breath
	var tanjiro_form_works: bool = await scene.water.activate_form(1)
	_check(tanjiro_form_works and scene.breathing.current_breath < tanjiro_breath_before, "Tanjiro Water Form still activates after switching")
	_check(scene.party.switch_to("zenitsu"), "Tanjiro to Zenitsu switch works")
	_check(scene.party.switch_to("inosuke"), "Zenitsu to Inosuke switch works")
	_check(scene.find_children("*", "CharacterBody3D", true, false).size() == 1 and scene.get_node("Player") == shared_player, "Switching creates no duplicate player body")
	for frame in 10:
		await get_tree().physics_frame
	_check(scene.player.is_on_floor() and scene.player.global_position.y > -0.2, "Active character remains on terrain after repeated switches")
	scene.party.set_switching_allowed(false)
	_check(not scene.party.switch_to("tanjiro") and scene.party.current_character == "inosuke", "Switch input is rejected during locked story state")
	scene.party.set_switching_allowed(true)

	for character_id in ["tanjiro", "zenitsu", "inosuke"]:
		scene.party.switch_to(character_id)
		SaveManager.save_checkpoint()
		var saved_position: Vector3 = scene.player.global_position
		GameManager.new_game()
		_check(SaveManager.load_save() and GameManager.save_data.current_playable_character == character_id, "Reload restores %s" % character_id.capitalize())
		_check(GameManager.save_data.player_position.distance_to(saved_position) < 0.1, "Reload preserves position for %s" % character_id.capitalize())
		scene.party.initialize_from_save()
		scene.party.switching_unlocked = true
		scene.party.set_switching_allowed(true)
	var preserved_stats: Dictionary = GameManager.save_data.story_flags.get("character_stats", {})
	preserved_stats["tanjiro"] = {"health": 63.0, "stamina": 71.0}
	preserved_stats["zenitsu"] = {"health": 39.0, "stamina": 52.0}
	GameManager.save_data.story_flags["character_stats"] = preserved_stats
	GameManager.save_data.current_playable_character = "zenitsu"
	scene.player.health = 39.0
	scene.player.stamina = 52.0
	scene.party.current_character = "tanjiro"
	scene.party.initialize_from_save()
	var restored_stats: Dictionary = GameManager.save_data.story_flags.get("character_stats", {})
	_check(is_equal_approx(float((restored_stats["tanjiro"] as Dictionary).health), 63.0), "Reloading another character does not overwrite Tanjiro vitals")
	_check(scene.party.current_character == "zenitsu" and is_equal_approx(scene.player.health, 39.0), "Reload restores Zenitsu independent vitals")

	GameManager.set_game_state(GameManager.GameState.GAMEPLAY)
	_check(SaveManager.request_autosave(), "Autosave remains functional in gameplay")
	GameManager.save_data.story_flags["character_switching_unlocked"] = false
	GameManager.save_data.story_flags["inosuke_unlocked"] = false
	GameManager.save_data.story_flags["zenitsu_unlocked"] = true
	GameManager.save_data.story_flags["zenitsu_tutorial_completed"] = false
	scene._restore_progress_state()
	_check(scene.state == scene.ProgressState.ZENITSU_TUTORIAL, "Reload during Zenitsu tutorial resumes that tutorial")
	GameManager.save_data.story_flags["zenitsu_tutorial_completed"] = true
	scene._restore_progress_state()
	_check(scene.state == scene.ProgressState.APPROACH_INOSUKE, "Completed Zenitsu tutorial resumes at Inosuke introduction")
	GameManager.save_data.story_flags["inosuke_unlocked"] = true
	GameManager.save_data.story_flags["inosuke_tutorial_completed"] = false
	scene._restore_progress_state()
	_check(scene.state == scene.ProgressState.INOSUKE_TUTORIAL, "Reload during Inosuke tutorial resumes that tutorial")
	GameManager.save_data.story_flags["inosuke_tutorial_completed"] = true
	GameManager.save_data.story_flags["character_switching_unlocked"] = true
	scene._restore_progress_state()
	_check(scene.state == scene.ProgressState.COMPLETE, "Completed tutorials restore the trio-ready state")
	SaveManager.save_checkpoint()
	for path in ["res://scenes/episode_01/chapter_01_last_normal_day.tscn", "res://scenes/episode_01/journey_to_shizu.tscn", "res://scenes/episode_01/shizu_training.tscn", "res://scenes/episode_01/final_training_challenge.tscn", "res://scenes/episode_01/final_selection.tscn"]:
		_check(ResourceLoader.exists(path) and load(path) != null, "Previous scene still loads: %s" % path.get_file())
	var chapter_script := load("res://scenes/episode_01/chapter_01_last_normal_day.gd") as Script
	_check(chapter_script.get_script_constant_map().get("POST_SELECTION_SCENE", "") == scene.SCENE_PATH, "Game restart router recognizes post-selection saves")
	_check(not ResourceLoader.exists("res://scenes/episode_01/drum_house.tscn"), "No later Drum House content was created")
	scene.queue_free()

func _on_attack_seen(attack_type: String) -> void:
	attacks_seen.append(attack_type)

func _on_ability_seen(character_id: String, _ability_name: String) -> void:
	abilities_seen.append(character_id)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
