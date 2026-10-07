// Imports no node.ms: Yoga has no web branch yet
// (~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md).

import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import {
	setup2d, begin2d, fillQuad, finishRecording, flushTargets, end2d,
} from "../../src/void2d/draw";
import { rgba, vec2 } from "../../src/void2d/types";
import { BlendMode } from "../../src/gpu/state";
when (voidProfiler) {
	import { OverlayMode } from "../../src/void2d/profiler";
	import {
		profilerOverlayFeedLive,
		profilerOverlaySetMode,
		profilerPrepare,
		profilerDraw,
	} from "../../src/void2d/profilerOverlay";
}

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void {
	gfxSetup();
	setup2d();
	when (voidProfiler) {
		profilerOverlayFeedLive();
		profilerOverlaySetMode(OverlayMode.Full);
	}
}

function frame(): void {
	const dpi: float32 = dpiScale();
	const w: float32 = (fbWidth() as float32) / dpi;
	const h: float32 = (fbHeight() as float32) / dpi;
	begin2d(w, h, dpi);
	fillQuad(vec2(8.0, 8.0), vec2(120.0, 8.0), vec2(120.0, 80.0), vec2(8.0, 80.0),
		rgba(0.2, 0.4, 0.9, 1.0), BlendMode.Alpha);
	finishRecording();
	flushTargets();
	when (voidProfiler) { profilerPrepare(w, h, dpi); }
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	end2d();
	when (voidProfiler) { profilerDraw(); }
	endPass();
	commit();
}

voidRun(800, 600, init, frame);
