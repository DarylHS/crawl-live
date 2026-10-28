class_name PyCsv
extends RefCounted
## Python's csv.DictWriter with the default "excel" dialect, as crawler/telemetry.py uses it (port plan
## 8.5), so the telemetry CSVs stay byte for byte what Python writes and analysis/ notebooks read them
## unchanged.
##
## Rules, all measured against CPython 3.13:
##  - every line ends "\r\n" (the file is opened with newline="", so nothing translates it);
##  - QUOTE_MINIMAL: a field is wrapped in double quotes (inner quotes doubled) when it contains a comma,
##    a double quote, "\r" or "\n"; a row with a single empty field is written as `""`;
##  - a cell is `""` for null (None), otherwise str(value): True/False for bools, ints plain, floats via
##    repr (PyFmt.repr_float), strings as they are;
##  - the header is the first row's keys in insertion order; a row missing a key gets an empty cell
##    (restval=""), a row with an extra key is an error (Python raises ValueError);
##  - files are appended to and the header is written only when the file is new or empty.
## File IO lives here and in Telemetry only (port plan 1). Paths may be absolute or user://.


## One cell as the csv module writes it before quoting: "" for null, else Python str().
static func cell_text(v: Variant) -> String:
	if v == null:
		return ""
	return PyFmt.str(v)


## QUOTE_MINIMAL for one field.
static func quote(text: String) -> String:
	if text.contains(",") or text.contains("\"") or text.contains("\r") or text.contains("\n"):
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text


## One CSV line (with the "\r\n") from a list of cell values.
static func encode_row(values: Array) -> String:
	if values.size() == 1 and cell_text(values[0]) == "":
		return "\"\"\r\n"
	var parts := PackedStringArray()
	for v in values:
		parts.append(quote(cell_text(v)))
	return ",".join(parts) + "\r\n"


## The text csv.DictWriter writes for `rows` (list of Dictionaries): the header first when
## `with_header`, then every row in the column order of the first row. Returns "" and push_errors on a
## row with a key that is not a column (Python: ValueError).
static func encode_rows(rows: Array, with_header: bool = true) -> String:
	if rows.is_empty():
		return ""
	var fields: Array = (rows[0] as Dictionary).keys()
	var out := encode_row(fields) if with_header else ""
	for row in rows:
		for k in row:
			if not fields.has(k):
				push_error("PyCsv: dict contains fields not in fieldnames: %s" % str(k))
				return ""
		var values: Array = []
		for f in fields:
			values.append(row[f] if row.has(f) else "")
		out += encode_row(values)
	return out


## Append each table (name -> Array of row Dictionaries) to <out_dir>/<prefix><name>.csv, writing a
## header for a new or empty file (Python write_tables). Empty tables and names in `skip` are left out.
## Creates the directory. Returns false (after push_error) if a file cannot be opened.
static func write_tables(tables: Dictionary, out_dir: String, prefix: String = "", skip: Array = []) -> bool:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ok := true
	for table_name in tables:
		var rows: Array = tables[table_name]
		if skip.has(table_name) or rows.is_empty():
			continue
		var path := out_dir.path_join("%s%s.csv" % [prefix, table_name])
		var is_new := not FileAccess.file_exists(path) or _size(path) == 0
		var text := encode_rows(rows, is_new)
		if text == "":
			ok = false
			continue
		var fh := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if fh == null:
			push_error("PyCsv: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
			ok = false
			continue
		fh.seek_end()
		fh.store_buffer(text.to_utf8_buffer())
		fh.close()
	return ok


static func _size(path: String) -> int:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return 0
	var n := fh.get_length()
	fh.close()
	return n


## Parse CSV text (excel dialect, as csv.reader) into an Array of rows, each an Array of Strings. Used by
## tests and the compare tooling; accepts "\r\n" or "\n" line ends and quoted fields with embedded
## line breaks.
static func parse(text: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var field := ""
	var in_quotes := false
	var started := false     # anything seen on the current row
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					in_quotes = false
			else:
				field += c
		elif c == "\"":
			in_quotes = true
			started = true
		elif c == ",":
			row.append(field)
			field = ""
			started = true
		elif c == "\r" or c == "\n":
			if c == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 1
			if started or field != "":
				row.append(field)
				rows.append(row)
			row = []
			field = ""
			started = false
		else:
			field += c
			started = true
		i += 1
	if started or field != "":
		row.append(field)
		rows.append(row)
	return rows


## csv.DictReader over a file: Array of Dictionaries (all values Strings); [] if the file is missing.
static func read_dicts(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var rows := parse(FileAccess.get_file_as_string(path))
	var out: Array = []
	if rows.is_empty():
		return out
	var header: Array = rows[0]
	for r in rows.slice(1):
		var d := {}
		for j in range(header.size()):
			d[header[j]] = r[j] if j < r.size() else ""
		out.append(d)
	return out
