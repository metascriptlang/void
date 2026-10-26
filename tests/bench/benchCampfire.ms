// T4 entry: the void3d campfire of scripts/gate3d.sh's bench, with the log group turning and the
// particles on. Every draw item applies its pipeline and its uniform blocks again, so this is the
// row that prices the door's per-draw uniform path; present.ms is the CPU time of one frame's
// recording and submission, frame.ms the wall time between frames.

import {
	initCampfire,
	frameCampfire,
	configureCampfire,
	configureCampfireCamera,
	configureCampfireLogSpin,
	configureCampfireParticles,
	campfireStats,
} from "../../src/examples/campfireScene";
import { PixelArtSettings } from "../../src/void3d/pixelArtRenderer";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

const WARMUP: int32 = 60;
const MEASURED: int32 = 240;
let frames: int32 = 0;
let started: float64 = 0.0;
let cpu: float64 = 0.0;

function frame(): void {
	const enter: float64 = performance.now();
	frameCampfire();
	const left: float64 = performance.now();
	if (frames >= WARMUP) { cpu = cpu + (left - enter); }
	frames = frames + 1;
	if (frames == WARMUP) { started = performance.now(); }
	if (frames == WARMUP + MEASURED) {
		const stats = campfireStats();
		console.log(`campfire.drawItems ${stats.drawItems}`);
		console.log(`campfire.meshes ${stats.meshes}`);
		console.log(`campfire.pipelines ${stats.pipelines}`);
		console.log(`campfire.uniforms ${stats.uniforms}`);
		console.log(`campfire.present.ms ${cpu / (MEASURED as float64)}`);
		console.log(`campfire.frame.ms ${(performance.now() - started) / (MEASURED as float64)}`);
		process.exit(0);
	}
}

configureCampfire(PixelArtSettings.full(), false);
configureCampfireCamera(false, 0.0);
configureCampfireLogSpin(0.11);
configureCampfireParticles(true);
voidRunConfigured(1280, 720, 1, 0, initCampfire, frame);
