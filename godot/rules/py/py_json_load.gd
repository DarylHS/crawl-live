class_name PyJsonLoad
extends RefCounted
## A JSON parser that keeps Python's int/float distinction (json.loads), for saves.
##
## Godot's JSON parser returns every number as float, so `1` and `1.0` cannot be told apart. A save
## written by Python (or by SaveGame, which writes through PyJson.dumps) has ints for counts and
## floats for ratios, and the rules compare them strictly, so SaveGame reads with this instead of
## coercing field by field. Numbers with no `.`, `e` or `E` become int; the rest become float.
##
## Floats written by Python's repr (what PyJson.dumps writes) are read back exactly: the parse uses
## String.to_float, which is correctly rounded up to 15 significant digits but can be one unit in the
## last place out for 16 to 17 digits, so a result whose PyFmt.repr_float differs from the text is
## nudged by up to 2 ulp until the repr matches. This removes the 1-ulp caveat of port plan risk R5
## for any text produced by repr. Text that is not a repr (hand written, 0.10) keeps to_float.
##
## Errors do not raise: parse() returns null and leaves the message in `error` (empty when fine), so
## a literal `null` is told apart by checking `error`. NaN, Infinity and -Infinity are accepted as
## Python's json accepts them. Objects keep insertion order; duplicate keys keep the last value.

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
	var digits := 0
	var in_exp := false
	while _i < _b.size():
		var c := _b[_i]
		if c >= 48 and c <= 57:
			if not in_exp:
				digits += 1
			_i += 1
		elif c == 45 or c == 43:
			_i += 1
		elif c == 46:
			is_float = true
			_i += 1
		elif c == 101 or c == 69:
			is_float = true
			in_exp = true
			_i += 1
		else:
			break
	var tok := _b.slice(start, _i).get_string_from_ascii()
	if not is_float:
		if not tok.is_valid_int():
			_err("bad number")
			return null
		return tok.to_int()
	if not tok.is_valid_float():
		_err("bad number")
		return null
	var x := tok.to_float()
	if digits > 15 and not is_inf(x):
		x = _exact(x, tok)
	return x


## The double whose Python repr is `tok`, if one is within 2 ulp of x; else x.
static func _exact(x: float, tok: String) -> float:
	if PyFmt.repr_float(x) == tok:
		return x
	var buf := PackedByteArray()
	buf.resize(8)
	buf.encode_double(0, x)
	var bits := buf.decode_s64(0)
	for delta in [1, -1, 2, -2]:
		buf.encode_s64(0, bits + delta)
		var y := buf.decode_double(0)
		if PyFmt.repr_float(y) == tok:
			return y
	return x
