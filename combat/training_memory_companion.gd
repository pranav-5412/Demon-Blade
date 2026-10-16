class_name TrainingMemoryCompanion
extends Node3D

signal telegraph_started(duration: float)
signal attack_resolved(avoided: bool, guarded: bool)
signal counter_window_changed(is_open: bool)

var player: ThirdPersonPlayer
var target_combatant: Combatant
var combatant: Combatant
var hurtbox: CombatHurtbox
var visual: Node3D
var telegraph_ring: MeshInstance3D
var counter_ring: MeshInstance3D
var sword: MeshInstance3D
var active := false
var counter_window_open := false
var telegraph_active := false
var trial_kind := "precision"
var arena_positions: Array[Vector3] = []
var position_index := 0
var run_token := 0

func _ready() -> void:
	_build_placeholder()
	set_process(false)

func configure(target_player: ThirdPersonPlayer, target: Combatant, kind: String, positions: Array[Vector3]) -> void:
	player = target_player
	target_combatant = target
	trial_kind = kind
	arena_positions = positions
	combatant.set_invulnerable(true)

func set_manifested(value: bool) -> void:
	visible = value
	if not value:
		stop_trial()

func manifest() -> void:
	visible = true
	scale = Vector3(0.05, 0.05, 0.05)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 0.65)

func start_trial() -> void:
	if active:
		return
	active = true
	run_token += 1
	_run_trial_loop(run_token)

func stop_trial() -> void:
	active = false
	run_token += 1
	telegraph_active = false
	counter_window_open = false
	if is_instance_valid(telegraph_ring):
		telegraph_ring.visible = false
	if is_instance_valid(counter_ring):
		counter_ring.visible = false
	if is_instance_valid(combatant):
		combatant.set_invulnerable(true)

func accepts_counter() -> bool:
	return active and counter_window_open

func accept_counter() -> void:
	if not counter_window_open:
		return
	counter_window_open = false
	combatant.set_invulnerable(true)
	counter_ring.visible = false
	counter_window_changed.emit(false)
	var original_scale := visual.scale
	var tween := create_tween()
	tween.tween_property(visual, "scale", original_scale * Vector3(1.16, 0.78, 1.16), 0.08)
	tween.tween_property(visual, "scale", original_scale, 0.16)

func _run_trial_loop(token: int) -> void:
	while active and token == run_token:
		if trial_kind == "speed" and not arena_positions.is_empty():
			var target_position := arena_positions[position_index % arena_positions.size()]
			position_index += 1
			var move_tween := create_tween()
			move_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			move_tween.tween_property(self, "global_position", target_position, 1.05)
			await move_tween.finished
			if not active or token != run_token:
				return
		_face_player()
		var telegraph_duration := 0.9 if trial_kind == "speed" else 0.88
		telegraph_active = true
		telegraph_ring.visible = true
		telegraph_started.emit(telegraph_duration)
		var windup_rotation := sword.rotation + Vector3(-0.72, 0.0, -0.62)
		var windup := create_tween()
		windup.tween_property(sword, "rotation", windup_rotation, telegraph_duration).set_trans(Tween.TRANS_SINE)
		await windup.finished
		if not active or token != run_token:
			return
		telegraph_active = false
		telegraph_ring.visible = false
		var guarded := target_combatant.is_guarding
		var attack_range := 4.8 if trial_kind == "speed" else 4.8
		var in_range := global_position.distance_to(player.global_position) <= attack_range
		var damaged := target_combatant.receive_damage(15.0 if trial_kind == "speed" else 18.0, true) if in_range else false
		var avoided := not damaged
		var strike := create_tween()
		strike.tween_property(sword, "rotation", Vector3(0.58, 0.0, 0.48), 0.11)
		strike.tween_property(sword, "rotation", Vector3.ZERO, 0.22)
		attack_resolved.emit(avoided, guarded and damaged)
		counter_window_open = true
		combatant.set_invulnerable(false)
		counter_ring.visible = true
		counter_window_changed.emit(true)
		await get_tree().create_timer(1.65 if trial_kind == "speed" else 1.18).timeout
		if not active or token != run_token:
			return
		if counter_window_open:
			counter_window_open = false
			combatant.set_invulnerable(true)
			counter_ring.visible = false
			counter_window_changed.emit(false)
		await get_tree().create_timer(0.75 if trial_kind == "speed" else 0.75).timeout

func _face_player() -> void:
	if not is_instance_valid(player):
		return
	var target := player.global_position
	target.y = global_position.y
	if global_position.distance_squared_to(target) > 0.001:
		look_at(target, Vector3.UP)

func _build_placeholder() -> void:
	_build_visuals()
	_build_combat_components()
	_build_rings()

func _build_visuals() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var is_speed := trial_kind == "speed" or name.contains("B")

	_create_body(is_speed)
	_create_mask(is_speed)
	if is_speed:
		_create_speed_marks()
	_create_sword(is_speed)

func _create_body(is_speed: bool) -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.24, 0.12, 0.42, 1.0) if is_speed else Color(0.14, 0.28, 0.38, 1.0)
	body_material.emission_enabled = true
	body_material.emission = Color(0.12, 0.03, 0.28, 1.0) if is_speed else Color(0.02, 0.15, 0.28, 1.0)
	body_material.emission_energy_multiplier = 0.35
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.34 if is_speed else 0.39
	body_mesh.height = 1.15 if is_speed else 1.45
	body_mesh.material = body_material
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.position.y = 0.72
	visual.add_child(body)

func _create_mask(is_speed: bool) -> void:
	var mask_material := StandardMaterial3D.new()
	mask_material.albedo_color = Color(0.82, 0.9, 0.96, 1.0) if is_speed else Color(0.72, 0.8, 0.84, 1.0)
	mask_material.emission_enabled = true
	mask_material.emission = Color(0.12, 0.5, 0.72, 1.0) if is_speed else Color(0.04, 0.22, 0.34, 1.0)
	mask_material.emission_energy_multiplier = 0.4
	var mask_mesh := SphereMesh.new()
	mask_mesh.radius = 0.29 if is_speed else 0.32
	mask_mesh.height = 0.3
	mask_mesh.material = mask_material
	var mask := MeshInstance3D.new()
	mask.name = "Mask"
	mask.mesh = mask_mesh
	mask.position = Vector3(0.0, 1.42 if is_speed else 1.62, -0.19)
	mask.scale = Vector3(1.0, 1.08, 0.42)
	visual.add_child(mask)

func _create_speed_marks() -> void:
	for side in [-1.0, 1.0]:
		var mark_mesh := BoxMesh.new()
		mark_mesh.size = Vector3(0.055, 0.18, 0.025)
		var mark_material := StandardMaterial3D.new()
		mark_material.albedo_color = Color(0.05, 0.7, 0.95, 1.0)
		mark_material.emission_enabled = true
		mark_material.emission = Color(0.0, 0.45, 0.9, 1.0)
		mark_mesh.material = mark_material
		var mark := MeshInstance3D.new()
		mark.mesh = mark_mesh
		mark.position = Vector3(0.1 * side, 1.42, -0.31)
		mark.rotation_degrees.z = 18.0 * side
		visual.add_child(mark)

func _create_sword(is_speed: bool) -> void:
	var sword_mesh := BoxMesh.new()
	sword_mesh.size = Vector3(0.08, 1.45 if is_speed else 1.7, 0.12)
	var sword_material := StandardMaterial3D.new()
	sword_material.albedo_color = Color(0.55, 0.72, 0.82, 1.0)
	sword_material.metallic = 0.75
	sword_mesh.material = sword_material
	sword = MeshInstance3D.new()
	sword.name = "Sword"
	sword.mesh = sword_mesh
	sword.position = Vector3(0.48, 0.95, -0.15)
	sword.rotation_degrees.z = -18.0
	visual.add_child(sword)

func _build_combat_components() -> void:
	combatant = Combatant.new()
	combatant.name = "Combatant"
	combatant.max_health = 999.0
	add_child(combatant)
	hurtbox = CombatHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.combatant_path = NodePath("../Combatant")
	var hurt_shape_node := CollisionShape3D.new()
	var hurt_shape := CapsuleShape3D.new()
	hurt_shape.radius = 0.48
	hurt_shape.height = 2.0
	hurt_shape_node.shape = hurt_shape
	hurtbox.position.y = 0.9
	hurtbox.add_child(hurt_shape_node)
	add_child(hurtbox)

func _build_rings() -> void:
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.95, 0.18, 0.08, 0.55)
	ring_material.emission_enabled = true
	ring_material.emission = Color(0.8, 0.05, 0.01, 1.0)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.05
	ring_mesh.outer_radius = 1.22
	ring_mesh.material = ring_material
	telegraph_ring = MeshInstance3D.new()
	telegraph_ring.name = "AttackTelegraph"
	telegraph_ring.mesh = ring_mesh
	telegraph_ring.position.y = 0.08
	telegraph_ring.visible = false
	add_child(telegraph_ring)
	var counter_material := StandardMaterial3D.new()
	counter_material.albedo_color = Color(0.08, 0.72, 1.0, 0.62)
	counter_material.emission_enabled = true
	counter_material.emission = Color(0.0, 0.45, 0.95, 1.0)
	counter_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var counter_mesh := TorusMesh.new()
	counter_mesh.inner_radius = 1.12
	counter_mesh.outer_radius = 1.34
	counter_mesh.material = counter_material
	counter_ring = MeshInstance3D.new()
	counter_ring.name = "CounterOpening"
	counter_ring.mesh = counter_mesh
	counter_ring.position.y = 0.1
	counter_ring.visible = false
	add_child(counter_ring)
