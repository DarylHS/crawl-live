"""The Showrunner: the System AI announcer and the viewer count.

Viewers rise with entertaining play and slowly decay when nothing happens.
Crossing a viewer threshold makes a sponsor send a loot box. Announcer lines
are data (LINES); it uses its own RNG so chatter never changes the dungeon.
"""
import random

from . import config as C
from .entities import MONSTERS, PET_QUIPS

START_VIEWERS = 50
MIN_VIEWERS = 20
IDLE_TURNS = 10                 # turns without excitement before viewers drift away
DECAY = 0.97                    # applied every IDLE_TURNS while idle
MULTI_WINDOW = 4                # kills this close together count as a streak
CLUTCH_FRAC = 0.25
SPEAK_CHANCE = {"kill": 0.4, "damage_taken": 0.5}   # others always speak
QUIP_CHANCE = 0.6               # how often the pet says something itself
FLEE_QUIP_GAP = 8               # turns between the mouse's excuses while it runs
PET_EVENTS = {"pet_kill": "kill", "pet_ability": "ability", "pet_level_up": "level_up",
              "pet_downed": "downed", "pet_flee": "flee"}

# (viewers needed, box tier, sponsor)
SPONSOR_GIFTS = [
    (300, "bronze", "Brightly Snacks"),
    (700, "silver", "Gloop Energy"),
    (1500, "gold", "Vantage Mattress Co."),
    (3000, "platinum", "Zorp Premium Hair Care"),
    (6000, "legendary", "The Consortium of Mild Concern"),
]

LINES = {
    "floor_start": [
        "Welcome to floor {depth}. Please enjoy your impending doom.",
        "Floor {depth} is now live. Smile for the cameras.",
        "Floor {depth}: now with 15% more collapse.",
        "Another floor, another chance to disappoint sponsors.",
        "Floor {depth}. The audience placed bets. You won't like the odds.",
    ],
    "kill": [
        "A {name}, dispatched. Riveting.",
        "That {name} had a family. Probably.",
        "The crowd loves a tidy kill.",
        "Another {name} down. The ratings tick up.",
        "Brutal. Efficient. Slightly rude. Good television.",
    ],
    "multi_kill": [
        "Multi-kill! The chat is going feral.",
        "A streak! Sponsors are texting each other.",
        "Two in one breath. Someone call the highlights team.",
        "Excellent carnage. Viewers are up.",
        "That's how you edit a trailer.",
    ],
    "clutch": [
        "Barely alive and still swinging. Viewers love it.",
        "Clutch! Your next of kin will be thrilled.",
        "That was one hit from a very short episode.",
        "Dramatic tension: achieved.",
        "Low health, high ratings. The System approves.",
    ],
    "damage_taken": [
        "Ouch. The audience felt that.",
        "You're bleeding on the set.",
        "Nice try at dodging. Points for effort.",
        "That's going in the blooper reel.",
        "Health is a resource. You are wasting it.",
    ],
    "level_up": [
        "Level {level}. Congratulations, you are marginally less doomed.",
        "Level {level}! Here is a participation sticker.",
        "You grew. The System remains unmoved.",
        "Level {level}: the audience claps politely.",
        "Stronger, faster, still on a timer.",
    ],
    "descend": [
        "Down you go. Mind the plot holes.",
        "Descending. The cameras follow.",
        "Running away is a valid genre.",
        "Next floor. Try to look surprised.",
        "Stairs: the only sensible contestant strategy.",
    ],
    "rest": [
        "Napping on live television. Bold.",
        "Resting. The viewers have gone for snacks.",
        "Sleep tight. The timer isn't.",
        "Recovered. Dull, but alive.",
        "Ratings dip during rest. Just saying.",
    ],
    "timer_warning": [
        "The floor is creaking. Perhaps hurry.",
        "Collapse imminent. Dramatic music cue.",
        "Tick tock. The ceiling has opinions.",
        "Time is a flat circle, and it's closing.",
        "Fewer minutes remain than you would like.",
    ],
    "achievement": [
        "Achievement unlocked: {achievement}. A box for you!",
        "Well, look at you: {achievement}. Gift incoming.",
        "{achievement}. The System is faintly impressed.",
        "Someone noticed {achievement}. Here's a prize.",
        "Another trophy. {achievement}. Don't let it go to your head.",
    ],
    "box_opened": [
        "Opening a {tier} box. The suspense is theoretical.",
        "A {tier} box! Let's see what we're pretending is generous.",
        "Unwrapping {tier}. Cue studio applause.",
        "{tier} box open. Try not to cry.",
        "The audience watches a {tier} box open. Peak entertainment.",
    ],
    "sponsor_gift": [
        "{sponsor} sends a {tier} box. They want you to know they care.",
        "A gift from {sponsor}: a {tier} box. Please say thank you.",
        "{sponsor} loves you today. {tier} box delivered.",
        "Viewers pooled their money. {sponsor} has sent a {tier} box.",
        "{sponsor} would like you to use their {tier} box responsibly.",
    ],
    "player_death": [
        "And that's a wrap. Thanks for dying on air.",
        "You have been cancelled.",
        "Dead. The ratings spike, briefly.",
        "A tragic finale. The sponsors send flowers.",
        "The System regrets nothing.",
    ],
    "pet_kill": [
        "{pet} claims a {name}. The pet merch is selling out.",
        "{pet} did that. You were mostly decorative.",
        "A {name}, mauled by {pet}. Adorable and horrifying.",
        "{pet} gets the kill. Polls show viewers prefer {pet} to you.",
        "{pet} just carried the episode.",
    ],
    "pet_downed": [
        "{pet} is down! The audience gasps on cue.",
        "Somebody get {pet} to a safe room. The ratings depend on it.",
        "{pet} has fallen. The comments section is furious with you.",
        "Losing {pet}? Bold creative choice.",
        "{pet} needs a nap and a lawyer.",
    ],
    "pet_ability": [
        "{pet} uses {ability}. Somebody clip that.",
        "{ability}! {pet} is the real contestant here.",
        "{pet} with the {ability}. Chef's kiss.",
        "{ability}, courtesy of {pet}. Sponsors are taking notes.",
        "{pet} remembers it has a special move: {ability}.",
    ],
    "boss_phase": [
        "{boss} is ANGRY now. Excellent television.",
        "Phase two! {boss} has called in favours.",
        "{boss} rips off the polite mask. Finally.",
        "And {boss} gets serious. Popcorn sales spike.",
        "{boss} demands reinforcements and a bigger trailer.",
    ],
    "boss_kill": [
        "{boss} is down! That was the expensive set piece.",
        "You beat {boss}. The writers are scrambling.",
        "{boss}: defeated. Somebody's getting fired upstairs.",
        "The crowd roars. {boss} will be missed by its agent.",
        "{boss} falls. Viewers are standing on their chairs.",
    ],
    "class_chosen": [
        "{title}. Bold. Let's see if it lasts.",
        "{title}, is it? The betting markets have adjusted.",
        "Welcome, {title}. Your contract is non-negotiable.",
        "{title}: an inspired choice, said nobody yet.",
        "The System registers your class: {title}. No refunds.",
    ],
    "victory": [
        "You survived. The producers are furious.",
        "Escape confirmed. Ratings: acceptable.",
        "You won! A sequel has been announced against your wishes.",
        "The finale was almost watchable.",
        "Contestant survives. The odds-makers weep.",
    ],
}


class Showrunner:
    def __init__(self, world):
        self.world = world
        self.rng = random.Random(world.seed ^ 0x5EED)
        self.viewers = START_VIEWERS
        self.peak = START_VIEWERS
        self.history = []                   # (turn, viewers) at each floor start and end
        self._kill_turns = []
        self._last_fun = 0
        self._gift_idx = 0
        for ev in LINES:
            if ev not in ("multi_kill", "clutch"):
                world.events.subscribe(ev, self._announce)
        for ev in ("kill", "level_up", "descend", "achievement", "floor_start", "boss_kill"):
            world.events.subscribe(ev, self._viewers)
        world.events.subscribe("turn", self._idle)
        for ev in PET_EVENTS:
            world.events.subscribe(ev, self._pet_quip)
        self._last_flee_quip = -FLEE_QUIP_GAP

    # --- Viewers -------------------------------------------------------

    def _gain(self, amount):
        self.viewers += int(amount)
        self.peak = max(self.peak, self.viewers)
        self._last_fun = self.world.turn
        while self._gift_idx < len(SPONSOR_GIFTS) and self.viewers >= SPONSOR_GIFTS[self._gift_idx][0]:
            _, tier, sponsor = SPONSOR_GIFTS[self._gift_idx]
            self._gift_idx += 1
            self.world.events.emit("sponsor_gift", tier=tier, sponsor=sponsor)
            self.world.add_box(tier, "sponsor")

    def _viewers(self, name, d):
        w = self.world
        if name == "kill":
            xp = d["xp"] if "xp" in d else MONSTERS[d["monster"]]["xp"]
            gain = 5 + 2 * xp + (15 if d.get("by") == "pet" else 0)
            self._kill_turns = [t for t in self._kill_turns if w.turn - t <= MULTI_WINDOW]
            self._kill_turns.append(w.turn)
            if len(self._kill_turns) >= 2:
                gain += 25 * (len(self._kill_turns) - 1)
                self._say("multi_kill")
            if d["player_hp"] <= d["player_max_hp"] * CLUTCH_FRAC:
                gain += 60
                self._say("clutch")
            self._gain(gain)
        elif name == "level_up":
            self._gain(40)
        elif name == "achievement":
            self._gain(50)
        elif name == "descend":
            late = d["timer_left"] < 0.25 * d["timer_max"]
            self._gain(100 if late else 30)
        elif name == "boss_kill":
            self._gain(150)
        elif name == "floor_start":
            self.history.append((d["turn"], self.viewers))

    def _idle(self, name, d):
        t = d["turn"]
        if t % IDLE_TURNS == 0 and t - self._last_fun >= IDLE_TURNS:
            self.viewers = max(MIN_VIEWERS, int(self.viewers * DECAY))

    # --- Announcer -----------------------------------------------------

    def _pet_quip(self, name, d):
        """The companion speaks for itself, in character."""
        lines = PET_QUIPS.get(d.get("species"), {}).get(PET_EVENTS[name])
        if not lines:
            return
        if name == "pet_flee":
            if self.world.turn - self._last_flee_quip < FLEE_QUIP_GAP:
                return
            self._last_flee_quip = self.world.turn
        elif self.rng.random() >= QUIP_CHANCE:
            return
        pet = self.world.pet
        self.world.messages.add(f"{d['pet']}: {self.rng.choice(lines)}",
                                pet.colour if pet else C.TEXT)

    def _say(self, kind, **ctx):
        line = self.rng.choice(LINES[kind]).format_map(_Safe(ctx))
        self.world.messages.add("SYSTEM: " + line, C.INFO)

    def _announce(self, name, d):
        if name == "damage_taken" and d["hp"] > self.world.player.max_hp * 0.4:
            return
        if self.rng.random() >= SPEAK_CHANCE.get(name, 1.0):
            return
        ctx = dict(d)
        if "monster_name" in d:
            ctx["name"] = d["monster_name"]
        elif "monster" in d:
            ctx["name"] = MONSTERS[d["monster"]]["name"]
        if "tier" in d:
            ctx["tier"] = d["tier"].capitalize()
        if name == "achievement":
            ctx["achievement"] = d["title"]
        self._say(name, **ctx)


class _Safe(dict):
    def __missing__(self, key):
        return "?"
