import { truncInt } from "../trueType/fontInfo";

export const NUMBER_ITEM_BYTES: int32 = 63;

const BIG_DIGITS: int32 = 15;
const EXPONENT_LIMIT: float64 = 100000.0;
const INT64_MAX: int64 = 9223372036854775807;

// A NUL-terminated C string over a shared byte array: ch() reads 0 at and past the end, as the
// terminator does, so every scan stops where the C one stops.
export struct Str {
	b: uint8[];
	s: int32;
	e: int32;
}

export function ch(this x: Str, i: int32): int32 {
	const k = x.s + i;
	if (i < 0 || k >= x.e || k >= (x.b.length as int32)) { return 0; }
	return x.b[k] as int32;
}

export function length(this x: Str): int32 {
	let n: int32 = 0;
	while (x.ch(n) != 0) { n += 1; }
	return n;
}

export function sub(this x: Str, from: int32, to: int32): Str {
	return { b: x.b, s: x.s + from, e: Math.min(x.s + to, x.e) };
}

export function eq(this x: Str, literal: string): boolean {
	const n = literal.byteLength();
	for (let i: int32 = 0; i < n; i++) {
		if (x.ch(i) != literal.byteAt(i)) { return false; }
	}
	return x.ch(n) == 0;
}

export function startsWith(this x: Str, literal: string): boolean {
	const n = literal.byteLength();
	for (let i: int32 = 0; i < n; i++) {
		if (x.ch(i) != literal.byteAt(i)) { return false; }
	}
	return true;
}

export function same(this x: Str, other: Str): boolean {
	let i: int32 = 0;
	while (true) {
		const a = x.ch(i);
		if (a != other.ch(i)) { return false; }
		if (a == 0) { return true; }
		i += 1;
	}
}

// nsvg__isspace: strchr over " \t\n\v\f\r" also finds the terminator, so 0 counts.
export function isSpace(c: int32): boolean {
	return c == 32 || (c >= 9 && c <= 13) || c == 0;
}

export function isDigit(c: int32): boolean {
	return c >= 48 && c <= 57;
}

export function contains(this x: Str, literal: string): boolean {
	const n = literal.byteLength();
	for (let i: int32 = 0; x.ch(i) != 0; i++) {
		let all = true;
		for (let k: int32 = 0; k < n; k++) {
			if (x.ch(i + k) != literal.byteAt(k)) { all = false; break; }
		}
		if (all) { return true; }
	}
	return false;
}

function digitsEnd(x: Str, from: int32): int32 {
	let i = from;
	while (isDigit(x.ch(i))) { i += 1; }
	return i;
}

// (double)strtoll(digits): saturates at LLONG_MAX; up to 15 digits the double sum is exact.
function digitsValue(x: Str, from: int32, to: int32): float64 {
	if (to - from <= BIG_DIGITS) {
		let sum: float64 = 0.0;
		for (let i = from; i < to; i++) { sum = sum * 10.0 + ((x.ch(i) - 48) as float64); }
		return sum;
	}
	let acc: int64 = 0;
	for (let i = from; i < to; i++) {
		const d = (x.ch(i) - 48) as int64;
		if (acc > (INT64_MAX - d) / 10) {
			acc = INT64_MAX;
			break;
		}
		acc = acc * 10 + d;
	}
	return acc as float64;
}

// strtol(x + from, &end, 10) clamped to +-EXPONENT_LIMIT, where pow(10, n) is already 0 or inf;
// returns the conversion's end, or `from` when nothing converts.
function exponentValue(x: Str, from: int32, out: float64[]): int32 {
	let i = from;
	while (isSpace(x.ch(i)) && x.ch(i) != 0) { i += 1; }
	let negative = false;
	if (x.ch(i) == 45) {
		negative = true;
		i += 1;
	} else if (x.ch(i) == 43) {
		i += 1;
	}
	const end = digitsEnd(x, i);
	if (end == i) { return from; }
	let value = digitsValue(x, i, end);
	if (value > EXPONENT_LIMIT) { value = EXPONENT_LIMIT; }
	out[0] = negative ? -value : value;
	return end;
}

// nsvg__atof, on the bytes of x up to its end.
export function atof(x: Str): float64 {
	let cur: int32 = 0;
	let sign: float64 = 1.0;
	let res: float64 = 0.0;
	let hasInt = false;
	let hasFrac = false;
	const first = x.ch(0);
	if (first == 43) {
		cur += 1;
	} else if (first == 45) {
		sign = -1.0;
		cur += 1;
	}
	if (isDigit(x.ch(cur))) {
		const end = digitsEnd(x, cur);
		res = digitsValue(x, cur, end);
		hasInt = true;
		cur = end;
	}
	if (x.ch(cur) == 46) {
		cur += 1;
		if (isDigit(x.ch(cur))) {
			const end = digitsEnd(x, cur);
			res += digitsValue(x, cur, end) / Math.pow(10.0, (end - cur) as float64);
			hasFrac = true;
			cur = end;
		}
	}
	if (!hasInt && !hasFrac) { return 0.0; }
	const marker = x.ch(cur);
	if (marker == 101 || marker == 69) {
		const exponent: float64[] = [0.0];
		const end = exponentValue(x, cur + 1, exponent);
		if (end != cur + 1) { res *= Math.pow(10.0, exponent[0]); }
	}
	return res * sign;
}

export function atofFloat(x: Str): float32 {
	return atof(x) as float32;
}

// nsvg__parseNumber: the end of the number that starts at `from`.
export function numberEnd(x: Str, from: int32): int32 {
	let s = from;
	const sign = x.ch(s);
	if (sign == 45 || sign == 43) { s += 1; }
	while (isDigit(x.ch(s))) { s += 1; }
	if (x.ch(s) == 46) {
		s += 1;
		while (isDigit(x.ch(s))) { s += 1; }
	}
	const marker = x.ch(s);
	const after = x.ch(s + 1);
	if ((marker == 101 || marker == 69) && after != 109 && after != 120) {
		s += 1;
		const expSign = x.ch(s);
		if (expSign == 45 || expSign == 43) { s += 1; }
		while (isDigit(x.ch(s))) { s += 1; }
	}
	return s;
}

// The bytes parseNumber keeps of the number that starts at `from` and ends at `end`.
export function numberItem(x: Str, from: int32, end: int32): Str {
	return x.sub(from, from + Math.min(end - from, NUMBER_ITEM_BYTES));
}

export function floatToInt(value: float32): int32 {
	const wide = value as float64;
	if (!(wide > -2147483649.0 && wide < 2147483648.0)) {
		throw new Error(`void2d svg: ${value} does not fit the 32-bit integer the rasterizer converts it to`);
	}
	return truncInt(wide);
}

// (unsigned int)value for a value the C then shifts into an alpha byte.
export function floatToByte(value: float32): int32 {
	if (!(value >= 0)) { return 0; }
	return truncInt(value as float64) & 255;
}
