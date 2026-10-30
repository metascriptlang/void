import { decodePng } from "../assets/png";
import { pngCases } from "./pngCases";

const FNV_OFFSET: uint64 = 0xCBF29CE484222325;
const FNV_PRIME: uint64 = 0x100000001B3;

function nibble(c: int32): int32 {
	return c >= 97 ? c - 87 : c - 48;
}

function hexBytes(hex: string): uint8[] {
	const n = hex.length / 2;
	const out: uint8[] = new Array<uint8>(n);
	for (let i: int32 = 0; i < n; i++) {
		out[i] = ((nibble(hex.charCodeAt(2 * i)) << 4) | nibble(hex.charCodeAt(2 * i + 1))) as uint8;
	}
	return out;
}

function mix(hash: uint64, byte: int32): uint64 {
	return (hash ^ ((byte & 255) as uint64)) * FNV_PRIME;
}

function mixInt(hash: uint64, value: int32): uint64 {
	let h = hash;
	for (let i: int32 = 0; i < 4; i++) { h = mix(h, (value >> (8 * i)) & 255); }
	return h;
}

function mixWide(hash: uint64, value: uint64): uint64 {
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

function hex64(value: uint64): string {
	const digits: string = "0123456789abcdef";
	let out: string = "";
	for (let shift: int32 = 60; shift >= 0; shift = shift - 4) {
		out = out + digits[((value >> (shift as uint64)) & 15) as int32];
	}
	return out;
}

function pixelHash(pixels: Span<uint8>): uint64 {
	let hash: uint64 = FNV_OFFSET;
	for (let i: int32 = 0; i < pixels.length; i++) { hash = (hash ^ (pixels[i] as uint64)) * FNV_PRIME; }
	return hash;
}

// Each case is "name digest hex". The digest folds, for requested channel counts 0..4, the
// outcome, size and pixel hash (or the failure reason) of the stb_image decode that was
// recorded from the C before it was deleted.
function digestOf(bytes: uint8[]): string {
	const prime: uint8[] = [0];
	let mine: uint64 = FNV_OFFSET;
	for (let req: int32 = 0; req <= 4; req++) {
		decodePng(prime, req, 4096);
		const port = decodePng(bytes, req, 4096);
		if (port.ok) {
			mine = mix(mine, 1);
			mine = mixInt(mine, port.value.width);
			mine = mixInt(mine, port.value.height);
			mine = mixInt(mine, port.value.channels);
			mine = mixWide(mine, pixelHash(port.value.pixels));
		} else {
			mine = mix(mine, 0);
			mine = mixText(mine, port.error);
		}
	}
	return hex64(mine);
}

test "the PNG decoder reproduces the digests recorded from stb_image" {
	let bad: int32 = 0;
	for (const row of pngCases) {
		const parts = row.split(" ");
		const got = digestOf(hexBytes(parts[2]));
		if (got != parts[1]) {
			bad++;
			console.log(`DIFFERS ${parts[0]}: ${got} vs ${parts[1]}`);
		}
	}
	assert pngCases.length == 389;
	assert bad == 0;
}
