import {
	void2dGlyphBox,
	void2dGlyphRasterize,
	void2dGlyphPageCreate,
	void2dGlyphPageClear,
} from "./glyph.h";

export const SUBPIXEL_VARIANTS: int32 = 4;
export const GLYPH_GUTTER: int32 = 1;
export const GLYPH_PAGE_SIZE: int32 = 1024;

export type GlyphPage = distinct int32;
export type GlyphPageHandle = distinct int32;
export const NO_GLYPH_PAGE: GlyphPage = (-1) as GlyphPage;
export const NO_GLYPH_PAGE_HANDLE: GlyphPageHandle = (-1) as GlyphPageHandle;

export enum AtlasError {
	TooLarge,
	Full,
}

export struct GlyphKey {
	face: int32;
	glyph: int32;
	sizePx: float32;
	variant: int32;
}

export struct GlyphTile {
	page: GlyphPage;
	x: int32;
	y: int32;
	width: int32;
	height: int32;
	left: int32;
	top: int32;
	refs: int32;
	key: uint64;
}

export struct PixelPlacement {
	whole: int32;
	variant: int32;
}

struct Shelf {
	page: GlyphPage;
	y: int32;
	height: int32;
	cursor: int32;
}

struct AtlasPage {
	handle: GlyphPageHandle;
	top: int32;
	drawnFrame: int32;
}

export interface GlyphAtlas {
	pageSize: int32;
	maxPages: int32;
	pages: Vec<AtlasPage>;
	shelves: Vec<Shelf>;
	tiles: Vec<GlyphTile>;
	freeTiles: Vec<int32>;
	index: Map<uint64, int32>;
	rasterizations: int32;
	reclaims: int32;
	frame: int32;
}

export function create(this typeof GlyphAtlas, pageSize: int32, maxPages: int32): GlyphAtlas {
	return {
		pageSize: pageSize,
		maxPages: maxPages,
		pages: new Array(0),
		shelves: new Array(0),
		tiles: new Array(0),
		freeTiles: new Array(0),
		index: new Map<uint64, int32>(),
		rasterizations: 0,
		reclaims: 0,
		frame: 0,
	};
}

export function quantizeX(deviceX: float32): PixelPlacement {
	const variants: float32 = SUBPIXEL_VARIANTS as float32;
	const quarters: int32 = Math.floor(deviceX * variants + 0.5) as int32;
	const whole: int32 = Math.floor((quarters as float32) / variants) as int32;
	return { whole: whole, variant: quarters - whole * SUBPIXEL_VARIANTS };
}

export function snapBaseline(deviceY: float32): int32 {
	return Math.floor(deviceY + 0.5) as int32;
}

export function packed(this key: GlyphKey): uint64 {
	const sizeQ: uint64 = (Math.floor(key.sizePx * 64.0 + 0.5) as int32) as uint64;
	return ((key.face as uint64) << 48) |
		((key.glyph as uint64) << 32) |
		(sizeQ << 8) |
		(key.variant as uint64);
}

export function tileSlots(this atlas: GlyphAtlas): int32 {
	return atlas.tiles.length as int32;
}

export function pageCount(this atlas: GlyphAtlas): int32 {
	return atlas.pages.length as int32;
}

export function pageHandle(this atlas: GlyphAtlas, page: GlyphPage): GlyphPageHandle {
	return atlas.pages[page as int32].handle;
}

export function beginFrame(this atlas: GlyphAtlas, frame: int32): void {
	atlas.frame = frame;
}

export function markDrawn(this atlas: GlyphAtlas, page: GlyphPage): void {
	atlas.pages[page as int32].drawnFrame = atlas.frame;
}

export function ensurePage(this atlas: GlyphAtlas): GlyphPageHandle {
	if ((atlas.pages.length as int32) == 0 && atlas.maxPages > 0) {
		const handle: int32 = void2dGlyphPageCreate(atlas.pageSize);
		if (handle >= 0) {
			atlas.pages.push({ handle: handle as GlyphPageHandle, top: 0, drawnFrame: -1 });
		}
	}
	return (atlas.pages.length as int32) > 0 ? atlas.pages[0].handle : NO_GLYPH_PAGE_HANDLE;
}

export function residentBytes(this atlas: GlyphAtlas): int32 {
	return (atlas.pages.length as int32) * atlas.pageSize * atlas.pageSize;
}

export function tile(this atlas: GlyphAtlas, index: int32): GlyphTile {
	return atlas.tiles[index];
}

export function release(this atlas: GlyphAtlas, index: int32): void {
	if (atlas.tiles[index].refs > 0) {
		atlas.tiles[index].refs = atlas.tiles[index].refs - 1;
	}
}

function liveTilesOn(atlas: GlyphAtlas, page: GlyphPage): int32 {
	let live: int32 = 0;
	for (let i = 0; i < (atlas.tiles.length as int32); i++) {
		if (atlas.tiles[i].page == page && atlas.tiles[i].refs > 0) { live = live + 1; }
	}
	return live;
}

function placeOnPage(
	atlas: GlyphAtlas,
	page: GlyphPage,
	width: int32,
	height: int32,
): [int32, int32] {
	const size: int32 = atlas.pageSize;
	for (let s = 0; s < (atlas.shelves.length as int32); s++) {
		const shelf: Shelf = atlas.shelves[s];
		const fits: boolean = shelf.page == page && height <= shelf.height &&
			height * 4 >= shelf.height * 3 && shelf.cursor + width <= size;
		if (fits) {
			atlas.shelves[s].cursor = shelf.cursor + width;
			return [shelf.cursor, shelf.y];
		}
	}
	const top: int32 = atlas.pages[page as int32].top;
	if (top + height > size || width > size) { return [-1, -1]; }
	atlas.shelves.push({ page: page, y: top, height: height, cursor: width });
	atlas.pages[page as int32].top = top + height;
	return [0, top];
}

function reclaimPage(atlas: GlyphAtlas): GlyphPage {
	for (let p = 0; p < (atlas.pages.length as int32); p++) {
		const page: GlyphPage = p as GlyphPage;
		if (atlas.pages[p].drawnFrame == atlas.frame || liveTilesOn(atlas, page) != 0) { continue; }
		for (let i = 0; i < (atlas.tiles.length as int32); i++) {
			if (atlas.tiles[i].page == page) {
				atlas.index.delete(atlas.tiles[i].key);
				atlas.tiles[i].page = NO_GLYPH_PAGE;
				atlas.tiles[i].refs = -1;
				atlas.freeTiles.push(i);
			}
		}
		const kept: Vec<Shelf> = new Array(0);
		for (const shelf of atlas.shelves) {
			if (shelf.page != page) { kept.push(shelf); }
		}
		atlas.shelves = kept;
		atlas.pages[p].top = 0;
		void2dGlyphPageClear(atlas.pages[p].handle as int32);
		atlas.reclaims = atlas.reclaims + 1;
		return page;
	}
	return NO_GLYPH_PAGE;
}

function allocate(
	atlas: GlyphAtlas,
	width: int32,
	height: int32,
): Result<[GlyphPage, int32, int32], AtlasError> {
	const w: int32 = width + GLYPH_GUTTER;
	const h: int32 = height + GLYPH_GUTTER;
	if (w > atlas.pageSize || h > atlas.pageSize) { return Result.err(AtlasError.TooLarge); }
	for (let p = 0; p < (atlas.pages.length as int32); p++) {
		const [x, y] = placeOnPage(atlas, p as GlyphPage, w, h);
		if (x >= 0) { return Result.ok([p as GlyphPage, x, y]); }
	}
	let page: GlyphPage = NO_GLYPH_PAGE;
	if ((atlas.pages.length as int32) < atlas.maxPages) {
		const handle: int32 = void2dGlyphPageCreate(atlas.pageSize);
		if (handle < 0) { return Result.err(AtlasError.Full); }
		atlas.pages.push({ handle: handle as GlyphPageHandle, top: 0, drawnFrame: -1 });
		page = ((atlas.pages.length as int32) - 1) as GlyphPage;
	} else {
		page = reclaimPage(atlas);
		if (page == NO_GLYPH_PAGE) { return Result.err(AtlasError.Full); }
	}
	const [x, y] = placeOnPage(atlas, page, w, h);
	return Result.ok([page, x, y]);
}

export function acquire(this atlas: GlyphAtlas, key: GlyphKey): Result<int32, AtlasError> {
	const packedKey: uint64 = key.packed();
	const hit = atlas.index.get(packedKey);
	if (hit.present) {
		atlas.tiles[hit.value].refs = atlas.tiles[hit.value].refs + 1;
		return Result.ok(hit.value);
	}
	const shift: float32 = (key.variant as float32) / (SUBPIXEL_VARIANTS as float32);
	const box: Ptr<int32> = void2dGlyphBox(key.face, key.glyph, key.sizePx, shift);
	const left: int32 = box[0];
	const top: int32 = box[1];
	const width: int32 = box[2] - left;
	const height: int32 = box[3] - top;
	let page: GlyphPage = NO_GLYPH_PAGE;
	let x: int32 = 0;
	let y: int32 = 0;
	if (width > 0 && height > 0) {
		const placed = try allocate(atlas, width, height);
		page = placed[0];
		x = placed[1];
		y = placed[2];
		void2dGlyphRasterize(key.face, key.glyph, key.sizePx, shift,
			atlas.pages[page as int32].handle as int32, x, y, width, height);
	}
	atlas.rasterizations = atlas.rasterizations + 1;
	const record: GlyphTile = {
		page: page,
		x: x,
		y: y,
		width: width > 0 ? width : 0,
		height: height > 0 ? height : 0,
		left: left,
		top: top,
		refs: 1,
		key: packedKey,
	};
	let index: int32 = atlas.tiles.length as int32;
	if ((atlas.freeTiles.length as int32) > 0) {
		index = atlas.freeTiles.pop();
		atlas.tiles[index] = record;
	} else {
		atlas.tiles.push(record);
	}
	atlas.index.set(packedKey, index);
	return Result.ok(index);
}
