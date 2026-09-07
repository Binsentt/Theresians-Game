extends "res://tools/gameplay_civilian_expansion_test.gd"

func _ready() -> void:
	# The inherited _run frees RemoteSync, HttpApi and QuestionProvider before
	# any profile or map fixture. Reject any attempted live request as well.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is HTTPRequest:
			node.free()
			push_error("Civilian fixture rejected a live HTTPRequest node")
			get_tree().quit(2)
	)
	_run.call_deferred()


func _write_json(path: String, data: Variant) -> void:
	var output_path := "res://docs/qa/2026-09-07-final-civilian-runtime.json" if path == RESULT_PATH else path
	super._write_json(output_path, data)
