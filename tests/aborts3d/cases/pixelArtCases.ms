// expect closed.setSettings: void3d: setSettings on a pixel-art preset that was closed
// expect closed.setLook: void3d: setLook on a pixel-art preset that was closed
// expect closed.setPalette: void3d: setPalette on a pixel-art preset that was closed
// expect closed.viewFor: void3d: viewFor on a pixel-art preset that was closed
// expect closed.drawToScreen: void3d: drawToScreen on a pixel-art preset that was closed
// expect closed.closePixelArt: void3d: closePixelArt on a pixel-art preset that was closed
import { argv } from "std/process";
import { Vec4 } from "../../../src/math/math3d";
import { DrawContext } from "../../../src/void3d/draw";
import { LowResView, ViewError } from "../../../src/void3d/blit";
import { PaletteError } from "../../../src/void3d/palette";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	setSettings,
	setLook,
	setPalette,
	drawToScreen,
	closePixelArt,
} from "../../../src/void3d/pixelArtRenderer";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function look(): PixelArtLook {
	return {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
}

function closedPixelArt(): PixelArtRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, PixelArtSettings.full(), look());
	if (!made.ok) { unreachable; }
	let pixelArt: PixelArtRenderer = made.value;
	closePixelArt(pixelArt);
	return pixelArt;
}

function run(name: string): void {
	let colors: Vec<uint32> = [0xFF000000, 0xFFFFFFFF];
	if (name == "closed.setSettings") {
		setSettings(closedPixelArt(), PixelArtSettings.full());
	} else if (name == "closed.setLook") {
		setLook(closedPixelArt(), look());
	} else if (name == "closed.setPalette") {
		const _r: Result<int32, PaletteError> = setPalette(closedPixelArt(), colors);
	} else if (name == "closed.viewFor") {
		const _r: Result<LowResView, ViewError> = closedPixelArt().viewFor(320, 240, 0.0, 0.0);
	} else if (name == "closed.drawToScreen") {
		drawToScreen(closedPixelArt());
	} else if (name == "closed.closePixelArt") {
		closePixelArt(closedPixelArt());
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
