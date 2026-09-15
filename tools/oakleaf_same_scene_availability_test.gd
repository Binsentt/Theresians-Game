extends Node

## Regression for live same-scene task transitions. Encounter prerequisites are
## temporary availability rules; they must never make InteractionManager prune
## the actor's one installed component permanently.

const OakleafEncounterScript := preload("res://scripts/oakleaf_battle_encounter.gd")


var _checks: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for autoload_name in ["RemoteSync", "HttpApi"]:
		var live := get_node_or_null("/root/" + autoload_name)
		if live != null:
			live.free()

	GameState.start_new_game({
		"student_id": "12345678",
		"parent_id": "123456",
		"player_name": "Same Scene Fixture",
		"grade_level": "Grade 4",
		"gender": "male",
	}, false)
	GameState.playtime_authorized = true
	GameState.current_task_index = 2
	GameState.current_quest = GameState.get_current_quest_text()
	GameState.set_mode(GameState.GameMode.EXPLORATION)

	var player := Node2D.new()
	player.name = "SameScenePlayer"
	player.add_to_group("player_character")
	add_child(player)
	var bandit2 := _make_actor("Bandits2", "oakleaf_bandits2")
	var bandit2_encounter := bandit2.get_child(0) if bandit2.get_child_count() == 1 else null
	await _frames(3)
	_expect(bandit2_encounter != null, "Bandits2 keeps exactly one installed encounter component while locked")
	if bandit2_encounter != null:
		_expect(bool(bandit2_encounter.call("is_registration_valid")), "Bandits2 registration is structurally valid before Task 3")
		_expect(not bool(bandit2_encounter.call("can_interact")), "Bandits2 remains unavailable before Task 3")
		GameState.oakleaf_defeated_bandits["oakleaf_bandits1"] = true
		GameState.current_task_index = GameState.OAKLEAF_BANDIT_TASK_INDEX
		GameState.current_quest = GameState.get_current_quest_text()
		player.global_position = bandit2.global_position
		await _frames(3)
		_expect(InteractionManager.get_active_interactable() == bandit2_encounter, "Bandits2 becomes interactable after the same-scene Task 3 transition")

	GameState.current_task_index = GameState.OAKLEAF_BANDIT_TASK_INDEX
	var boss := _make_actor("Boss-Bandit", "oakleaf_boss_bandit")
	var boss_encounter := boss.get_child(0) if boss.get_child_count() == 1 else null
	await _frames(3)
	_expect(boss_encounter != null, "Boss keeps one installed encounter component while normal Bandits remain")
	if player != null and boss != null and boss_encounter != null:
		_expect(bool(boss_encounter.call("is_registration_valid")), "Boss registration is structurally valid while its prerequisite is locked")
		_expect(not bool(boss_encounter.call("can_interact")), "Boss remains unavailable before all five Bandits")
		for encounter_id in GameState.OAKLEAF_BANDIT_IDS:
			GameState.oakleaf_defeated_bandits[encounter_id] = true
		GameState.current_task_index = GameState.OAKLEAF_BOSS_TASK_INDEX
		GameState.current_quest = GameState.get_current_quest_text()
		player.global_position = boss.global_position
		await _frames(3)
		_expect(InteractionManager.get_active_interactable() == boss_encounter, "Boss becomes interactable after the same-scene 5-of-5 transition")

	_finish()


func _make_actor(actor_name: String, encounter_id: String) -> Node2D:
	var actor := Node2D.new()
	actor.name = actor_name
	add_child(actor)
	var encounter := OakleafEncounterScript.new()
	encounter.name = "OakleafBattleEncounter"
	encounter.call("configure", actor, {
		"encounter_id": encounter_id,
		"male_scene": "res://Battle/Battle-Enemy/male_vs_bandit.tscn",
		"female_scene": "res://Battle/Battle-Enemy/female_vs_bandit.tscn",
	})
	actor.add_child(encounter)
	return actor


func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame


func _expect(condition: bool, label: String) -> void:
	_checks.append({"name": label, "passed": condition})
	if not condition:
		push_error(label)


func _finish() -> void:
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("passed", false))).size()
	print("OAKLEAF_SAME_SCENE_AVAILABILITY_TEST " + JSON.stringify({
		"passed": _checks.size() - failed,
		"failed": failed,
		"checks": _checks,
	}))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failed == 0 else 1)
