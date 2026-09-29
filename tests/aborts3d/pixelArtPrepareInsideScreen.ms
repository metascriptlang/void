// expect: void3d: prepareFrame with a pass already open; it would nest inside it
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { beginScreenPass } from "../../src/gpu/target";
import { LowResView } from "../../src/void3d/blit";
import { Vec4 } from "../../src/math/math3d";
import { gfxSetup } from "../../src/sokol/gpu";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/pixelArtRenderer";
@include("../../src/sokol/bridge.h");

extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const LOOK: PixelArtLook = {
	background: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
	fog: { start: 0.5, end: 0.8, strength: 0.85, color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 } },
	saturation: 0.0,
};
const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const VIEW: LowResView = { width: 64, height: 64, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
let items: Vec<DrawItem> = [];
let blocks: Vec<float32> = [];
const created: Result<PixelArtRenderer, PixelArtError> =
	PixelArtRenderer.create(context, PixelArtSettings.full(), LOOK);

function init(): void {
	gfxSetup();
}

function frame(): void {
	beginScreenPass(CLEAR);
	if (created.ok) {
		let renderer: PixelArtRenderer = created.value;
		const _prepared: Result<int32, PixelArtError> =
			prepareFrame(renderer, context, items, blocks, blocks, VIEW);
	}
}

voidRun(1280, 720, init, frame);
