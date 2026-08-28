extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameStateScript.new()
	state.start_new_game({"player_name": "Test Student", "grade_level": "Grade 1"}, false)
	_expect(state.current_lives == 3 and state.max_lives == 3, "New Game must initialize the canonical player life to three.")

	state.lose_life()
	_expect(state.current_lives == 2, "One incorrect answer must reduce the canonical player life once.")
	state.begin_encounter({"encounter_id": "first-bandit"})
	state.record_encounter_victory()
	_expect(state.current_lives == 2, "Winning an ordinary encounter must not restore player life.")

	state.begin_encounter({"encounter_id": "second-bandit"})
	_expect(state.current_lives == 2, "The next ordinary battle must begin with the remaining canonical player life.")
	state.lose_life()
	state.record_encounter_victory()
	_expect(state.current_lives == 1, "A second battle loss must persist into the next encounter.")

	var save_data: Dictionary = state.build_save_data()
	var loaded := GameStateScript.new()
	loaded.apply_save_data(save_data, false)
	_expect(loaded.current_lives == 1, "Loading a current-cycle save must restore its remaining player life.")
	loaded.lose_life(2)
	_expect(loaded.current_lives == 0, "Player life must never become negative.")

	var legacy := GameStateScript.new()
	legacy.apply_save_data({"player_name": "Legacy", "learning_cycle_version": 0}, false)
	_expect(legacy.current_lives == 3, "A legacy save without life fields must use the safe canonical default.")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("battle_life_persistence_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
