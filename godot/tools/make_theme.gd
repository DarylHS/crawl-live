extends SceneTree
## Writes ui/theme/crawl_theme.tres, the game's one Theme (port plan 10.3): the config.py colours
## from ui_config.json, the bundled DejaVu Sans Mono and the four pygame font faces.
##
##   godot --headless --path godot -s res://tools/make_theme.gd
##
## Colours and faces sit under the custom type "Crawl" (read through HudStyle); the stock Control
## types get the same font, text colour and panel look so P7's menus start from it. tests/ui/test_hud_style.gd
## checks the saved file against ui_config.json, so a colour change in the config shows up as a failure
## until this tool is run again.

const OUT := "res://ui/theme/crawl_theme.tres"
## face name -> [bold, pixel size] (crawler/ui/hud.py Renderer fonts).
const FACES := {"font": [false, 15], "small": [false, 13], "big": [true, 22], "huge": [true, 56]}
## Colours written as literals in crawler/ui/hud.py: the bar track, your row in the tracker, the dark
## strip behind the first-person labels.
const HUD_COLOURS := {"BAR_BACK": [45, 42, 58], "YOU_ROW": [60, 52, 30], "LABEL_BACK": [0, 0, 0, 160]}


func _initialize() -> void:
	var th := Theme.new()
	var regular := UiFonts.mono(false)
	var bold := UiFonts.mono(true)
	th.default_font = regular
	th.default_font_size = 15
	var colours: Dictionary = Content.table("ui_config")["colours"]
	for n: String in colours:
		th.set_color(n, HudStyle.TYPE, UiColours.of(colours[n]))
	for n: String in HUD_COLOURS:                       # colours hud.py writes inline
		th.set_color(n, HudStyle.TYPE, UiColours.of(HUD_COLOURS[n]))
	for face: String in FACES:
		th.set_font(face, HudStyle.TYPE, bold if FACES[face][0] else regular)
		th.set_font_size(face, HudStyle.TYPE, FACES[face][1])
	for t in ["Label", "RichTextLabel", "Button"]:
		th.set_color("font_color", t, UiColours.c("TEXT"))
	th.set_color("default_color", "RichTextLabel", UiColours.c("TEXT"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = UiColours.c("PANEL_BG")
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	var err := ResourceSaver.save(th, OUT)
	print("make_theme: saved %s (error %d)" % [OUT, err])
	quit(err)
