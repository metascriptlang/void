// expect neverApplied: gpu door: draw with a pipeline that declares a uniform block at slot
// expect afterPipelineChange: gpu door: draw with a pipeline that declares a uniform block at slot
import { argv } from "std/process";
import { gfxSetup } from "../../../src/sokol/gpu";
import { Vec4 } from "../../../src/math/math3d";
import { RenderState, Face } from "../../../src/gpu/state";
import { beginScreenPass, SWAPCHAIN_LAYOUT } from "../../../src/gpu/target";
import { uniformSlotMask, UNIFORM_SLOTS } from "../../../src/gpu/door";
import { PipelineCache, pipelineFor } from "../../../src/gpu/pipeline";
import {
	Program,
	ProgramKey,
	doorProgram,
	vertexLayoutOf,
	uniformBlockLength,
	applyPipeline,
	applyUniforms,
	draw,
} from "../../../src/void3d/gpu3d";
@include("../../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const LIT: ProgramKey = ProgramKey.of(Program.Lit);
let cache: PipelineCache = PipelineCache.empty();

function caseName(): string {
	return (argv.length as int32) > 1 ? argv[1] : "";
}

function pipeline(state: RenderState): uint32 {
	return pipelineFor(
		cache, doorProgram(LIT), vertexLayoutOf(LIT), true, state, SWAPCHAIN_LAYOUT,
	);
}

function applyEveryBlock(): void {
	const mask: uint32 = uniformSlotMask(doorProgram(LIT));
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		if ((mask & ((1 as uint32) << (slot as uint32))) == 0) { continue; }
		let zeros: Vec<float32> = new Array(uniformBlockLength(LIT, slot));
		for (let i = 0; i < (zeros.length as int32); i++) { zeros[i] = 0.0; }
		applyUniforms(slot, zeros);
	}
}

function init(): void { gfxSetup(); }

function frame(): void {
	const name: string = caseName();
	beginScreenPass(BLACK);
	applyPipeline(pipeline(RenderState.defaults()));
	if (name == "afterPipelineChange") {
		applyEveryBlock();
		applyPipeline(pipeline(RenderState.defaults().withCulling(Face.None)));
	} else if (name != "neverApplied") {
		console.log(`no case named '${name}'`);
		process.exit(0);
	}
	draw(0, 0, 1);
	console.log(`${name} returned`);
	process.exit(0);
}
voidRun(64, 64, init, frame);
