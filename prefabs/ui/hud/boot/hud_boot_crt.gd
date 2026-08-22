class_name HudBootCrt
extends CanvasLayer

## The gameplay HUD arriving as a CRT striking, rather than as an alpha fade.
##
## THE SHADER IS THE QUOTA TERMINAL'S, UNCHANGED. elevator_screen_fullscreen
## already implements a tube warming up - power_on opens a raster from a centre
## line, adds the boot flare and settles into the scanlines - and it is already a
## canvas_item shader. Porting a second copy of that curve into a HUD-specific
## shader would give the helmet and the terminal two different ideas of what a
## tube does, which is exactly the drift the fullscreen port's own header warns
## about.
##
## THE HUD IS ADOPTED, NOT COPIED. A second HudVariant bound to the same HudState
## would be two widgets answering the same question, and the one behind the glass
## would be the one nobody could see was wrong. This reparents the live HUD into
## a SubViewport for the duration and hands the same node back afterwards.

## The tube, 0 (dark) to 1 (settled). ANIMATED, and the only authority for it -
## the setter derives everything else, so nothing else can go stale after a skip.
@export_range(0.0, 1.0) var power_on := 0.0:
	set = set_power_on

var _material: ShaderMaterial
var _hud: CanvasLayer

@onready var _content: SubViewport = $Content
@onready var _crt: ColorRect = $Crt


func _ready() -> void:
	_material = _crt.material as ShaderMaterial
	if _material == null:
		push_warning("HudBootCrt has no ShaderMaterial on Crt; the boot will be blank.")
	_crt.resized.connect(_fit_to_screen)
	_fit_to_screen()
	set_power_on(power_on)


## BOTH ASPECTS TOGETHER: the shader's crop divides frame_aspect by content_aspect,
## so pushing one without the other stretches the HUD at every aspect but 16:9.
func _fit_to_screen() -> void:
	var rect := _crt.size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return
	_content.size = Vector2i(rect)
	if _material == null:
		return
	var aspect := rect.x / rect.y
	_material.set_shader_parameter("frame_aspect", aspect)
	_material.set_shader_parameter("content_aspect", aspect)
	_material.set_shader_parameter("screen_aspect", aspect)


## Takes the live HUD behind the glass. Idempotent, so a replay cannot adopt twice.
func adopt(hud: CanvasLayer) -> void:
	if hud == null or hud == _hud:
		return
	_hud = hud
	if hud.get_parent() != null:
		hud.get_parent().remove_child(hud)
	_content.add_child(hud)
	hud.visible = true
	# Pushed at runtime, never authored: a ViewportTexture written into a .tscn
	# resolves viewport_path against the scene it was saved in, and this one is
	# instanced into a level. Same reason elevator_monitor_shot.gd re-pushes its.
	if _material != null:
		_material.set_shader_parameter("content_tex", _content.get_texture())


## THE ONE TEARDOWN PATH, from the settled beat and from a skip; returns the HUD
## rather than freeing it, because it outlives this overlay by the whole game.
func release(host: Node) -> CanvasLayer:
	var hud := _hud
	_hud = null
	if hud != null:
		_content.remove_child(hud)
		if host != null:
			host.add_child(hud)
	queue_free()
	return hud


func set_power_on(value: float) -> void:
	power_on = clampf(value, 0.0, 1.0)
	# Derived, not decided: a second animated property saying "booting" is how one
	# of them ends up stale after a skip, and the gather is not free.
	visible = power_on > 0.001
	if _material != null:
		_material.set_shader_parameter("power_on", power_on)
