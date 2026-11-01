import { gfxSetup, makeImage, makeView } from "../../src/host/gpu";
import { BlendMode } from "../../src/gpu/state";
import { setup2d, preparePipelines, drawCallCount } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { add, present } from "../../src/void2d/scene";
import { rgba, tile } from "../../src/void2d/types";
import { Texture } from "../../src/gpu/texture";
import { loadImageFile } from "../../src/assets/imageFile";
import { doorFrameStat, DOOR_STAT_UNIFORM_APPLIES } from "../../src/gpu/doorGpu.ms";
import { voidCaptureExit } from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// One pipeline, runs split by the texture view: the params block is equal for every run, so a
// run applies it only when the previous run's block is not the one bound. A scroll scope per run
// shifts the block, so those runs apply it each time.
const RUNS: int32 = 6;
let sameScene: Scene2D | null = null;
let clippedScene: Scene2D | null = null;
let frame: int32 = 0;
let sameDraws: int32 = 0;
let sameApplies: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL run uniform guard: ${message}`);
	voidCaptureExit(1);
}

function twoViews(): Texture[] {
	const sheet = loadImageFile("assets/test.png");
	const image: uint32 = makeImage(sheet.pixels as Span<uint32>, sheet.width, sheet.height);
	const first: Texture = Texture.adopt(image, makeView(image), sheet.width, sheet.height);
	const second: Texture = Texture.adopt(image, makeView(image), sheet.width, sheet.height);
	return [first, second];
}

function init(): void {
	gfxSetup();
	setup2d();
	const prepared: Vec<BlendMode> = [BlendMode.Alpha];
	preparePipelines(prepared);
	const views = twoViews();
	const plain = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const clipped = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	for (let i: int32 = 0; i < RUNS; i++) {
		const x: float32 = (i as float32) * 40.0;
		plain.add(plain.sprite(tile(views[i % 2], 32.0, 32.0)).at(x, 8.0));
		const area = clipped.mask(24.0, 24.0).at(x, 8.0);
		area.addChild(clipped.sprite(tile(views[i % 2], 32.0, 32.0)));
		area.scrollTo(0.0, (i as float32) * 3.0);
		clipped.add(area);
	}
	sameScene = plain;
	clippedScene = clipped;
}

function frameFn(): void {
	frame++;
	if (frame == 1) { (sameScene as Scene2D).present(); return; }
	if (frame == 2) {
		sameApplies = doorFrameStat(DOOR_STAT_UNIFORM_APPLIES) as int32;
		sameDraws = drawCallCount();
		(clippedScene as Scene2D).present();
		return;
	}
	const clippedApplies: int32 = doorFrameStat(DOOR_STAT_UNIFORM_APPLIES) as int32;
	console.log(`runs ${RUNS} sameDraws ${sameDraws} sameApplies ${sameApplies} clippedApplies ${clippedApplies}`);
	if (sameDraws != RUNS) { fail(`expected ${RUNS} runs, drew ${sameDraws}`); return; }
	if (sameApplies != 1) { fail(`equal blocks applied ${sameApplies} times, not once`); return; }
	if (clippedApplies < RUNS) { fail(`${RUNS} clipped runs applied ${clippedApplies} blocks`); return; }
	console.log("PASS run uniform guard");
	voidCaptureExit(0);
}

voidRunConfigured(320, 240, 1, 0, init, frameFn);
