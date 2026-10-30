class_name HudLog
extends RefCounted
## The message log under the map (crawler/ui/hud.py `draw_log`): the last LOG_LINES lines, long
## messages wrapped at word boundaries so they never run under the side panel (continuation lines are
## indented two spaces), older lines fading toward the panel colour by 10% a line.


## [[text, colour Array]] wrapped to `max_w` pixels in the `font` face, the last LOG_LINES of them.
## `hold_box` keeps the newest "The ... box contains: ..." line, and every line after it (the System's comment on the
## prize), off the log (P8: the box is still rattling).
static func wrapped(style: HudStyle, messages: MessageLog, max_w: int, hold_box: bool = false) -> Array:
	var lines: Array = []
	var entries: Array = messages.recent(HudPlace.LOG_LINES)
	if hold_box:
		var more: Array = messages.recent(HudPlace.LOG_LINES + 8)
		for i in range(more.size() - 1, -1, -1):          # the newest "box contains" line, and everything after it
			if " box contains: " in String(more[i][0]):
				entries = more.slice(maxi(0, i - HudPlace.LOG_LINES), i)
				break
	for entry: Array in entries:
		var line := ""
		for word in _words(entry[0]):
			var trial := (line + " " + word).strip_edges()
			if style.width("font", trial) > max_w and line != "":
				lines.append([line, entry[1]])
				line = "  " + word
			else:
				line = trial
		lines.append([line, entry[1]])
	return lines.slice(maxi(0, lines.size() - HudPlace.LOG_LINES))


## Python str.split(): runs of whitespace separate words, none are empty.
static func _words(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in s:
		if ch == " " or ch == "\t" or ch == "\n":
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


## The colour of line i of n after fading: int(c * fade + back * (1 - fade)) per channel, with
## fade = 1 - 0.1 * age and age counted from the newest line.
static func faded(colour: Array, back: Array, age: int) -> Color:
	var fade := 1.0 - 0.1 * age
	var rgb: Array[int] = []
	for i in 3:
		rgb.append(int(colour[i] * fade + back[i] * (1.0 - fade)))
	return Color8(rgb[0], rgb[1], rgb[2])


## Draw the log panel into `list`.
static func build(list: HudList, world: World, hold_box: bool = false) -> void:
	var st := list.style
	var y0 := HudPlace.MAP_H
	list.fill(Rect2i(0, y0, HudPlace.MAP_W, HudPlace.SCREEN_H - y0), st.colour("PANEL_BG"))
	list.fill(Rect2i(0, y0, HudPlace.MAP_W, 1), st.colour("WALL_DIM"))
	var lines := wrapped(st, world.messages, HudPlace.MAP_W - 24, hold_box)
	var back := Content.table("ui_config")["colours"]["PANEL_BG"] as Array
	for i in lines.size():
		var col := faded(lines[i][1], back, lines.size() - 1 - i)
		list.text(lines[i][0], 12, y0 + 8 + i * 17, col)
