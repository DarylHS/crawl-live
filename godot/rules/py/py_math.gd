class_name PyMath
extends RefCounted
## Python numeric semantics that GDScript gets differently (port plan sections 2.1 and 3).
##
## Floor division and modulo follow the sign of the divisor, round() is half-to-even, sum() of
## floats is CPython 3.12+ compensated summation, and sorted()/min()/max() are stable and keep the
## first extreme. Pure static functions: no state, no Node, no Engine dependency.
##
## Division by zero is a push_error and returns 0 (Python raises ZeroDivisionError); the game never
## divides by zero, so the error is a bug signal for the caller rather than a rule.


## Python a // b for ints (floor, not truncation): floordiv(-1, 2) == -1, floordiv(7, -2) == -4.
static func floordiv(a: int, b: int) -> int:
	if b == 0:
		push_error("PyMath.floordiv: integer division by zero")
		return 0
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Python a % b for ints: the result has the sign of the divisor (mod(-1, 5) == 4, mod(5, -3) == -1).
static func mod(a: int, b: int) -> int:
	if b == 0:
		push_error("PyMath.mod: integer modulo by zero")
		return 0
	var r := a % b
	if r != 0 and ((r < 0) != (b < 0)):
		r += b
	return r


## Python a % b for floats: sign of the divisor, and a zero result takes the divisor's sign.
static func fmod_py(a: float, b: float) -> float:
	if b == 0.0:
		push_error("PyMath.fmod_py: float modulo by zero")
		return 0.0
	var r := fmod(a, b)
	if r != 0.0:
		if (r < 0.0) != (b < 0.0):
			r += b
		return r
	var zero := 0.0   # a literal -0.0 is folded to +0.0 by the GDScript parser, so negate a variable
	return -zero if b < 0.0 else zero


## Python round(x) with no digits: half to even, returns an int. round(2.5) == 2, round(-0.5) == 0,
## round(12.5) == 12. Non-finite input is a push_error (Python raises) and returns 0.
static func round_half_even(x: float) -> int:
	if not is_finite(x):
		push_error("PyMath.round_half_even: cannot round a non-finite value")
		return 0
	var f := floorf(x)
	var diff := x - f
	if diff < 0.5:
		return int(f)
	if diff > 0.5:
		return int(f) + 1
	return int(f) if int(f) % 2 == 0 else int(f) + 1


## Python round(x, n) for n >= 0, returns a float. Python rounds the exact binary value correctly,
## which is what "%.nf" does, so format and parse back (port plan 3.1; parsing a short decimal is
## exact in Godot). Non-finite values come back unchanged.
static func round_n(x: float, n: int) -> float:
	if not is_finite(x):
		return x
	if n < 0:
		push_error("PyMath.round_n: negative digits are not supported")
		return x
	if n > 300:
		return x
	return (("%." + str(n) + "f") % x).to_float()


## Python 3.12+ sum() of floats (Neumaier compensated summation, CPython's float fast path):
## differs from a naive loop in the last bit for some inputs. Sums of ints and bools stay plain.
static func fsum_py(values: Array) -> float:
	var f := 0.0
	var c := 0.0
	for v in values:
		var x := float(v)
		var t := f + x
		if absf(f) >= absf(x):
			c += (f - t) + x
		else:
			c += (x - t) + f
		f = t
	if c != 0.0 and is_finite(c):
		f += c
	return f


## Python truthiness for Variants: 0, 0.0, "", [], {}, null and false are falsy.
static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT:
			return v != 0
		TYPE_FLOAT:
			return v != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v) != ""
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, \
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			return v.size() > 0
	return true


## Python three-way comparison of two values of the same kind: numbers (int, float, bool),
## strings, and Arrays as tuples (first differing element, then length). Returns -1, 0 or 1.
static func compare_values(a: Variant, b: Variant) -> int:
	if a is Array and b is Array:
		return compare_tuples(a, b)
	if (a is String or a is StringName) and (b is String or b is StringName):
		var sa := String(a)
		var sb := String(b)
		if sa == sb:
			return 0
		return -1 if sa < sb else 1
	if a == b:
		return 0
	return -1 if a < b else 1


## Python tuple/list ordering: compare element by element, the shorter wins a tie. -1, 0 or 1.
static func compare_tuples(a: Array, b: Array) -> int:
	var n := mini(a.size(), b.size())
	for i in n:
		var c := compare_values(a[i], b[i])
		if c != 0:
			return c
	if a.size() == b.size():
		return 0
	return -1 if a.size() < b.size() else 1


## Python sorted(arr, key=key, reverse=reverse): a new Array, stable. The key Callable is called once
## per element in order. Keys may be numbers, strings or Arrays (tuples). With reverse the order
## of equal elements is still the original one, as in Python.
static func stable_sort_by(arr: Array, key: Callable, reverse: bool = false) -> Array:
	var rows: Array = []
	for i in arr.size():
		rows.append([key.call(arr[i]), i, arr[i]])
	rows.sort_custom(func(x: Array, y: Array) -> bool:
		var c := compare_values(x[0], y[0])
		if c == 0:
			return x[1] < y[1]
		return c > 0 if reverse else c < 0)
	var out: Array = []
	for r in rows:
		out.append(r[2])
	return out


## Python list.sort(key=key, reverse=reverse): sorts arr in place (stable). Works on typed arrays.
static func stable_sort_in_place(arr: Array, key: Callable, reverse: bool = false) -> void:
	var sorted_items := stable_sort_by(arr, key, reverse)
	arr.clear()
	arr.append_array(sorted_items)


## Python min(arr, key=key): the first element with the smallest key. Empty input returns default
## (Python raises unless default= is given).
static func min_by(arr: Array, key: Callable, default: Variant = null) -> Variant:
	if arr.is_empty():
		return default
	var best: Variant = arr[0]
	var best_key: Variant = key.call(best)
	for i in range(1, arr.size()):
		var k: Variant = key.call(arr[i])
		if compare_values(k, best_key) < 0:
			best = arr[i]
			best_key = k
	return best


## Python max(arr, key=key): the first element with the largest key (ties keep the earlier one).
static func max_by(arr: Array, key: Callable, default: Variant = null) -> Variant:
	if arr.is_empty():
		return default
	var best: Variant = arr[0]
	var best_key: Variant = key.call(best)
	for i in range(1, arr.size()):
		var k: Variant = key.call(arr[i])
		if compare_values(k, best_key) > 0:
			best = arr[i]
			best_key = k
	return best
