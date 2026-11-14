extends Node
## Captures raw screens for the Play Store listing into res://store/raw_shots/ :
##   Godot --path . --resolution 1080x1920 res://tests/store_shots.tscn -- <cream|night|mint>

var main: Control


func _ready() -> void:
	get_window().unresizable = false
	get_window().size = Vector2i(1080, 1920)
	get_window().position = Vector2i(0, 0)
	_run.call_deferred()


func _shot(name: String, wait := 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://store/raw_shots"))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://store/raw_shots/%s.png" % name))
	print("saved ", name, " ", img.get_size())


func _seed(theme_id: String, level: int, selected: String, owned: Array) -> void:
	var stars := {}
	for i in range(1, level):
		stars[str(i)] = 3 if i % 4 != 2 else 2
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "level", level)
	cfg.set_value("progress", "score", 2840)
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "owned", owned)
	cfg.set_value("progress", "selected", selected)
	cfg.set_value("settings", "theme", theme_id)
	var d := Time.get_date_dict_from_system()
	cfg.set_value("progress", "gift_date", "%04d-%02d-%02d" % [d.year, d.month, d.day])   # no gift popup in shots
	cfg.set_value("settings", "music", false)
	cfg.save("user://save.cfg")


func _half_solve(b: Board, cats: int) -> void:
	for r in b.n:
		for c in b.n:
			var i := r * b.n + c
			if c != int(b.solution[r]) and (r + c) % 3 == 0:
				b._set_cell(i, Board.MARK)
	b._commit()
	for r in cats:
		b.try_cat(r * b.n + int(b.solution[r]))


func _run() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "cream"
	match mode:
		"cream": _seed("cream", 31, "cat", ["cat", "dog"])
		"night": _seed("night", 46, "dog", ["cat", "dog"])
		"mint": _seed("mint", 18, "bunny", ["cat", "dog", "bunny"])
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().create_timer(1.0).timeout
	if mode == "cream":
		main._play_level(28)
		await get_tree().create_timer(0.8).timeout
		_half_solve(main.board, 3)
		await get_tree().create_timer(1.6).timeout   # let those popups fade
		main.board.try_cat(3 * main.board.n + int(main.board.solution[3]))
		await _shot("1_board", 0.3)
		main._open_levels()
		await _shot("2_levels", 0.8)
		main._play_level(14)
		await get_tree().create_timer(0.6).timeout
		var b: Board = main.board
		for r in b.n:
			b.try_cat(r * b.n + int(b.solution[r]))
		await _shot("3_win", 3.0)
		main._open_shop()
		await _shot("4_friends", 0.8)
	elif mode == "night":
		main._play_level(45)
		await get_tree().create_timer(0.8).timeout
		_half_solve(main.board, 4)
		await _shot("5_night", 1.4)
	else:
		main._go_home()
		await _shot("6_home", 1.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	get_tree().quit()
