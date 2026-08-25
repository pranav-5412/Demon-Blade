extends Node

const SCENE := preload("res://scenes/episode_01/final_selection.tscn")

var failures: Array[String] = []
var checks := 0
var enemy_telegraphs := 0
var boss_telegraphs := 0

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if failures.is_empty():
		print("FINAL_SELECTION_AUTOMATIC_TEST: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("FINAL_SELECTION_AUTOMATIC_TEST: FAIL (%d failures / %d checks)" % [failures.size(), checks])
		get_tree().quit(1)

func _run() -> void:
	GameManager.new_game()
	GameManager.save_data.story_flags["training_completed"] = true
	GameManager.save_data.story_flags["final_selection_intro_seen"] = true
	for form_number in range(1, 8):
		GameManager.save_data.story_flags["water_form_%d_unlocked" % form_number] = true
	var scene := SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	_check(scene.current_day == 1, "Day 1 begins")
	_check(scene.day_label.text == "DAY 1 / 5", "Day counter appears")
	_check(scene.active_enemies.size() == 2, "Day 1 controlled spawn count")
	_check(scene.active_enemies.size() <= 6, "Active enemy cap is respected")
	_check(scene.get_node("EnvironmentGeometry").get_child_count() >= 20, "Multi-region terrain builds")
	for frame in 45:
		await get_tree().physics_frame
	_check(scene.get_node("Player").is_on_floor() and scene.get_node("Player").global_position.y > 0.5, "Player remains supported at the Day 1 spawn")
	scene.player_combatant.current_health = 50.0
	scene.player.health = 50.0
	scene.seconds_since_damage = scene.HEALTH_REGEN_DELAY
	scene._update_health_regeneration(1.0)
	_check(scene.player.health > 50.0 and scene.player.health < scene.player.max_health, "Health regenerates slowly after the damage delay")
	scene.player_combatant.restore_full_health()
	var valid_position := GameManager.save_data.player_position
	GameManager.save_data.player_position = Vector3(500, 10, 500)
	_check(scene._saved_or_checkpoint_position(1) == scene.DAY_CHECKPOINTS[1], "Out-of-bounds saved positions are rejected")
	GameManager.save_data.player_position = valid_position
	scene.player.global_position = Vector3(0, -5, 10)
	await scene._rescue_from_void()
	_check(scene.player.global_position.distance_to(scene.DAY_CHECKPOINTS[1]) < 0.5, "Void fall returns player to current day checkpoint")
	var kinds := ["standard", "fast", "brute", "ranged", "elite"]
	var health_values: Array[float] = []
	for index in kinds.size():
		var enemy = scene._spawn_enemy(kinds[index], Vector3(index * 2.0 - 4.0, 1, 14))
		health_values.append(enemy.combatant.max_health)
		_check(enemy.archetype == kinds[index], "%s archetype configures" % kinds[index])
		_check(enemy.telegraph != null, "%s has attack telegraph" % kinds[index])
	_check(health_values[0] != health_values[1] and health_values[2] > health_values[0] and health_values[4] > health_values[2], "Archetypes have distinct durability")
	var spawn_points_grounded := true
	for day in range(1, 5):
		for spawn_position: Vector3 in scene.DAY_SPAWNS[day]:
			var ray := PhysicsRayQueryParameters3D.create(spawn_position + Vector3(0, 3, 0), spawn_position + Vector3(0, -5, 0))
			if scene.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				spawn_points_grounded = false
	_check(spawn_points_grounded, "Encounter spawns have terrain beneath them")
	var standard = scene.active_enemies[0]
	var health_before: float = standard.combatant.current_health
	var player_hitbox = scene.get_node("Player/CombatController/Hitbox")
	player_hitbox.damage = 12.0
	standard.hurtbox.receive_hit(player_hitbox)
	_check(standard.combatant.current_health < health_before, "Player damages demons")
	var breath_before: float = scene.breathing.current_breath
	var form_activated: bool = await scene.water.activate_form(1)
	_check(form_activated and scene.breathing.current_breath < breath_before, "Water Form activates and spends breath in combat")
	var wan_before := GameManager.save_data.wan_currency
	standard.combatant.receive_damage(9999.0)
	await get_tree().process_frame
	_check(GameManager.save_data.wan_currency > wan_before, "Demon death awards WAN")
	_check(not standard.active, "Demon enters dead state")
	var ranged = scene._spawn_enemy("ranged", scene.player.global_position + Vector3(0, 0, -5))
	var player_health_before: float = scene.player_combatant.current_health
	ranged.windup_time = 0.01
	ranged.attack_telegraphed.connect(func(_enemy, _attack): enemy_telegraphs += 1)
	ranged._perform_attack()
	await get_tree().create_timer(1.1).timeout
	_check(enemy_telegraphs > 0, "Enemy attack emits readable telegraph hook")
	_check(scene.player_combatant.current_health < player_health_before, "Ranged demon damages player with delayed attack")
	scene._refresh_lock_target()
	_check(scene.combat.lock_target != null, "Lock-on receives an enemy target")
	scene.day_transitioning = false
	scene.marker_reached = true
	scene.kills_this_day = int(scene.DAY_CONFIG[1].kills)
	scene._check_day_complete()
	await get_tree().create_timer(2.1).timeout
	_check(scene.current_day == 2, "Day requirements advance progression")
	_check(bool(GameManager.save_data.story_flags.get("final_selection_day_1_completed", false)), "Completed day saves")
	_check(int(GameManager.save_data.story_flags.get("final_selection_day", 0)) == 2, "Saved day is current")
	scene.day_transitioning = false
	await scene._on_player_defeated()
	_check(scene.current_day == 2, "Death restores the current day (actual %d)" % scene.current_day)
	_check(bool(GameManager.save_data.story_flags.get("final_selection_day_1_completed", false)), "Death preserves completed days")
	_check(scene.player.global_position.distance_to(scene.DAY_CHECKPOINTS[2]) < 2.0, "Death restores the day checkpoint position (%s)" % scene.player.global_position)
	scene._start_day(4, false)
	scene.day_transitioning = false
	scene.player.global_position = scene._camp_position_for_day()
	scene.player_combatant.current_health = 20.0
	scene.player.health = 20.0
	scene.interaction_label.visible = true
	scene._on_player_interact()
	_check(scene.recovery_used_today and scene.player.health == scene.player.max_health, "Limited recovery point restores health once per day")
	scene.current_day = 5
	scene._start_day(5, false)
	scene.marker_reached = true
	scene._spawn_boss()
	await get_tree().process_frame
	_check(is_instance_valid(scene.boss), "Day 5 boss appears")
	_check(scene.boss_panel.visible, "Boss health bar appears")
	_check(scene.boss.archetype == "boss" and scene.boss.combatant.max_health >= 800.0, "Boss is specialized beyond normal enemies")
	scene.boss.attack_telegraphed.connect(func(_enemy, _attack): boss_telegraphs += 1)
	scene.player.global_position = scene.boss.global_position + Vector3(0, 0, 3)
	scene.player_combatant.restore_full_health()
	scene.boss.windup_time = 0.01
	scene.boss.attack_index = -1
	var health_before_boss_attack: float = scene.player_combatant.current_health
	scene.boss._perform_attack()
	await get_tree().create_timer(0.65).timeout
	_check(boss_telegraphs > 0, "Boss attack emits telegraph")
	_check(scene.player_combatant.current_health < health_before_boss_attack, "Boss attack damages the player")
	var boss_max: float = scene.boss.combatant.max_health
	scene.boss.combatant.receive_damage(boss_max * 0.55)
	await get_tree().process_frame
	_check(scene.boss.current_phase == 2, "Boss enters phase 2 at half health")
	_check(scene.boss_name.text.contains("PHASE 2"), "Boss phase UI updates")
	scene.boss.combatant.receive_damage(9999.0)
	await get_tree().process_frame
	_check(not scene.boss.active and int(scene.boss.state) == 5, "Boss stops attacking after defeat")
	_check(bool(GameManager.save_data.story_flags.get("final_selection_boss_defeated", false)), "Boss defeat flag saves")
	_check(bool(GameManager.save_data.story_flags.get("final_selection_completed", false)), "Final Selection completion saves")
	_check(int(GameManager.save_data.story_flags.get("final_selection_day", 0)) == 5, "Completion preserves Day 5")
	_check(scene.objective_label.text.contains("Choose your sword material."), "Completion objective is exact")
	_check(GameManager.save_data.sword_material.is_empty(), "Sword material selection does not begin")
	_check(SaveManager.has_save(), "Checkpoint file exists")
	_check(SaveManager.load_save() and int(GameManager.save_data.story_flags.get("final_selection_day", 0)) == 5, "Reload restores progression")
	_check(GameManager.can_autosave() or GameManager.current_state == GameManager.GameState.GAMEPLAY, "Autosave gameplay state remains supported")
	for path in ["res://scenes/episode_01/chapter_01_last_normal_day.tscn", "res://scenes/episode_01/journey_to_shizu.tscn", "res://scenes/episode_01/shizu_training.tscn", "res://scenes/episode_01/final_training_challenge.tscn"]:
		_check(ResourceLoader.exists(path) and load(path) != null, "Existing scene still loads: %s" % path.get_file())
	scene.queue_free()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
