extends Node
## Renders every screen and saves PNGs to user://screens/  (needs a window, not --headless):
##   Godot --path . res://tests/screenshots.tscn

var main: Control


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	DirAccess.make_dir_recursive_absolute("user://screens")
	get_viewport().get_texture().get_image().save_png("user://screens/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://screens/%s.png" % name))


func _run() -> void:
	var theme_id := "night" if OS.get_cmdline_user_args().has("night") else "cream"
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "level", 14)
	cfg.set_value("progress", "score", 3150)
	cfg.set_value("progress", "stars", {"1": 3, "2": 3, "3": 2, "4": 3, "5": 1, "6": 3, "7": 2, "8": 3, "9": 3, "10": 2, "11": 3, "12": 2, "13": 1})
	cfg.set_value("progress", "owned", ["cat", "dog"])
	cfg.set_value("progress", "selected", "cat")
	cfg.set_value("settings", "theme", theme_id)
	cfg.set_value("settings", "music", false)
	cfg.save("user://save.cfg")
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _shot(theme_id + "_home", 1.5)
	main._open_levels()
	await _shot(theme_id + "_levels")
	main._go(main.settings)
	await _shot(theme_id + "_settings")
	main._play_level(12)
	var b: Board = main.board
	await get_tree().create_timer(0.6).timeout
	for c in b.n:
		if c != int(b.solution[0]):
			b._set_cell(c, Board.MARK)
	b._commit()
	b.try_cat(int(b.solution[0]))
	b.try_cat(3 * b.n + int(b.solution[3]))
	await _shot(theme_id + "_game", 1.4)
	while not b.locked:
		b.hint()
	await _shot(theme_id + "_win", 3.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	get_tree().quit()
