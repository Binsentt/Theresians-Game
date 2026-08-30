extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameStateScript.new()
	_expect(state.has_method("begin_encounter"), "GameState must own encounter creation.")
	_expect(state.has_method("record_encounter_loss"), "GameState must own retry and game-over counting.")
	_expect(state.has_method("record_encounter_victory"), "GameState must own encounter victory cleanup.")
	_expect(state.has_method("get_encounter_question_scope"), "GameState must provide the canonical question scope.")

	if _failures.is_empty():
		state.current_task_index = 2
		var first_bandit_scope: Dictionary = state.tasks[2].get("question_scope", {})
		_expect(String(first_bandit_scope.get("grade", "")) == "Grade 1", "First Bandit must explicitly configure Grade 1.")
		_expect(String(first_bandit_scope.get("difficulty", "")) == "Easy", "First Bandit must explicitly configure Easy difficulty.")
		_expect(String(first_bandit_scope.get("topic", "")) == "Basic Addition", "First Bandit must explicitly configure Basic Addition.")
		state.capture_runtime("res://scenes/oak_leaf_village.tscn", Vector2(321.0, 654.0))
		var context: Dictionary = state.begin_encounter({
			"encounter_id": "oakleaf_bandit",
			"question_scope": first_bandit_scope,
		})
		_expect(String(context.get("encounter_id", "")) == "oakleaf_bandit", "Encounter ID should persist in GameState.")
		_expect(int(context.get("quest_checkpoint", -1)) == 2, "Encounter should preserve the active task checkpoint.")
		_expect(context.get("source_position", {}) is Dictionary, "Encounter should serialize the exact return position.")
		_expect(state.get_encounter_question_scope() == first_bandit_scope, "Explicit Grade, Difficulty, and Topic scope should be preserved.")
		var first_loss: Dictionary = state.record_encounter_loss()
		var resumed_context: Dictionary = state.begin_encounter({"encounter_id": "oakleaf_bandit"})
		var second_loss: Dictionary = state.record_encounter_loss()
		var final_loss: Dictionary = state.record_encounter_loss()
		_expect(int(first_loss.get("retry_count", 0)) == 1 and not bool(first_loss.get("game_over", true)), "First loss should allow a retry.")
		_expect(int(resumed_context.get("retry_count", 0)) == 1, "Returning to the same saved encounter must preserve its retry count.")
		_expect(resumed_context.get("question_scope", {}) == first_bandit_scope, "Retrying an encounter must preserve its exact question scope.")
		_expect(int(second_loss.get("retry_count", 0)) == 2 and not bool(second_loss.get("game_over", true)), "Second loss should allow a retry.")
		_expect(bool(final_loss.get("game_over", false)), "Third loss should produce game over.")
		_expect(state.current_task_index == 2, "Game over must reset only to the encounter checkpoint, not the whole story.")
		state.current_scene_path = "res://scenes/city_of_knowledge.tscn"
		_expect(String(state.get_encounter_question_scope().get("difficulty", "")) == "Medium", "City of Knowledge should map to Medium questions.")
		state.current_scene_path = "res://scenes/2nd Village/Pinehill Village.tscn"
		_expect(String(state.get_encounter_question_scope().get("difficulty", "")) == "Hard", "Pinehill Village should map to Hard questions.")
		state.current_scene_path = "res://scenes/oak_leaf_village.tscn"
		state.begin_encounter({"encounter_id": "oakleaf_bandit", "retry_count": 2})
		var victory: Dictionary = state.record_encounter_victory()
		_expect(bool(victory.get("success", false)) and state.get_active_encounter_context().is_empty(), "Victory should clear retry state without advancing a task itself.")

		var warnings: Array[int] = []
		var time_limit_events := [0]
		state.playtime_warning.connect(func(minutes: int) -> void: warnings.append(minutes))
		state.time_limit_reached.connect(func() -> void: time_limit_events[0] += 1)
		state.configure_playtime_allowance({
			"daily_limit_minutes": 60,
			"remaining_seconds": 1801,
			"can_play": true,
		}, true)
		state.consume_playtime_clock(2.0)
		state.consume_playtime_clock(2.0)
		_expect(warnings == [30], "The 30-minute warning should emit once when its threshold is crossed.")
		state.configure_playtime_allowance({
			"daily_limit_minutes": 60,
			"remaining_seconds": 0,
			"can_play": false,
		}, false)
		state.configure_playtime_allowance({
			"daily_limit_minutes": 60,
			"remaining_seconds": 0,
			"can_play": false,
		}, false)
		_expect(time_limit_events[0] == 1, "A server-expired lease should emit the time-limit event exactly once.")

	if _failures.is_empty():
		print("battle_lifecycle_test: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
