import { KbFontBoundsError } from "../void2d/kb/blob";
import { KbFont, kbCodepointToGlyphId, kbFontFromMemory } from "../void2d/kb/font";

const GLYPHS_BELOW: int32 = 0x30000;
const GLYPHS_STRIDE: int32 = 251;
const GLYPHS_MUTATED: int32 = 0x400;
export const KB_FONT_GLYPH_FAILED: uint32 = 0xDEADBEEF;

export class KbFontFacts {
	error: int32 = 0;
	hasBlob: boolean = false;
	blobSize: int32 = 0;
	blobHash: uint32 = 0;
	cmap: int32 = 0;
	cmap14: int32 = 0;
	glyphHash: uint32 = 0;
}

export function kbFnv(h: uint32, v: uint32): uint32 {
	return (h ^ v) * 16777619;
}

export function kbFontCodepoints(mutated: boolean): int32[] {
	let codepoints: int32[] = [];
	if (mutated) {
		for (let cp: int32 = 0; cp < GLYPHS_MUTATED; cp++) { codepoints.push(cp); }
		return codepoints;
	}
	for (let cp: int32 = 0; cp < GLYPHS_BELOW; cp++) { codepoints.push(cp); }
	for (let cp: int32 = GLYPHS_BELOW; cp < 0x110000; cp += GLYPHS_STRIDE) { codepoints.push(cp); }
	codepoints.push(0x10FFFF);
	return codepoints;
}

export function kbFontBlobHash(blob: uint8[]): uint32 {
	let h: uint32 = 2166136261;
	for (let i: int32 = 0; i < blob.length; i++) { h = kbFnv(h, blob[i] as uint32); }
	return h;
}

export function kbFontFacts(font: KbFont, codepoints: int32[]): KbFontFacts {
	const facts = new KbFontFacts();
	facts.error = font.error;
	facts.hasBlob = font.hasBlob;
	facts.blobSize = font.blob.length as int32;
	facts.blobHash = kbFontBlobHash(font.blob);
	facts.cmap = font.cmap as int32;
	facts.cmap14 = font.cmap14 as int32;
	if (font.error == 6) { return facts; }
	let h: uint32 = 2166136261;
	if (font.cmap != 0) {
		try {
			for (const cp of codepoints) { h = kbFnv(h, kbCodepointToGlyphId(font, cp) as uint32); }
		} catch (e) {
			if (e instanceof KbFontBoundsError) { h = KB_FONT_GLYPH_FAILED; } else { throw e; }
		}
	}
	facts.glyphHash = h;
	return facts;
}

export function kbFontFold(h: uint32, facts: KbFontFacts): uint32 {
	let r = kbFnv(h, facts.error as uint32);
	r = kbFnv(r, facts.hasBlob ? 1 : 0);
	r = kbFnv(r, facts.blobSize as uint32);
	r = kbFnv(r, facts.blobHash);
	r = kbFnv(r, facts.cmap as uint32);
	r = kbFnv(r, facts.cmap14 as uint32);
	return kbFnv(r, facts.glyphHash);
}

export function kbFontInputs(bytes: uint8[]): uint8[][] {
	let inputs: uint8[][] = [bytes];
	for (const mutated of kbFontMutations(bytes)) { inputs.push(mutated); }
	return inputs;
}

export function kbFontDigestOf(bytes: uint8[], skips: int32[]): uint32 {
	let h: uint32 = 2166136261;
	const inputs = kbFontInputs(bytes);
	for (let i: int32 = 0; i < inputs.length; i++) {
		if (skips.includes(i)) { continue; }
		const font = kbFontFromMemory(inputs[i], 0);
		h = kbFontFold(h, kbFontFacts(font, kbFontCodepoints(i > 0)));
	}
	return h;
}

function kbFontMutations(bytes: uint8[]): uint8[][] {
	const length: int32 = bytes.length as int32;
	let inputs: uint8[][] = [];
	for (let cut: int32 = 0; cut < length; cut += cut < 100 ? 3 : (length / 40) + 1) {
		inputs.push(bytes.slice(0, cut));
	}
	const copy = bytes.slice(0, length);
	for (let at: int32 = 0; at < length; at += at < 300 ? 5 : (length / 80) + 1) {
		const was: uint8 = copy[at];
		copy[at] = was ^ 0xFF;
		inputs.push(copy.slice(0, length));
		copy[at] = 0x7F;
		inputs.push(copy.slice(0, length));
		copy[at] = was;
	}
	return inputs;
}
