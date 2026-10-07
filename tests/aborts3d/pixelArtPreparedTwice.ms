// expect: void3d: prepareFrame on a frame no drawToScreen or endPrepared ended
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { LowResView } from "../../src/void3d/blit";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/pixelArtRenderer";

const LOOK: PixelArtLook = {
	background: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
	fog: { start: 0.5, end: 0.8, strength: 0.85, color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 } },
	saturation: 0.0,
};
const VIEW: LowResView = { width: 64, height: 64, scale: 1, offsetX: 0.0, offsetY: 0.0 };

let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
let items: Vec<DrawItem> = [];
let blocks: Vec<float32> = [];
const created: Result<PixelArtRenderer, PixelArtError> =
	PixelArtRenderer.create(context, PixelArtSettings.full(), LOOK);
if (created.ok) {
	let renderer: PixelArtRenderer = created.value;
	renderer.core.prepared = true;
	const _again: Result<int32, PixelArtError> =
		prepareFrame(renderer, items, blocks, blocks, VIEW);
}
console.log("a second prepareFrame returned");
