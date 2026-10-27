extends TestCase
## PyRandom vs CPython. The 116-seed proof replays scripts/py_random_reference.py output
## (about 12.7 MB, too big to commit): scripts/gd_test.sh regenerates it with Python on every run
## and passes the path in the PY_RANDOM_REF environment variable. The remaining tests pin values
## taken from CPython 3.13 and need no file.

var _ref: Dictionary = {}
var _compared: Array = [0]


func before_all() -> void:
	var path := TestHelpers.env("PY_RANDOM_REF")
	if path != "" and FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_ref = parsed


# --- Pinned CPython values ---------------------------------------------------------------

func test_known_python_values() -> void:
	assert_eq(PyRandom.new(42).random(), 0.6394267984578837)
	var r := PyRandom.new(0)
	assert_eq(r.getrandbits(32), 3626764237)
	assert_eq(r.randint(1, 6), 4)
	# Negative seeds use abs(); seed 0 is the key [0].
	assert_eq(PyRandom.new(-7).random(), PyRandom.new(7).random())


func test_get_state_layout() -> void:
	var r := PyRandom.new(12345)
	var s := r.get_state()
	assert_eq(s.size(), 625)
	assert_eq(s[624], 624, "fresh seed: index is 624")
	var r2 := PyRandom.new(1)
	r2.set_state(s)
	assert_eq(r2.random(), PyRandom.new(12345).random())


func test_choice_empty_returns_null() -> void:
	assert_null(PyRandom.new(1).choice([]))


# --- words_used ---------------------------------------------------------------------------

func test_words_used_counts_32_bit_outputs() -> void:
	var r := PyRandom.new(5)
	assert_eq(r.words_used, 0, "seeding draws nothing")
	r.random()
	assert_eq(r.words_used, 2)
	r.getrandbits(1)
	assert_eq(r.words_used, 3)
	r.getrandbits(32)
	assert_eq(r.words_used, 4)
	r.getrandbits(33)
	assert_eq(r.words_used, 6)
	r.getrandbits(0)
	assert_eq(r.words_used, 6, "k == 0 draws nothing")
	r.getrandbits(62)
	assert_eq(r.words_used, 8)


func test_words_used_through_choices_and_randint() -> void:
	var r := PyRandom.new(9)
	r.choices([1, 2, 3], [1, 1, 1])
	assert_eq(r.words_used, 2, "one random() per choices draw")
	var before := r.words_used
	var v := r.randint(1, 20)
	assert_between(v, 1, 20)
	assert_gt(r.words_used, before)
	# Rejection sampling draws again, so the counter tracks the exact stream position.
	var twin := PyRandom.new(9)
	for i in r.words_used:
		twin.genrand_uint32()
	assert_eq(twin.random(), r.random())


func test_set_state_keeps_counter() -> void:
	var r := PyRandom.new(3)
	r.random()
	r.set_state(PyRandom.new(4).get_state())
	assert_eq(r.words_used, 2)


# --- state_digest -------------------------------------------------------------------------

func test_state_digest_format() -> void:
	var r := PyRandom.new(12345)
	var s := r.get_state()
	var parts := PackedStringArray()
	parts.append(str(s[624]))
	for i in 624:
		parts.append(str(s[i]))
	assert_eq(r.state_digest(), ",".join(parts).sha256_text(), "sha256 of 'index,w0,...,w623'")
	assert_eq(r.state_digest().length(), 64)
	# Pinned from Python 3.13: st = random.Random(12345).getstate()[1];
	# hashlib.sha256((str(st[624]) + "," + ",".join(map(str, st[:624]))).encode()).hexdigest()
	assert_eq(r.state_digest(), "1e7a8ca3eaf1a251fcae4bd87035c2a528062b2660a24beb4f74b775001652c3")


func test_state_digest_tracks_the_stream() -> void:
	var a := PyRandom.new(8)
	var b := PyRandom.new(8)
	assert_eq(a.state_digest(), b.state_digest())
	a.random()
	assert_ne(a.state_digest(), b.state_digest())
	b.random()
	assert_eq(a.state_digest(), b.state_digest())


# --- The 116-seed proof -------------------------------------------------------------------

func test_reference_file_loaded() -> void:
	assert_true(_ref.has("seeds"), "set PY_RANDOM_REF (scripts/gd_test.sh does this)")
	assert_eq(_ref.get("seeds", []).size(), 116)


func test_reference_seed(i = use_parameters(range(116))) -> void:
	if not _ref.has("seeds"):
		fail_test("PY_RANDOM_REF not loaded")
		return
	var entry: Dictionary = _ref["seeds"][i]
	assert_eq(PyRandomReplay.run_seed(entry, _compared), "", "seed %s" % entry["seed"])
