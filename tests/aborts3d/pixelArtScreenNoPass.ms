// expect: void3d: drawToScreen outside a screen pass; open one with beginScreenPass
import { DrawContext } from "../../src/void3d/draw";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	drawToScreen,
} from "../../src/void3d/pixelArtRenderer";

const LOOK: PixelArtLook = {
	background: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
	fog: { start: 0.5, end: 0.8, strength: 0.85, color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 } },
	saturation: 0.0,
};

let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
const created: Result<PixelArtRenderer, PixelArtError> =
	PixelArtRenderer.create(context, PixelArtSettings.full(), LOOK);
if (created.ok) {
	let renderer: PixelArtRenderer = created.value;
	renderer.core.prepared = true;
	drawToScreen(renderer, context);
}
console.log("drawToScreen outside a screen pass returned");
