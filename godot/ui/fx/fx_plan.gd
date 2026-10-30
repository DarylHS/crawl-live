class_name FxPlan
extends RefCounted
## Which effects fire for which World event (port plan 10.x, phase P8): a pure table, headless and
## testable. The rules emit events on `World.events` (EventBus) as they happen ("player_attack",
## "damage_taken", "kill", "boss_phase", "bomb", "box_opened", ...). FxDirector listens, asks `plan`
## what to show, and shows it. Nothing here reads or changes a World, and no effect ever feeds back
## into the rules: effects are read-only, wall-clock decoration.
##
## `plan(event, data, ctx)` returns a list of effect descriptors (Dictionaries):
##   {"k": "sound",  "name": "hit", "delay": 0.0}
##   {"k": "flash",  "at": "target", "strength": 1.0, "dur": 0.18}   a white flash on a sprite
##   {"k": "number", "at": "target" | "player" | "screen", "text": "-5", "tone": "hit", "dur": 0.9}
##   {"k": "shake",  "amp": 0.6, "dur": 0.35}                        screen shake, amp 0 to 1
##   {"k": "burst",  "kind": "bomb", "at": "bomb" | "target" | "player", "count": 40}
##   {"k": "swing"}                                                  the weapon view model swings
## `ctx` is {"mode": "on" | "reduced" | "off", "max_hp": int}. The mode (FxSettings.profile) removes or
## scales effects here, in one place: sounds are always planned (volume and mute are separate), and
## the "off" mode plans nothing else.

## Tones decide a floating number's colour and size (FxCanvas).
const TONES: Array[String] = ["hit", "crit", "hurt", "heal", "miss", "pet", "boss", "nat20"]
## A hit that takes this share of your max HP shakes the screen.
const BIG_HIT_SHARE := 0.25
## Effects flashing or shaking last about this long (seconds).
const FLASH_DUR := 0.18
const NUMBER_DUR := 0.95
## Box reveal: the lid opens this long after the box starts shaking (FxReveal.OPEN_AT).
const BOX_OPEN_DELAY := 0.75


## The effects for one event. Unknown events plan nothing.
static func plan(event: String, data: Dictionary, ctx: Dictionary = {}) -> Array[Dictionary]:
	var p := FxSettings.profile(String(ctx.get("mode", "on")))
	var out: Array[Dictionary] = []
	match event:
		"player_attack":
			if p["swing"]:
				out.append({"k": "swing"})
			if not data.get("hit", true):
				out.append(_sound("miss"))
				_number(out, p, "target", "miss", "miss")
		"player_hit":
			var crit: bool = data.get("crit", false)
			var dmg := int(data.get("damage", 0))
			out.append(_sound("crit" if crit else "hit"))
			_flash(out, p, 1.0)
			_number(out, p, "target", "CRIT -%d!" % dmg if crit else "-%d" % dmg, "crit" if crit else "hit", NUMBER_DUR + (0.25 if crit else 0.0))
			_burst(out, p, "crit" if crit else "hit", "target", 14 if crit else 6)
			if crit:
				_shake(out, p, 0.6, 0.35)
		"nat20":
			_number(out, p, "target", "NATURAL 20", "nat20", 1.2)
		"damage_taken":
			var dmg2 := int(data.get("damage", 0))
			var max_hp := maxi(1, int(ctx.get("max_hp", 1)))
			out.append(_sound("hurt"))
			_number(out, p, "player", "-%d" % dmg2, "hurt")
			if float(dmg2) / float(max_hp) >= BIG_HIT_SHARE:
				_shake(out, p, 0.35, 0.28)
		"dodged":
			_number(out, p, "player", "dodged", "miss", 0.7)
		"kill":
			out.append(_sound("kill"))
			_burst(out, p, "kill", "target", 16 if not data.get("boss", false) else 40)
			if data.get("boss", false):
				_shake(out, p, 0.5, 0.45)
		"boss_phase":
			out.append(_sound("roar"))
			_shake(out, p, 1.0, 0.8)
			_number(out, p, "screen", "PHASE TWO", "boss", 1.6)
		"boss_kill":
			out.append(_sound("fanfare"))
			_shake(out, p, 0.8, 0.6)
		"bomb":
			out.append(_sound("boom"))
			_burst(out, p, "bomb", "bomb", 44)
			_shake(out, p, 0.55, 0.4)
		"pet_hit":
			out.append(_sound("hit"))
			_flash(out, p, 0.7)
			_number(out, p, "target", "-%d" % int(data.get("damage", 0)), "pet")
		"box_opened":
			if p["reveal"]:
				out.append(_sound("box_shake"))
				out.append(_sound("box_open", BOX_OPEN_DELAY))
			else:
				out.append(_sound("box_open"))
		"achievement":
			out.append(_sound("achievement"))
		"step":
			out.append(_sound("step"))
		"descend":
			out.append(_sound("descend"))
		"item_use":
			var healed := int(data.get("healed", 0))
			if healed > 0:
				out.append(_sound("heal"))
				_number(out, p, "player", "+%d" % healed, "heal")
				_burst(out, p, "heal", "player", 12)
			else:
				out.append(_sound("pickup"))
		"item_pickup":
			out.append(_sound("pickup"))
		"level_up":
			out.append(_sound("levelup"))
		"combat_start":
			out.append(_sound("combat"))
		"player_death":
			out.append(_sound("death"))
			_shake(out, p, 0.8, 0.7)
	return out


## Events FxDirector subscribes to (everything `plan` knows).
static func events() -> Array[String]:
	return ["player_attack", "player_hit", "nat20", "damage_taken", "dodged", "kill", "boss_phase",
			"boss_kill", "bomb", "pet_hit", "box_opened", "achievement", "step", "descend", "item_use",
			"item_pickup", "level_up", "combat_start", "player_death", "turn", "riposte"]


static func _sound(sound_name: String, delay: float = 0.0) -> Dictionary:
	return {"k": "sound", "name": sound_name, "delay": delay}


static func _flash(out: Array[Dictionary], p: Dictionary, strength: float) -> void:
	if float(p["flash"]) > 0.0:
		out.append({"k": "flash", "at": "target", "strength": strength * float(p["flash"]), "dur": FLASH_DUR})


static func _number(out: Array[Dictionary], p: Dictionary, at: String, text: String, tone: String,
		dur: float = NUMBER_DUR) -> void:
	if p["numbers"]:
		out.append({"k": "number", "at": at, "text": text, "tone": tone, "dur": dur})


static func _shake(out: Array[Dictionary], p: Dictionary, amp: float, dur: float) -> void:
	if float(p["shake"]) > 0.0:
		out.append({"k": "shake", "amp": amp * float(p["shake"]), "dur": dur})


static func _burst(out: Array[Dictionary], p: Dictionary, kind: String, at: String, count: int) -> void:
	var n := roundi(count * float(p["particles"]))
	if n > 0:
		out.append({"k": "burst", "kind": kind, "at": at, "count": n})
