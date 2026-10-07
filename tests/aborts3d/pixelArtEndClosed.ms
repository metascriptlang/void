// expect: void3d: endPrepared on a pixel-art preset that was closed
import { Vec4 } from "../../src/math/math3d";
import { DrawContext } from "../../src/void3d/draw";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt,
	endPrepared,
} from "../../src/void3d/pixelArtRenderer";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const look: PixelArtLook = {
	background: BLACK,
	outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
	fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
	saturation: 0.0,
};
let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
const made: Result<PixelArtRenderer, PixelArtError> =
	PixelArtRenderer.create(context, PixelArtSettings.full(), look);
if (!made.ok) { unreachable; }
let preset: PixelArtRenderer = made.value;
closePixelArt(preset);
endPrepared(preset);
console.log("endPrepared on a closed pixel-art preset returned");
