import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { vec3 } from "../math/math3d";
import { sinf, cosf } from "../math/mat4";
import {
	ParticleSystemAsset, ParticleEffect, RenderMode, RenderAlignment, SimulationSpace,
} from "../particles/asset";
import { constantCurve, constantColor, rgbaColor, curveOf, linearCurve, key } from "../particles/curve";
import { NodeRef, Scene2D, TileCell } from "../void2d/node";
import { cellMatrix } from "../void2d/render";
import "../void2d/scene";
import { Tile, Transform2D, rgba, tile, identity2d, trs2d, vec2 } from "../void2d/types";
import { ParticleEmitter2D, Particles2DErrorKind, particles, play, update } from "../void2d/particles2d";
import { approx, fakeTexture } from "./helpers";

function fresh(): Scene2D { return Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)); }

function at(x: float32, y: float32): Transform2D {
	return { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: x, ty: y };
}

// One particle at the emitter, living 2 s, with no speed and no gravity.
function single(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.startLifetime = constantCurve(2.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.startSizeX = constantCurve(4.0);
	a.main.startColor = constantColor(rgbaColor(1.0, 0.5, 0.25, 1.0));
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	return a;
}

function emitter(s: Scene2D, a: ParticleSystemAsset, t: Tile): ParticleEmitter2D {
	const effect: ParticleEffect = { systems: [a] };
	const made = s.particles(effect, [t], 3);
	if (!made.ok) { unreachable; }
	return made.value;
}

function first(e: ParticleEmitter2D): TileCell {
	return e.node.scene.tileCells[e.node.scene.payloads[e.node.id.index]][0];
}

test "a particle draws as one centred cell of its size and colour where the emitter stands" {
	const s = fresh();
	let e = emitter(s, single(), tile(fakeTexture(5), 16.0, 16.0));
	e.play(at(100.0, 50.0));
	const n = e.update(1.0 / 60.0, at(100.0, 50.0), VIEW);
	assert n.ok && n.value == 1;
	assert e.node.count() == 1;
	const c: TileCell = first(e);
	assert approx(c.x, 100.0) && approx(c.y, 50.0);
	assert approx(c.scaleX * c.tile.w, 4.0) && approx(c.scaleY * c.tile.h, 4.0);
	assert approx(c.tile.dx, -8.0) && approx(c.tile.dy, -8.0);
	assert approx(c.color.r, 1.0) && approx(c.color.g, 0.5) && approx(c.color.b, 0.25);
}

test "gravity pulls a particle down the screen and +x speed moves it right" {
	const s = fresh();
	let a = single();
	a.main.startSpeed = constantCurve(10.0);
	a.main.gravityModifier = constantCurve(1.0);
	a.main.startRotationZ = constantCurve(0.5);
	a.shape.enabled = true;
	a.shape.rotation = { x: 0.0, y: 90.0, z: 0.0 };
	a.shape.angle = 0.0;
	a.shape.radius = 0.0;
	let e = emitter(s, a, tile(fakeTexture(5), 16.0, 16.0));
	e.play(identity2d());
	for (let k = 0; k < 30; k++) { const _n = e.update(1.0 / 60.0, identity2d(), VIEW); }
	const c: TileCell = first(e);
	assert c.x > 4.0;
	assert c.y > 1.0;
	assert approx(c.rotation, 0.5);
}

test "the texture sheet picks the frame's quarter of a 2x2 tile" {
	const s = fresh();
	let a = single();
	a.textureSheetAnimation.enabled = true;
	a.textureSheetAnimation.numTilesX = 2;
	a.textureSheetAnimation.numTilesY = 2;
	a.textureSheetAnimation.frameOverTime = curveOf(1.0, linearCurve([key(0.0, 0.0), key(1.0, 1.0)]));
	let e = emitter(s, a, tile(fakeTexture(5), 32.0, 32.0));
	e.play(identity2d());
	// At 1.1 s of 2 s the sheet is at 0.55 of 4 frames: frame 2, the bottom-left quarter.
	for (let k = 0; k < 66; k++) { const _n = e.update(1.0 / 60.0, identity2d(), VIEW); }
	const c: TileCell = first(e);
	assert approx(c.tile.w, 16.0) && approx(c.tile.h, 16.0);
	assert approx(c.tile.u0, 0.0) && approx(c.tile.u1, 0.5);
	assert approx(c.tile.v0, 0.5) && approx(c.tile.v1, 1.0);
}

test "a system rendered as None draws nothing but still simulates" {
	const s = fresh();
	let a = single();
	a.renderer.renderMode = RenderMode.None;
	let e = emitter(s, a, tile(fakeTexture(5), 16.0, 16.0));
	e.play(identity2d());
	const n = e.update(1.0 / 60.0, identity2d(), VIEW);
	assert n.ok && n.value == 1;
	assert e.node.count() == 0;
}

test "a particle whose life ends leaves the node" {
	const s = fresh();
	let e = emitter(s, single(), tile(fakeTexture(5), 16.0, 16.0));
	e.play(identity2d());
	for (let k = 0; k < 121; k++) { const _n = e.update(1.0 / 60.0, identity2d(), VIEW); }
	assert e.node.count() == 0;
}

test "a falling particle's trail draws as a strip of its width down the screen" {
	const s = fresh();
	let a = single();
	a.main.gravityModifier = constantCurve(1.0);
	a.trails.enabled = true;
	a.trails.minVertexDistance = 0.0;
	a.trails.colorOverTrail = constantColor(rgbaColor(1.0, 1.0, 1.0, 0.5));
	let e = emitter(s, a, tile(fakeTexture(5), 16.0, 16.0));
	e.play(at(100.0, 50.0));
	for (let k = 0; k < 20; k++) { const n = e.update(1.0 / 60.0, at(100.0, 50.0), VIEW); }
	const g: NodeRef = e.trailNodes[0];
	const mesh: float32[] = s.meshes[s.payloads[g.id.index]].mesh;
	const vertices: int32 = (mesh.length as int32) / 8;
	assert vertices >= 6 && vertices % 6 == 0;
	let lowest: float32 = 0.0;
	for (let v = 0; v < vertices; v++) {
		const x: float32 = mesh[v * 8];
		assert approx(x, 98.0) || approx(x, 102.0);
		if (mesh[v * 8 + 1] > lowest) { lowest = mesh[v * 8 + 1]; }
		assert approx(mesh[v * 8 + 4], 1.0) && approx(mesh[v * 8 + 5], 0.5) && approx(mesh[v * 8 + 7], 0.5);
	}
	// The particle fell, and screen y grows downward.
	assert lowest > 50.0 && approx(first(e).y, lowest);
}

// ---- render mode and alignment against Unity's baked quads (tests/unity/goldens) ----

const CORNER_TOL: float32 = 1e-3;
const UNITY_DT: float64 = 0.1;
// A view wide enough that no default size limit (minParticleSize 0, maxParticleSize 0.5) reaches a test particle.
const VIEW: float32 = 1000.0;

struct UnityQuad {
	vx: float32;
	vy: float32;
	forceY: float32;
	width: float32;
	height: float32;
	rotationDegrees: float32;
	mode: RenderMode;
	alignment: RenderAlignment;
	lengthScale: float32;
	velocityScale: float32;
	pivotX: float32;
	pivotY: float32;
	freeform: boolean;
	rotateWith: boolean;
	allowRoll: boolean;
	minSize: float32;
	maxSize: float32;
	viewport: float32;
}

function quad(vx: float32, vy: float32): UnityQuad {
	return {
		vx: vx, vy: vy, forceY: 0.0, width: 1.0, height: 1.0, rotationDegrees: 0.0,
		mode: RenderMode.Billboard, alignment: RenderAlignment.View, lengthScale: 1.0,
		velocityScale: 0.0, pivotX: 0.0, pivotY: 0.0, freeform: false, rotateWith: true, allowRoll: true,
		minSize: 0.0, maxSize: 0.5, viewport: VIEW,
	};
}

// ParticleCapture.StretchCase: one particle drifting in the xy plane.
function unityAsset(q: UnityQuad): ParticleSystemAsset {
	let a = single();
	a.main.simulationSpace = SimulationSpace.Local;
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSizeX = constantCurve(q.width);
	a.main.startSize3D = true;
	a.main.startSizeY = constantCurve(q.height);
	a.main.startSizeZ = constantCurve(1.0);
	a.main.startRotationZ = constantCurve(q.rotationDegrees * 0.017453292519943295);
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.x = constantCurve(q.vx);
	a.velocityOverLifetime.y = constantCurve(q.vy);
	a.velocityOverLifetime.z = constantCurve(0.0);
	if (q.forceY != 0.0) {
		a.forceOverLifetime.enabled = true;
		a.forceOverLifetime.y = constantCurve(q.forceY);
	}
	a.renderer.renderMode = q.mode;
	a.renderer.alignment = q.alignment;
	a.renderer.lengthScale = q.lengthScale;
	a.renderer.velocityScale = q.velocityScale;
	a.renderer.pivot = vec3(q.pivotX, q.pivotY, 0.0);
	a.renderer.freeformStretching = q.freeform;
	a.renderer.rotateWithStretchDirection = q.rotateWith;
	a.renderer.allowRoll = q.allowRoll;
	a.renderer.minParticleSize = q.minSize;
	a.renderer.maxParticleSize = q.maxSize;
	return a;
}

function golden(name: string): JsonValue {
	const text = readFile(`tests/unity/goldens/${name}.json`);
	if (!text.ok) { unreachable; }
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) { unreachable; }
	return parsed.value;
}

// The cell's corners in Unity's y-up frame, top-left first, as the baked quad lists them.
function cellCorners(c: TileCell): float32[] {
	const m: Transform2D = cellMatrix(c);
	const t: Tile = c.tile;
	const a = vec2(t.dx, t.dy) * m;
	const b = vec2(t.dx + t.w, t.dy) * m;
	const d = vec2(t.dx + t.w, t.dy + t.h) * m;
	const e = vec2(t.dx, t.dy + t.h) * m;
	return [a.x, -a.y, b.x, -b.y, d.x, -d.y, e.x, -e.y];
}

// Replays a baked-quad golden through the 2D writer at Unity's step, 4 sub-steps per frame, and
// counts the corners that differ.
function cornerMisses(name: string, q: UnityQuad): int32 {
	const s = fresh();
	let e = emitter(s, unityAsset(q), tile(fakeTexture(5), 16.0, 16.0));
	e.effect.clock.fixedStep = UNITY_DT / 4.0;
	e.play(identity2d());
	const frames = golden(name).getDynamicField("frames");
	let misses: int32 = 0;
	for (let k = 1; k < (frames.length() as int32); k++) {
		const n = e.update(UNITY_DT, identity2d(), q.viewport);
		if (!n.ok || n.value != 1) { return 1000; }
		const baked = frames.at(k).getDynamicField("bakedQuads");
		const wanted: int32 = baked.length() as int32;
		if (e.node.count() != wanted) { return 1000; }
		if (wanted == 0) { continue; }
		const mine: float32[] = cellCorners(first(e));
		const pos = baked.at(0).getDynamicField("pos");
		for (let v = 0; v < 4; v++) {
			for (let axis = 0; axis < 2; axis++) {
				const unity: float32 = pos.at(v).at(axis).asNumber() as float32;
				const d: float32 = mine[v * 2 + axis] - unity;
				if (d > CORNER_TOL || d < -CORNER_TOL) { misses = misses + 1; }
			}
		}
	}
	return misses;
}

function stretched(vx: float32, vy: float32, lengthScale: float32, velocityScale: float32): UnityQuad {
	let q = quad(vx, vy);
	q.mode = RenderMode.Stretch;
	q.lengthScale = lengthScale;
	q.velocityScale = velocityScale;
	return q;
}

test "stretch: the quad is size * lengthScale long with its head at the particle (ls 1 and 2, vs 0)" {
	assert cornerMisses("stretch_ls1_vs0", stretched(3.0, 4.0, 1.0, 0.0)) == 0;
	assert cornerMisses("stretch_ls2_vs0", stretched(3.0, 4.0, 2.0, 0.0)) == 0;
}

test "stretch: velocityScale adds speed * velocityScale to the length (vs 0.5, ls 1 and 2)" {
	assert cornerMisses("stretch_ls1_vs05", stretched(3.0, 4.0, 1.0, 0.5)) == 0;
	assert cornerMisses("stretch_ls2_vs05", stretched(3.0, 4.0, 2.0, 0.5)) == 0;
}

test "stretch: the direction and speed are the total velocity, and the particle's rotation is ignored" {
	let q = stretched(3.0, 0.0, 1.0, 0.5);
	q.forceY = 4.0;
	q.width = 2.0;
	q.height = 2.0;
	q.rotationDegrees = 45.0;
	assert cornerMisses("stretch_size2_rot45_total", q) == 0;
}

test "stretch: the width is size.x and the length is built from size.y" {
	let q = stretched(3.0, 4.0, 1.0, 0.5);
	q.height = 3.0;
	assert cornerMisses("stretch_size3d_1x3", q) == 0;
}

test "stretch: pivot.x moves the quad across the stretch by pivot.x * size.x, pivot.y along it by 2 * pivot.y * size.y" {
	let q = stretched(3.0, 4.0, 1.0, 0.0);
	q.pivotX = 0.5;
	q.pivotY = 0.25;
	assert cornerMisses("stretch_pivot", q) == 0;
	q.lengthScale = 2.0;
	q.pivotY = 0.0;
	assert cornerMisses("stretch_pivotx05_ls2", q) == 0;
	q.pivotX = 0.0;
	q.pivotY = 0.5;
	assert cornerMisses("stretch_pivoty05_ls2", q) == 0;
	q = stretched(3.0, 4.0, 1.0, 0.5);
	q.width = 2.0;
	q.height = 3.0;
	q.pivotX = 0.5;
	q.pivotY = 0.5;
	assert cornerMisses("stretch_size3d_2x3_vs05_pivot", q) == 0;
}

test "stretch: a particle that does not move draws nothing, as Unity's quad collapses to a point" {
	const s = fresh();
	let e = emitter(s, unityAsset(stretched(0.0, 0.0, 1.0, 0.5)), tile(fakeTexture(5), 16.0, 16.0));
	e.play(identity2d());
	const n = e.update(UNITY_DT, identity2d(), VIEW);
	assert n.ok && n.value == 1;
	assert e.node.count() == 0;
}

test "billboard: a rotated view billboard turns clockwise on screen about the particle" {
	let q = quad(3.0, 4.0);
	q.rotationDegrees = 45.0;
	assert cornerMisses("billboard_view_rot45", q) == 0;
}

test "billboard: a non-square size is width x height before rotation" {
	let q = quad(3.0, 4.0);
	q.height = 3.0;
	q.rotationDegrees = 45.0;
	assert cornerMisses("billboard_size3d_1x3_rot45", q) == 0;
}

test "billboard: pivot shifts the quad by pivot * size in its own axes, then the rotation turns the shift too" {
	let q = quad(3.0, 4.0);
	q.width = 2.0;
	q.height = 2.0;
	q.pivotX = 0.5;
	q.pivotY = 0.25;
	assert cornerMisses("billboard_pivot_rot0", q) == 0;
	q.rotationDegrees = 45.0;
	assert cornerMisses("billboard_pivot_rot45", q) == 0;
}

test "billboard with Velocity alignment turns the sprite's x axis along the velocity, whatever the particle's rotation" {
	const s = fresh();
	let q = quad(3.0, 4.0);
	q.alignment = RenderAlignment.Velocity;
	q.rotationDegrees = 45.0;
	let e = emitter(s, unityAsset(q), tile(fakeTexture(5), 16.0, 16.0));
	e.effect.clock.fixedStep = UNITY_DT / 4.0;
	e.play(identity2d());
	const n = e.update(UNITY_DT, identity2d(), VIEW);
	assert n.ok && n.value == 1;
	const c: TileCell = first(e);
	// Velocity (3, 4) in y-up is (3, -4) on screen: the x axis points right and up the screen.
	assert approx(c.rotation, -0.9272952);
	assert approx(c.scaleX * c.tile.w, 1.0) && approx(c.scaleY * c.tile.h, 1.0);
}

function refusal(mode: RenderMode, cameraVelocityScale: float32): Particles2DErrorKind {
	let a = single();
	a.renderer.renderMode = mode;
	a.renderer.cameraVelocityScale = cameraVelocityScale;
	const effect: ParticleEffect = { systems: [a] };
	const made = fresh().particles(effect, [tile(fakeTexture(5), 16.0, 16.0)], 3);
	if (made.ok) { return Particles2DErrorKind.Effect; }
	if (made.error.system != 0) { unreachable; }
	return made.error.kind;
}

test "a render mode with a third axis is refused by name" {
	assert refusal(RenderMode.HorizontalBillboard, 0.0) == Particles2DErrorKind.RenderModeNeedsThirdAxis;
	assert refusal(RenderMode.VerticalBillboard, 0.0) == Particles2DErrorKind.RenderModeNeedsThirdAxis;
	assert refusal(RenderMode.Mesh, 0.0) == Particles2DErrorKind.RenderModeNeedsThirdAxis;
}

test "cameraVelocityScale is refused on a stretched system and ignored where it does nothing" {
	assert refusal(RenderMode.Stretch, 0.5) == Particles2DErrorKind.CameraVelocity;
	assert refusal(RenderMode.Billboard, 0.5) == Particles2DErrorKind.Effect;
	assert refusal(RenderMode.None, 0.5) == Particles2DErrorKind.Effect;
}

// ---- freeform stretching, roll ----

function freeformQuad(rotateWith: boolean): UnityQuad {
	let q = stretched(0.3, 0.4, 1.0, 5.0);
	q.height = 2.0;
	q.rotationDegrees = 45.0;
	q.freeform = true;
	q.rotateWith = rotateWith;
	return q;
}

test "stretch: without freeformStretching, rotateWithStretchDirection changes nothing" {
	let q = freeformQuad(false);
	q.freeform = false;
	assert cornerMisses("stretch_freeform0_rotwith0", q) == 0;
	q.rotateWith = true;
	assert cornerMisses("stretch_freeform0_rotwith1", q) == 0;
}

test "freeform stretch: the particle's rotated quad is stretched along the velocity about its centre, to length / size.y times" {
	assert cornerMisses("stretch_freeform1_rotwith0", freeformQuad(false)) == 0;
}

test "freeform stretch: rotateWithStretchDirection turns the quad by the stretch direction's rotation before the stretch" {
	assert cornerMisses("stretch_freeform1_rotwith1", freeformQuad(true)) == 0;
}

test "freeform stretch: the stretch factor is built from size.y, so a wider-than-tall quad stretches more" {
	let q = stretched(0.3, 0.4, 2.0, 5.0);
	q.width = 2.0;
	q.freeform = true;
	q.rotateWith = false;
	assert cornerMisses("stretch_freeform1_rotwith0_size2x1_ls2_rot0", q) == 0;
	q.rotateWith = true;
	assert cornerMisses("stretch_freeform1_rotwith1_size2x1_ls2_rot0", q) == 0;
}

test "freeform stretch: pivot shifts the quad before it is rotated and stretched" {
	let q = freeformQuad(false);
	q.pivotX = 0.5;
	q.pivotY = 0.25;
	assert cornerMisses("stretch_freeform1_rotwith0_pivot", q) == 0;
	q.rotateWith = true;
	assert cornerMisses("stretch_freeform1_rotwith1_pivot", q) == 0;
}

// The clamp goldens carry their limits and camera in `settings`: the unit is the viewport width,
// 2 * orthographicSize * aspect.
function clampMisses(name: string): int32 {
	const g = golden(name);
	const st = g.getDynamicField("settings");
	const stretch: boolean = st.getDynamicField("renderMode").asString() == "Stretch";
	let q = stretch
		? stretched(3.0, 4.0, st.getDynamicField("lengthScale").asNumber() as float32, st.getDynamicField("velocityScale").asNumber() as float32)
		: quad(3.0, 4.0);
	const size = g.getDynamicField("frames").at(1).getDynamicField("particles").at(0).getDynamicField("startSize");
	q.width = size.at(0).asNumber() as float32;
	q.height = size.at(1).asNumber() as float32;
	q.minSize = st.getDynamicField("minParticleSize").asNumber() as float32;
	q.maxSize = st.getDynamicField("maxParticleSize").asNumber() as float32;
	q.viewport = 2.0 * (st.getDynamicField("orthographicSize").asNumber() as float32)
		* (st.getDynamicField("cameraAspect").asNumber() as float32);
	return cornerMisses(name, q);
}

test "billboard: a larger side above maxParticleSize * viewport width scales the quad uniformly down to it" {
	assert clampMisses("billboard_clamp_max_big") == 0;
	assert clampMisses("billboard_clamp_max_tall") == 0;
	assert clampMisses("billboard_clamp_max_wide") == 0;
	assert clampMisses("billboard_clamp_max_big_aspect05") == 0;
	assert clampMisses("billboard_clamp_max_big_aspect1") == 0;
	assert clampMisses("billboard_clamp_max_big_ortho5") == 0;
}

test "billboard: a larger side below minParticleSize * viewport width scales the quad uniformly up to it, one inside is untouched" {
	assert clampMisses("billboard_clamp_min_small") == 0;
	assert clampMisses("billboard_clamp_min_small_aspect05") == 0;
	assert clampMisses("billboard_clamp_min_thin") == 0;
	assert clampMisses("billboard_clamp_inside") == 0;
}

test "stretch: the size limits take the width only, the length keeps the unclamped size" {
	assert clampMisses("stretch_clamp_max") == 0;
	assert clampMisses("stretch_clamp_max_big") == 0;
	assert clampMisses("stretch_clamp_max_wide") == 0;
	assert clampMisses("stretch_clamp_min") == 0;
}

test "billboard: allowRoll has no effect under an orthographic camera that looks down -z" {
	let q = quad(3.0, 4.0);
	q.rotationDegrees = 45.0;
	q.allowRoll = false;
	assert cornerMisses("billboard_view_rot45_noroll", q) == 0;
	q.height = 3.0;
	assert cornerMisses("billboard_view_size1x3_rot45_noroll", q) == 0;
}

// ---- a moved and rotated emitter (tests/unity/goldens/billboard_moved_*) ----

const EMITTER_TURN: float32 = 0.5235987755982988;

// Unity's emitter: at (2, 1) turned 30 degrees counter-clockwise. In the y-down frame the turn is
// a negative rotation.
function movedEmitter(): Transform2D { return trs2d(2.0, -1.0, -EMITTER_TURN, 1.0, 1.0); }

// Replays a moved-emitter golden. A Local-space system draws into a node that carries the
// emitter's transform; a World-space one into an untransformed node. Corners are compared on
// screen. Unity bakes a Local-space quad around the particle's local position, so its offsets
// from that centre are placed around the particle's world position.
function movedMisses(name: string, alignment: RenderAlignment, worldSpace: boolean): int32 {
	const s = fresh();
	let q = quad(3.0, 4.0);
	q.height = 3.0;
	q.rotationDegrees = 20.0;
	q.alignment = alignment;
	let a = unityAsset(q);
	a.main.simulationSpace = worldSpace ? SimulationSpace.World : SimulationSpace.Local;
	let e = emitter(s, a, tile(fakeTexture(5), 16.0, 16.0));
	if (!worldSpace) { e.node.setPosition(2.0, -1.0).setRotation(-EMITTER_TURN); }
	e.effect.clock.fixedStep = UNITY_DT / 4.0;
	e.play(movedEmitter());
	const frames = golden(name).getDynamicField("frames");
	const co: float32 = cosf(EMITTER_TURN);
	const si: float32 = sinf(EMITTER_TURN);
	let misses: int32 = 0;
	for (let k = 1; k < (frames.length() as int32); k++) {
		const n = e.update(UNITY_DT, movedEmitter(), VIEW);
		if (!n.ok || n.value != 1 || e.node.count() != 1) { return 1000; }
		const c: TileCell = first(e);
		const m: Transform2D = trs2d(c.x, c.y, c.rotation, c.scaleX, c.scaleY);
		const t: Tile = c.tile;
		const own: float32[] = [t.dx, t.dy, t.dx + t.w, t.dy, t.dx + t.w, t.dy + t.h, t.dx, t.dy + t.h];
		const baked = frames.at(k);
		const pos = baked.getDynamicField("bakedQuads").at(0).getDynamicField("pos");
		const centre = baked.getDynamicField("particles").at(0).getDynamicField("pos");
		const px: float32 = centre.at(0).asNumber() as float32;
		const py: float32 = centre.at(1).asNumber() as float32;
		const wx: float32 = worldSpace ? 0.0 : px * co - py * si + 2.0 - px;
		const wy: float32 = worldSpace ? 0.0 : px * si + py * co + 1.0 - py;
		for (let v = 0; v < 4; v++) {
			const p = e.node.localToGlobal(vec2(own[v * 2], own[v * 2 + 1]) * m);
			const mine: float32[] = [p.x, -p.y];
			const shift: float32[] = [wx, wy];
			for (let axis = 0; axis < 2; axis++) {
				const unity: float32 = (pos.at(v).at(axis).asNumber() as float32) + shift[axis];
				const d: float32 = mine[axis] - unity;
				if (d > CORNER_TOL || d < -CORNER_TOL) { misses = misses + 1; }
			}
		}
	}
	return misses;
}

test "view alignment stays screen-aligned under a turned Local-space emitter node" {
	assert movedMisses("billboard_moved_view_local", RenderAlignment.View, false) == 0;
}

test "world alignment stays screen-aligned under a turned Local-space emitter node" {
	assert movedMisses("billboard_moved_world_local", RenderAlignment.World, false) == 0;
}

test "local alignment turns the quad with the emitter in a Local-space system" {
	assert movedMisses("billboard_moved_local_local", RenderAlignment.Local, false) == 0;
}

test "view and world alignment are unaffected by the emitter's turn in a World-space system" {
	assert movedMisses("billboard_moved_view_world", RenderAlignment.View, true) == 0;
	assert movedMisses("billboard_moved_world_world", RenderAlignment.World, true) == 0;
}

test "local alignment adds the emitter's turn in a World-space system, whose node is not turned" {
	assert movedMisses("billboard_moved_local_world", RenderAlignment.Local, true) == 0;
}
