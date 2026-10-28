class_name PyJsonLoad
extends RefCounted
## A JSON parser that keeps Python's int/float distinction (json.loads), for saves.
##
## Godot's JSON parser returns every number as float, so `1` and `1.0` cannot be told apart. A save
## written by Python (or by SaveGame, which writes through PyJson.dumps) has ints for counts and
## floats for ratios, and the rules compare them strictly, so SaveGame reads with this instead of
## coercing field by field. Numbers with no `.`, `e` or `E` become int; the rest become float.
##
## Floats written by Python's repr (what PyJson.dumps writes) are read back exactly: String.to_float is
## correctly rounded only for short plain decimals (it was 3 ulp out at 0.009999999999999995), so the digits are
## read here and scaled by an exact power of ten, and unless that is Clinger's exact fast path the result is
## nudged by up to MAX_ULP ulp (nearest first) until its PyFmt.repr_float equals the text. This removes the 1-ulp
## caveat of port plan risk R5 for any text produced by repr. Text that is not a repr (hand written, 0.10) keeps
## the scaled reading.
##
## A lone surrogate escape (\\ud800 not followed by a low one) is not valid in a Godot String: it becomes whatever
## String.chr makes of it (Python keeps the lone surrogate); saves never contain one (ensure_ascii pairs them).
##
## Errors do not raise: parse() returns null and leaves the message in `error` (empty when fine), so
## a literal `null` is told apart by checking `error`. NaN, Infinity and -Infinity are accepted as
## Python's json accepts them. Objects keep insertion order; duplicate keys keep the last value.

## How far the scaled mantissa can be off that the repr search covers (String.to_float was out by 3 ulp at 0.01 and
## by more further down, which is why _float reads the digits itself).
const MAX_ULP: int = 16

## "" after a successful parse, else "message at offset N".
static var error: String = ""

static var _b: PackedByteArray
static var _i: int = 0
static var _fail: bool = false


## json.loads(text). Returns null and sets `error` on a syntax error.
static func parse(text: String) -> Variant:
	error = ""
	_b = text.to_utf8_buffer()
	_i = 0
	_fail = false
	_ws()
	var v: Variant = _value()
	if not _fail:
		_ws()
		if _i < _b.size():
			_err("extra data")
	_b = PackedByteArray()
	if _fail:
		return null
	return v


static func _err(msg: String) -> void:
	if not _fail:
		_fail = true
		error = "%s at offset %d" % [msg, _i]


static func _ws() -> void:
	while _i < _b.size():
		var c := _b[_i]
		if c == 32 or c == 10 or c == 13 or c == 9:
			_i += 1
		else:
			return


static func _lit(word: String) -> bool:
	var n := word.length()
	if _i + n <= _b.size() and _b.slice(_i, _i + n).get_string_from_ascii() == word:
		_i += n
		return true
	return false


static func _value() -> Variant:
	if _i >= _b.size():
		_err("unexpected end")
		return null
	var c := _b[_i]
	if c == 123:
		return _object()
	if c == 91:
		return _array()
	if c == 34:
		return _string()
	if c == 116:
		if _lit("true"):
			return true
	elif c == 102:
		if _lit("false"):
			return false
	elif c == 110:
		if _lit("null"):
			return null
	elif c == 78:
		if _lit("NaN"):
			return NAN
	elif c == 73:
		if _lit("Infinity"):
			return INF
	elif c == 45 and _i + 1 < _b.size() and _b[_i + 1] == 73:
		_i += 1
		if _lit("Infinity"):
			return -INF
		_i -= 1
	elif c == 45 or (c >= 48 and c <= 57):
		return _number()
	_err("unexpected value")
	return null


static func _object() -> Variant:
	var d := {}
	_i += 1
	_ws()
	if _i < _b.size() and _b[_i] == 125:
		_i += 1
		return d
	while not _fail:
		_ws()
		if _i >= _b.size() or _b[_i] != 34:
			_err("expected a string key")
			return null
		var k: String = _string()
		_ws()
		if _i >= _b.size() or _b[_i] != 58:
			_err("expected ':'")
			return null
		_i += 1
		_ws()
		var v: Variant = _value()
		if _fail:
			return null
		d[k] = v
		_ws()
		if _i < _b.size() and _b[_i] == 44:
			_i += 1
			continue
		if _i < _b.size() and _b[_i] == 125:
			_i += 1
			return d
		_err("expected ',' or '}'")
	return null


static func _array() -> Variant:
	var a: Array = []
	_i += 1
	_ws()
	if _i < _b.size() and _b[_i] == 93:
		_i += 1
		return a
	while not _fail:
		_ws()
		var v: Variant = _value()
		if _fail:
			return null
		a.append(v)
		_ws()
		if _i < _b.size() and _b[_i] == 44:
			_i += 1
			continue
		if _i < _b.size() and _b[_i] == 93:
			_i += 1
			return a
		_err("expected ',' or ']'")
	return null


static func _hex4() -> int:
	if _i + 4 > _b.size():
		_err("bad \\u escape")
		return 0
	var s := _b.slice(_i, _i + 4).get_string_from_ascii()
	if not s.is_valid_hex_number():
		_err("bad \\u escape")
		return 0
	_i += 4
	return s.hex_to_int()


static func _string() -> String:
	_i += 1
	var out := ""
	var start := _i
	while _i < _b.size():
		var c := _b[_i]
		if c == 34:
			out += _b.slice(start, _i).get_string_from_utf8()
			_i += 1
			return out
		if c == 92:
			out += _b.slice(start, _i).get_string_from_utf8()
			_i += 1
			if _i >= _b.size():
				break
			var e := _b[_i]
			_i += 1
			match e:
				34:
					out += "\""
				92:
					out += "\\"
				47:
					out += "/"
				98:
					out += "\b"
				102:
					out += "\f"
				110:
					out += "\n"
				114:
					out += "\r"
				116:
					out += "\t"
				117:
					var code := _hex4()
					if code >= 0xD800 and code < 0xDC00 and _i + 6 <= _b.size() and _b[_i] == 92 and _b[_i + 1] == 117:
						_i += 2
						var lo := _hex4()
						code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
					out += String.chr(code)
				_:
					_err("bad escape")
					return ""
			start = _i
		elif c < 32:
			_err("control character in string")
			return ""
		else:
			_i += 1
	_err("unterminated string")
	return ""


static func _number() -> Variant:
	var start := _i
	var is_float := false
	while _i < _b.size():
		var c := _b[_i]
		if c >= 48 and c <= 57:
			_i += 1
		elif c == 45 or c == 43:
			_i += 1
		elif c == 46:
			is_float = true
			_i += 1
		elif c == 101 or c == 69:
			is_float = true
			_i += 1
		else:
			break
	var tok := _b.slice(start, _i).get_string_from_ascii()
	if not _number_ok(tok):
		_err("bad number")
		return null
	if not is_float:
		return tok.to_int()
	return _float(tok)


## JSON's number grammar, as Python's json accepts it: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
## (so 01, -01, 00, "1.", "1e" and "1e+" are errors).
static func _number_ok(tok: String) -> bool:
	var i := 0
	var n := tok.length()
	if i < n and tok[i] == "-":
		i += 1
	if i >= n or not tok[i].is_valid_int():
		return false
	if tok[i] == "0":
		i += 1
	else:
		while i < n and tok[i].is_valid_int():
			i += 1
	if i < n and tok[i] == ".":
		i += 1
		var f := i
		while i < n and tok[i].is_valid_int():
			i += 1
		if i == f:
			return false
	if i < n and (tok[i] == "e" or tok[i] == "E"):
		i += 1
		if i < n and (tok[i] == "+" or tok[i] == "-"):
			i += 1
		var e := i
		while i < n and tok[i].is_valid_int():
			i += 1
		if i == e:
			return false
	return i == n


## x scaled by 10**e10 in steps that never pass through an infinite power (pow(10, 309) is inf).
static func _scale(x: float, e10: int) -> float:
	if e10 == 0:
		return x
	var n := absi(e10)
	if n <= 22:
		return x * _P10[n] if e10 > 0 else x / _P10[n]
	var a := n / 2
	var b := n - a
	if e10 > 0:
		return x * pow(10.0, float(a)) * pow(10.0, float(b))
	return x / pow(10.0, float(a)) / pow(10.0, float(b))


## Powers of ten that are exact doubles (10**0 .. 10**22).
const _P10: Array[float] = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
		1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22]


## The float of a JSON float token. Mantissa digits M (at most 18) and a decimal exponent are read here, not by
## String.to_float, whose error grows with small exponents (3 ulp at 0.01, more below). Clinger's fast path
## (M below 2**53, exponent within 22) is one correctly rounded multiply or divide, so exact. Otherwise the
## result is within an ulp or two and the repr search finds the double whose Python repr is the token.
static func _float(tok: String) -> float:
	var text := tok
	var neg := text.begins_with("-")
	if neg:
		text = text.substr(1)
	var e10 := 0
	var epos := maxi(text.find("e"), text.find("E"))
	if epos >= 0:
		e10 = text.substr(epos + 1).to_int()
		text = text.substr(0, epos)
	var dot := text.find(".")
	var digs := text
	if dot >= 0:
		digs = text.substr(0, dot) + text.substr(dot + 1)
		e10 -= text.length() - dot - 1
	digs = digs.lstrip("0")
	if digs.length() > 18:
		return tok.to_float()      # too long for an int: only hand-written text, keep Godot's reading
	var m := digs.to_int() if digs != "" else 0
	var x := float(m)
	var exact := m < 9007199254740992 and absi(e10) <= 22
	x = _scale(x, e10)
	if neg:
		x = -x
	if not exact and m != 0 and not is_inf(x) and x != 0.0:
		x = _exact(x, tok)
	return x


## The double whose Python repr is `tok`, if one is within MAX_ULP ulp of x (nearest first); else x.
static func _exact(x: float, tok: String) -> float:
	if PyFmt.repr_float(x) == tok:
		return x
	var buf := PackedByteArray()
	buf.resize(8)
	buf.encode_double(0, x)
	var bits := buf.decode_s64(0)
	for k in range(1, MAX_ULP + 1):
		for delta in [k, -k]:
			buf.encode_s64(0, bits + delta)
			var y := buf.decode_double(0)
			if PyFmt.repr_float(y) == tok:
				return y
	return x
