import { decodeAnimation, DecodedAnimation } from "../assets/image";
import { Scene2D, DrawKind } from "../void2d/node";
import "../void2d/scene";
import { rgba, Tile } from "../void2d/types";
import {
	AnimationError, SheetLayout, AnimationSheet, MAX_SHEET_SIDE,
	sheetLayout, packSheet, sheetOf, frameTiles, animation,
} from "../void2d/animation";
import { fakeTexture, approx } from "./helpers";
import { GifFrame, animatedGif, solidFrame, bytesOf } from "./imageBytes";

const SHEET_VIEW: uint32 = 7;

function fourFrames(): Vec<GifFrame> {
	const patch: GifFrame = {
		x: 1, y: 1, w: 2, h: 1, indices: bytesOf([2, 2]), delayCentiseconds: 5, disposal: 2,
	};
	const corner: GifFrame = {
		x: 0, y: 0, w: 1, h: 1, indices: bytesOf([3]), delayCentiseconds: 1, disposal: 1,
	};
	return [solidFrame(4, 3, 0, 10), solidFrame(4, 3, 1, 20), patch, corner];
}

function decodedFour(): DecodedAnimation {
	const decoded = decodeAnimation(animatedGif(0x39, 4, 3, fourFrames()));
	if (!decoded.ok) {
		console.log("animationSheetCheck: the four-frame GIF did not decode");
		unreachable;
	}
	return decoded.value;
}

function layoutOf(frameW: int32, frameH: int32, count: int32): SheetLayout {
	const layout = sheetLayout(frameW, frameH, count);
	if (!layout.ok) {
		console.log(`animationSheetCheck: no layout for ${count} frames of ${frameW}x${frameH}`);
		unreachable;
	}
	return layout.value;
}

function sheetFour(): AnimationSheet {
	const a: DecodedAnimation = decodedFour();
	return sheetOf(a, fakeTexture(SHEET_VIEW), layoutOf(4, 3, 4));
}

test "frames are laid out in a near-square grid" {
	assert layoutOf(4, 3, 1).columns == 1 && layoutOf(4, 3, 1).rows == 1;
	assert layoutOf(4, 3, 3).columns == 2 && layoutOf(4, 3, 3).rows == 2;
	const twelve: SheetLayout = layoutOf(4, 3, 12);
	assert twelve.columns == 4 && twelve.rows == 3;
	assert twelve.width == 16 && twelve.height == 9;
}

test "a sheet stays within the side no backend can exceed, and says which limit it hit" {
	const edge: SheetLayout = layoutOf(8192, 1, 2);
	assert edge.width == MAX_SHEET_SIDE && edge.columns == 2;
	const stacked: SheetLayout = layoutOf(9000, 10, 3);
	assert stacked.columns == 1 && stacked.rows == 3 && stacked.width == 9000;
	const tall = sheetLayout(16384, 16384, 2);
	assert !tall.ok;
	if (!tall.ok) { assert tall.error == AnimationError.SheetTooLarge; }
	const none = sheetLayout(4, 3, 0);
	assert !none.ok;
	if (!none.ok) { assert none.error == AnimationError.NoFrames; }
}

test "packSheet copies each decoded frame into its cell and leaves the spare cell clear" {
	const a: DecodedAnimation = decodedFour();
	const layout: SheetLayout = layoutOf(4, 3, 3);
	let three: DecodedAnimation = { ...a, frameCount: 3 };
	const sheet: Vec<uint32> = packSheet(three, layout);
	assert (sheet.length as int32) == layout.width * layout.height;
	for (let f: int32 = 0; f < 3; f++) {
		const left: int32 = (f % layout.columns) * 4;
		const top: int32 = (f / layout.columns) * 3;
		for (let y: int32 = 0; y < 3; y++) {
			for (let x: int32 = 0; x < 4; x++) {
				assert sheet[(top + y) * layout.width + left + x] == a.pixels[f * 12 + y * 4 + x];
			}
		}
	}
	for (let y: int32 = 3; y < 6; y++) {
		for (let x: int32 = 4; x < 8; x++) { assert sheet[y * layout.width + x] == (0 as uint32); }
	}
}

test "each frame's tile is its cell of the one sheet, to the texel" {
	const sheet: AnimationSheet = sheetFour();
	const tiles: Tile[] = frameTiles(sheet);
	assert (tiles.length as int32) == 4;
	for (let f: int32 = 0; f < 4; f++) {
		const left: float32 = ((f % 2) * 4) as float32;
		const top: float32 = ((f / 2) * 3) as float32;
		assert approx(tiles[f].u0, left / 8.0) && approx(tiles[f].u1, (left + 4.0) / 8.0);
		assert approx(tiles[f].v0, top / 6.0) && approx(tiles[f].v1, (top + 3.0) / 6.0);
		assert approx(tiles[f].w, 4.0) && approx(tiles[f].h, 3.0);
		assert approx(tiles[f].texW, 8.0) && approx(tiles[f].texH, 6.0);
		assert tiles[f].source.sameAs(tiles[0].source);
		assert tiles[f].source.view() == SHEET_VIEW;
		assert !tiles[f].alphaPremultiplied;
	}
}

test "scene.animation makes an Anim over the sheet that plays the GIF's own delays" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const node = s.animation(sheetFour());
	s.add(node);
	assert node.kind() === DrawKind.Anim;
	assert approx(node.content().w, 4.0) && approx(node.content().h, 3.0);
	assert (node.animFrames().frames.length as int32) == 4;
	assert node.animFrames().delaysMs[0] == 100 && node.animFrames().delaysMs[2] == 50;
	assert node.animFrames().frameIndex() == 0;
	s.tick(0.1);
	assert node.animFrames().frameIndex() == 1;
	s.tick(0.2);
	assert node.animFrames().frameIndex() == 2;
	s.tick(0.05);
	assert node.animFrames().frameIndex() == 3;
	s.tick(0.1);
	assert node.animFrames().frameIndex() == 0;
}
