extends SceneTree
## Pre-builds the 100 campaign levels into res://assets/levels.json.
##   Godot --headless --path . --script res://tools/build_levels.gd
## For every level it generates several unique-solution candidates, scores how hard each
## is to solve with human logic, and keeps the one matching that level's place on the curve.

const OUT := "res://assets/levels.json"


func _initialize() -> void:
	var gen := PuzzleGenerator.new()
	var levels: Array = []
	var seen := {}
	var t0 := Time.get_ticks_msec()
	for level in range(1, PuzzleGenerator.LEVEL_COUNT + 1):
		var size := PuzzleGenerator.size_for_level(level)
		var count := 10 if size <= 6 else (7 if size <= 8 else 5)
		var cands: Array = []
		for k in count:
			var p := gen.generate(size, level * 7919 + 17 + k * 104729)
			var key := str(p["regions"])
			if seen.has(key) or gen.solve(p["regions"], 2).size() != 1:
				continue
			p["difficulty"] = gen.difficulty(p["regions"])
			cands.append(p)
		cands.sort_custom(func(a, b): return a["difficulty"] < b["difficulty"])
		var target := PuzzleGenerator.target_hardness(level)
		var pick: Dictionary = cands[clampi(roundi(target * (cands.size() - 1)), 0, cands.size() - 1)]
		seen[str(pick["regions"])] = true
		levels.append({"size": size, "regions": pick["regions"], "solution": pick["solution"],
			"difficulty": pick["difficulty"]})
		print("level %3d  %2dx%-2d  difficulty %5d   (%d candidates, %.1fs total)" % [
			level, size, size, pick["difficulty"], cands.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(levels))
	f.close()
	print("saved ", OUT)
	quit()
