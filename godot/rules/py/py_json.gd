class_name PyJson
extends RefCounted
## Python-compatible JSON for saves and traces (port plan sections 2.1, 3.2 and 4).
##
## dumps() writes what Python's json.dumps(v) writes by default: Dictionary insertion order (no
## sorting), ", " and ": " separators, ints as ints, floats via PyFmt.repr_float, true/false/null,
## ensure_ascii escapes (\uXXXX, surrogate pairs above the BMP). Godot's JSON.stringify sorts keys and
## prints 14 significant digits, so never use it for saves.
##
## loads() wraps the JSON parser. Godot returns every number as float (so 1 and 1.0 are
## indistinguishable); callers that need ints coerce by schema (Content, SaveGame).


## json.dumps(v). ensure_ascii := false keeps non-ASCII characters as they are (json.dumps(...,
## ensure_ascii=False)); indent >= 0 pretty prints with that many spaces per level (indent=n) and
## then uses "," plus newline between items, as Python does.
## compact := true is separators=(",", ":") (indent must then be -1), as the trace files use.
static func dumps(v: Variant, ensure_ascii: bool = true, indent: int = -1, compact: bool = false) -> String:
	_compact = compact
	var text := _dump(v, ensure_ascii, indent, 0)
	_compact = false
	return text


static var _compact := false


static func _dump(v: Variant, ascii: bool, indent: int, level: int) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return "%d" % v
		TYPE_FLOAT:
			if is_nan(v):
				return "NaN"
			if is_inf(v):
				return "Infinity" if v > 0.0 else "-Infinity"
			return PyFmt.repr_float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(String(v), ascii)
		TYPE_ARRAY:
			var arr: Array = v
			if arr.is_empty():
				return "[]"
			var parts := PackedStringArray()
			for e in arr:
				parts.append(_dump(e, ascii, indent, level + 1))
			return _join("[", "]", parts, indent, level)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				return "{}"
			var parts := PackedStringArray()
			for k in d:
				parts.append(_quote(_key_text(k), ascii) + (":" if _compact else ": ") + _dump(d[k], ascii, indent, level + 1))
			return _join("{", "}", parts, indent, level)
		TYPE_VECTOR2I:
			return _dump([v.x, v.y], ascii, indent, level)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return _dump(Array(v), ascii, indent, level)
	push_error("PyJson.dumps: cannot serialise a value of type %s" % type_string(typeof(v)))
	return "null"


static func _join(open: String, close: String, parts: PackedStringArray, indent: int, level: int) -> String:
	if indent < 0:
		return open + ("," if _compact else ", ").join(parts) + close
	var pad := " ".repeat(indent * (level + 1))
	return open + "\n" + pad + (",\n" + pad).join(parts) + "\n" + " ".repeat(indent * level) + close


## Dict keys become strings as in json.dumps: ints and floats by their text, bools and null as JSON words.
static func _key_text(k: Variant) -> String:
	match typeof(k):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(k)
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if k else "false"
		TYPE_INT:
			return "%d" % k
		TYPE_FLOAT:
			return PyFmt.repr_float(k)
	push_error("PyJson.dumps: unsupported dictionary key type %s" % type_string(typeof(k)))
	return ""


static func _quote(s: String, ascii: bool) -> String:
	var out := "\""
	for i in s.length():
		var code := s.unicode_at(i)
		match code:
			34:
				out += "\\\""
			92:
				out += "\\\\"
			10:
				out += "\\n"
			13:
				out += "\\r"
			9:
				out += "\\t"
			8:
				out += "\\b"
			12:
				out += "\\f"
			_:
				if code < 32:
					out += "\\u%04x" % code
				elif ascii and code > 126:
					if code > 0xFFFF:
						var c := code - 0x10000
						out += "\\u%04x\\u%04x" % [0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF)]
					else:
						out += "\\u%04x" % code
				else:
					out += String.chr(code)
	return out + "\""


## json.loads(text) through Godot's parser. Every number comes back as float. A syntax error is a
## push_error and returns null (Python raises JSONDecodeError); a literal `null` also gives null,
## so check parse_ok first when the difference matters.
static func loads(text: String) -> Variant:
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		push_error("PyJson.loads: %s at line %d" % [parser.get_error_message(), parser.get_error_line()])
		return null
	return parser.data


## True when text is valid JSON (so a null from loads() can be told from a failure).
static func parse_ok(text: String) -> bool:
	return JSON.new().parse(text) == OK
