import { DecodedAnimation } from "../assets/image";
import { Texture, TextureError } from "../gpu/texture";
import { Tile, tile } from "./types";
import { Scene2D, NodeRef } from "./node";

export const MAX_SHEET_SIDE: int32 = 16384;

export enum AnimationError {
	NoFrames,
	SheetTooLarge,
	TextureRefused,
}

export struct SheetLayout {
	columns: int32;
	rows: int32;
	width: int32;
	height: int32;
}

export interface AnimationSheet {
	texture: Texture;
	layout: SheetLayout;
	frameW: int32;
	frameH: int32;
	frameCount: int32;
	delays: Vec<int32>;
}

export function sheetLayout(
	frameW: int32,
	frameH: int32,
	count: int32,
): Result<SheetLayout, AnimationError> {
	if (count <= 0 || frameW <= 0 || frameH <= 0) { return Result.err(AnimationError.NoFrames); }
	let columns: int32 = 1;
	while (columns * columns < count) { columns = columns + 1; }
	while (columns > 1 && (columns as int64) * (frameW as int64) > (MAX_SHEET_SIDE as int64)) {
		columns = columns - 1;
	}
	const rows: int32 = (count + columns - 1) / columns;
	const width: int64 = (columns as int64) * (frameW as int64);
	const height: int64 = (rows as int64) * (frameH as int64);
	if (width > (MAX_SHEET_SIDE as int64) || height > (MAX_SHEET_SIDE as int64)) {
		return Result.err(AnimationError.SheetTooLarge);
	}
	return Result.ok({
		columns: columns, rows: rows, width: width as int32, height: height as int32,
	});
}

export function packSheet(a: DecodedAnimation, layout: SheetLayout): Vec<uint32> {
	let pixels: Vec<uint32> = new Array(layout.width * layout.height);
	const frameSize: int32 = a.width * a.height;
	for (let f: int32 = 0; f < a.frameCount; f++) {
		const left: int32 = (f % layout.columns) * a.width;
		const top: int32 = (f / layout.columns) * a.height;
		for (let y: int32 = 0; y < a.height; y++) {
			for (let x: int32 = 0; x < a.width; x++) {
				const at: int32 = (top + y) * layout.width + left + x;
				pixels[at] = a.pixels[f * frameSize + y * a.width + x];
			}
		}
	}
	return pixels;
}

export function sheetOf(
	a: DecodedAnimation,
	texture: Texture,
	layout: SheetLayout,
): AnimationSheet {
	return {
		texture: texture, layout: layout, frameW: a.width, frameH: a.height,
		frameCount: a.frameCount, delays: a.delays,
	};
}

export function uploadAnimation(a: DecodedAnimation): Result<AnimationSheet, AnimationError> {
	const layout: SheetLayout = try sheetLayout(a.width, a.height, a.frameCount);
	const made: Result<Texture, TextureError> =
		Texture.fromPixels(packSheet(a, layout), layout.width, layout.height, true);
	if (!made.ok) { return Result.err(AnimationError.TextureRefused); }
	return Result.ok(sheetOf(a, made.value, layout));
}

export function frameTiles(sheet: AnimationSheet): Tile[] {
	const whole: Tile = tile(
		sheet.texture, sheet.layout.width as float32, sheet.layout.height as float32,
	);
	let tiles: Tile[] = [];
	for (let f: int32 = 0; f < sheet.frameCount; f++) {
		const left: int32 = (f % sheet.layout.columns) * sheet.frameW;
		const top: int32 = (f / sheet.layout.columns) * sheet.frameH;
		tiles.push(whole.sub(
			left as float32, top as float32, sheet.frameW as float32, sheet.frameH as float32,
		));
	}
	return tiles;
}

export function animation(this s: Scene2D, sheet: AnimationSheet): NodeRef {
	let total: int32 = 0;
	for (const delay of sheet.delays) { total = total + delay; }
	const fps: float32 = (sheet.frameCount as float32) * 1000.0 / (total as float32);
	return s.anim(frameTiles(sheet), fps).setFrameDelays(sheet.delays);
}
