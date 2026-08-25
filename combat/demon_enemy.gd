class_name DemonEnemy
extends CharacterBody3D

signal died(enemy: DemonEnemy, wan_reward: int, archetype: String)
signal attack_telegraphed(enemy: DemonEnemy, attack_name: StringName)
signal attack_landed(enemy: DemonEnemy)
signal health_updated(current: float, maximum: float)
signal phase_changed(phase_number: int)

enum AIState { IDLE, PATROL, CHASE, ATTACK, STAGGER, DEAD }

const ARCHETYPES := {
	"standard": {"health": 75.0, "damage": 10.0, "speed": 3.2, "detect": 15.0, "range": 2.3, "cooldown": 1.45, "windup": 0.62, "wan": 3, "color": Color(0.38, 0.12, 0.12)},
	"fast": {"health": 52.0, "damage": 8.0, "speed": 5.0, "detect": 19.0, "range": 2.0, "cooldown": 0.95, "windup": 0.42, "wan": 4, "color": Color(0.38, 0.1, 0.42)},
	"brute": {"health": 145.0, "damage": 20.0, "speed": 2.15, "detect": 14.0, "range": 2.9, "cooldown": 2.15, "windup": 1.05, "wan": 7, "color": Color(0.36, 0.24, 0.08)},
	"ranged": {"health": 68.0, "damage": 11.0, "speed": 2.8, "detect": 22.0, "range": 10.0, "cooldown": 1.8, "windup": 0.85, "wan": 6, "color": Color(0.08, 0.28, 0.34)},
	"elite": {"health": 215.0, "damage": 18.0, "speed": 3.65, "detect": 24.0, "range": 3.0, "cooldown": 1.2, "windup": 0.62, "wan": 14, "color": Color(0.45, 0.08, 0.08)},
	"boss": {"health": 850.0, "damage": 24.0, "speed": 2.8, "detect": 35.0, "range": 4.2, "cooldown": 1.8, "windup": 1.0, "wan": 60, "color": Color(0.22, 0.035, 0.03)},
}

var archetype := "standard"
var target: ThirdPersonPlayer
var target_combatant: Combatant
var combatant: Combatant
var hurtbox: CombatHurtbox
var visual: Node3D
var body_mesh: MeshInstance3D
var telegraph: MeshInstance3D
var state := AIState.IDLE
var damage := 10.0
var movement_speed := 3.0
var detection_range := 15.0
var attack_range := 2.3
var attack_cooldown := 1.4
var windup_time := 0.6
var wan_reward := 3
var next_attack_time := 0.0
var spawn_origin := Vector3.ZERO
var patrol_target := Vector3.ZERO
var stagger_hits := 0
var current_phase := 1
var attack_index := 0
var active := true

func _ready() -> void:
	_build_actor()
	set_physics_process(true)

func configure(kind: String, player: ThirdPersonPlayer, player_combatant: Combatant) -> void:
	archetype = kind if ARCHETYPES.has(kind) else "standard"
	target = player
	target_combatant = player_combatant
	var stats: Dictionary = ARCHETYPES[archetype]
	combatant.max_health = float(stats.health)
	combatant.current_health = combatant.max_health
	damage = float(stats.damage)
	movement_speed = float(stats.speed)
	detection_range = float(stats.detect)
	attack_range = float(stats.range)
	attack_cooldown = float(stats.cooldown)
	windup_time = float(stats.windup)
	wan_reward = int(stats.wan)
	spawn_origin = global_position
	patrol_target = spawn_origin + Vector3(2.0, 0.0, 1.5)
	_apply_archetype_visual(stats.color)
	health_updated.emit(combatant.current_health, combatant.max_health)

func _physics_process(delta: float) -> void:
	if not active or state in [AIState.ATTACK, AIState.STAGGER, AIState.DEAD] or not is_instance_valid(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if distance > detection_range + 8.0:
		state = AIState.IDLE
		velocity = Vector3.ZERO
		return
	if distance <= attack_range and Time.get_ticks_msec() / 1000.0 >= next_attack_time:
		_perform_attack()
		return
	state = AIState.CHASE
	var direction := target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		velocity = direction * movement_speed
		look_at(global_position + direction, Vector3.UP)
		move_and_slide()
	else:
		velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= 18.0 * delta

func _perform_attack() -> void:
	if state == AIState.DEAD:
		return
	state = AIState.ATTACK
	velocity = Vector3.ZERO
	attack_index += 1
	if archetype == "boss":
		_perform_boss_attack(attack_index)
	else:
		_perform_normal_attack()

func _perform_normal_attack() -> void:
	var attack_name: StringName = &"ranged_orb" if archetype == "ranged" else (&"heavy_slam" if archetype == "brute" else &"claw_strike")
	attack_telegraphed.emit(self, attack_name)
	telegraph.visible = true
	var original_scale := visual.scale
	var windup := create_tween()
	windup.tween_property(visual, "scale", original_scale * Vector3(1.18, 0.82, 1.18), windup_time)
	await windup.finished
	if state == AIState.DEAD:
		return
	telegraph.visible = false
	if archetype == "ranged":
		_launch_projectile()
	elif global_position.distance_to(target.global_position) <= attack_range + 0.7:
		if target_combatant.receive_damage(damage, true):
			attack_landed.emit(self)
	var recover := create_tween()
	recover.tween_property(visual, "scale", original_scale, 0.25)
	await recover.finished
	next_attack_time = Time.get_ticks_msec() / 1000.0 + attack_cooldown
	if state != AIState.DEAD:
		state = AIState.CHASE

func _perform_boss_attack(index: int) -> void:
	var pattern_count := 5 if current_phase == 2 else 3
	var pattern := index % pattern_count
	var attack_name: StringName = [&"heavy_slam", &"wide_sweep", &"forward_charge", &"shockwave", &"frenzy_combo"][pattern]
	attack_telegraphed.emit(self, attack_name)
	telegraph.visible = true
	var original_scale := visual.scale
	var prep := create_tween()
	prep.tween_property(visual, "scale", original_scale * Vector3(1.22, 0.78, 1.22), windup_time * (0.72 if current_phase == 2 else 1.0))
	await prep.finished
	if state == AIState.DEAD:
		return
	telegraph.visible = false
	match pattern:
		0:
			_damage_player_in_radius(4.7, damage * 1.25)
		1:
			_damage_player_in_radius(6.2, damage * 0.8)
		2:
			var charge_direction := (target.global_position - global_position).normalized()
			charge_direction.y = 0.0
			move_and_collide(charge_direction * 5.5)
			_damage_player_in_radius(3.2, damage)
		3:
			_spawn_shockwave()
		4:
			for strike in 3:
				_damage_player_in_radius(4.0, damage * 0.55)
				await get_tree().create_timer(0.22).timeout
	var recover := create_tween()
	recover.tween_property(visual, "scale", original_scale, 0.3)
	await recover.finished
	next_attack_time = Time.get_ticks_msec() / 1000.0 + attack_cooldown * (0.68 if current_phase == 2 else 1.0)
	if state != AIState.DEAD:
		state = AIState.CHASE

func _launch_projectile() -> void:
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.75, 0.82)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.5, 0.8)
	mesh.material = material
	orb.mesh = mesh
	get_parent().add_child(orb)
	orb.global_position = global_position + Vector3(0, 1.2, 0)
	var target_position := target.global_position + Vector3(0, 0.8, 0)
	var flight := create_tween()
	flight.tween_property(orb, "global_position", target_position, 0.75)
	await flight.finished
	if is_instance_valid(target) and orb.global_position.distance_to(target.global_position + Vector3(0, 0.8, 0)) < 1.5:
		if target_combatant.receive_damage(damage, true):
			attack_landed.emit(self)
	orb.queue_free()

func _spawn_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0
	mesh.outer_radius = 1.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.15, 0.04, 0.7)
	material.emission_enabled = true
	material.emission = Color(0.7, 0.08, 0.01)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	ring.mesh = mesh
	ring.position = Vector3(0, 0.12, 0)
	add_child(ring)
	var wave := create_tween()
	wave.parallel().tween_property(ring, "scale", Vector3.ONE * 8.0, 0.65)
	wave.parallel().tween_property(material, "albedo_color:a", 0.0, 0.65)
	await get_tree().create_timer(0.42).timeout
	_damage_player_in_radius(8.5, damage * 0.75)
	await wave.finished
	ring.queue_free()

func _damage_player_in_radius(radius: float, amount: float) -> void:
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= radius:
		if target_combatant.receive_damage(amount, true):
			attack_landed.emit(self)

func _on_damaged(_amount: float, _guarded: bool) -> void:
	if state == AIState.DEAD:
		return
	health_updated.emit(combatant.current_health, combatant.max_health)
	if archetype == "boss" and current_phase == 1 and combatant.current_health <= combatant.max_health * 0.5:
		current_phase = 2
		movement_speed *= 1.18
		phase_changed.emit(2)

func _on_staggered_signal() -> void:
	if archetype == "brute":
		stagger_hits += 1
		if stagger_hits % 3 != 0:
			return
	_start_stagger()

func _start_stagger() -> void:
	if state in [AIState.DEAD, AIState.STAGGER]:
		return
	state = AIState.STAGGER
	velocity = Vector3.ZERO
	var original := visual.rotation
	var reaction := create_tween()
	reaction.tween_property(visual, "rotation:z", 0.35, 0.08)
	reaction.tween_property(visual, "rotation", original, 0.22)
	await reaction.finished
	if state != AIState.DEAD:
		state = AIState.CHASE

func _on_defeated() -> void:
	if state == AIState.DEAD:
		return
	state = AIState.DEAD
	active = false
	velocity = Vector3.ZERO
	telegraph.visible = false
	hurtbox.set_deferred("monitorable", false)
	died.emit(self, wan_reward, archetype)
	var fade := create_tween()
	fade.parallel().tween_property(visual, "scale", visual.scale * Vector3(1.15, 0.05, 1.15), 0.55)
	fade.parallel().tween_property(self, "position:y", position.y - 0.8, 0.55)
	fade.tween_callback(queue_free)

func _build_actor() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.12, 0.12)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.52
	mesh.height = 1.8
	mesh.material = material
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = mesh
	body_mesh.position.y = 0.95
	visual.add_child(body_mesh)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.08, 0.02)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.8, 0.02, 0.0)
	for side in [-1.0, 1.0]:
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.08
		eye_mesh.height = 0.16
		eye_mesh.material = eye_material
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.position = Vector3(0.16 * side, 1.5, -0.47)
		visual.add_child(eye)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.52
	shape.height = 1.9
	collision.shape = shape
	collision.position.y = 0.95
	add_child(collision)
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	hurtbox = CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.combatant_path = NodePath("../Combatant")
	var hurt_collision := CollisionShape3D.new()
	var hurt_shape := CapsuleShape3D.new()
	hurt_shape.radius = 0.62
	hurt_shape.height = 2.15
	hurt_collision.shape = hurt_shape
	hurt_collision.position.y = 0.95
	hurtbox.add_child(hurt_collision)
	add_child(hurtbox)
	var telegraph_mesh := TorusMesh.new()
	telegraph_mesh.inner_radius = 1.15
	telegraph_mesh.outer_radius = 1.4
	var telegraph_material := StandardMaterial3D.new()
	telegraph_material.albedo_color = Color(1.0, 0.08, 0.02, 0.7)
	telegraph_material.emission_enabled = true
	telegraph_material.emission = Color(0.8, 0.02, 0.0)
	telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	telegraph_mesh.material = telegraph_material
	telegraph = MeshInstance3D.new()
	telegraph.mesh = telegraph_mesh
	telegraph.position.y = 0.08
	telegraph.visible = false
	add_child(telegraph)
	combatant.damaged.connect(_on_damaged)
	combatant.staggered.connect(_on_staggered_signal)
	combatant.defeated.connect(_on_defeated)

func _apply_archetype_visual(color: Color) -> void:
	var material := body_mesh.mesh.material as StandardMaterial3D
	material.albedo_color = color
	match archetype:
		"fast": visual.scale = Vector3(0.78, 0.9, 0.78)
		"brute": visual.scale = Vector3(1.35, 1.25, 1.35)
		"ranged": visual.scale = Vector3(0.92, 1.1, 0.92)
		"elite": visual.scale = Vector3(1.2, 1.25, 1.2)
		"boss":
			visual.scale = Vector3(2.6, 2.8, 2.6)
			telegraph.scale = Vector3.ONE * 2.2
			var horn_mesh := CylinderMesh.new()
			horn_mesh.top_radius = 0.0
			horn_mesh.bottom_radius = 0.18
			horn_mesh.height = 1.2
			horn_mesh.material = material
			for side in [-1.0, 1.0]:
				var horn := MeshInstance3D.new()
				horn.mesh = horn_mesh
				horn.position = Vector3(0.32 * side, 1.9, 0)
				horn.rotation_degrees.z = -22.0 * side
				visual.add_child(horn)
