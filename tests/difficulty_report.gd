extends SceneTree
## Prints board size and difficulty for a range of levels:
##   Godot --headless --path . --script res://tests/difficulty_report.gd
## Difficulty = tier * 1000 + rounds (tier 0 = easy singles ... 3 = needs guessing).


func _initialize() -> void:
	var gen := PuzzleGenerator.new()
	for lvl in [1, 2, 3, 4, 7, 10, 11, 15, 20, 21, 28, 35, 36, 45, 55, 56, 80, 120]:
		var t := Time.get_ticks_msec()
		var p := gen.generate_level(lvl)
		print("level %3d  %dx%d  difficulty %5d  (%d ms)" % [lvl, p["size"], p["size"], p["difficulty"], Time.get_ticks_msec() - t])
	quit()
