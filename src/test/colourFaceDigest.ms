import {
	COLOUR_OK,
	COLOUR_PRESENT,
	ColourBox,
	ColourLayer,
	ColourSfnt,
	colourCompose,
	colourFaceGlyphIndex,
	colourFaceHasLayers,
	colourFaceOpen,
	colourFaceReason,
	colourFaceSfnt,
	colourGlyphBox,
	colourGlyphLayers,
	colourGlyphRender,
} from "../void2d/colourEmoji/colourFace";

const FNV_OFFSET: uint64 = 0xCBF29CE484222325;
const FNV_PRIME: uint64 = 0x100000001B3;
const MAX_TILE_TEXELS: int32 = 262144;

// A running FNV-1a hash. The pins in colourFacePins.ms were recorded from the C colourFace.c
// feeding the same events in the same order, before that file was deleted.
export class Digest {
	h: uint64 = FNV_OFFSET;
}

export function mix(d: Digest, byte: int32): void {
	d.h = (d.h ^ ((byte & 255) as uint64)) * FNV_PRIME;
}

export function mixInt(d: Digest, value: int32): void {
	for (let i: int32 = 0; i < 4; i++) { mix(d, (value >> (8 * i)) & 255); }
}

export function mixWide(d: Digest, value: uint64): void {
	for (let i: int32 = 0; i < 8; i++) { mix(d, ((value >> ((8 * i) as uint64)) & 255) as int32); }
}

export function mixText(d: Digest, text: string): void {
	mixInt(d, text.length);
	for (let i: int32 = 0; i < text.length && i < 256; i++) {
		const c = text.charCodeAt(i);
		mix(d, c >= 32 && c < 127 ? c : 63);
	}
}

export function hex64(value: uint64): string {
	const digits: string = "0123456789abcdef";
	let out: string = "";
	for (let shift: int32 = 60; shift >= 0; shift = shift - 4) {
		out = out + digits[((value >> (shift as uint64)) & 15) as int32];
	}
	return out;
}

function nibble(c: int32): int32 {
	return c >= 97 ? c - 87 : c - 48;
}

export function hexBytes(hex: string): uint8[] {
	const n = hex.length / 2;
	const out: uint8[] = new Array<uint8>(n);
	for (let i: int32 = 0; i < n; i++) {
		out[i] = ((nibble(hex.charCodeAt(2 * i)) << 4) | nibble(hex.charCodeAt(2 * i + 1))) as uint8;
	}
	return out;
}

export function mixReason(d: Digest): void {
	mixText(d, colourFaceReason());
}

export function digestFont(d: Digest, bytes: uint8[], sizes: float32[], indexes: boolean): void {
	const opened = colourFaceOpen(bytes, 0);
	let status = opened.status;
	const sfnt = new ColourSfnt();
	const face = opened.face;
	if (status == COLOUR_OK && face != null && colourFaceSfnt(face, bytes, sfnt) != COLOUR_OK) {
		status = -1;
	}
	mixInt(d, status);
	mixReason(d);
	if (status != COLOUR_OK || face == null) { return; }
	mixInt(d, sfnt.numGlyphs);
	mixInt(d, sfnt.head as int32);
	mixInt(d, sfnt.hhea as int32);
	mixInt(d, sfnt.hmtx as int32);
	mixInt(d, sfnt.hmtxLength as int32);
	mixInt(d, sfnt.outlines ? 1 : 0);
	mixInt(d, colourFaceHasLayers(face) ? 1 : 0);
	if (indexes) {
		for (let cp: int32 = 0; cp < 0x30000; cp += (cp >= 0x1F000 && cp < 0x20000 ? 1 : 61)) {
			mixInt(d, colourFaceGlyphIndex(face, bytes, cp));
		}
	}
	const layers: ColourLayer[] = new Array<ColourLayer>(256);
	for (let g: int32 = 0; g < sfnt.numGlyphs; g++) {
		const count = colourGlyphLayers(face, bytes, g, layers, 256);
		mixInt(d, count);
		for (let i: int32 = 0; i < count; i++) {
			mixInt(d, layers[i].glyph);
			mixInt(d, layers[i].r as int32);
			mixInt(d, layers[i].g as int32);
			mixInt(d, layers[i].b as int32);
			mixInt(d, layers[i].a as int32);
		}
		mixReason(d);
		for (const size of sizes) {
			const box = new ColourBox();
			const boxStatus = colourGlyphBox(face, bytes, g, size, box);
			mixInt(d, boxStatus);
			mixInt(d, box.width);
			mixInt(d, box.height);
			mixInt(d, box.bearingX);
			mixInt(d, box.bearingY);
			mixInt(d, box.ppem);
			mixReason(d);
			if (boxStatus == COLOUR_PRESENT && box.width * box.height <= MAX_TILE_TEXELS) {
				const tile: uint32[] = new Array<uint32>(box.width * box.height);
				for (let i: int32 = 0; i < tile.length; i++) { tile[i] = 0xA5A5A5A5; }
				const renderStatus = colourGlyphRender(face, bytes, g, size, tile, box.width, box.width, box.height);
				mixInt(d, renderStatus);
				if (renderStatus == COLOUR_PRESENT) {
					let tileHash: uint64 = FNV_OFFSET;
					for (let i: int32 = 0; i < tile.length; i++) {
						for (let c: int32 = 0; c < 4; c++) {
							tileHash = (tileHash ^ (((tile[i] >> ((8 * c) as uint32)) & 255) as uint64)) * FNV_PRIME;
						}
					}
					mixWide(d, tileHash);
				}
				mixReason(d);
			}
		}
	}
}

// Every truncation of the font, and the font with four 0xFF bytes stamped at each offset.
export function digestMutants(d: Digest, bytes: uint8[], step: int32): void {
	const sizes: float32[] = [16.0];
	for (let cut: int32 = 0; cut <= bytes.length; cut += step) {
		const part: uint8[] = new Array<uint8>(cut);
		for (let i: int32 = 0; i < cut; i++) { part[i] = bytes[i]; }
		digestFont(d, part, sizes, false);
		if (cut + 4 <= bytes.length) {
			const stamped: uint8[] = new Array<uint8>(bytes.length);
			for (let i: int32 = 0; i < bytes.length; i++) { stamped[i] = bytes[i]; }
			for (let i: int32 = 0; i < 4; i++) { stamped[cut + i] = 0xFF; }
			digestFont(d, stamped, sizes, false);
		}
	}
}

export function composeCase(seed: int32): uint64 {
	const w = 1 + (seed * 7) % 13;
	const h = 1 + (seed * 5) % 11;
	const cw = 1 + (seed * 3) % 9;
	const ch = 1 + (seed * 11) % 8;
	const ox = ((seed * 13) % 17) - 6;
	const oy = ((seed * 17) % 15) - 5;
	const rgba: uint32 = (seed as uint32) * 2654435761;
	const dst: uint32[] = new Array<uint32>(w * h);
	const coverage: uint8[] = new Array<uint8>(cw * ch);
	let state: uint32 = (seed as uint32) * 2654435761 + 12345;
	for (let i: int32 = 0; i < w * h; i++) { state = state * 1664525 + 1013904223; dst[i] = state; }
	for (let i: int32 = 0; i < cw * ch; i++) {
		state = state * 1664525 + 1013904223;
		coverage[i] = ((state >> 24) % 3 == 0 ? 0 : (state >> 16)) as uint8;
	}
	const layer: ColourLayer = {
		glyph: 0, r: (rgba & 255) as uint8, g: ((rgba >> 8) & 255) as uint8,
		b: ((rgba >> 16) & 255) as uint8, a: ((rgba >> 24) & 255) as uint8,
	};
	colourCompose(dst, w, w, h, coverage, cw, ox, oy, cw, ch, layer);
	let hash: uint64 = FNV_OFFSET;
	for (let i: int32 = 0; i < w * h; i++) {
		for (let c: int32 = 0; c < 4; c++) {
			hash = (hash ^ (((dst[i] >> ((8 * c) as uint32)) & 255) as uint64)) * FNV_PRIME;
		}
	}
	return hash;
}

export function digestCompose(d: Digest): void {
	for (let seed: int32 = 0; seed < 400; seed++) { mixWide(d, composeCase(seed)); }
}

export const SIZES: float32[] = [4.0, 8.0, 16.0, 24.5, 32.0, 64.0, 137.0, 300.0];
export const ODD_SIZES: float32[] = [
	0.0, -3.0, 0.5, 1.0, 5000.0, 9000.0, 16000.0, 16384.0, 16385.0, 20000.0, (0.0 / 0.0) as float32,
];

// The case list: "font:<name>", "odd:<name>", "cut:<name>:<step>" or "compose".
export function digestCase(name: string, bytes: uint8[]): uint64 {
	const d = new Digest();
	if (name.startsWith("font:")) {
		digestFont(d, bytes, SIZES, true);
	} else if (name.startsWith("odd:")) {
		digestFont(d, bytes, ODD_SIZES, false);
	} else if (name.startsWith("cut:")) {
		digestMutants(d, bytes, name.endsWith(":97") ? 97 : 4);
	} else {
		throw new Error(`unknown colour pin case ${name}`);
	}
	return d.h;
}
