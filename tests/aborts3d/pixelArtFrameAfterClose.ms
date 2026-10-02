// expect: void3d: prepareFrame on a pixel-art preset that was closed
import { Vec4 } from "../../src/math/math3d";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../src/void3d/gpu3d";
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { LowResView } from "../../src/void3d/blit";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	prepareFrame,
	closePixelArt,
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
let pixelArt: PixelArtRenderer = made.value;
closePixelArt(pixelArt);
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let none: Vec<DrawItem> = [];
const view: LowResView = { width: 32, height: 24, scale: 1, offsetX: 0.0, offsetY: 0.0 };
const _drawn: Result<int32, PixelArtError> = prepareFrame(pixelArt, none, camera, lights, view);
console.log("a closed pixel-art preset prepared a frame");
