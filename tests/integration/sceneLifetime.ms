import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { endPass, commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d, buffersAlive } from "../../src/void2d/draw";
import { renderTargetsAlive } from "../../src/void2d/render";
import { rgba, blurFilter } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureSlotsDiffer, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 128;
const HEIGHT: int32 = 96;
const CLOSURES: int32 = 16;
const CLOSED_IN_ONE_FRAME: int32 = 9;
const CLEAR = rgba(0.0, 0.0, 0.0, 1.0);
const kept: Scene2D = Scene2D.create(CLEAR);
const keptNode: NodeRef = kept.add(kept.rect(40.0, 40.0, rgba(0.0, 0.0, 1.0, 1.0)).at(20.0, 20.0))
	.setFilter(blurFilter(3.0));
let stage: int32 = 0;
let initialBuffers: int32 = 0;
let keptBuffers: int32 = 0;
let keptTargets: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL scene lifetime: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function exerciseMisuse(misuse: string): void {
	const s: Scene2D = Scene2D.create(CLEAR);
	const node: NodeRef = s.add(s.rect(4.0, 4.0, rgba(1.0, 1.0, 1.0, 1.0)));
	s.close();
	if (misuse.equals("present")) { s.present(); }
	if (misuse.equals("node")) { node.setAlpha(0.5); }
	if (misuse.equals("construct")) { s.group(); }
	if (misuse.equals("close")) { s.close(); }
	console.log(`a closed scene accepted ${misuse}`);
	voidCaptureExit(0);
}

function init(): void {
	gfxSetup();
	setup2d();
	initialBuffers = buffersAlive();
	const misuse: string = env.get("VOID_SCENE_LIFETIME_MISUSE");
	if (!misuse.equals("")) { exerciseMisuse(misuse); }
}

function closeOneScene(): void {
	const temporary: Scene2D = Scene2D.create(CLEAR);
	const node: NodeRef = temporary.add(
		temporary.rect(40.0, 40.0, rgba(1.0, 0.0, 0.0, 1.0)).at(20.0, 20.0),
	).setFilter(blurFilter(3.0));
	temporary.present();
	if (renderTargetsAlive() <= keptTargets) {
		fail("the temporary scene drew without a filter target");
	}
	temporary.close();
	if (!temporary.isClosed()) { fail("close did not mark the scene closed"); }
	if (node.isLive()) { fail("a closed scene left its node live"); }
	if (buffersAlive() != keptBuffers || renderTargetsAlive() != keptTargets) {
		fail(
			`a closed scene kept resources: buffers ${buffersAlive()} of ${keptBuffers}, ` +
			`targets ${renderTargetsAlive()} of ${keptTargets}`,
		);
	}
}

function closeInsideOpenFrame(): void {
	const scenes: Vec<Scene2D> = new Array(0);
	for (let k: int32 = 0; k < CLOSED_IN_ONE_FRAME; k++) {
		const s: Scene2D = Scene2D.create(CLEAR);
		s.add(s.rect(8.0, 8.0, rgba(1.0, 0.0, 0.0, 1.0)).at((k * 10) as float32, 4.0));
		s.prepare(WIDTH as float32, HEIGHT as float32, 1.0);
		scenes.push(s);
	}
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	for (const s of scenes) { s.drawScreen(); }
	endPass();
	for (const s of scenes) { s.close(); }
	commit();
}

function frame(): void {
	if (stage == 0) {
		kept.present();
		keptBuffers = buffersAlive();
		keptTargets = renderTargetsAlive();
		if (keptTargets == 0) { fail("the kept scene's blur took no filter target"); }
		if (voidCaptureGrab(0) == 0) { fail("kept-scene readback failed"); }
	} else if (stage % 2 == 1) {
		closeOneScene();
	} else {
		kept.present();
		if (voidCaptureGrab(1) == 0) { fail("kept-scene readback failed"); }
		if (voidCaptureSlotsDiffer() != 0) { fail("closing another scene changed the kept scene"); }
	}
	stage = stage + 1;
	if (stage <= CLOSURES * 2) { return; }
	if (stage == CLOSURES * 2 + 1) {
		closeInsideOpenFrame();
		return;
	}
	if (stage == CLOSURES * 2 + 2) {
		kept.present();
		if (buffersAlive() != keptBuffers) {
			fail(
				`${CLOSED_IN_ONE_FRAME} scenes closed inside one frame left buffers: ` +
				`${buffersAlive()} of ${keptBuffers} after the next frame`,
			);
		}
		return;
	}
	kept.close();
	if (keptNode.isLive()) { fail("the kept scene's node outlived its close"); }
	if (buffersAlive() != initialBuffers || renderTargetsAlive() != 0) {
		fail(
			`closing the last scene kept resources: buffers ${buffersAlive()} of ` +
			`${initialBuffers}, targets ${renderTargetsAlive()}`,
		);
	}
	console.log(
		`PASS scene lifetime: ${CLOSURES} closed scenes released buffers and filter targets; ` +
		`${CLOSED_IN_ONE_FRAME} closed inside one open frame released at the next; ` +
		"the kept scene's pixels held; the last close returned to the start",
	);
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
