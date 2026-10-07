import {
	AtlasError,
	GlyphAtlas,
	GlyphTile,
	GLYPH_GUTTER,
	NO_GLYPH_PAGE,
	maskKey,
} from "./glyphAtlas";
import { PlacedGlyph, glyphAtlas, isPixelExact, uvRect } from "./labelText";
import { NO_RUN } from "./textLayout";
import { Transform2D } from "./types";
import {
	SvgMaskError,
	SvgMaskRefusal,
	SvgMaskSource,
	svgMaskParse,
	svgMaskRasterize,
} from "./svgMask";

export type IconId = distinct int32;
export const NO_ICON_PLACEMENT: int32 = -1;
export const MAX_ICONS: int32 = 65535;
export const ICON_SUPERSAMPLE: int32 = 2;

const ICON_SIZE_NOISE: float32 = 0.001;

struct IconEntry {
	source: SvgMaskSource;
	held: int32;
}

struct IconPlacement {
	icon: IconId;
	tile: int32;
	maskWidth: int32;
	maskHeight: int32;
	refusal: string;
}

export struct PlacedIcon {
	drawn: boolean;
	refused: boolean;
	exact: boolean;
	glyph: PlacedGlyph;
}

let icons: Vec<IconEntry> = [];
let placements: Vec<IconPlacement> = [];
let freePlacements: Vec<int32> = [];
let refusedIcons: int32 = 0;
let reportedIcons: int32 = 0;
let rasterizedIcons: int32 = 0;

const hidden: PlacedGlyph = {
	tile: -1, page: NO_GLYPH_PAGE, x: 0.0, y: 0.0, w: 0.0, h: 0.0,
	u0: 0.0, v0: 0.0, u1: 0.0, v1: 0.0, run: NO_RUN,
};

export function registerIcon(source: string): Result<IconId, SvgMaskRefusal> {
	if ((icons.length as int32) >= MAX_ICONS) {
		return Result.err({
			error: SvgMaskError.TooLarge,
			what: `the icon table holds ${MAX_ICONS} icons and ids are not reused`,
		});
	}
	const parsed = try svgMaskParse(source);
	icons.push({ source: parsed, held: 0 });
	return Result.ok(((icons.length as int32) - 1) as IconId);
}

function stopOnUnknownIcon(call: string, icon: IconId): void {
	console.log(`void2d icon: ${call}: icon ${icon as int32} is not registered`);
	unreachable;
}

export function requireIcon(icon: IconId, call: string): void {
	const id: int32 = icon as int32;
	if (id < 0 || id >= (icons.length as int32)) { stopOnUnknownIcon(call, icon); }
}

export function iconWidth(icon: IconId): float32 {
	requireIcon(icon, "iconWidth");
	return icons[icon as int32].source.width;
}

export function iconHeight(icon: IconId): float32 {
	requireIcon(icon, "iconHeight");
	return icons[icon as int32].source.height;
}

export function iconHolds(icon: IconId): int32 {
	requireIcon(icon, "iconHolds");
	return icons[icon as int32].held;
}

export function iconRefusals(): int32 { return refusedIcons; }

export function iconRefusalReports(): int32 { return reportedIcons; }

export function iconRasterizations(): int32 { return rasterizedIcons; }

export function maskSide(deviceLength: float32): int32 {
	if (!(deviceLength > ICON_SIZE_NOISE)) { return 0; }
	return (Math.ceil((deviceLength - ICON_SIZE_NOISE) as float64) as int32) * ICON_SUPERSAMPLE;
}

export function acquireIconMask(
	atlas: GlyphAtlas,
	icon: IconId,
	maskWidth: int32,
	maskHeight: int32,
): Result<int32, string> {
	requireIcon(icon, "acquireIconMask");
	const key = maskKey(icon as int32, maskWidth, maskHeight);
	const held: int32 = atlas.retainMask(key);
	if (held >= 0) { return Result.ok(held); }
	const room: int32 = atlas.pageSize - GLYPH_GUTTER;
	if (maskWidth < 1 || maskHeight < 1 || maskWidth > room || maskHeight > room) {
		return Result.err(
			`${AtlasError.TooLarge.toString()}: a ${maskWidth}x${maskHeight} mask does not fit ` +
			`a ${atlas.pageSize} page`,
		);
	}
	const tile = atlas.reserveMask(key, maskWidth, maskHeight);
	if (!tile.ok) { return Result.err(tile.error.toString()); }
	rasterizedIcons = rasterizedIcons + 1;
	const drawn = svgMaskRasterize(icons[icon as int32].source, maskWidth, maskHeight);
	if (!drawn.ok) {
		atlas.discard(tile.value);
		return Result.err(`${drawn.error.error.toString()}: ${drawn.error.what}`);
	}
	const filled = atlas.fillMask(tile.value, drawn.value);
	if (!filled.ok) {
		atlas.discard(tile.value);
		return Result.err(filled.error.toString());
	}
	return Result.ok(tile.value);
}

export function allocateIconPlacement(icon: IconId): int32 {
	requireIcon(icon, "scene.icon");
	const row: IconPlacement = {
		icon: icon, tile: -1, maskWidth: 0, maskHeight: 0, refusal: "",
	};
	icons[icon as int32].held = icons[icon as int32].held + 1;
	if ((freePlacements.length as int32) > 0) {
		const index: int32 = freePlacements.pop();
		placements[index] = row;
		return index;
	}
	placements.push(row);
	return (placements.length as int32) - 1;
}

export function iconOf(index: int32): IconId { return placements[index].icon; }

export function iconTile(index: int32): int32 { return placements[index].tile; }

function dropTile(index: int32): void {
	if (placements[index].tile >= 0) { glyphAtlas.release(placements[index].tile); }
	placements[index].tile = -1;
	placements[index].maskWidth = 0;
	placements[index].maskHeight = 0;
}

export function releaseIconTile(index: int32): void { dropTile(index); }

export function releaseIconPlacement(index: int32): void {
	dropTile(index);
	const icon: int32 = placements[index].icon as int32;
	icons[icon].held = icons[icon].held - 1;
	freePlacements.push(index);
}

export function placeIcon(
	index: int32,
	width: float32,
	height: float32,
	world: Transform2D,
	scale: float32,
): PlacedIcon {
	const exact: boolean = isPixelExact(world);
	const linear: float32 = exact
		? world.a
		: Math.sqrt(Math.abs(world.a * world.d - world.b * world.c)) as float32;
	const devicePerLocal: float32 = linear * scale;
	const deviceW: float32 = width * devicePerLocal;
	const deviceH: float32 = height * devicePerLocal;
	const maskWidth: int32 = maskSide(deviceW);
	const maskHeight: int32 = maskSide(deviceH);
	if (maskWidth == 0 || maskHeight == 0) {
		dropTile(index);
		return { drawn: false, refused: false, exact: exact, glyph: hidden };
	}
	if (placements[index].tile < 0 ||
		placements[index].maskWidth != maskWidth || placements[index].maskHeight != maskHeight) {
		dropTile(index);
		const acquired = acquireIconMask(glyphAtlas, placements[index].icon, maskWidth, maskHeight);
		if (!acquired.ok) {
			refusedIcons = refusedIcons + 1;
			if (placements[index].refusal != acquired.error) {
				reportedIcons = reportedIcons + 1;
				console.log(`void2d: an icon mask was refused (${acquired.error})`);
			}
			placements[index].refusal = acquired.error;
			return { drawn: false, refused: true, exact: exact, glyph: hidden };
		}
		placements[index].tile = acquired.value;
		placements[index].maskWidth = maskWidth;
		placements[index].maskHeight = maskHeight;
		placements[index].refusal = "";
	}
	const tile: GlyphTile = glyphAtlas.tile(placements[index].tile);
	const [u0, v0, u1, v1] = tile.uvRect();
	const quadW: float32 = (maskWidth as float32) / (ICON_SUPERSAMPLE as float32);
	const quadH: float32 = (maskHeight as float32) / (ICON_SUPERSAMPLE as float32);
	let glyph: PlacedGlyph = hidden;
	if (exact) {
		const originX: float32 = Math.floor((world.tx * scale) as float64) as float32;
		const originY: float32 = Math.floor((world.ty * scale) as float64) as float32;
		const centredX: float32 = world.tx * scale + (deviceW - quadW) * 0.5;
		const centredY: float32 = world.ty * scale + (deviceH - quadH) * 0.5;
		const left: float32 = Math.floor((centredX + 0.5) as float64) as float32;
		const top: float32 = Math.floor((centredY + 0.5) as float64) as float32;
		glyph = {
			tile: placements[index].tile, page: tile.page,
			x: left - originX, y: top - originY, w: quadW, h: quadH,
			u0: u0, v0: v0, u1: u1, v1: v1, run: NO_RUN,
		};
	} else {
		const localW: float32 = quadW / devicePerLocal;
		const localH: float32 = quadH / devicePerLocal;
		glyph = {
			tile: placements[index].tile, page: tile.page,
			x: (width - localW) * 0.5, y: (height - localH) * 0.5, w: localW, h: localH,
			u0: u0, v0: v0, u1: u1, v1: v1, run: NO_RUN,
		};
	}
	return { drawn: true, refused: false, exact: exact, glyph: glyph };
}
