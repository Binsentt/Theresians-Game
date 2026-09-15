extends Node

## Isolated data-contract regression: no gameplay scene, network transport, or
## production save namespace is opened by this fixture.

const RemoteSyncScript := preload("res://scripts/remote_sync.gd")
const OAKLEAF_SCENE := "res://scenes/oak_leaf_village.tscn"
const ENCOUNTER_IDS := [
	"oakleaf_bandits1",
	"oakleaf_bandits2",
	"oakleaf_bandits3",
	"oakleaf_bandits4",
	"oakleaf_bandits5",
	"oakleaf_boss_bandit",
]

var _checks: Array[Dictionary] = []
var _initial_save_paths: Dictionary = {}
var _pending_path := "user://qa_local_saves/oakleaf_encounter_data_integrity_outbox.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	GameState.enable_local_qa_mode()
	for entry in GameState.list_saves():
		_initial_save_paths[String(entry.get("save_path", ""))] = true
	GameState.start_new_game({
		"student_id": "12345678",
		"parent_id": "123456",
		"player_name": "Oakleaf Data Fixture",
		"grade_level": "Grade 6",
		"gender": "female",
	}, false)
	GameState.playtime_authorized = true

	var declared_scope: Dictionary = GameState.tasks[2].get("question_scope", {})
	_expect(not declared_scope.has("grade") and not declared_scope.has("grade_level"), "First Bandit metadata does not hardcode a Student grade")
	GameState.current_task_index = 2
	var first_context: Dictionary = GameState.begin_encounter({
		"encounter_id": "oakleaf_bandits1",
		"source_scene_path": OAKLEAF_SCENE,
		"question_scope": declared_scope,
	})
	_expect(first_context.get("question_scope", {}) == {"grade": "Grade 6", "difficulty": "Easy"}, "First Bandit resolves the current Student grade with Oakleaf Easy")
	GameState.encounter_context.clear()
	GameState.end_battle()
	GameState.set_mode(GameState.GameMode.EXPLORATION)

	var sync := RemoteSyncScript.new()
	sync.set("_pending_file", _pending_path)
	var backend_question := {
		"id": 90210,
		"question_set_id": 77,
		"question": "18 + 24 = ?",
		"choices": ["40", "41", "42", "43"],
		"correct": 2,
		"grade": "Grade 6",
		"difficulty": "Easy",
	}
	for encounter_id in ENCOUNTER_IDS:
		GameState.encounter_context = {
			"encounter_id": encounter_id,
			"source_scene_path": OAKLEAF_SCENE,
			"source_position": {"x": 300.0, "y": 400.0},
			"quest_checkpoint": 3,
			"retry_count": 0,
			"question_scope": {"grade": "Grade 6", "difficulty": "Easy"},
		}
		var payload: Dictionary = sync.call("_build_question_result_payload", backend_question, true)
		_expect(String(payload.get("canonical_battle_id", "")) == encounter_id, "%s remains the canonical battle attribution for backend-shaped questions" % encounter_id)

	GameState.encounter_context["encounter_id"] = "oakleaf_bandits3"
	var stable_payload: Dictionary = sync.call("_build_question_result_payload", backend_question, false)
	sync.call("_enqueue_pending_result", stable_payload)
	sync.call("_enqueue_pending_result", stable_payload)
	var queued: Array = sync.call("_load_pending")
	_expect(queued.size() == 1, "transport retry keeps one durable result for the same result_event_id")
	var new_attempt: Dictionary = sync.call("_build_question_result_payload", backend_question, false)
	_expect(String(new_attempt.get("result_event_id", "")) != String(stable_payload.get("result_event_id", "")), "a genuine later answer receives a distinct result_event_id")
	_expect(String(new_attempt.get("canonical_battle_id", "")) == "oakleaf_bandits3", "new answer retains the same active Bandit attribution")
	sync.free()

	GameState.start_new_game({
		"student_id": "12345678",
		"parent_id": "123456",
		"player_name": "Oakleaf Position Fixture",
		"grade_level": "Grade 6",
		"gender": "male",
	}, false)
	GameState.playtime_authorized = true
	GameState.current_scene_path = OAKLEAF_SCENE
	GameState.current_task_index = GameState.OAKLEAF_BANDIT_TASK_INDEX
	GameState.oakleaf_defeated_bandits["oakleaf_bandits1"] = true
	GameState.player_position = Vector2(1.0, 2.0)
	var source_position := Vector2(321.25, 411.75)
	GameState.begin_encounter({
		"encounter_id": "oakleaf_bandits2",
		"source_scene_path": OAKLEAF_SCENE,
		"source_position": source_position,
		"quest_checkpoint": GameState.current_task_index,
		"question_scope": {"difficulty": "Easy"},
	})
	var victory: Dictionary = GameState.record_encounter_victory()
	var save_data: Dictionary = GameState.build_save_data()
	_expect(bool(victory.get("oakleaf", {}).get("changed", false)), "Bandits2 victory records through the canonical encounter lifecycle")
	_expect(GameState.current_scene_path == OAKLEAF_SCENE and GameState.player_position.is_equal_approx(source_position), "victory restores the captured Oakleaf source scene and position before autosave")
	var saved_position: Dictionary = save_data.get("player_position", {})
	_expect(is_equal_approx(float(saved_position.get("x", 0.0)), source_position.x) and is_equal_approx(float(saved_position.get("y", 0.0)), source_position.y), "serialized save data keeps the exact encounter return position")
	_expect(GameState.encounter_context.is_empty(), "victory clears only the completed encounter context")
	_expect(GameState.is_oakleaf_bandit_defeated("oakleaf_bandits2") and not GameState.is_oakleaf_bandit_defeated("oakleaf_bandits3"), "victory preserves independent Bandit defeated state")

	_cleanup()
	_finish()


func _cleanup() -> void:
	if FileAccess.file_exists(_pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_pending_path))
	for entry in GameState.list_saves():
		var save_path := String(entry.get("save_path", ""))
		if not _initial_save_paths.has(save_path):
			GameState.delete_save(save_path)


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("OAKLEAF_ENCOUNTER_DATA_INTEGRITY_TEST " + JSON.stringify({
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
	}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
