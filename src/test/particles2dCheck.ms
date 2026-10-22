import { ParticleSystemAsset, ParticleEffect, RenderMode, SimulationSpace } from "../particles/asset";
import { constantCurve, constantColor, rgbaColor, curveOf, linearCurve, key } from "../particles/curve";
import { NodeRef, Scene2D, TileCell } from "../void2d/node";
import "../void2d/scene";
import { Tile, Transform2D, rgba, tile, identity2d } from "../void2d/types";
import { ParticleEmitter2D, particles, play, update } from "../void2d/particles2d";
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
	const n = e.update(1.0 / 60.0, at(100.0, 50.0));
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
	for (let k = 0; k < 30; k++) { const _n = e.update(1.0 / 60.0, identity2d()); }
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
	for (let k = 0; k < 66; k++) { const _n = e.update(1.0 / 60.0, identity2d()); }
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
	const n = e.update(1.0 / 60.0, identity2d());
	assert n.ok && n.value == 1;
	assert e.node.count() == 0;
}

test "a particle whose life ends leaves the node" {
	const s = fresh();
	let e = emitter(s, single(), tile(fakeTexture(5), 16.0, 16.0));
	e.play(identity2d());
	for (let k = 0; k < 121; k++) { const _n = e.update(1.0 / 60.0, identity2d()); }
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
	for (let k = 0; k < 20; k++) { const n = e.update(1.0 / 60.0, at(100.0, 50.0)); }
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
