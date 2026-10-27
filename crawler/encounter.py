"""Combat mode: who is fighting, in what order, and what you have left this turn.

An Encounter exists only while a fight is on (World.combat is None otherwise). It
holds the initiative order, the round number, the player's turn budget (one move,
one action and one bonus action per round) and who has used their reaction (one
attack of opportunity each per round). It is plain data; the World rolls
initiative, spends the budget and runs the other combatants' turns.
"""

PARTS = ("move", "action", "bonus")
PART_NAMES = {"move": "move", "action": "action", "bonus": "bonus action"}


class Encounter:
    def __init__(self, player):
        self.player = player
        self.order = []                 # [(sort key, entity, roll, modifier)], best first
        self.round = 0                  # 0 until the first round begins
        self.budget = dict.fromkeys(PARTS, True)
        self.reacted = set()            # who has used their reaction since their last turn
        self._seq = 0

    def __contains__(self, entity):
        return any(e is entity for _, e, _, _ in self.order)

    def add(self, entity, roll, modifier):
        """Place a combatant by initiative: higher total first, then the higher modifier,
        then the player; later joiners go after earlier ones with the same numbers."""
        if entity in self:
            return
        self._seq += 1
        key = (-(roll + modifier), -modifier, entity is not self.player, self._seq)
        self.order.append((key, entity, roll, modifier))
        self.order.sort(key=lambda row: row[0])

    # --- Reactions (attacks of opportunity) ---------------------------------

    def can_react(self, entity):
        return entity in self and entity not in self.reacted

    def react(self, entity):
        self.reacted.add(entity)

    def ready(self, entity):
        """A creature's reaction comes back at the start of its turn."""
        self.reacted.discard(entity)

    def remove(self, entity):
        self.order = [row for row in self.order if row[1] is not entity]

    @property
    def entities(self):
        return [e for _, e, _, _ in self.order]

    @property
    def monsters(self):
        """Combatants other than the player and the pet (anything with an 'alerted' flag)."""
        return [e for e in self.entities if hasattr(e, "alerted")]

    def total(self, entity):
        return next(r + m for _, e, r, m in self.order if e is entity)

    def before(self, entity):
        """Combatants that act before entity in a round."""
        es = self.entities
        return es[:next(i for i, e in enumerate(es) if e is entity)]

    def after(self, entity):
        """Combatants that act after entity in a round."""
        es = self.entities
        return es[next(i for i, e in enumerate(es) if e is entity) + 1:]

    # --- The player's turn budget ----------------------------------------

    def has(self, part):
        return self.budget[part]

    def spend(self, part):
        self.budget[part] = False

    def reset_budget(self):
        self.budget = dict.fromkeys(PARTS, True)

    @property
    def turn_over(self):
        """Your turn ends by itself once both the move and the action are spent."""
        return not self.budget["move"] and not self.budget["action"]
