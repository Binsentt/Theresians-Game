extends Node

const TeacherInteractionScript := preload("res://scripts/teacher_task_interaction.gd")
const InteractableAreaScript := preload("res://scripts/interactable_area.gd")

var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	var world := Node2D.new()
	world.name = "TeacherHouseFixture"
	add_child(world)
	var dialogue_host := Node.new()
	dialogue_host.name = "CanvasLayer"
	world.add_child(dialogue_host)
	var quest_ui := Node.new()
	quest_ui.name = "Panel"
	dialogue_host.add_child(quest_ui)

	var teacher := AnimatedSprite2D.new()
	teacher.name = "Teacher"
	teacher.position = Vector2(641.0, 341.0)
	teacher.scale = Vector2(0.065, 0.065)
	world.add_child(teacher)
	var foot_area := Area2D.new()
	foot_area.name = "Area2D"
	foot_area.scale = Vector2(41.0, 4.076921)
	teacher.add_child(foot_area)
	var foot_scale_before := foot_area.scale

	var sensor := Area2D.new()
	sensor.name = "Area2D2"
	sensor.position = Vector2(-15.384399, 13.555786)
	sensor.set_script(InteractableAreaScript)
	teacher.add_child(sensor)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(76.92285, 107.692505)
	shape_node.shape = rectangle
	shape_node.position = Vector2(7.692383, -7.692383)
	sensor.add_child(shape_node)
	var sensor_position_before := sensor.position

	var installer: Node = TeacherInteractionScript.new()
	var supports_install: bool = installer.has_method("install_for_scene")
	_expect(supports_install, "Teacher interaction adapter exposes a runtime-only installer")
	if supports_install:
		installer.call("install_for_scene", world, TeacherInteractionScript)
		await get_tree().process_frame
		var adapter: Node = teacher.get_node_or_null("TeacherTaskInteraction")
		var target: Variant = sensor.call("_get_interaction_target") if sensor.has_method("_get_interaction_target") else null
		_expect(adapter != null and target == adapter and adapter.has_method("interact") and adapter.has_method("can_interact"), "existing Teacher sensor targets one valid quest interaction adapter")
		installer.call("install_for_scene", world, TeacherInteractionScript)
		_expect(teacher.get_children().filter(func(child: Node) -> bool: return child.name == "TeacherTaskInteraction").size() == 1, "runtime installer cannot duplicate the Teacher adapter")

		var world_size: Vector2 = rectangle.size * sensor.global_scale.abs()
		_expect(world_size.x >= 36.0 and world_size.x <= 48.0 and world_size.y >= 30.0 and world_size.y <= 44.0, "Teacher interaction footprint supports a sensible adjacent distance")
		for offset in [Vector2(14.0, 0.0), Vector2(-14.0, 0.0), Vector2(0.0, 14.0), Vector2(0.0, -14.0)]:
			var local_point: Vector2 = sensor.to_local(sensor.global_position + offset)
			_expect(absf(local_point.x) <= rectangle.size.x * 0.5 and absf(local_point.y) <= rectangle.size.y * 0.5, "Teacher sensor reaches the adjacent %s direction without body overlap" % str(offset))
		_expect(sensor.position == sensor_position_before, "Teacher sensor remains centered at the existing feet position")
		_expect(foot_area.scale == foot_scale_before, "Teacher foot collision/sensor geometry remains unchanged")
	installer.free()

	world.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("TEACHER_INTERACTION_RANGE_TEST " + JSON.stringify({"passed": _checks.size() - failed, "failed": failed, "checks": _checks}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
