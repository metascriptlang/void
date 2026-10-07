import {
	void2dSpriteCount,
	void2dSpriteIndex,
	void2dSpriteCodepoint,
	void2dSpriteTableFault,
	void2dSpritePadding,
	void2dSpriteCanvasWidth,
	void2dSpriteCanvasHeight,
} from "./spriteGlyph.h";

extern function void2dSpriteDraw(
	id: int32, cellWidth: int32, cellHeight: int32, thickness: int32, canvas: Span<uint8>,
): int32;

export const SPRITE_FIRST_CODEPOINT: int32 = 0x2500;

export enum SpriteError {
	NoSuchSprite,
	BadCell,
	Geometry,
	OutOfMemory,
	BadBuffer,
}

export struct SpriteCanvas {
	pixels: Vec<uint8>;
	width: int32;
	height: int32;
	padX: int32;
	padY: int32;
}

export function spriteCount(): int32 {
	return void2dSpriteCount();
}

export function spriteIndex(codepoint: int32): int32 {
	return void2dSpriteIndex(codepoint);
}

export function spriteCodepoint(id: int32): int32 {
	return void2dSpriteCodepoint(id);
}

export function spriteTableFault(): int32 {
	return void2dSpriteTableFault();
}

function spriteStatus(code: int32): SpriteError {
	if (code < 1 || code > 5) {
		console.log(`void2d sprite: the drawer returned the unknown status ${code}`);
		unreachable;
	}
	return match (code) {
		1 => SpriteError.NoSuchSprite,
		2 => SpriteError.BadCell,
		3 => SpriteError.Geometry,
		4 => SpriteError.OutOfMemory,
		_ => SpriteError.BadBuffer,
	};
}

export function drawSprite(
	codepoint: int32, cellWidth: int32, cellHeight: int32, thickness: int32,
): Result<SpriteCanvas, SpriteError> {
	const id: int32 = void2dSpriteIndex(codepoint);
	if (id == 0) { return Result.err(SpriteError.NoSuchSprite); }
	if (cellWidth < 1 || cellHeight < 1 || thickness < 1) {
		return Result.err(SpriteError.BadCell);
	}
	const width: int32 = void2dSpriteCanvasWidth(cellWidth);
	const height: int32 = void2dSpriteCanvasHeight(cellHeight);
	let pixels: Vec<uint8> = new Array(width * height);
	const code: int32 = void2dSpriteDraw(id, cellWidth, cellHeight, thickness, pixels);
	if (code != 0) { return Result.err(spriteStatus(code)); }
	return Result.ok({
		pixels: pixels,
		width: width,
		height: height,
		padX: void2dSpritePadding(cellWidth),
		padY: void2dSpritePadding(cellHeight),
	});
}
