import { Scene2D, group, local, paint } from "../void2d/node";
import { create } from "../void2d/scene";
import { rgba } from "../void2d/types";
import { DrawContext, withUniformCapacity } from "../void3d/draw";
import { Scene3D, Transform3D, addGroup, create as createScene3D, identity, rootId } from "../void3d/scene";
import { MotionDocument, MotionTrack, ValueKind, linearKeyframe } from "pulse/src/document";
import { MotionPlayer, motionOptions } from "pulse/src/player";
import { VoidBindings } from "../motion/bindings";
import { VoidClock } from "../motion/clock";

function ramp(slot: string, property: string, to: float64): MotionTrack {
	return {
		slot,
		property,
		kind: ValueKind.Number,
		keyframes: [linearKeyframe(property + "0", 0, 0), linearKeyframe(property + "1", 400, to)],
	};
}

function slide(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 400,
				tracks: [ramp("box", "x", 200), ramp("box", "alpha", 1), ramp("cube", "y", 2), ramp("cube", "rotationY", 1)],
				placements: [],
				labels: [],
			},
		],
	};
}

const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const node = scene.group();
const world = Scene3D.create(DrawContext.withUniformCapacity(0));
const cube = addGroup(world, world.rootId(), Transform3D.identity());
const clock = new VoidClock();
const bindings = new VoidBindings();
bindings.node("box", node, ["x", "alpha"]);
bindings.object("cube", world, cube, ["y", "rotationY"]);
const player = new MotionPlayer(slide(), bindings.bindings, motionOptions(clock.clock));
let frames: int32 = 0;
while (clock.pending() > 0) {
	clock.tick(0.1);
	frames += 1;
	const t = world.nodes[cube.index].local;
	console.log(`frame ${frames}: x ${node.local().x} alpha ${node.paint().alpha} cube y ${t.position.y} rotation y ${t.rotation.y}`);
}
player.dispose();
