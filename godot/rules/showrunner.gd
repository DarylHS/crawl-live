class_name Showrunner
extends RefCounted
## The Showrunner: the System AI announcer and the viewer count (crawler/showrunner.py).
##
## Viewers rise with entertaining play and slowly decay when nothing happens. Crossing a viewer
## threshold makes a sponsor send a loot box. Announcer lines are data (lines.json); it uses its own
## RNG (world seed ^ 0x5EED) so chatter never changes the dungeon. Subscription order is RNG order:
## the announcer first (in lines.json order), then the box reaction, the viewer model, the idle
## clock and the pet quips, exactly as Python subscribes.
##
## The owning world is held through a WeakRef (port plan section 3, "Back-references to World"):
## World -> Showrunner -> World would otherwise be a strong reference cycle. The world must own its
## Showrunner for its whole life; a Showrunner kept without its world gets null from `world`.
## Duck-typed world: it needs seed, events, messages, turn, pet, player, hero_name, address,
## contract, mod(), practice() and add_box().

static var START_VIEWERS: int = Content.config("showrunner")["START_VIEWERS"]
static var MIN_VIEWERS: int = Content.config("showrunner")["MIN_VIEWERS"]
## Viewer curve resolution for the post-run report.
static var SAMPLE_EVERY: int = Content.config("showrunner")["SAMPLE_EVERY"]
## Turns without excitement before viewers drift away.
static var IDLE_TURNS: int = Content.config("showrunner")["IDLE_TURNS"]
## Applied every IDLE_TURNS while idle.
static var DECAY: float = Content.config("showrunner")["DECAY"]
## Kills this close together count as a streak.
static var MULTI_WINDOW: int = Content.config("showrunner")["MULTI_WINDOW"]
static var CLUTCH_FRAC: float = Content.config("showrunner")["CLUTCH_FRAC"]
## Events the System only comments on some of the time (scaled by SASS_LEVEL); others always. This is
## the config table itself, so tests may patch an entry (the monkeypatch.setitem analogue).
static var SPEAK_CHANCE: Dictionary = Content.config("showrunner")["SPEAK_CHANCE"]
## How often the pet says something itself.
static var QUIP_CHANCE: float = Content.config("showrunner")["QUIP_CHANCE"]
## Turns between the mouse's excuses while it runs.
static var FLEE_QUIP_GAP: int = Content.config("showrunner")["FLEE_QUIP_GAP"]
static var PET_EVENTS: Dictionary = Content.config("showrunner")["PET_EVENTS"]
static var JACKPOT_VALUE: int = Content.config("lines")["JACKPOT_VALUE"]

## The owning world, held through a WeakRef.
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef
var rng: PyRandom
var viewers: int
var peak: int
## [turn, viewers] at each floor start and end.
var history: Array = []
## [turn, viewers] every SAMPLE_EVERY turns.
var samples: Array = []
var _kill_turns: Array = []
var _last_fun: int = 0
var _gift_idx: int = 0
var _last_flee_quip: int = 0


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)
	rng = PyRandom.new(int(world_value.seed) ^ 0x5EED)
	viewers = START_VIEWERS
	peak = START_VIEWERS
	samples = [[0, START_VIEWERS]]
	var ev: EventBus = world_value.events
	var lines: Dictionary = Content.table("lines")
	for name in lines:
		var e: String = name
		if (e != "multi_kill" and e != "clutch" and not e.begins_with("box_")) \
				or e == "box_reroll" or e == "box_trade":
			ev.subscribe(e, _announce)
	ev.subscribe("box_opened", _box_reaction)
	for e in ["kill", "level_up", "descend", "achievement", "floor_start", "boss_kill"]:
		ev.subscribe(e, _viewers)
	ev.subscribe("turn", _idle)
	for e in PET_EVENTS:
		ev.subscribe(e, _pet_quip)
	_last_flee_quip = -FLEE_QUIP_GAP


## SPONSOR_GIFTS: [{viewers, tier, sponsor}, ...] in threshold order.
static func sponsor_gifts() -> Array:
	return Content.table("sponsor_gifts")


# --- Viewers -----------------------------------------------------------------

func _gain(amount: int) -> void:
	var w: Object = world
	var scaled: float = amount * float(Contracts.effect(w, "viewer_mult")) \
			* (1 + 0.03 * w.practice("showmanship")) * (1 + 0.05 * w.mod("cha"))
	var got: int = int(scaled)
	viewers += got
	w.events.emit("viewers_gained", {"amount": got})
	peak = maxi(peak, viewers)
	_last_fun = w.turn
	var gifts: Array = sponsor_gifts()
	while _gift_idx < gifts.size() and viewers >= int(gifts[_gift_idx]["viewers"]):
		var tier: String = gifts[_gift_idx]["tier"]
		var sponsor: String = gifts[_gift_idx]["sponsor"]
		_gift_idx += 1
		w.events.emit("sponsor_gift", {"tier": tier, "sponsor": sponsor})
		w.add_box(tier, "A gift from %s for reaching %s viewers." % [sponsor, PyFmt.thousands(viewers)])


func _viewers(name: String, d: Dictionary) -> void:
	var w: Object = world
	if name == "kill":
		var xp: int = d["xp"] if d.has("xp") else Content.monster(d["monster"])["xp"]
		var gain: int = 5 + 2 * xp + (15 if d.get("by") == "pet" else 0)
		var kept: Array = []
		for t in _kill_turns:
			if w.turn - t <= MULTI_WINDOW:
				kept.append(t)
		_kill_turns = kept
		_kill_turns.append(w.turn)
		if _kill_turns.size() >= 2:
			gain += 25 * (_kill_turns.size() - 1)
			_say("multi_kill")
		if d["player_hp"] <= d["player_max_hp"] * CLUTCH_FRAC:
			gain += 60
			_say("clutch")
		_gain(gain)
	elif name == "level_up":
		_gain(40)
	elif name == "achievement":
		_gain(50)
	elif name == "descend":
		var late: bool = d["timer_left"] < 0.25 * d["timer_max"]
		_gain(100 if late else 30)
	elif name == "boss_kill":
		_gain(150)
	elif name == "floor_start":
		history.append([d["turn"], viewers])


func _idle(_name: String, d: Dictionary) -> void:
	var t: int = d["turn"]
	if PyMath.mod(t, SAMPLE_EVERY) == 0:
		samples.append([t, viewers])
	if PyMath.mod(t, IDLE_TURNS) == 0 and t - _last_fun >= IDLE_TURNS:
		viewers = maxi(MIN_VIEWERS, int(viewers * DECAY))


# --- Announcer ---------------------------------------------------------------

## The companion speaks for itself, in character.
func _pet_quip(name: String, d: Dictionary) -> void:
	var w: Object = world
	var by_species: Dictionary = Content.table("pet_quips").get(d.get("species"), {})
	var lines: Array = by_species.get(PET_EVENTS[name], [])
	if lines.is_empty():
		return
	if name == "pet_flee":
		if w.turn - _last_flee_quip < FLEE_QUIP_GAP:
			return
		_last_flee_quip = w.turn
	elif rng.random() >= QUIP_CHANCE:
		return
	var pet: Variant = w.pet
	w.messages.add("%s: %s" % [d["pet"], rng.choice(lines)], pet.colour if pet != null else GameConfig.TEXT)


## Pick a line for the event, spicier as SASS_LEVEL rises, and post it.
func _say(kind: String, ctx: Dictionary = {}) -> void:
	var pools: Dictionary = Content.table("lines")[kind]
	var spicy: bool = rng.random() < minf(1.0, maxf(0.0, float(GameConfig.SASS_LEVEL - 4) / 4))
	var pool: Array = pools["spicy"] if spicy and not pools.get("spicy", []).is_empty() else pools["mild"]
	var w: Object = world
	var full := {"hero": w.hero_name, "address": w.address}
	full.merge(ctx, true)
	var line: String = PyFmt.format_map(rng.choice(pool), full)
	w.messages.add("SYSTEM: " + line, GameConfig.INFO)


## React to what came out of a loot box, judged against the box's average.
func _box_reaction(_name: String, d: Dictionary) -> void:
	var item: Dictionary = Content.item(d["item"])
	_say(box_kind(d["tier"], d["item"]), {"item": item["name"],
			"tier": Content.box(d["tier"])["name"], "value": item["value"],
			"ev": PyFmt.fixed(Loot.box_stats(d["tier"])[0], 0)})


func _announce(name: String, d: Dictionary) -> void:
	var w: Object = world
	if (name == "kill" or name == "pet_kill") and PyMath.truthy(d.get("boss")):
		return                          # boss_kill has its own lines
	if name == "practice_level" and not (d["level"] in [1, 5, 10, 15]):
		return                          # milestones only, or it never shuts up
	if name == "damage_taken" and d["hp"] > w.player.max_hp * 0.4:
		return
	if name == "opportunity_attack" and (d["target"] != "player" or not d["hit"]):
		return                          # the lines are about you getting caught, and hit
	var chattiness: float = minf(1.3, maxf(0.3, float(GameConfig.SASS_LEVEL) / 7))
	if rng.random() >= float(SPEAK_CHANCE.get(name, 1.0)) * chattiness:
		return
	var ctx: Dictionary = d.duplicate()
	if d.has("monster_name"):
		ctx["name"] = d["monster_name"]
	elif d.has("monster"):
		ctx["name"] = Content.monster(d["monster"])["name"]
	if d.has("tier"):
		ctx["tier"] = PyFmt.capitalize(d["tier"])
	if name == "achievement":
		ctx["achievement"] = d["title"]
		ctx["why"] = d["why"]
		ctx["reward"] = d["reward"]
	if d.has("contract"):
		ctx["deal"] = Contracts.contracts()[d["contract"]]["name"]
	_say(name, ctx)


## Which reaction a box result gets: junk, jackpot, or bad/meh/good against EV +/- 1 SD.
static func box_kind(tier: String, key: String) -> String:
	var stats: Array = Loot.box_stats(tier)
	var ev: float = stats[0]
	var sd: float = stats[1]
	var item: Dictionary = Content.item(key)
	if item["kind"] == "junk":
		return "box_junk"
	if item["value"] >= JACKPOT_VALUE:
		return "box_jackpot"
	if item["value"] < ev - sd:
		return "box_bad"
	if item["value"] > ev + sd:
		return "box_good"
	return "box_meh"
