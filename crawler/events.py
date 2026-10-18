"""A tiny publish/subscribe event bus.

The world emits events ("kill", "descend", ...) and other systems listen:
achievements, the announcer, and later telemetry. Subscribing to "*" receives
every event, which is how telemetry will log a whole run.
"""
from collections import defaultdict


class EventBus:
    def __init__(self):
        self._subs = defaultdict(list)

    def subscribe(self, name, fn):
        self._subs[name].append(fn)

    def emit(self, name, **data):
        for fn in self._subs.get(name, ()):
            fn(name, data)
        for fn in self._subs.get("*", ()):
            fn(name, data)
