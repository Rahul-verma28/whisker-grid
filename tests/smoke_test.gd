extends Node
## Headless smoke test (run as a scene so autoloads like Sfx exist):
##   Godot --headless --path . res://tests/smoke_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func tap(board: Board, idx: int) -> void:
	var cs := board._cell_size()
	var pos := board._origin() + (Vector2(idx % board.n, idx / board.n) + Vector2(0.5, 0.5)) * cs
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	board._gui_input(down)
	var up := down.duplicate()
	up.pressed = false
	board._gui_input(up)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))

	# --- 100 pre-built levels
	var gen := PuzzleGenerator.new()
	var ok := true
	var sizes_ok := true
	var last_size := 0
	for lv in range(1, 101):
		var p := PuzzleGenerator.campaign_level(lv)
		gen.n = p["size"]
		if gen.solve(p["regions"], 2) != [p["solution"]]:
			ok = false
		if p["size"] < last_size:
			sizes_ok = false
		last_size = p["size"]
	check(ok, "all 100 levels have exactly one solution")
	check(sizes_ok and PuzzleGenerator.campaign_level(1)["size"] == 4 and last_size == 10, "grid grows 4x4 -> 10x10 and never shrinks")
	for lv in [1, 3, 5]:
		check(PuzzleGenerator.campaign_level(lv)["difficulty"] < 2000, "level %d is easy" % lv)

	# --- app flow
	var main: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	check(main.home.visible and not main.game.visible, "home shows on start")
	check(main.play_sub.text.begins_with("Level 1"), "play button offers level 1")
	main.points = 0
	main._on_play()
	await get_tree().process_frame
	var board: Board = main.board
	check(main.game.visible and board.n == 4 and main.playing == 1, "level 1 opens as 4x4")

	var n := board.n
	var good := int(board.solution[0])
	var wrong := 0 if good != 0 else 2
	tap(board, wrong)
	check(board.state[wrong] == Board.MARK, "single tap marks X")
	await get_tree().create_timer(0.5).timeout
	tap(board, wrong)
	check(board.state[wrong] == Board.EMPTY, "second slow tap removes X")
	await get_tree().create_timer(0.5).timeout
	tap(board, wrong)
	tap(board, wrong)
	check(board.state[wrong] == Board.MARK and main.lives == 2 and main.mistakes == 1, "wrong double-tap costs a heart")
	tap(board, good)
	tap(board, good)
	check(board.state[good] == Board.CAT, "right double-tap places the friend")

	# finish: 1 mistake -> 2 stars, level 2 unlocked, celebration shows
	while not board.locked:
		board.try_cat((func():
			for r in board.n:
				var i: int = r * board.n + int(board.solution[r])
				if board.state[i] != Board.CAT:
					return i
			return -1).call())
	await get_tree().create_timer(1.6).timeout
	check(main.win.visible and main.win_title.text == "Purr-fect!", "celebration screen appears")
	check(main.win_star_count == 2 and int(main.stars["1"]) == 2, "1 mistake earns 2 stars")
	check(main.level == 2, "level 2 unlocked")
	check(main.points == 40, "2 stars on first clear pays 20 + 2x10 = 40 coins")
	check(main.win_double != null and not main.win_double.disabled, "double-coins video offered")
	main.win_next.call()
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.playing == 2 and not main.win.visible, "next level starts")

	# out of hearts
	var bad: Array = []
	for i in board.n * board.n:
		if int(board.solution[i / board.n]) != i % board.n:
			bad.append(i)
	for k in 3:
		board.try_cat(bad[k * 5])
	await get_tree().create_timer(1.0).timeout
	check(main.lives == 0 and main.popup.visible and main.popup_primary.text.contains("+1 heart"), "out of hearts offers a revive video")
	main.popup_actions[1].call()
	await get_tree().process_frame
	check(main.lives == 3 and not board.locked and board.cat_count() == 0, "start over resets")

	# hints come from a stock (3 + daily gift); empty stock -> video / coins popup
	var stock: int = main.hints
	main._on_hint()
	check(main.hints == stock - 1, "hint uses the stock")
	main.hints = 0
	main._on_hint()
	check(main.popup.visible and main.popup_title.text == "Need a hint?", "empty stock offers video or coins")
	main.popup.visible = false
	while not board.locked:
		board.hint()
	await get_tree().create_timer(1.6).timeout
	check(main.win_star_count == 2 and main.level == 3, "1 hint -> 2 stars, level 3 unlocked")

	# levels map
	main._open_levels()
	await get_tree().create_timer(0.2).timeout
	check(main.levels_screen.visible and main.level_tiles.size() == 100, "levels map shows 100 levels")
	main._on_level_tile(50)
	check(main.levels_screen.visible, "locked level can't be opened")
	main._on_level_tile(1)
	await get_tree().process_frame
	check(main.game.visible and main.playing == 1, "replay an unlocked level")

	# daily
	main._go_home()
	main._on_daily()
	await get_tree().process_frame
	check(main.daily and main.board.n == 7, "daily challenge opens (7x7)")

	# shop + character switching
	main._go_home()
	main.points = 1200
	main._open_shop()
	main._on_shop_button("dog")
	check(main.owned.has("dog") and main.selected == "dog" and main.points == 600, "buy dog for 600 coins")
	check(main.board.cat_tex == Characters.icon("dog") and main.stage_view.character_id == "dog", "dog shows on board and home stage")
	check(main.rule_labels["color"].text == "1 dog per colour", "rule text follows the friend")

	# settings
	main._go(main.settings)
	check(main.settings.visible, "settings screen opens")
	var sfx: Node = get_tree().root.get_node("Sfx")
	check(sfx.music_on and sfx.sfx_on, "music and sound on by default")

	# ad rules: no forced ads early, max one per 3 levels, gaps respected
	var ads: Node = get_tree().root.get_node("Ads")
	ads._levels_since = 5
	ads._last_interstitial = -1e9
	ads._last_rewarded = -1e9
	check(not ads.should_interstitial(8), "no break ads up to level 8")
	check(ads.should_interstitial(9), "break ad allowed after level 8 when rules pass")
	ads._levels_since = 2
	check(not ads.should_interstitial(20), "at most one break ad every 3 levels")
	ads._levels_since = 3
	ads._last_rewarded = ads._now()
	check(not ads.should_interstitial(20), "no break ad right after a rewarded video")
	ads._last_rewarded = -1e9
	ads._last_interstitial = ads._now()
	check(not ads.should_interstitial(20), "no two break ads within 4 minutes")

	# animations exist on every model
	for id in ["cat", "dog", "bunny", "mouse"]:
		var model := Characters.model(id).instantiate()
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(ap != null and ap.has_animation("idle") and ap.has_animation("happy"), "%s has idle + happy animations" % id)
		model.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	print("\n%s (%d failures)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
