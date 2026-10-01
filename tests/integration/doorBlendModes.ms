import { gfxSetup } from "../../src/sokol/gpu";
import { exit } from "std/process";
import { RenderState, BlendMode } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT, TargetLayout } from "../../src/gpu/target";
import { PipelineCache } from "../../src/gpu/pipeline";
import { Program, VertexLayout, pipelineFor } from "../../src/void3d/gpu3d";
@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

function modes(): Vec<BlendMode> {
	return [
		BlendMode.None, BlendMode.Alpha, BlendMode.Add, BlendMode.AlphaAdd,
		BlendMode.SoftAdd, BlendMode.Multiply, BlendMode.AlphaMultiply, BlendMode.Erase,
		BlendMode.Screen, BlendMode.Subtract, BlendMode.Max, BlendMode.Min,
	];
}

function fail(message: string): void {
	console.log(`FAIL door blend modes: ${message}`);
	exit(1);
}

function init(): void {
	gfxSetup();
	let cache: PipelineCache = PipelineCache.empty();
	let made: Vec<uint32> = [];
	let alpha: uint32 = 0;
	for (const mode of modes()) {
		const state: RenderState = RenderState.defaults().withBlendMode(mode);
		const first: uint32 = pipelineFor(
			cache, Program.Copy, VertexLayout.Fullscreen, false, state, SWAPCHAIN_LAYOUT,
		);
		const again: uint32 = pipelineFor(
			cache, Program.Copy, VertexLayout.Fullscreen, false, state, SWAPCHAIN_LAYOUT,
		);
		if (first != again) { fail(`${mode.toString()} made a second pipeline for one key`); }
		for (const earlier of made) {
			if (earlier == first) { fail(`${mode.toString()} reused another mode's pipeline`); }
		}
		made.push(first);
		if (mode == BlendMode.Alpha) { alpha = first; }
	}
	console.log(`PASS door blend modes: ${made.length} shared modes make distinct pipelines`);
	const environment: TargetLayout = TargetLayout.environment();
	const spelled: uint32 = pipelineFor(
		cache,
		Program.Copy,
		VertexLayout.Fullscreen,
		false,
		RenderState.defaults().withBlendMode(BlendMode.Alpha),
		environment,
	);
	if (spelled != alpha || cache.entries.length != made.length) {
		fail(`the environment's own formats (${environment.toString()}) made a second screen pipeline`);
	}
	console.log(`PASS door screen layout: SWAPCHAIN_LAYOUT keys as ${environment.toString()}`);
	exit(0);
}

function frame(): void { fail("init did not stop"); }
voidRunConfigured(96, 96, 1, 0, init, frame);
