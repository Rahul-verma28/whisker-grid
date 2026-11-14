class_name PuzzleGenerator
extends RefCounted
## Generates "hidden cats" puzzles:
##   an N x N grid split into N coloured regions, with exactly one cat per
##   row, column and region, and no two cats touching (diagonals included).
## Puzzles are deterministic per level (seeded) and almost always have a
## single unique solution.

var n: int = 5
var rng := RandomNumberGenerator.new()


const LEVEL_COUNT := 100
## [size, first level, last level] for the 100-level campaign.
const BANDS := [[4, 1, 5], [5, 6, 12], [6, 13, 22], [7, 23, 36], [8, 37, 54], [9, 55, 76], [10, 77, 100]]

static var _levels: Array = []


## The pre-built campaign level (1..100), loaded from assets/levels.json.
static func campaign_level(level: int) -> Dictionary:
	if _levels.is_empty():
		var f := FileAccess.open("res://assets/levels.json", FileAccess.READ)
		if f:
			_levels = JSON.parse_string(f.get_as_text())
	if level >= 1 and level <= _levels.size():
		var d: Dictionary = _levels[level - 1].duplicate(true)
		d["size"] = int(d["size"])
		d["regions"] = d["regions"].map(func(v): return int(v))
		d["solution"] = d["solution"].map(func(v): return int(v))
		return d
	return PuzzleGenerator.new().generate_level(level)


## How hard (0 = easiest candidate, 1 = hardest) a level should be.
## Levels 1-5 are always the easiest; after that each board size starts gentle,
## gets tougher towards its end, and the overall ceiling rises through the campaign.
static func target_hardness(level: int) -> float:
	if level <= 5:
		return 0.0
	var overall := clampf((level - 5) / 60.0, 0.0, 1.0)
	return progress_in_band(level) * (0.35 + 0.65 * overall)


static func band_for_level(level: int) -> Array:
	for b in BANDS:
		if level <= b[2]:
			return b
	return BANDS[-1]


static func size_for_level(level: int) -> int:
	return band_for_level(level)[0]


## 0.0 at the start of a size band (easiest) -> 1.0 at its end (hardest).
static func progress_in_band(level: int) -> float:
	var b := band_for_level(level)
	return clampf(float(level - b[1]) / maxf(1.0, b[2] - b[1]), 0.0, 1.0)


## Builds a few candidate puzzles, ranks them by how hard they are to solve
## logically, and picks one that matches the level's place in its size band.
## Each board size starts gentle and gets trickier before the grid grows.
func generate_level(level: int) -> Dictionary:
	var size := size_for_level(level)
	var count := 6 if size <= 6 else (4 if size == 7 else (3 if size == 8 else 2))
	var candidates: Array = []
	for k in count:
		var p := generate(size, level * 7919 + 17 + k * 104729)
		p["difficulty"] = difficulty(p["regions"])
		candidates.append(p)
	candidates.sort_custom(func(a, b): return a["difficulty"] < b["difficulty"])
	return candidates[roundi(target_hardness(level) * (count - 1))]


func generate(size: int, seed_value: int) -> Dictionary:
	n = size
	rng.seed = seed_value
	var best: Dictionary = {}
	var best_count: int = 1 << 30
	for _attempt in 30:
		var sol: Array = _random_solution()
		if sol.is_empty():
			continue
		var regions: Array = _grow_regions(sol)
		var count: int = _make_unique(regions, sol)
		if count < best_count:
			best_count = count
			best = {"size": n, "regions": regions, "solution": sol}
		if count == 1:
			break
	return best


# ---------------------------------------------------------------- solution

func _shuffled_range(count: int) -> Array:
	var a: Array = range(count)
	for i in range(count - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


func _random_solution() -> Array:
	var cols: Array = []
	var used: Array = []
	used.resize(n)
	used.fill(false)
	if _place(0, cols, used):
		return cols
	return []


func _place(r: int, cols: Array, used: Array) -> bool:
	if r == n:
		return true
	for c in _shuffled_range(n):
		if used[c]:
			continue
		if r > 0 and absi(c - int(cols[r - 1])) <= 1:
			continue
		cols.append(c)
		used[c] = true
		if _place(r + 1, cols, used):
			return true
		cols.pop_back()
		used[c] = false
	return false


# ---------------------------------------------------------------- regions

func _neighbors4(idx: int) -> Array:
	var r: int = idx / n
	var c: int = idx % n
	var out: Array = []
	if r > 0: out.append(idx - n)
	if r < n - 1: out.append(idx + n)
	if c > 0: out.append(idx - 1)
	if c < n - 1: out.append(idx + 1)
	return out


func _grow_regions(sol: Array) -> Array:
	var regions: Array = []
	regions.resize(n * n)
	regions.fill(-1)
	var assigned: Array = []
	for r in n:
		var idx: int = r * n + int(sol[r])
		regions[idx] = r
		assigned.append(idx)
	# Random growth: picking a random already-coloured cell means big regions
	# grow faster, giving the uneven shapes that make puzzles interesting.
	while assigned.size() < n * n:
		var from: int = assigned[rng.randi_range(0, assigned.size() - 1)]
		var nb: Array = _neighbors4(from)
		var to: int = nb[rng.randi_range(0, nb.size() - 1)]
		if regions[to] == -1:
			regions[to] = regions[from]
			assigned.append(to)
	return regions


func _region_connected_without(regions: Array, region: int, removed: int) -> bool:
	var cells: Array = []
	for i in n * n:
		if regions[i] == region and i != removed:
			cells.append(i)
	if cells.is_empty():
		return false
	var seen := {cells[0]: true}
	var stack: Array = [cells[0]]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for nb in _neighbors4(cur):
			if nb != removed and regions[nb] == region and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == cells.size()


## Repeatedly finds an alternative solution and breaks it by moving one of its
## cats' cells into a neighbouring region. Returns the final solution count
## (1 = unique, 2 = still ambiguous).
func _make_unique(regions: Array, sol: Array) -> int:
	for _iter in 80:
		var sols: Array = solve(regions, 2)
		if sols.size() <= 1:
			return sols.size()
		var alt: Array = sols[0] if sols[0] != sol else sols[1]
		var fixed := false
		for r in _shuffled_range(n):
			if int(alt[r]) == int(sol[r]):
				continue
			var idx: int = r * n + int(alt[r])
			var own: int = regions[idx]
			if not _region_connected_without(regions, own, idx):
				continue
			for nb in _neighbors4(idx):
				if regions[nb] != own:
					regions[idx] = regions[nb]
					fixed = true
					break
			if fixed:
				break
		if not fixed:
			return 2
	return solve(regions, 2).size()


# ---------------------------------------------------------------- difficulty

## Solves like a person would and scores the hardest trick needed:
##   tier 0 - a row/column/colour has only one possible cell left
##   tier 1 - "pointing": a colour fits in only one row/column, so clear the rest of it
##   tier 2 - "what if": a cell would wipe out every option of some row/column/colour
##   tier 3 - logic above gets stuck (needs guessing)
## Score = tier * 1000 + number of deduction rounds.
func difficulty(regions: Array) -> int:
	var cand: Array = []
	cand.resize(n * n)
	cand.fill(true)
	var groups: Array = []
	for r in n:
		groups.append(range(r * n, r * n + n))
	for c in n:
		groups.append(range(c, n * n, n))
	for g in n:
		var cells: Array = []
		for i in n * n:
			if regions[i] == g:
				cells.append(i)
		groups.append(cells)
	var placed := {}
	var tier := 0
	var rounds := 0
	while placed.size() < n and rounds < 200:
		rounds += 1
		if _place_singles(cand, groups, placed, regions):
			continue
		if _pointing(cand, groups, regions):
			tier = maxi(tier, 1)
			continue
		if _what_if(cand, groups, regions):
			tier = maxi(tier, 2)
			continue
		return 3000 + rounds
	return tier * 1000 + rounds


func _blocked_by(idx: int, regions: Array) -> Array:
	var out: Array = []
	var r := idx / n
	var c := idx % n
	for i in n * n:
		if i == idx:
			continue
		var ri := i / n
		var ci := i % n
		if ri == r or ci == c or regions[i] == regions[idx] or (absi(ri - r) <= 1 and absi(ci - c) <= 1):
			out.append(i)
	return out


func _place_singles(cand: Array, groups: Array, placed: Dictionary, regions: Array) -> bool:
	for g in groups:
		var live: Array = g.filter(func(i): return cand[i])
		if live.size() == 1 and not placed.has(live[0]):
			placed[live[0]] = true
			for j in _blocked_by(live[0], regions):
				cand[j] = false
			return true
	return false


func _pointing(cand: Array, groups: Array, regions: Array) -> bool:
	var changed := false
	for g in range(2 * n, 3 * n):   # colour groups
		var live: Array = groups[g].filter(func(i): return cand[i])
		if live.is_empty():
			continue
		var rows := {}
		var cols := {}
		for i in live:
			rows[i / n] = true
			cols[i % n] = true
		if rows.size() == 1:
			var r: int = rows.keys()[0]
			for i in range(r * n, r * n + n):
				if cand[i] and regions[i] != g - 2 * n:
					cand[i] = false
					changed = true
		if cols.size() == 1:
			var c: int = cols.keys()[0]
			for i in range(c, n * n, n):
				if cand[i] and regions[i] != g - 2 * n:
					cand[i] = false
					changed = true
	return changed


func _what_if(cand: Array, groups: Array, regions: Array) -> bool:
	for idx in n * n:
		if not cand[idx]:
			continue
		var blocked := {}
		for j in _blocked_by(idx, regions):
			blocked[j] = true
		for g in groups:
			if g.has(idx):
				continue
			var alive := false
			for i in g:
				if cand[i] and not blocked.has(i):
					alive = true
					break
			if not alive:
				cand[idx] = false
				return true
	return false


# ---------------------------------------------------------------- solver

## Returns up to `limit` solutions (each an Array of column-per-row).
func solve(regions: Array, limit: int) -> Array:
	var out: Array = []
	var cols: Array = []
	var used_c: Array = []
	used_c.resize(n)
	used_c.fill(false)
	var used_r: Array = []
	used_r.resize(n)
	used_r.fill(false)
	_solve_row(0, regions, cols, used_c, used_r, out, limit)
	return out


func _solve_row(r: int, regions: Array, cols: Array, used_c: Array, used_r: Array, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	if r == n:
		out.append(cols.duplicate())
		return
	for c in n:
		if used_c[c]:
			continue
		if r > 0 and absi(c - int(cols[r - 1])) <= 1:
			continue
		var reg: int = regions[r * n + c]
		if used_r[reg]:
			continue
		cols.append(c)
		used_c[c] = true
		used_r[reg] = true
		_solve_row(r + 1, regions, cols, used_c, used_r, out, limit)
		cols.pop_back()
		used_c[c] = false
		used_r[reg] = false
		if out.size() >= limit:
			return
