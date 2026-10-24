extends RefCounted

## A very short shared visual handoff before the existing VS scenes replace the
## exploration world. It intentionally owns no battle, progression, or audio
## state; each existing caller continues to own those systems.

const LAYER_NAME := "BattleBlinkTransition"
const FLASH_NAME := "Flash"
const FADE_IN_SECONDS := 0.14
const FADE_OUT_SECONDS := 0.18
const FLASH_ALPHA := 1.0
const INITIAL_FLASH_ALPHA := 0.12


static func play(world: Node) -> void:
	if world == null or not is_instance_valid(world) or world.get_node_or_null(LAYER_NAME) != null:
		return
	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = 128
	var flash := ColorRect.new()
	flash.name = FLASH_NAME
	# Keep the first rendered frame visible; the tween still reaches the same
	# brief peak before fading back out.
	flash.color = Color(0.0, 0.0, 0.0, INITIAL_FLASH_ALPHA)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(flash)
	world.add_child(layer)
	var tween := world.create_tween()
	tween.tween_property(flash, "color:a", FLASH_ALPHA, FADE_IN_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(flash, "color:a", 0.0, FADE_OUT_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	if is_instance_valid(layer):
		layer.queue_free()
