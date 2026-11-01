import { NodeRef, Scene2D, group, local, paint, remove, setScaleX } from "../void2d/node";
import { close, create } from "../void2d/scene";
import { rgba } from "../void2d/types";
import { DrawContext, withUniformCapacity } from "../void3d/draw";
import {
	NodeId3D,
	Scene3D,
	Transform3D,
	addGroup,
	create as createScene3D,
	identity,
	remove as removeObject,
	rootId,
	setLocal,
} from "../void3d/scene";
import { eulerQuat } from "../math/math3d";
import {
	MotionDocument,
	MotionKeyframe,
	MotionTrack,
	ValueKind,
	colorValue,
	linearKeyframe,
	numberValue,
} from "pulse/src/document";
import { interpolate } from "pulse/src/evaluate";
import { MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { springByStiffness } from "pulse/src/spring";
import { MotionTarget } from "pulse/src/target";
import { AnimatedValue, spring } from "pulse/src/value";
import { VoidBindings } from "../motion/bindings";
import { VoidClock } from "../motion/clock";

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) <= 1e-5;
}

function ramp(slot: string, property: string, from: float64, to: float64): MotionTrack {
	return {
		slot,
		property,
		kind: ValueKind.Number,
		keyframes: [linearKeyframe(property + "0", 0, from), linearKeyframe(property + "1", 250, to)],
	};
}

function documentOf(tracks: MotionTrack[]): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{ id: "main", duration: 250, tracks, placements: [], labels: [] }],
	};
}

function moveAndFade(): MotionDocument {
	const red: MotionKeyframe = { ...linearKeyframe("c0", 0, 0), value: colorValue(1, 0, 0, 1) };
	const blue: MotionKeyframe = { ...linearKeyframe("c1", 250, 0), value: colorValue(0, 0, 1, 0.5) };
	return documentOf([
		ramp("box", "x", 0, 80),
		ramp("box", "alpha", 0, 1),
		{ slot: "box", property: "color", kind: ValueKind.Color, keyframes: [red, blue] },
	]);
}

function refusal(action: () => void): string {
	try { action(); } catch (e) { return e.message; }
	return "";
}

function box(scene: Scene2D): NodeRef {
	return scene.group();
}

test "a document moves a node, fades it and shifts its colour across Void frames" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.node("box", node, ["x", "alpha", "color"]);
	const player = new MotionPlayer(moveAndFade(), bindings.bindings, motionOptions(clock.clock));
	assert clock.pending() === 1, "a playing player asks Void's loop for a frame";
	clock.tick(0.125);
	assert near(node.local().x, 40), node.local().x.toString();
	assert near(node.paint().alpha, 0.5), node.paint().alpha.toString();
	const middle = node.paint().color;
	const oklab = interpolate(colorValue(1, 0, 0, 1), colorValue(0, 0, 1, 0.5), 0.5).color;
	assert near(middle.r, oklab.r) && near(middle.g, oklab.g) && near(middle.b, oklab.b) && near(middle.a, 0.75);
	clock.tick(0.125);
	assert near(node.local().x, 80) && near(node.paint().alpha, 1);
	const end = node.paint().color;
	assert end.r === 0.0 && end.b === 1.0 && end.a === 0.5;
	assert player.progress === 1 && clock.pending() === 0, "a finished player leaves Void's loop idle";
	scene.close();
}

test "revert writes back what the node held before the first frame" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	node.setScaleX(3.0);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.node("box", node, ["x", "scaleX"]);
	const doc = documentOf([ramp("box", "x", 10, 90), ramp("box", "scaleX", 1, 2)]);
	const player = new MotionPlayer(doc, bindings.bindings, motionOptions(clock.clock));
	clock.tick(0.125);
	assert near(node.local().x, 50) && near(node.local().scaleX, 1.5);
	player.revert();
	assert node.local().x === 0.0 && node.local().scaleX === 3.0;
	assert clock.pending() === 0;
	scene.close();
}

test "a disposed player writes nothing on later frames" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.node("box", node, ["x"]);
	const player = new MotionPlayer(documentOf([ramp("box", "x", 0, 100)]), bindings.bindings, motionOptions(clock.clock));
	clock.tick(0.0625);
	assert near(node.local().x, 25);
	player.dispose();
	assert clock.pending() === 0;
	clock.tick(0.125);
	assert near(node.local().x, 25);
	scene.close();
}

test "an animated value springs a node's x on Void frames" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const clock = new VoidClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.subscribe((next: float64): void => { node.setX(next as float32); });
	value.animate(spring(100, springByStiffness(170, 26, 1)));
	clock.tick(0.05);
	const early = node.local().x;
	assert early > 0 && early < 100, early.toString();
	assert near(early, value.get());
	for (let i = 0; i < 240 && clock.pending() > 0; i += 1) { clock.tick(1.0 / 60.0); }
	assert clock.pending() === 0 && node.local().x === 100.0;
	value.dispose();
	scene.close();
}

test "a wrong kind, an unknown property and a split scale are refused by slot and property" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const bindings = new VoidBindings();
	assert refusal((): void => { bindings.node("box", node, ["width"]); }) ===
		"motion: box.width is not a Void 2D node property";
	assert refusal((): void => { bindings.node("box", node, ["scale", "scaleY"]); }) ===
		"motion: box.scale and box.scaleY both write one scale";
	bindings.node("box", node, ["x", "color", "scale"]);
	assert refusal((): void => { bindings.bindings[0].write(colorValue(1, 1, 1, 1)); }) ===
		"motion: box.x is bound as a number";
	assert refusal((): void => { bindings.bindings[1].write(bindings.bindings[0].read!()); }) ===
		"motion: box.color is bound as a colour";
	node.setScaleX(2.0);
	assert refusal((): void => { bindings.bindings[2].read!(); }) ===
		"motion: box.scale reads a non-uniform scale; bind its axes instead";
	scene.close();
}

function objectAt(scene: Scene3D): NodeId3D {
	const start: Transform3D = { ...Transform3D.identity(), rotation: eulerQuat(0.0, 0.0, 0.25) };
	return addGroup(scene, scene.rootId(), start);
}

test "a document drives a 3D object's position, rotation and scale, and revert restores them" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const id = objectAt(scene);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.object("cube", scene, id, ["x", "z", "rotationY", "scale"]);
	assert refusal((): void => { bindings.object("cube", scene, id, ["roll"]); }) ===
		"motion: cube.roll is not a Void 3D object property";
	const doc = documentOf([
		ramp("cube", "x", 0, 4),
		ramp("cube", "z", 0, -2),
		ramp("cube", "rotationY", 0, 1),
		ramp("cube", "scale", 1, 3),
	]);
	const player = new MotionPlayer(doc, bindings.bindings, motionOptions(clock.clock));
	clock.tick(0.125);
	const t = scene.nodes[id.index].local;
	assert near(t.position.x, 2) && near(t.position.z, -1) && t.position.y === 0.0;
	assert near(t.scale.x, 2) && near(t.scale.y, 2) && near(t.scale.z, 2);
	const q = eulerQuat(0.0, 0.5, 0.25);
	assert near(t.rotation.x, q.x) && near(t.rotation.y, q.y) && near(t.rotation.z, q.z) && near(t.rotation.w, q.w);
	player.revert();
	const back = scene.nodes[id.index].local;
	const start = eulerQuat(0.0, 0.0, 0.25);
	assert back.position.x === 0.0 && back.position.z === 0.0 && back.scale.x === 1.0;
	assert near(back.rotation.y, start.y) && near(back.rotation.z, start.z) && near(back.rotation.w, start.w);
}

test "a second player on one node property replaces the first, and bindings share its target" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const clock = new VoidClock();
	const first = new VoidBindings();
	first.node("box", node, ["x"]);
	const second = new VoidBindings();
	second.node("card", node, ["x"]);
	assert first.bindings[0].target === second.bindings[0].target, "one node property has one target";
	const older = new MotionPlayer(documentOf([ramp("box", "x", 0, 100)]), first.bindings, motionOptions(clock.clock));
	clock.tick(0.05);
	assert near(node.local().x, 20);
	const newer = new MotionPlayer(documentOf([ramp("card", "x", 50, 0)]), second.bindings, motionOptions(clock.clock));
	clock.tick(0.125);
	assert near(node.local().x, 25), node.local().x.toString();
	assert older.cancelled, "the older player holds nothing and is cancelled";
	assert (first.bindings[0].target as MotionTarget).writers === 1;
	clock.tick(0.125);
	assert near(node.local().x, 0);
	newer.dispose();
	older.dispose();
}

test "rotation axes animated together past a quarter turn compose without flipping" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const id = objectAt(scene);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.object("cube", scene, id, ["rotationX", "rotationY"]);
	const player = new MotionPlayer(
		documentOf([ramp("cube", "rotationX", 0, 0.5), ramp("cube", "rotationY", 0, 2.5)]),
		bindings.bindings,
		motionOptions(clock.clock),
	);
	for (let frame = 1; frame <= 10; frame += 1) {
		clock.tick(0.025);
		const t = (frame as float32) / 10.0;
		const want = eulerQuat(0.5 * t, 2.5 * t, 0.25);
		const q = scene.nodes[id.index].local.rotation;
		assert near(q.x, want.x) && near(q.y, want.y) && near(q.z, want.z) && near(q.w, want.w),
			"frame " + frame.toString();
	}
	player.dispose();
}

test "a rotation set outside the bindings is read back before the next axis write" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const id = objectAt(scene);
	const bindings = new VoidBindings();
	bindings.object("cube", scene, id, ["rotationY", "rotationZ"]);
	bindings.bindings[0].write(numberValue(0.5));
	setLocal(scene, id, { ...scene.nodes[id.index].local, rotation: eulerQuat(0.0, 0.5, 1.0) });
	assert near(bindings.bindings[1].read!().number, 1.0);
	bindings.bindings[0].write(numberValue(0.75));
	const want = eulerQuat(0.0, 0.75, 1.0);
	const q = scene.nodes[id.index].local.rotation;
	assert near(q.x, want.x) && near(q.y, want.y) && near(q.z, want.z) && near(q.w, want.w);
}

test "a node or object removed while its player runs is skipped, and the player still finishes" {
	const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = box(scene);
	const kept = box(scene);
	const world = Scene3D.create(DrawContext.withUniformCapacity(0));
	const id = objectAt(world);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.node("box", node, ["x"]);
	bindings.node("kept", kept, ["x"]);
	bindings.object("cube", world, id, ["x", "rotationY"]);
	const player = new MotionPlayer(
		documentOf([ramp("box", "x", 0, 100), ramp("kept", "x", 0, 100), ramp("cube", "x", 0, 4), ramp("cube", "rotationY", 0, 1)]),
		bindings.bindings,
		motionOptions(clock.clock),
	);
	clock.tick(0.125);
	node.remove();
	removeObject(world, id);
	clock.tick(0.125);
	assert near(kept.local().x, 100) && player.progress === 1 && clock.pending() === 0;
	player.dispose();
	scene.close();
}

test "revert of a rotation writes back the exact quaternion the object held" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const start: Transform3D = { ...Transform3D.identity(), rotation: eulerQuat(0.3, 2.0, -0.7) };
	const id = addGroup(scene, scene.rootId(), start);
	const clock = new VoidClock();
	const bindings = new VoidBindings();
	bindings.object("cube", scene, id, ["rotationX", "rotationZ"]);
	const player = new MotionPlayer(
		documentOf([ramp("cube", "rotationX", 0, 1), ramp("cube", "rotationZ", 0, 1)]),
		bindings.bindings,
		motionOptions(clock.clock),
	);
	clock.tick(0.125);
	player.revert();
	const q = scene.nodes[id.index].local.rotation;
	assert q.x === start.rotation.x && q.y === start.rotation.y && q.z === start.rotation.z && q.w === start.rotation.w;
}
