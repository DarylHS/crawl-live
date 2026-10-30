class_name ViewModelPose
extends RefCounted
## Where the first-person weapon is drawn: a swing is a few key poses blended with smoothstep, plus
## the idle sway while you walk or stand. Headless maths (tests check the poses); ViewModel draws it.
##
## A pose is {"off": Vector2, "rot": float, "scale": float}: the shift in pixels of the 320 x 200 frame
## from the resting spot (+y is down), the turn in radians about the hands (+ leans right), and a size
## multiplier (bigger means nearer, a lunge). Styles follow the items' `style`: "blade", "blunt", and
## "unarmed" for bare fists.

## Key poses [progress, off.x, off.y, rot, scale] per style; the swing runs 0 to 1 over `duration`.
const KEYS := {
	"blade": [[0.0, 0.0, 0.0, 0.0, 1.0], [0.25, 14.0, 10.0, 0.45, 1.0], [0.55, -30.0, -6.0, -0.8, 1.06],
			[0.8, -22.0, 4.0, -0.5, 1.0], [1.0, 0.0, 0.0, 0.0, 1.0]],
	"blunt": [[0.0, 0.0, 0.0, 0.0, 1.0], [0.3, 10.0, -22.0, 0.5, 1.0], [0.55, -4.0, 14.0, -0.35, 1.15],
			[0.75, -2.0, 10.0, -0.2, 1.08], [1.0, 0.0, 0.0, 0.0, 1.0]],
	"unarmed": [[0.0, 0.0, 0.0, 0.0, 1.0], [0.3, -6.0, 8.0, -0.08, 0.95], [0.55, -8.0, -28.0, 0.0, 1.3],
			[0.8, -4.0, -8.0, 0.0, 1.1], [1.0, 0.0, 0.0, 0.0, 1.0]],
}
## Seconds a swing lasts per style (a heavy weapon is slower).
const DURATION := {"blade": 0.30, "blunt": 0.38, "unarmed": 0.22}


static func duration(style: String) -> float:
	return float(DURATION.get(style, DURATION["blunt"]))


## The pose `k` (0 to 1) through a swing. Out-of-range k clamps; unknown styles swing like blunt weapons.
static func swing(style: String, k: float) -> Dictionary:
	var keys: Array = KEYS.get(style, KEYS["blunt"])
	k = clampf(k, 0.0, 1.0)
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if k <= float(b[0]):
			var u := (k - float(a[0])) / (float(b[0]) - float(a[0]))
			u = u * u * (3.0 - 2.0 * u)
			return {"off": Vector2(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u)),
					"rot": lerpf(a[3], b[3], u), "scale": lerpf(a[4], b[4], u)}
	var last: Array = keys[keys.size() - 1]
	return {"off": Vector2(last[1], last[2]), "rot": last[3], "scale": last[4]}


## The resting sway: a slow breath when still, and a walking bob and side sway tied to `walked`, the
## distance walked in tiles (two bobs per tile). `strength` 0 turns the sway off ("reduced" and "off").
static func idle(time: float, walked: float, moving: float, strength: float) -> Vector2:
	if strength <= 0.0:
		return Vector2.ZERO
	var breath := Vector2(sin(time * 1.3) * 0.8, sin(time * 1.9) * 0.8)
	var phase := walked * TAU * 1.0
	var bob := Vector2(sin(phase) * 3.0, absf(cos(phase)) * -2.5) * clampf(moving, 0.0, 1.0)
	return (breath + bob) * strength
