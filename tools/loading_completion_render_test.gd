extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/loading_screen.gd")
	var completion_start := source.find("func _complete_threaded_scene_load")
	var completion_end := source.find("func ", completion_start + 1)
	var completion := source.substr(completion_start, completion_end - completion_start if completion_end > completion_start else source.length() - completion_start)
	_assert(source.find("_set_resource_progress(1.0)") < source.find("_complete_threaded_scene_load.call_deferred"), "Threaded completion sets the real 100% value before scheduling the transition")
	_assert(completion.contains("await RenderingServer.frame_post_draw"), "Loading waits for a rendered post-draw frame after reaching 100%")
	_assert(completion.contains("if DisplayServer.get_name() == \"headless\":"), "Headless regression runs use a non-rendering completion-frame fallback")
	_assert(completion.contains("await get_tree().process_frame"), "The headless fallback yields one real engine frame without synthesizing progress")
	_assert(completion.find("await RenderingServer.frame_post_draw") < completion.find("change_scene_to_packed"), "The rendered completion frame precedes the scene swap")
	_finish()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("LOADING_COMPLETION_RENDER_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("LOADING_COMPLETION_RENDER_TEST: FAIL")
	quit(1)
