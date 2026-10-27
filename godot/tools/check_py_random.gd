extends SceneTree
## godot --headless --path godot -s tools/check_py_random.gd -- <reference.json>
## Replays scripts/py_random_reference.py output against PyRandom and compares exactly.

const PyRandomC := preload("res://rules/py_random.gd")
var _fails := 0
var _values := 0


func _dec(s):
	if s == null:
		return null
	if s is Array:
		var a: Array = []
		for v in s:
			a.append(_dec(v))
		return a
	var t: String = s
	if t.begins_with("f:"):
		var h := t.substr(2)
		var bytes := PackedByteArray()
		bytes.resize(8)
		# big-endian hex of the IEEE bits -> store the two 32-bit halves, little-endian
		bytes.encode_u32(4, h.substr(0, 8).hex_to_int())
		bytes.encode_u32(0, h.substr(8, 8).hex_to_int())
		return bytes.decode_double(0)
	return int(t)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <reference.json>")
		quit(2)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if data == null:
		printerr("cannot parse ", args[0])
		quit(2)
		return
	var seeds_ok := 0
	for entry in data["seeds"]:
		if _run_seed(entry):
			seeds_ok += 1
		else:
			break
	print("python ", data["python"], ": seeds ok ", seeds_ok, "/", data["seeds"].size(), ", values compared ", _values)
	if _fails == 0 and seeds_ok == data["seeds"].size():
		print("PASS")
	quit(0 if (_fails == 0 and seeds_ok == data["seeds"].size()) else 1)


func _fail(seed_s: String, idx: int, op: String, want, got) -> bool:
	_fails += 1
	printerr("MISMATCH seed=", seed_s, " call=", idx, " op=", op, "\n  want=", str(want).left(300), "\n  got =", str(got).left(300))
	return false


func _eq(seed_s: String, idx: int, op: String, want, got) -> bool:
	_values += 1 if not (want is Array) else want.size()
	var same: bool = (typeof(want) == typeof(got)) and (want == got)
	if want is float and got is float:
		same = want == got
	if not same:
		return _fail(seed_s, idx, op, want, got)
	return true


func _run_seed(entry: Dictionary) -> bool:
	var seed_s: String = entry["seed"]
	var r = PyRandomC.new(int(seed_s))
	var snap: Array = []
	var calls: Array = entry["calls"]
	for idx in range(calls.size()):
		var c: Dictionary = calls[idx]
		var op: String = c["op"]
		var a: Dictionary = c["args"]
		var want = _dec(c["res"])
		var got = null
		match op:
			"random":
				got = r.random()
			"getrandbits":
				var k: int = int(a["k"])
				if k <= 63:
					var v: int = r.getrandbits(k)
					got = [v & 0xFFFFFFFF] if k <= 32 else [v & 0xFFFFFFFF, v >> 32]
					if k == 0:
						got = [0]
				else:
					got = r.getrandbits_words(k)
			"randint":
				got = r.randint(int(a["a"]), int(a["b"]))
			"randrange":
				var stop = null if a["stop"] == null else int(a["stop"])
				got = r.randrange(int(a["start"]), stop, int(a["step"]))
			"choice":
				got = r.choice(_dec(a["seq"]))
			"shuffle":
				var x: Array = []
				for i in range(int(a["n"])):
					x.append(i * int(a["mul"]) + 1)
				r.shuffle(x)
				got = x
			"sample":
				var pop: Array = []
				for i in range(int(a["n"])):
					pop.append(i * 3 + 1)
				got = r.sample(pop, int(a["k"]))
			"choices":
				var pop: Array = []
				for i in range(int(a["n"])):
					pop.append(i * 5 + 2)
				got = r.choices(pop, _dec(a["weights"]), int(a["k"]), _dec(a["cum"]))
			"uniform":
				got = r.uniform(_dec(a["a"]), _dec(a["b"]))
			"snapshot":
				snap = r.get_state()
				got = snap
			"restore":
				r.set_state(snap)
				continue
			"setstate":
				r.set_state(_dec(a["state"]))
				continue
			"getstate_end":
				got = r.get_state()
			_:
				return _fail(seed_s, idx, op, "known op", op)
		if not _eq(seed_s, idx, op, want, got):
			return false
	return true
