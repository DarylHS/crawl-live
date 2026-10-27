class_name PyFmt
extends RefCounted
## Python text formatting for the rules and messages (port plan sections 2.1 and 3.3).
##
## Covers the f-string specs the game actually uses (grep of crawler/): {:+d}, {:,}, {:02d},
## {:.nf}, {:+.nf}, {:.n%}, {:+.n%}, {:,.0f}, {:>3}, plus str()/repr() of floats, bools and None,
## str.capitalize and str.format_map with plain {name} placeholders. Godot's str() prints floats with
## 14 digits and bools in lower case, so anything a player, a log, a CSV or a save sees goes through
## here. Pure static functions.
##
## PyFmt.str shadows the builtin only as a member: inside this class a bare str(x) still calls the
## builtin (measured), and it is only used on ints here.

const _TWO_53 := 9007199254740992
const _MAX_EXACT_POW10 := 22


## 10.0 ** k for 0 <= k <= 22, all exactly representable doubles.
static func _pow10(k: int) -> float:
	var v := 1.0
	for i in k:
		v *= 10.0
	return v


## Is M * 10 ** k exactly the double x? Only answers yes when Clinger's fast path proves it (M below
## 2**53 and one correctly rounded multiplication or division by an exact power of ten); a no may
## still be a true match, the caller then tries more digits.
static func _clinger_equal(m: int, k: int, x: float) -> bool:
	if m >= _TWO_53:
		return false
	var fm := float(m)
	if k >= 0:
		if k <= _MAX_EXACT_POW10:
			return fm * _pow10(k) == x
		var extra := k - _MAX_EXACT_POW10
		if extra > 15:
			return false
		var scale := int(_pow10(extra))
		if m > _TWO_53 / scale:
			return false
		return float(m * scale) * _pow10(_MAX_EXACT_POW10) == x
	if -k <= _MAX_EXACT_POW10:
		return fm / _pow10(-k) == x
	return false


## Python repr(float) / str(float): the shortest digits that read back as the same double, fixed
## notation for 1e-4 <= |x| < 1e16 and exponent form ("1e-05", "1.5e+16") outside it. Trailing ".0"
## on whole numbers, "nan", "inf", "-inf", "-0.0".
##
## Digits come from String.num_scientific (Godot's round-trip printer, at most 17 digits; "%e" is not
## supported by GDScript's formatter and "%f" is inexact past about 16 digits in general). It is not
## always the shortest or the closest (1e23 prints as 9.999999999999999e+22, some doubles carry a
## 17th digit, a few end one off), so the digits are improved in two steps: the shortest decimal that
## Clinger's exact check proves reads back as the same double wins, and 16 or 17 digit results in the
## range 1e-4 to 1e15 are redone with "%.nf" (exact there, ties to even like Python). Measured against
## CPython on 12,000+ values (game values, edge exponents, random doubles): no differences. A random
## double outside those paths could still print a digit longer than Python's.
static func repr_float(x: float) -> String:
	if is_nan(x):
		return "nan"
	if is_inf(x):
		return "inf" if x > 0.0 else "-inf"
	if x == 0.0:
		return "-0.0" if 1.0 / x < 0.0 else "0.0"
	var negative := x < 0.0
	var ax := absf(x)
	var text := String.num_scientific(ax)
	var mant := text
	var e10 := 0
	var epos := text.find("e")
	if epos >= 0:
		mant = text.left(epos)
		e10 = text.substr(epos + 1).to_int()
	var int_part := mant
	var frac_part := ""
	var dot := mant.find(".")
	if dot >= 0:
		int_part = mant.left(dot)
		frac_part = mant.substr(dot + 1)
	var digits := int_part + frac_part
	var decpt := int_part.length() + e10
	while digits.length() > 1 and digits.begins_with("0"):
		digits = digits.substr(1)
		decpt -= 1
	while digits.length() > 1 and digits.ends_with("0"):
		digits = digits.left(digits.length() - 1)
	# Shorter exact candidates, shortest first: Godot's printer is not always the shortest (1e23 prints
	# as 9.999999999999999e+22, some doubles carry a 17th digit).
	var found := false
	for n in range(1, digits.length()):
		var cand := _round_digits(digits, n, decpt)
		if _clinger_equal(cand[0].to_int(), cand[1] - n, ax):
			digits = cand[0]
			decpt = cand[1]
			while digits.length() > 1 and digits.ends_with("0"):
				digits = digits.left(digits.length() - 1)
			found = true
			break
	if not found and digits.length() >= 16 and ax >= 1e-4 and ax < 1e15:
		# Python picks the decimal of that length closest to the exact value (ties to even);
		# num_scientific can be off by one in the last digit. "%.nf" is exact at this magnitude.
		var fixed_text := ("%." + str(digits.length() - decpt) + "f") % ax
		var fd := fixed_text.replace(".", "").lstrip("0")
		if fd.length() == digits.length():
			digits = fd
	var ex := decpt - 1
	var out := ""
	if decpt <= -4 or decpt > 16:
		out = digits.left(1)
		if digits.length() > 1:
			out += "." + digits.substr(1)
		out += "e" + ("+" if ex >= 0 else "-") + ("%02d" % absi(ex))
	elif decpt <= 0:
		out = "0." + "0".repeat(-decpt) + digits
	elif decpt >= digits.length():
		out = digits + "0".repeat(decpt - digits.length()) + ".0"
	else:
		out = digits.left(decpt) + "." + digits.substr(decpt)
	return "-" + out if negative else out


## Round a digit string to n digits (half up on the dropped part), carrying; returns [digits, decpt].
static func _round_digits(digits: String, n: int, decpt: int) -> Array:
	var kept := digits.left(n)
	if digits.length() > n and digits.substr(n, 1) >= "5":
		var arr := kept.split("")
		var i := n - 1
		while i >= 0:
			if arr[i] == "9":
				arr[i] = "0"
				i -= 1
			else:
				arr[i] = str(arr[i].to_int() + 1)
				break
		kept = "".join(arr)
		if i < 0:
			kept = "1" + kept.left(n - 1)
			decpt += 1
	return [kept, decpt]


## Python repr(v): strings quoted (single quotes unless the text holds one and no double quote),
## lists, dicts, None, True/False, floats via repr_float, Vector2i as the tuple "(x, y)".
static func repr(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return _repr_string(String(v))
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for e in v:
				parts.append(repr(e))
			return "[" + ", ".join(parts) + "]"
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k in v:
				parts.append(repr(k) + ": " + repr(v[k]))
			return "{" + ", ".join(parts) + "}"
	return PyFmt.str(v)


static func _repr_string(s: String) -> String:
	var quote := "'"
	if s.contains("'") and not s.contains("\""):
		quote = "\""
	var out := quote
	for i in s.length():
		var ch := s.substr(i, 1)
		var code := s.unicode_at(i)
		if ch == quote or ch == "\\":
			out += "\\" + ch
		elif ch == "\n":
			out += "\\n"
		elif ch == "\r":
			out += "\\r"
		elif ch == "\t":
			out += "\\t"
		elif code < 32 or code == 127:
			out += "\\x%02x" % code
		else:
			out += ch
	return out + quote


## Python str(v): True/False, None, floats via repr_float, ints plain, strings as is, containers as
## repr.
static func str(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "None"
		TYPE_BOOL:
			return "True" if v else "False"
		TYPE_FLOAT:
			return repr_float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2I:
			return "(%d, %d)" % [v.x, v.y]
		TYPE_ARRAY, TYPE_DICTIONARY:
			return repr(v)
	if typeof(v) == TYPE_INT:
		return "%d" % v
	return var_to_str(v)


## f"{x:.{n}f}". Non-finite values print as Python does ("nan", "inf", "-inf").
static func fixed(x: float, n: int) -> String:
	if is_nan(x):
		return "nan"
	if is_inf(x):
		return "inf" if x > 0.0 else "-inf"
	return ("%." + str(n) + "f") % x


## f"{x:+.{n}f}".
static func signed_fixed(x: float, n: int) -> String:
	var s := fixed(x, n)
	return s if s.begins_with("-") else "+" + s


## f"{n:+d}".
static func signed_int(n: int) -> String:
	return "+%d" % n if n >= 0 else "%d" % n


## f"{x:.{n}%}": scale by 100 in floating point, then fixed.
static func percent(x: float, n: int) -> String:
	return fixed(x * 100.0, n) + "%"


## f"{x:+.{n}%}".
static func signed_percent(x: float, n: int) -> String:
	var s := percent(x, n)
	return s if s.begins_with("-") else "+" + s


## f"{n:,}".
static func thousands(n: int) -> String:
	return _group("%d" % n)


## f"{x:,.{n}f}".
static func thousands_fixed(x: float, n: int) -> String:
	var s := fixed(x, n)
	if is_nan(x) or is_inf(x):
		return s
	return _group(s)


## Insert commas into the integer part of a plain decimal string (optional leading "-").
static func _group(s: String) -> String:
	var sign_part := ""
	if s.begins_with("-"):
		sign_part = "-"
		s = s.substr(1)
	var frac := ""
	var dot := s.find(".")
	if dot >= 0:
		frac = s.substr(dot)
		s = s.left(dot)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s.substr(i, 1) + out
		count += 1
	return sign_part + out + frac


## f"{n:0{width}d}": zero padded to a total width, the sign counted ("-5" with width 3 is "-05").
static func zero_pad(n: int, width: int) -> String:
	var digits := "%d" % absi(n)
	var sign_part := "-" if n < 0 else ""
	var pad := width - sign_part.length() - digits.length()
	return sign_part + "0".repeat(maxi(pad, 0)) + digits


## f"{s:>{width}}" (str.rjust).
static func rjust(s: String, width: int) -> String:
	return " ".repeat(maxi(width - s.length(), 0)) + s


## f"{s:<{width}}" (str.ljust).
static func ljust(s: String, width: int) -> String:
	return s + " ".repeat(maxi(width - s.length(), 0))


## Python str.capitalize(): first character upper case, the rest lower case ("opening_act" stays
## one word; Godot's capitalize() would split it and title-case it).
static func capitalize(s: String) -> String:
	if s.is_empty():
		return s
	return s.left(1).to_upper() + s.substr(1).to_lower()


## template.format_map(_Safe(ctx)): plain {name} placeholders, a missing name gives "?", "{{" and
## "}}" are literal braces. Values are formatted with PyFmt.str. An unmatched brace is a push_error
## (Python raises ValueError) and leaves the rest of the template as it is.
static func format_map(template: String, ctx: Dictionary) -> String:
	var out := ""
	var i := 0
	var n := template.length()
	while i < n:
		var ch := template.substr(i, 1)
		if ch == "{":
			if i + 1 < n and template.substr(i + 1, 1) == "{":
				out += "{"
				i += 2
				continue
			var close := template.find("}", i + 1)
			if close < 0:
				push_error("PyFmt.format_map: single '{' in format string")
				return out + template.substr(i)
			var key := template.substr(i + 1, close - i - 1)
			out += PyFmt.str(ctx[key]) if ctx.has(key) else "?"
			i = close + 1
		elif ch == "}":
			if i + 1 < n and template.substr(i + 1, 1) == "}":
				out += "}"
				i += 2
				continue
			push_error("PyFmt.format_map: single '}' in format string")
			return out + template.substr(i)
		else:
			out += ch
			i += 1
	return out
