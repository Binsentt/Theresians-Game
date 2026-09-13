extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	_expect(source.contains('const TELEMETRY_CONTRACT_VERSION := "2.0"'), "GameState declares telemetry contract version 2.0.")
	_expect(source.contains('const QUEST_GRAPH_VERSION := "oakleaf-city-pinehill-v1"'), "GameState declares the canonical quest graph version.")
	_expect(source.contains('"oakleaf.bandits.bandit_%d"'), "Oakleaf normal bandits are represented as stable internal sub-milestones.")
	_expect(source.contains('"is_player_facing": false'), "Internal bandit victories are not player-facing quest completions.")
	_expect(source.contains('_completed_player_facing_tasks'), "Player-facing completion identity is persisted for idempotent quest counts.")
	_expect(source.contains('"activity_started_at"'), "Active activity timing is included in save data.")
	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("quest_telemetry_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
