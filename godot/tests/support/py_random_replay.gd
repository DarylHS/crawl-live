class_name PyRandomReplay
extends RefCounted
## Replays one seed's call log from scripts/py_random_reference.py against PyRandom.
## Encoding: int -> decimal string, float -> "f:" + 16 hex digits of the IEEE-754 bits, None -> null.

static func decode(s: Variant) -> Variant:
	if s == null:
		return null
	if s is Array:
		var a: Array = []
		for v in s:
			a.append(decode(v))
		return a
	var t: String = s
	if t.begins_with("f:"):
		var h := t.substr(2)
		var bytes := PackedByteArray()
		bytes.resize(8)
		# big-endian hex of the IEEE bits -> two 32-bit halves, little-endian
		bytes.encode_u32(4, h.substr(0, 8).hex_to_int())
		bytes.encode_u32(0, h.substr(8, 8).hex_to_int())
		return bytes.decode_double(0)
	return int(t)


## Returns "" when every call of the entry matches Python, else a description of the first mismatch.
## `compared` (a one-element Array) accumulates the number of values checked.
static func run_seed(entry: Dictionary, compared: Array) -> String:
	var r := PyRandom.new(int(entry["seed"]))
	var snap: Array = []
	var calls: Array = entry["calls"]
	for idx in range(calls.size()):
		var c: Dictionary = calls[idx]
		var op: String = c["op"]
		var a: Dictionary = c["args"]
		var want = decode(c["res"])
		var got = null
		match op:
			"random":
				got = r.random()
			"getrandbits":
				var k: int = int(a["k"])
				if k == 0:
					got = [0]
				elif k <= 63:
					var v: int = r.getrandbits(k)
					got = [v & 0xFFFFFFFF] if k <= 32 else [v & 0xFFFFFFFF, v >> 32]
				else:
					got = r.getrandbits_words(k)
			"randint":
				got = r.randint(int(a["a"]), int(a["b"]))
			"randrange":
				var stop = null if a["stop"] == null else int(a["stop"])
				got = r.randrange(int(a["start"]), stop, int(a["step"]))
			"choice":
				got = r.choice(decode(a["seq"]))
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
				got = r.choices(pop, decode(a["weights"]), int(a["k"]), decode(a["cum"]))
			"uniform":
				got = r.uniform(decode(a["a"]), decode(a["b"]))
			"snapshot":
				snap = r.get_state()
				got = snap
			"restore":
				r.set_state(snap)
				continue
			"setstate":
				r.set_state(decode(a["state"]))
				continue
			"getstate_end":
				got = r.get_state()
			_:
				return "call %d: unknown op %s" % [idx, op]
		compared[0] += want.size() if want is Array else 1
		if typeof(want) != typeof(got) or want != got:
			return "call %d op %s: want %s got %s" % [idx, op, str(want).left(200), str(got).left(200)]
	return ""
