extends Node

const QuizManagerScript = preload("res://Battle/Battle-Enemy/QuizManager.gd")

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var http_source := FileAccess.get_file_as_string("res://scripts/http_api.gd")
	_expect(http_source.contains('normalized.ends_with("/quest_telemetry_contract_test.tscn")'), "This telemetry test is forced through the loopback-only QA profile.")
	_expect(http_source.contains('normalized.ends_with("/final_game_flow_state_test.tscn")'), "The full quest/save regression is forced through the loopback-only QA profile.")
	_expect(http_source.contains('normalized.ends_with("/remote_sync_pending_queue_test.tscn")'), "The telemetry outbox regression is forced through the loopback-only QA profile.")
	_expect(source.contains('const TELEMETRY_CONTRACT_VERSION := "2.0"'), "GameState declares telemetry contract version 2.0.")
	_expect(source.contains('const QUEST_GRAPH_VERSION := "oakleaf-city-pinehill-v1"'), "GameState declares the canonical quest graph version.")
	_expect(source.contains('"oakleaf.bandits.bandit_%d"'), "Oakleaf normal bandits are represented as stable internal sub-milestones.")
	_expect(source.contains('"is_player_facing": false'), "Internal bandit victories are not player-facing quest completions.")
	_expect(source.contains('_completed_player_facing_tasks'), "Player-facing completion identity is persisted for idempotent quest counts.")
	_expect(source.contains('"activity_started_at"'), "Active activity timing is included in save data.")
	_expect(source.contains("_start_current_task_activity_after_transition"), "Every genuine task transition starts timing for the next canonical task.")
	_expect(source.contains("emit_current_task_activity_started()"), "Task transitions emit a canonical task-start boundary.")
	var quiz_source := FileAccess.get_file_as_string("res://Battle/Battle-Enemy/QuizManager.gd")
	_expect(quiz_source.contains('"question_presented_at"'), "Quiz presentation captures a timestamp for per-question evidence.")
	_expect(quiz_source.contains('"answer_submitted_at"'), "Quiz submission captures a timestamp for per-question evidence.")
	_expect(quiz_source.contains('"response_time_seconds"'), "Quiz submission captures non-negative response duration.")
	var sync_source := FileAccess.get_file_as_string("res://scripts/remote_sync.gd")
	_expect(sync_source.contains('payload["question_presented_at"]'), "RemoteSync forwards question presentation timing.")
	_expect(sync_source.contains('payload["response_time_seconds"]'), "RemoteSync forwards question response timing.")
	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("quest_telemetry_contract_test: PASS")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
