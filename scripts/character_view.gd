class_name CharacterView
extends SubViewportContainer
## A little 3D stage showing one animated character (made in Blender), with cartoon
## outlines and soft rim lighting. Plays "idle" in a loop; call cheer() for a happy hop.

var character_id := ""
var always_happy := false
var _vp: SubViewport
var _pivot: Node3D
var _anim: AnimationPlayer
var _t := 0.0

const NO_OUTLINE := ["Whisker", "Spark", "Pupil", "Iris", "Mouth", "Blush", "NoseShine", "Stripe"]


func _init(id := "cat", happy := false, zoom := 1.0) -> void:
	always_happy = happy
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# purely decorative: never take touches away from the buttons around it
	set_process_input(false)
	set_process_unhandled_input(false)
	_vp = SubViewport.new()
	_vp.gui_disable_input = true
	_vp.handle_input_locally = false
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0.95, 0.9)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	for l in [[Vector3(-40, 30, 0), 0.95, Color(1, 0.96, 0.9)], [Vector3(-15, -140, 0), 0.55, Color(1, 0.85, 0.7)],
			[Vector3(-30, 180, 0), 0.25, Color(0.8, 0.85, 1.0)]]:
		var d := DirectionalLight3D.new()
		d.rotation_degrees = l[0]
		d.light_energy = l[1]
		d.light_color = l[2]
		_vp.add_child(d)
	var cam := Camera3D.new()
	var cam_pos := Vector3(0, 1.5, 4.4 / zoom)
	var look := Vector3(0, 1.32 if happy else 1.12, 0)
	cam_pos.y += look.y - 1.12
	cam.transform = Transform3D(Basis.looking_at(look - cam_pos), cam_pos)
	cam.fov = 40
	_vp.add_child(cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	show_character(id)


func show_character(id: String) -> void:
	if id == character_id:
		return
	character_id = id
	for c in _pivot.get_children():
		c.queue_free()
	var scene := Characters.model(id)
	if scene == null:
		return
	var model := scene.instantiate()
	_pivot.add_child(model)
	_style(model)
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for a in _anim.get_animation_list():
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(func(_n): _anim.play("idle"))
		_anim.play("happy" if always_happy else "idle")


## Cartoon outline (inverted hull) + rim light on every body part.
func _style(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var skip := false
		for k in NO_OUTLINE:
			if mi.name.contains(k):
				skip = true
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
			m.roughness = maxf(m.roughness, 0.45)
			if not skip:
				var line := StandardMaterial3D.new()
				line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				line.cull_mode = BaseMaterial3D.CULL_FRONT
				line.grow = true
				line.grow_amount = 0.016
				line.albedo_color = Color("#4d2e1e")
				m.next_pass = line
			mi.set_surface_override_material(s, m)
	for c in node.get_children():
		_style(c)


## One happy hop (or keep cheering if always_happy).
func cheer() -> void:
	if _anim == null:
		return
	_anim.play("happy")
	if not always_happy:
		get_tree().create_timer(_anim.get_animation("happy").length * 2.0).timeout.connect(
			func(): if _anim and not always_happy: _anim.play("idle"))


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = sin(_t * 0.6) * 0.35   # gentle look-around on top of the animation
