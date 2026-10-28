// What a decode answers, folded into one FNV-1a 64 digest: the outcome, the size, the pixel and
// delay hashes, and the failure text unless the failing path's text is not the decoder's own.

const FNV_OFFSET: uint64 = 0xCBF29CE484222325;
const FNV_PRIME: uint64 = 0x100000001B3;

export class DecodeOutcome {
	ok: boolean = false;
	width: int32 = 0;
	height: int32 = 0;
	channels: int32 = 0;
	frames: int32 = 0;
	pixels: uint64 = 0;
	delays: uint64 = 0;
	text: string = "";
}

export function digestStart(): uint64 {
	return FNV_OFFSET;
}

export function mix(hash: uint64, byte: int32): uint64 {
	return (hash ^ ((byte & 255) as uint64)) * FNV_PRIME;
}

export function mixInt(hash: uint64, value: int32): uint64 {
	let h = hash;
	for (let i: int32 = 0; i < 4; i++) { h = mix(h, (value >> (8 * i)) & 255); }
	return h;
}

export function mixWide(hash: uint64, value: uint64): uint64 {
	let h = hash;
	for (let i: int32 = 0; i < 8; i++) { h = mix(h, ((value >> ((8 * i) as uint64)) & 255) as int32); }
	return h;
}

function mixText(hash: uint64, text: string): uint64 {
	let h = mix(hash, text.length);
	for (let i: int32 = 0; i < text.length && i < 63; i++) {
		const c = text.charCodeAt(i);
		h = mix(h, c >= 32 && c < 127 ? c : 63);
	}
	return h;
}

// withText is false for a failure whose text names the last format stb_image tried, not the one
// that was decoded.
export function mixOutcome(hash: uint64, o: DecodeOutcome, withText: boolean): uint64 {
	let h = hash;
	if (!o.ok) {
		h = mix(h, 0);
		return withText ? mixText(h, o.text) : h;
	}
	h = mix(h, 1);
	h = mixInt(h, o.width);
	h = mixInt(h, o.height);
	h = mixInt(h, o.channels);
	h = mixInt(h, o.frames);
	h = mixWide(h, o.pixels);
	return mixWide(h, o.delays);
}

export function hashBytes(bytes: Readonly<Span<uint8>>): uint64 {
	let hash: uint64 = FNV_OFFSET;
	for (let i: int32 = 0; i < bytes.length; i++) { hash = (hash ^ (bytes[i] as uint64)) * FNV_PRIME; }
	return hash;
}

// The 0xAABBGGRR words as the bytes stb_image returns them.
export function hashWords(words: Readonly<Span<uint32>>): uint64 {
	let hash: uint64 = FNV_OFFSET;
	for (let i: int32 = 0; i < words.length; i++) {
		const w = words[i];
		hash = (hash ^ ((w & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ (((w >> 8) & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ (((w >> 16) & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ ((w >> 24) as uint64)) * FNV_PRIME;
	}
	return hash;
}

export function hashInts(values: Readonly<Span<int32>>): uint64 {
	let hash: uint64 = FNV_OFFSET;
	for (let i: int32 = 0; i < values.length; i++) {
		const w = values[i] as uint32;
		hash = (hash ^ ((w & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ (((w >> 8) & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ (((w >> 16) & 255) as uint64)) * FNV_PRIME;
		hash = (hash ^ ((w >> 24) as uint64)) * FNV_PRIME;
	}
	return hash;
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
