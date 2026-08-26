class_name DrumDemon
extends DemonEnemy

signal room_manipulation_requested(quarter_turns: int)

var drum_attack_count := 0

func configure_drum_boss(player: ThirdPersonPlayer, player_combatant: Combatant) -> void:
	configure("boss", player, player_combatant)
	combatant.max_health = 920.0
	combatant.current_health = combatant.max_health
	damage = 22.0
	movement_speed = 2.65
	attack_cooldown = 1.65
	windup_time = 1.0
	wan_reward = 85
	health_updated.emit(combatant.current_health, combatant.max_health)

func _perform_boss_attack(index: int) -> void:
	var uses_drum := index % (3 if current_phase == 1 else 2) == 0
	if not uses_drum:
		await super._perform_boss_attack(index)
		return
	drum_attack_count += 1
	var turns := -1 if drum_attack_count % 2 == 0 else 1
	attack_telegraphed.emit(self, &"drum_room_shift")
	telegraph.visible = true
	var original_scale := visual.scale
	var prep := create_tween()
	prep.tween_property(visual, "scale", original_scale * Vector3(1.18, 0.82, 1.18), windup_time * 0.8)
	await prep.finished
	if state == AIState.DEAD:
		return
	telegraph.visible = false
	room_manipulation_requested.emit(turns)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(target):
		_damage_player_in_radius(5.5, damage * (0.65 if current_phase == 1 else 0.82))
	var recover := create_tween()
	recover.tween_property(visual, "scale", original_scale, 0.28)
	await recover.finished
	next_attack_time = Time.get_ticks_msec() / 1000.0 + attack_cooldown * (0.68 if current_phase == 2 else 1.0)
	if state != AIState.DEAD:
		state = AIState.CHASE
