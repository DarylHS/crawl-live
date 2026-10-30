class_name FxParticles
extends Node3D
## One-shot particle bursts in the 3D view: hit sparks, kill dust, bomb fire and smoke, healing motes.
##
## Godot has two particle nodes: GPUParticles3D (the graphics card simulates thousands of particles
## from a ParticleProcessMaterial) and CPUParticles3D (the same options, simulated in script-free
## engine code on the processor). These bursts are tens of particles, so CPUParticles3D is used: it is
## cheap at this size, behaves the same on every renderer (the game defaults to the Compatibility
## renderer, and software GL under Xvfb), and needs no shader. Each burst is a one-shot node that frees
## itself when it finishes (`finished` signal).
##
## Particles are little unshaded squares (hard pixels, no filtering) whose colour fades along a Gradient.
## The count is chosen by the caller (FxPlan, scaled by the Effects setting).

const MAX_LIVE := 14                       ## bursts alive at once; the oldest goes first
## Per kind: lifetime s, speed min and max (tiles/s), gravity (tiles/s^2, negative falls), size (tiles),
## spread degrees, colours (start to end, the end is transparent), direction.
const KINDS := {
	"hit": {"life": 0.35, "v0": 0.8, "v1": 1.8, "g": -3.0, "size": 0.035, "spread": 180.0,
			"c0": Color(1.0, 1.0, 0.85), "c1": Color(1.0, 0.55, 0.15), "dir": Vector3.UP},
	"crit": {"life": 0.5, "v0": 1.2, "v1": 2.8, "g": -3.0, "size": 0.045, "spread": 180.0,
			"c0": Color(1.0, 0.95, 0.5), "c1": Color(1.0, 0.35, 0.1), "dir": Vector3.UP},
	"kill": {"life": 0.7, "v0": 0.3, "v1": 0.9, "g": 0.2, "size": 0.07, "spread": 180.0,
			"c0": Color(0.72, 0.68, 0.62), "c1": Color(0.35, 0.33, 0.32), "dir": Vector3.UP},
	"bomb": {"life": 0.8, "v0": 1.5, "v1": 4.0, "g": -4.0, "size": 0.06, "spread": 180.0,
			"c0": Color(1.0, 0.9, 0.4), "c1": Color(0.9, 0.2, 0.05), "dir": Vector3.UP},
	"smoke": {"life": 1.2, "v0": 0.3, "v1": 1.1, "g": 0.4, "size": 0.14, "spread": 180.0,
			"c0": Color(0.3, 0.28, 0.28), "c1": Color(0.1, 0.1, 0.1), "dir": Vector3.UP},
	"heal": {"life": 0.9, "v0": 0.2, "v1": 0.7, "g": 0.8, "size": 0.035, "spread": 40.0,
			"c0": Color(0.7, 1.0, 0.7), "c1": Color(0.2, 0.8, 0.4), "dir": Vector3.UP},
	"ember": {"life": 1.0, "v0": 0.08, "v1": 0.2, "g": 0.1, "size": 0.012, "spread": 30.0,
			"c0": Color(1.0, 0.8, 0.3), "c1": Color(0.9, 0.25, 0.05), "dir": Vector3.UP},
}

static var _materials: Dictionary = {}     ## kind -> StandardMaterial3D
static var _mesh: QuadMesh = null

var started: int = 0                       ## bursts started (tests read it)


## A burst of `count` particles of `kind` at a world position (tiles). The bomb adds a smoke puff.
func burst(kind: String, pos: Vector3, count: int) -> void:
	if count <= 0 or not KINDS.has(kind):
		return
	_spawn(kind, pos, count)
	if kind == "bomb":
		_spawn("smoke", pos, maxi(4, count / 3))


## Remove every burst (a key press skips the rest of them).
func clear() -> void:
	for c in get_children():
		c.queue_free()


## How many bursts are alive.
func live() -> int:
	var n := 0
	for c in get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


func _spawn(kind: String, pos: Vector3, count: int) -> void:
	while get_child_count() >= MAX_LIVE:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	var p := configure(CPUParticles3D.new(), kind, count)
	p.one_shot = true
	p.explosiveness = 0.9
	p.finished.connect(p.queue_free)
	add_child(p)
	p.position = pos
	p.emitting = true
	started += 1


## Set up a CPUParticles3D for a kind (also used by the wall torches for their embers).
static func configure(p: CPUParticles3D, kind: String, count: int) -> CPUParticles3D:
	var k: Dictionary = KINDS[kind]
	p.amount = maxi(1, count)
	p.lifetime = k["life"]
	p.direction = k["dir"]
	p.spread = k["spread"]
	p.initial_velocity_min = k["v0"]
	p.initial_velocity_max = k["v1"]
	p.gravity = Vector3(0.0, float(k["g"]), 0.0)
	p.scale_amount_min = float(k["size"]) * 0.7
	p.scale_amount_max = float(k["size"])
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([k["c0"], k["c1"], Color(k["c1"].r, k["c1"].g, k["c1"].b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad()
	p.material_override = _material(kind)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _quad() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
	return _mesh


## Unshaded, vertex-coloured, always facing the camera. Smoke is drawn without alpha-cut so it fades softly.
static func _material(kind: String) -> StandardMaterial3D:
	if not _materials.has(kind):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.disable_receive_shadows = true
		_materials[kind] = m
	return _materials[kind]
