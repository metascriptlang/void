import {
	clippedArea, growthTarget, quadCoverage, scissorMax, scissorMin, scissorRectOf, scopeAt,
	ScissorRect,
} from "../void2d/coverage";
import { COMMAND_FLOATS } from "../void2d/commandFields";

const FNV_OFFSET: uint32 = 2166136261;
const FNV_PRIME: uint32 = 16777619;
const SEED: uint32 = 2463534242;
const AREA_STEPS: float64 = 1048576.0;

export type MinMaxOf = (edge: float32, scale: float32) => int32;
export type GrowthOf = (have: int32, need: int32) => int32;
export type RectOf = (
	cmd: Readonly<Span<float32>>,
	scopes: Readonly<Span<float32>>,
	scopeCount: int32,
	useScopes: boolean,
	dpi: float32,
	fbW: float32,
	fbH: float32,
) => ScissorRect;
export type AreaOf = (poly: Readonly<Span<float64>>, count: int32, rect: ScissorRect) => float64;
export type QuadOf = (
	affine: Readonly<Span<float32>>,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	scale: float32,
	x0: int32,
	y0: int32,
	x1: int32,
	y1: int32,
) => float64;

// Digests of the C arithmetic of batcher.c (scissor, coverage, buffer growth) recorded over these
// inputs before the port replaced it. Each FNV-1a is 32 bits over little-endian ints; an area is
// mixed as its round to 2^-20 pixel, high then low word, so float64 needs no bit cast.
const COVERAGE_PINS: string[] = [
	"minMax b845b83a",
	"growth 6f2204e4",
	"rect 2662c7c6",
	"area 6c62535d",
	"quad 7f9b55c3",
];

class Digest {
	h: uint32 = FNV_OFFSET;
}

class Source {
	state: uint32 = SEED;
}

function mix(d: Digest, byte: int32): void {
	d.h = (d.h ^ ((byte & 255) as uint32)) * FNV_PRIME;
}

function mixInt(d: Digest, value: int32): void {
	for (let i: int32 = 0; i < 4; i++) { mix(d, (value >> (8 * i)) & 255); }
}

function mixArea(d: Digest, value: float64): void {
	if (value != value) {
		mixInt(d, -1);
		mixInt(d, -1);
		return;
	}
	const steps: float64 = Math.round(value * AREA_STEPS);
	const high: float64 = Math.floor(steps / 4294967296.0);
	const low: float64 = steps - high * 4294967296.0;
	mixInt(d, high as int32);
	for (let i: int32 = 0; i < 4; i++) {
		mix(d, (Math.floor(low / Math.pow(256.0, i as float64)) % 256.0) as int32);
	}
}

function hex32(value: uint32): string {
	const digits: string = "0123456789abcdef";
	let out: string = "";
	for (let shift: int32 = 28; shift >= 0; shift = shift - 4) {
		out = out + digits[((value >> (shift as uint32)) & 15) as int32];
	}
	return out;
}

function next(s: Source): uint32 {
	s.state ^= s.state << 13;
	s.state ^= s.state >> 17;
	s.state ^= s.state << 5;
	return s.state;
}

function unit(s: Source): float64 {
	return (next(s) as float64) / 4294967296.0;
}

const ZERO: float32 = 0.0;
const SPECIAL: float32[] = [
	0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, 2.0, 1e9, -1e9, 2147483520.0, 2147483648.0,
	-2147483648.0, -2147483904.0, 3e9, -3e9, 1e30, -1e30, 3.4e38,
];
const SCALES: float32[] = [1.0, 2.0, 1.5, 0.5, 1.25, 3.0, 0.75, 1.0 / 3.0];
const HAVES: int32[] = [0, -5, 1, 1 << 20, 3 << 19, 1 << 24, 100 << 20, 192 << 20, 1 << 30, 12345];

function pick(s: Source): float32 {
	const r: uint32 = next(s) % 8;
	if (r == 0) { return SPECIAL[(next(s) % (SPECIAL.length as uint32)) as int32]; }
	if (r == 1) { return ((unit(s) - 0.5) * 4000.0) as float32; }
	if (r == 2) { return (((next(s) % 4000) as float64) / 8.0 - 200.0) as float32; }
	if (r == 3) { return (unit(s) * 40.0 - 10.0) as float32; }
	if (r == 4) { return ZERO / ZERO; }
	if (r == 5) { return (((next(s) & 1) == 0) ? (1.0 as float32) : (-1.0 as float32)) / ZERO; }
	return ((unit(s) - 0.5) * 300.0) as float32;
}

function pickFinite(s: Source): float32 {
	const r: uint32 = next(s) % 4;
	if (r == 0) { return (((next(s) % 4000) as float64) / 8.0 - 200.0) as float32; }
	if (r == 1) { return ((unit(s) - 0.5) * 4000.0) as float32; }
	return ((unit(s) - 0.5) * 300.0) as float32;
}

function pickScale(s: Source): float32 {
	return SCALES[(next(s) % (SCALES.length as uint32)) as int32];
}

export function digestMinMax(min: MinMaxOf, max: MinMaxOf): uint32 {
	const s = new Source();
	const d = new Digest();
	for (let i: int32 = 0; i < 30000; i++) {
		const edge: float32 = pick(s);
		const scale: float32 = pick(s);
		mixInt(d, min(edge, scale));
		mixInt(d, max(edge, scale));
	}
	return d.h;
}

export function digestGrowth(growth: GrowthOf): uint32 {
	const s = new Source();
	const d = new Digest();
	for (let i: int32 = 0; i < 30000; i++) {
		const have: int32 = (next(s) & 3) == 0 ? HAVES[(next(s) % 10) as int32]
			: ((next(s) % 1073741824) as int32);
		const need: int32 = (next(s) & 3) == 0
			? HAVES[(next(s) % 10) as int32] + ((next(s) % 3) as int32) - 1
			: ((next(s) % 400000000) as int32) - 1000;
		mixInt(d, growth(have, need));
	}
	return d.h;
}

export function digestRect(rectOf: RectOf): uint32 {
	const s = new Source();
	const d = new Digest();
	const scopeRows: int32 = 6;
	let scopes: Vec<float32> = [];
	for (let r: int32 = 0; r < scopeRows * 8; r++) { scopes.push(pickFinite(s)); }
	let cmd: Vec<float32> = [];
	for (let i: int32 = 0; i < COMMAND_FLOATS; i++) { cmd.push(0.0); }
	for (let i: int32 = 0; i < 30000; i++) {
		const dpi: float32 = pickScale(s);
		const useScopes: boolean = (next(s) % 8) != 0;
		if ((next(s) & 15) == 0) {
			for (let r: int32 = 0; r < scopeRows * 8; r++) { scopes[r] = pickFinite(s); }
		}
		for (let k: int32 = 0; k < COMMAND_FLOATS; k++) { cmd[k] = 0.0; }
		const clipKind: uint32 = next(s) % 4;
		cmd[8] = clipKind == 0 ? 0.0 : pickFinite(s);
		cmd[9] = clipKind == 0 ? 0.0 : pickFinite(s);
		cmd[10] = clipKind == 0 ? 0.0
			: (clipKind == 1 ? pickFinite(s) : (pickFinite(s) < 0.0 ? 0.0 : 200.0));
		cmd[11] = clipKind == 0 ? 0.0
			: (clipKind == 1 ? pickFinite(s) : (pickFinite(s) < 0.0 ? 0.0 : 100.0));
		cmd[14] = (next(s) & 3) == 0 ? pickScale(s) : 0.0;
		cmd[31] = (((next(s) % 9) as int32) - 2) as float32;
		const fbW: float32 = (next(s) & 7) == 0 ? pickFinite(s) : 400.0;
		const fbH: float32 = (next(s) & 7) == 0 ? pickFinite(s) : 300.0;
		const rect: ScissorRect = rectOf(
			cmd, scopes, useScopes ? scopeRows : 0, useScopes, dpi, fbW, fbH,
		);
		mixInt(d, rect.x0);
		mixInt(d, rect.y0);
		mixInt(d, rect.x1);
		mixInt(d, rect.y1);
	}
	return d.h;
}

export function digestArea(areaOf: AreaOf): uint32 {
	const s = new Source();
	const d = new Digest();
	let poly: Vec<float64> = [];
	for (let i: int32 = 0; i < 24; i++) { poly.push(0.0); }
	for (let i: int32 = 0; i < 30000; i++) {
		const kind: uint32 = next(s) % 3;
		const n: int32 = kind == 0 ? ((next(s) % 6) as int32) + 3 : ((next(s) % 2) as int32) + 3;
		const radius: float64 = unit(s) * 200.0;
		for (let k: int32 = 0; k < n; k++) {
			if (kind == 0) {
				const angle: float64 = (k as float64) * 6.283185307179586 / (n as float64);
				poly[k * 2] = 100.0 + Math.cos(angle) * radius;
				poly[k * 2 + 1] = 80.0 + Math.sin(angle) * radius;
			} else {
				poly[k * 2] = (unit(s) - 0.25) * 500.0;
				poly[k * 2 + 1] = (unit(s) - 0.25) * 400.0;
			}
		}
		const x0: int32 = ((next(s) % 100) as int32) - 20;
		const y0: int32 = ((next(s) % 100) as int32) - 20;
		const x1: int32 = x0 + ((next(s) % 300) as int32) - 20;
		const y1: int32 = y0 + ((next(s) % 300) as int32) - 20;
		mixArea(d, areaOf(poly, n, { x0, y0, x1, y1 }));
	}
	return d.h;
}

export function digestQuad(quadOf: QuadOf): uint32 {
	const s = new Source();
	const d = new Digest();
	let affine: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
	for (let i: int32 = 0; i < 30000; i++) {
		const mode: uint32 = next(s) % 3;
		if (mode == 0) {
			affine[0] = 1.0;
			affine[1] = 0.0;
			affine[2] = 0.0;
			affine[3] = 1.0;
		} else if (mode == 1) {
			const angle: float32 = (unit(s) * 6.28) as float32;
			affine[0] = Math.cos(angle as float64) as float32;
			affine[1] = Math.sin(angle as float64) as float32;
			affine[2] = -affine[1];
			affine[3] = affine[0];
		} else {
			for (let k: int32 = 0; k < 4; k++) { affine[k] = ((unit(s) - 0.5) * 4.0) as float32; }
		}
		const x: float32 = pickFinite(s);
		const y: float32 = pickFinite(s);
		const w: float32 = (unit(s) * 300.0) as float32;
		const h: float32 = (unit(s) * 300.0) as float32;
		const scale: float32 = pickScale(s);
		const x0: int32 = ((next(s) % 100) as int32) - 20;
		const y0: int32 = ((next(s) % 100) as int32) - 20;
		const x1: int32 = x0 + ((next(s) % 400) as int32) - 20;
		const y1: int32 = y0 + ((next(s) % 400) as int32) - 20;
		mixArea(d, quadOf(affine, x, y, w, h, scale, x0, y0, x1, y1));
	}
	return d.h;
}

export function coverageDigests(
	min: MinMaxOf,
	max: MinMaxOf,
	growth: GrowthOf,
	rectOf: RectOf,
	areaOf: AreaOf,
	quadOf: QuadOf,
): string[] {
	return [
		`minMax ${hex32(digestMinMax(min, max))}`,
		`growth ${hex32(digestGrowth(growth))}`,
		`rect ${hex32(digestRect(rectOf))}`,
		`area ${hex32(digestArea(areaOf))}`,
		`quad ${hex32(digestQuad(quadOf))}`,
	];
}

function portRect(
	cmd: Readonly<Span<float32>>,
	scopes: Readonly<Span<float32>>,
	scopeCount: int32,
	useScopes: boolean,
	dpi: float32,
	fbW: float32,
	fbH: float32,
): ScissorRect {
	return scissorRectOf(cmd, scopes, scopeAt(cmd, scopeCount, useScopes), dpi, fbW, fbH);
}

test "the coverage port reproduces the digests recorded from the C" {
	const got: string[] = coverageDigests(
		scissorMin, scissorMax, growthTarget, portRect, clippedArea, quadCoverage,
	);
	assert got.length == COVERAGE_PINS.length;
	let bad: int32 = 0;
	for (let i: int32 = 0; i < (got.length as int32); i++) {
		if (got[i] != COVERAGE_PINS[i]) {
			bad++;
			console.log(`DIFFERS ${got[i]} vs ${COVERAGE_PINS[i]}`);
		}
	}
	assert bad == 0;
}
