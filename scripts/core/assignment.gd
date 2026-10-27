class_name Assignment
extends RefCounted
## Optimal one-to-one matching (Hungarian algorithm, O(n^3)).


## `cost` is an n*n grid, row-major: cost[r * n + c].
## Returns, for each row, the column it's matched to, minimising the total.
static func solve(cost: PackedFloat64Array, n: int) -> PackedInt32Array:
	var inf := 1e18
	var u := PackedFloat64Array()
	var v := PackedFloat64Array()
	var minv := PackedFloat64Array()
	var p := PackedInt32Array()  # column -> row (1-based, 0 = none)
	var way := PackedInt32Array()
	var used := PackedByteArray()
	u.resize(n + 1)
	v.resize(n + 1)
	minv.resize(n + 1)
	p.resize(n + 1)
	way.resize(n + 1)
	used.resize(n + 1)
	u.fill(0.0)
	v.fill(0.0)
	p.fill(0)
	way.fill(0)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		minv.fill(inf)
		used.fill(0)
		while true:
			used[j0] = 1
			var i0 := p[j0]
			var delta := inf
			var j1 := 0
			var row := (i0 - 1) * n
			for j in range(1, n + 1):
				if used[j] == 0:
					var cur := cost[row + j - 1] - u[i0] - v[j]
					if cur < minv[j]:
						minv[j] = cur
						way[j] = j0
					if minv[j] < delta:
						delta = minv[j]
						j1 = j
			for j in n + 1:
				if used[j] == 1:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while j0 != 0:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
	var out := PackedInt32Array()
	out.resize(n)
	for j in range(1, n + 1):
		if p[j] > 0:
			out[p[j] - 1] = j - 1
	return out
