extends Node
## Runs preserved standalone assertions in the canonical MCP project context.
## Only SceneTree entry/exit plumbing is adapted; assertion bodies stay intact.

const CASES := [
	"battle_lifecycle_test", "battle_life_persistence_test",
	"decorative_npc_wanderer_test", "first_bandit_question_scope_test",
	"game_leaderboard_contract_test", "http_api_production_config_test",
	"http_api_timeout_test", "leaderboard_scene_load_test",
	"loading_completion_render_test", "load_game_scene_contract_test",
	"question_pool_exhaustion_test", "question_provider_normalization_test",
	"quest_activity_event_test", "student_id_compatibility_test",
	"tutorial_activity_boundary_test",
	"main_menu_ui_layout_test", "player_speed_and_title_regression_test",
]
var results: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi", "QuestionProvider"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()
	for case_name in CASES:
		var path := "res://tools/" + String(case_name) + ".gd"
		var source := FileAccess.get_file_as_string(path)
		source = source.replace("extends SceneTree", "extends Node")
		source = source.replace("func _init()", "func fixture_initialize()")
		source = source.replace("func _initialize()", "func fixture_initialize()")
		source += "\nvar fixture_exit := -1\nfunc quit(code: int = 0) -> void:\n\tfixture_exit = code\n"
		source += "\nvar root: Window:\n\tget:\n\t\treturn get_tree().root\n"
		source += "\nvar process_frame: Signal:\n\tget:\n\t\treturn get_tree().process_frame\n"
		source += "\nvar physics_frame: Signal:\n\tget:\n\t\treturn get_tree().physics_frame\n"
		source += "\nfunc get_root() -> Window:\n\treturn get_tree().root\n"
		source += "\nfunc create_timer(seconds: float) -> SceneTreeTimer:\n\treturn get_tree().create_timer(seconds)\n"
		var script := GDScript.new()
		script.source_code = source
		var compiled := script.reload()
		if compiled != OK:
			results.append({"case": case_name, "exit": -2, "compiled": false})
			continue
		var suite = script.new()
		add_child(suite)
		suite.fixture_initialize()
		var deadline := Time.get_ticks_msec() + 15000
		while suite.fixture_exit == -1 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		results.append({"case": case_name, "exit": suite.fixture_exit, "compiled": true})
		print("LEGACY_CONTRACT " + JSON.stringify(results.back()))
		suite.queue_free()
		await get_tree().process_frame
	var failures := results.filter(func(row: Dictionary) -> bool: return row.exit != 0).size()
	var output := FileAccess.open("res://docs/qa/2026-09-07-gameplay-legacy-contracts.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	print("GAMEPLAY_LEGACY_CONTRACT_SUITE " + JSON.stringify({"passed": results.size() - failures, "failed": failures}))
	get_tree().quit(1 if failures else 0)
