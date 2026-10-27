class_name PyRandom
extends RefCounted
## Use: var rng := PyRandom.new(seed)   (class_name needs the global class cache: run
## `godot --headless --path godot --import` once on a fresh checkout; scripts/gd_test.sh does).
## Without the cache, preload still works: const PyRandomC := preload("res://rules/py_random.gd")
## Exact port of CPython 3.13 random.Random (MT19937 core + Lib/random.py methods).
## Same seed -> same stream as Python. All values are 64-bit signed GDScript ints,
## masked to 32 bits explicitly; no step relies on unsigned wraparound.
##
## Seeding: PyRandom.new(seed) takes any int in int64 range (negative -> abs, like Python).
## Seeds beyond 63 bits: PyRandom.from_words(words) with the 32-bit little-endian words
## of abs(seed). Python seed arithmetic (^, *, +) must stay below 2^63 on the GDScript side.
##
## State: get_state() returns 625 ints == Python's getstate()[1] (624 words + index);
## set_state() accepts the same. Python's gauss slot is never used by the game (None).
##
## Limits: getrandbits(k) returns an int for k <= 63; use getrandbits_words(k) for larger k.
## randrange/randint arguments must keep (stop - start) within int64 (< 2^63).

const N := 624
const M := 397
const MASK32 := 0xFFFFFFFF

var mt := PackedInt64Array()
var index := N + 1
## 32-bit outputs drawn so far (random() counts 2, getrandbits(k) counts ceil(k / 32)): the
## trace counter that matches CountingRandom in scripts/py_trace.py. Seeding and set_state do not
## change it.
var words_used: int = 0


func _init(seed_value: int = 0) -> void:
	mt.resize(N)
	seed_int(seed_value)


static func from_words(words: Array):
	var r = (load("res://rules/py_random.gd") as GDScript).new(0)
	r.seed_words(words)
	return r


func seed_int(seed_value: int) -> void:
	# Python: abs(seed), split into 32-bit little-endian words, at least one word.
	var n := seed_value
	if n < 0:
		n = -n  # (int64 min is unsupported)
	var key: Array = []
	if n == 0:
		key.append(0)
	while n != 0:
		key.append(n & MASK32)
		n = n >> 32
	seed_words(key)


func _init_genrand(s: int) -> void:
	mt[0] = s & MASK32
	for i in range(1, N):
		var p: int = mt[i - 1]
		# 1812433253 < 2^31, (p ^ p>>30) < 2^32  =>  product < 2^63
		mt[i] = (1812433253 * (p ^ (p >> 30)) + i) & MASK32
	index = N


func seed_words(key: Array) -> void:
	_init_genrand(19650218)
	var klen := key.size()
	var i := 1
	var j := 0
	var k: int = maxi(N, klen)
	while k > 0:
		var p: int = mt[i - 1]
		# 1664525 < 2^21: product < 2^53
		mt[i] = ((mt[i] ^ ((p ^ (p >> 30)) * 1664525)) + int(key[j]) + j) & MASK32
		i += 1
		j += 1
		if i >= N:
			mt[0] = mt[N - 1]
			i = 1
		if j >= klen:
			j = 0
		k -= 1
	k = N - 1
	while k > 0:
		var p: int = mt[i - 1]
		# 1566083941 < 2^31: product < 2^63
		mt[i] = ((mt[i] ^ ((p ^ (p >> 30)) * 1566083941)) - i) & MASK32
		i += 1
		if i >= N:
			mt[0] = mt[N - 1]
			i = 1
		k -= 1
	mt[0] = 0x80000000
	index = N


func _generate() -> void:
	var kk := 0
	var y := 0
	while kk < N - M:
		y = (mt[kk] & 0x80000000) | (mt[kk + 1] & 0x7FFFFFFF)
		mt[kk] = mt[kk + M] ^ (y >> 1) ^ (0x9908B0DF if (y & 1) else 0)
		kk += 1
	while kk < N - 1:
		y = (mt[kk] & 0x80000000) | (mt[kk + 1] & 0x7FFFFFFF)
		mt[kk] = mt[kk + (M - N)] ^ (y >> 1) ^ (0x9908B0DF if (y & 1) else 0)
		kk += 1
	y = (mt[N - 1] & 0x80000000) | (mt[0] & 0x7FFFFFFF)
	mt[N - 1] = mt[M - 1] ^ (y >> 1) ^ (0x9908B0DF if (y & 1) else 0)
	index = 0


func genrand_uint32() -> int:
	if index >= N:
		_generate()
	var y: int = mt[index]
	index += 1
	words_used += 1
	y ^= y >> 11
	y ^= (y << 7) & 0x9D2C5680
	y ^= (y << 15) & 0xEFC60000
	y ^= y >> 18
	return y & MASK32


## Python random.random(): 53-bit float.
func random() -> float:
	var a := genrand_uint32() >> 5
	var b := genrand_uint32() >> 6
	return (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)


## Python getrandbits(k) as 32-bit little-endian words (any k >= 0; k == 0 -> [0]).
func getrandbits_words(k: int) -> Array:
	assert(k >= 0)
	var words: Array = []
	if k == 0:
		words.append(0)
		return words
	if k <= 32:
		words.append(genrand_uint32() >> (32 - k))
		return words
	var nw := (k - 1) / 32 + 1
	var left := k
	for i in range(nw):
		var r := genrand_uint32()
		if left < 32:
			r = r >> (32 - left)
		words.append(r)
		left -= 32
	return words


## Python getrandbits(k) for 0 <= k <= 63 as an int.
func getrandbits(k: int) -> int:
	assert(k >= 0 and k <= 63)
	if k == 0:
		return 0
	if k <= 32:
		return genrand_uint32() >> (32 - k)
	var lo := genrand_uint32()
	var hi := genrand_uint32() >> (64 - k)
	return lo | (hi << 32)


static func bit_length(n: int) -> int:
	var b := 0
	while n > 0:
		b += 1
		n = n >> 1
	return b


## Python _randbelow_with_getrandbits(n), n > 0, n < 2^63.
func randbelow(n: int) -> int:
	assert(n > 0)
	var k := bit_length(n)
	var r := getrandbits(k)
	while r >= n:
		r = getrandbits(k)
	return r


## Python randrange(start) when stop == null; randrange(start, stop[, step]) otherwise.
func randrange(start: int, stop = null, step: int = 1) -> int:
	if stop == null:
		assert(start > 0, "empty range for randrange()")
		return randbelow(start)
	var width: int = int(stop) - start
	if step == 1:
		assert(width > 0, "empty range in randrange()")
		return start + randbelow(width)
	var n := 0
	if step > 0:
		n = (width + step - 1) / step
	elif step < 0:
		n = _floordiv(width + step + 1, step)
	else:
		assert(false, "zero step for randrange()")
	assert(n > 0, "empty range in randrange()")
	return start + step * randbelow(n)


static func _floordiv(a: int, b: int) -> int:
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


func randint(a: int, b: int) -> int:
	return randrange(a, b + 1)


func choice(seq: Array) -> Variant:
	if seq.is_empty():
		push_error("PyRandom.choice: cannot choose from an empty sequence")
		return null
	return seq[randbelow(seq.size())]


## In-place shuffle (Python 3.11+ algorithm).
func shuffle(x: Array) -> void:
	for i in range(x.size() - 1, 0, -1):
		var j := randbelow(i + 1)
		var t = x[i]
		x[i] = x[j]
		x[j] = t


## Python sample(population, k) (no counts): returns a new Array.
func sample(population: Array, k: int) -> Array:
	var n := population.size()
	assert(k >= 0 and k <= n, "Sample larger than population or is negative")
	var result: Array = []
	result.resize(k)
	var setsize := 21
	if k > 5:
		# ceil(log(k * 3, 4)) exactly as Python computes it (log(x) / log(4))
		setsize += 1 << (2 * int(ceil(log(k * 3.0) / log(4.0))))
	if n <= setsize:
		var pool := population.duplicate()
		for i in range(k):
			var j := randbelow(n - i)
			result[i] = pool[j]
			pool[j] = pool[n - i - 1]
	else:
		var selected := {}
		for i in range(k):
			var j := randbelow(n)
			while selected.has(j):
				j = randbelow(n)
			selected[j] = true
			result[i] = population[j]
	return result


## Python choices(population, weights, cum_weights=..., k=...). weights/cum_weights: Array of
## int/float or null. Like Python, ints are accumulated as ints and the total converted to float.
func choices(population: Array, weights = null, k: int = 1, cum_weights = null) -> Array:
	var n := population.size()
	var out: Array = []
	if cum_weights == null:
		if weights == null:
			var nf := n + 0.0
			for i in range(k):
				out.append(population[int(floor(random() * nf))])
			return out
		var acc: Array = []
		var total_acc = 0
		for w in weights:
			total_acc = total_acc + w
			acc.append(total_acc)
		cum_weights = acc
	assert(cum_weights.size() == n, "The number of weights does not match the population")
	var total: float = cum_weights[cum_weights.size() - 1] + 0.0
	assert(total > 0.0 and is_finite(total), "Total of weights must be finite and > 0")
	var hi0 := n - 1
	for i in range(k):
		var x := random() * total
		var lo := 0
		var hi := hi0
		while lo < hi:
			var mid := (lo + hi) / 2
			if x < cum_weights[mid]:
				hi = mid
			else:
				lo = mid + 1
		out.append(population[lo])
	return out


func uniform(a: float, b: float) -> float:
	return a + (b - a) * random()


## Python getstate()[1]: 624 words followed by the index (625 ints).
func get_state() -> Array:
	var s: Array = []
	s.resize(N + 1)
	for i in range(N):
		s[i] = mt[i]
	s[N] = index
	return s


## Accepts Python's getstate()[1] layout (625 ints).
func set_state(state: Array) -> void:
	assert(state.size() == N + 1)
	for i in range(N):
		mt[i] = int(state[i]) & MASK32
	index = int(state[N])
	assert(index >= 0 and index <= N)


## sha256 hex of "index,w0,...,w623" (the trace's per-stream state fingerprint).
func state_digest() -> String:
	var parts := PackedStringArray()
	parts.append(str(index))
	for i in range(N):
		parts.append(str(mt[i]))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(",".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()
