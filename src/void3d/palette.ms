// Palette quantization LUT (RENDERER-BRIEF §3.3, technique 4): every color the post pass
// produces is replaced by its nearest palette color, looked up in a small 3D table.
//
// The table has `levels` steps per channel and is stored as a 2D texture `levels * levels`
// wide and `levels` high: cell (red, green, blue) sits at x = red + blue * levels, y = green,
// the addressing postFs uses. It is built on the CPU and uploaded into one dynamic image, so
// a palette swap (day/night, a season, a faded look) rewrites pixels and touches no pipeline,
// and the image is rebuilt from `pixels` after a context loss.

import {
	makeDynamicImage,
	makeTextureView,
	updateImage,
	destroyImage,
	destroyView,
} from "./gpu3d";

export const DEFAULT_PALETTE_LEVELS: int32 = 16;
// 32 * 32 = 1024 texels across, half of GLES3's minimum texture size limit.
export const MAX_PALETTE_LEVELS: int32 = 32;

const OPAQUE: uint32 = 0xFF000000;
const BYTE: uint32 = 0xFF;
const BYTE_RANGE: float32 = 255.0;
const HALF: float32 = 0.5;

// Channel weights of the color distance (weighted squared RGB, green counting most).
const RED_WEIGHT: float32 = 2.0;
const GREEN_WEIGHT: float32 = 4.0;
const BLUE_WEIGHT: float32 = 3.0;

export struct PaletteLut {
	levels: int32;
	// Texture byte order, as makeImage takes it: 0xAABBGGRR.
	pixels: Vec<uint32>;
	image: uint32;
	texture: uint32;
	// The pixels changed since the last upload.
	dirty: boolean;
}

export enum PaletteError {
	LevelsOutOfRange,
	EmptyPalette,
}

// A table that keeps every color (each cell holds its own color, so only the level count
// quantizes); `fill` writes a palette into it.
export function withLevels(
	this typeof PaletteLut,
	levels: int32,
): Result<PaletteLut, PaletteError> {
	if (levels < 2 || levels > MAX_PALETTE_LEVELS) {
		return Result.err(PaletteError.LevelsOutOfRange);
	}
	const pixels: Vec<uint32> = new Array(levels * levels * levels);
	const step: float32 = BYTE_RANGE / ((levels - 1) as float32);
	for (let green = 0; green < levels; green++) {
		for (let blue = 0; blue < levels; blue++) {
			for (let red = 0; red < levels; red++) {
				const color: uint32 = (levelByte(red, step) << 16) | (levelByte(green, step) << 8) |
					levelByte(blue, step);
				pixels[cellIndex(levels, red, green, blue)] = textureColor(color);
			}
		}
	}
	return Result.ok({ levels: levels, pixels: pixels, image: 0, texture: 0, dirty: true });
}

export function width(this lut: PaletteLut): int32 {
	return lut.levels * lut.levels;
}

export function height(this lut: PaletteLut): int32 {
	return lut.levels;
}

// The byte of level `level` when levels are `step` bytes apart, rounded.
function levelByte(level: int32, step: float32): uint32 {
	const byte: float32 = (level as float32) * step + HALF;
	return byte as uint32;
}

// Pixel index of cell (red, green, blue), each in 0..levels-1.
export function cellIndex(levels: int32, red: int32, green: int32, blue: int32): int32 {
	return green * levels * levels + blue * levels + red;
}

function channel(color: uint32, shift: int32): float32 {
	const byte: uint32 = (color >> (shift as uint32)) & BYTE;
	return (byte as float32) / BYTE_RANGE;
}

// Palette colors are written the way palettes are published, 0xRRGGBB.
function distanceTo(color: uint32, red: float32, green: float32, blue: float32): float32 {
	const dr: float32 = channel(color, 16) - red;
	const dg: float32 = channel(color, 8) - green;
	const db: float32 = channel(color, 0) - blue;
	return RED_WEIGHT * dr * dr + GREEN_WEIGHT * dg * dg + BLUE_WEIGHT * db * db;
}

// Index of the palette color nearest to (red, green, blue); the first one wins a tie.
export function nearestColor(
	palette: Span<uint32>,
	red: float32,
	green: float32,
	blue: float32,
): int32 {
	let best: int32 = 0;
	let bestDistance: float32 = distanceTo(palette[0], red, green, blue);
	for (let i = 1; i < (palette.length as int32); i++) {
		const distance: float32 = distanceTo(palette[i], red, green, blue);
		if (distance < bestDistance) {
			best = i;
			bestDistance = distance;
		}
	}
	return best;
}

// 0xRRGGBB → 0xFFBBGGRR.
export function textureColor(color: uint32): uint32 {
	const red: uint32 = (color >> 16) & BYTE;
	const green: uint32 = (color >> 8) & BYTE;
	const blue: uint32 = color & BYTE;
	return OPAQUE | (blue << 16) | (green << 8) | red;
}

// Maps every cell to its nearest palette color (0xRRGGBB each). Allocates nothing; the next
// upload sends the new pixels. Returns the number of cells written.
export function fill(ref lut: PaletteLut, palette: Span<uint32>): Result<int32, PaletteError> {
	if (palette.length == 0) { return Result.err(PaletteError.EmptyPalette); }
	const levels: int32 = lut.levels;
	const step: float32 = 1.0 / ((levels - 1) as float32);
	for (let green = 0; green < levels; green++) {
		for (let blue = 0; blue < levels; blue++) {
			for (let red = 0; red < levels; red++) {
				const nearest: int32 = nearestColor(
					palette,
					(red as float32) * step,
					(green as float32) * step,
					(blue as float32) * step,
				);
				lut.pixels[cellIndex(levels, red, green, blue)] = textureColor(palette[nearest]);
			}
		}
	}
	lut.dirty = true;
	return Result.ok(levels * levels * levels);
}

// Creates the image on first use (and after forgetGpu), then sends the pixels if they changed.
// Call before the pass that samples the table: sokol takes one update per image per frame.
export function upload(ref lut: PaletteLut): void {
	if (lut.image == 0) {
		lut.image = makeDynamicImage(lut.width(), lut.height());
		lut.texture = makeTextureView(lut.image);
		lut.dirty = true;
	}
	if (lut.dirty) {
		updateImage(lut.image, lut.pixels);
		lut.dirty = false;
	}
}

// After a context loss: the handles are stale (and may name new objects), so they are dropped
// without destroying anything; the next upload rebuilds the image from `pixels`.
export function forgetGpu(ref lut: PaletteLut): void {
	lut.image = 0;
	lut.texture = 0;
	lut.dirty = true;
}

export function releaseGpu(ref lut: PaletteLut): void {
	if (lut.texture != 0) { destroyView(lut.texture); }
	if (lut.image != 0) { destroyImage(lut.image); }
	forgetGpu(lut);
}
