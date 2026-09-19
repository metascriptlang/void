// The harness's own parsers, in one place and under test.
//
// tests/golden/compare.ms and tests/bench/check.ms both read text that something else
// printed — a markdown table and a `key value` row — and both used to carry their own copy
// of this arithmetic. Two copies is two places for a parser bug to hide, in the phase whose
// slogan is "distrust the harness before the engine"; and the first version of
// `parseFloat64` did hide one, silently reading `-4312` as `4312`, which would have made
// the counter gate blind to the exact regression it exists to catch.
//
// This file is reached from src/test/index.ms, so `msc test src/test/index.ms` runs these.

// What `parseInt32` answers for text that is not a plain run of digits: an empty cell, the
// `-` placeholder tests/PENDING.md uses for a row with no image budget, or a number written
// with a separator. A budget that does not parse has to be reported as unparseable rather
// than quietly read as zero — zero is a real budget, and the author would be sent looking
// at the renderer.
export const NOT_A_NUMBER: int32 = -1;

export function trimSpaces(text: string): string {
	let start: int32 = 0;
	let end: int32 = text.length as int32;
	while (start < end && (text.charAt(start) == " " || text.charAt(start) == "\t")) {
		start = start + 1;
	}
	while (end > start && (text.charAt(end - 1) == " " || text.charAt(end - 1) == "\t")) {
		end = end - 1;
	}
	return text.substring(start, end);
}

export function parseInt32(text: string): int32 {
	const digits = trimSpaces(text);
	const length: int32 = digits.length as int32;
	if (length == 0) { return NOT_A_NUMBER; }
	for (let i: int32 = 0; i < length; i++) {
		const code: int32 = digits.charCodeAt(i) as int32;
		if (code < "0".code || code > "9".code) { return NOT_A_NUMBER; }
	}
	let value: int32 = 0;
	for (let i: int32 = 0; i < length; i++) {
		value = value * 10 + ((digits.charCodeAt(i) as int32) - "0".code);
	}
	return value;
}

// Sign and exponent included, because MetaScript prints a float64 in whatever form it likes
// and a counter that regressed to a negative number must not come back positive.
export function parseFloat64(text: string): float64 {
	const length: int32 = text.length as int32;
	let index: int32 = 0;
	let sign: float64 = 1.0;
	if (index < length && (text.charCodeAt(index) as int32) == "-".code) {
		sign = -1.0;
		index = index + 1;
	} else if (index < length && (text.charCodeAt(index) as int32) == "+".code) {
		index = index + 1;
	}
	let value: float64 = 0.0;
	while (index < length) {
		const code: int32 = text.charCodeAt(index) as int32;
		if (code < "0".code || code > "9".code) { break; }
		value = value * 10.0 + ((code - "0".code) as float64);
		index = index + 1;
	}
	if (index < length && (text.charCodeAt(index) as int32) == ".".code) {
		index = index + 1;
		let scale: float64 = 1.0;
		while (index < length) {
			const code: int32 = text.charCodeAt(index) as int32;
			if (code < "0".code || code > "9".code) { break; }
			scale = scale * 10.0;
			value = value + ((code - "0".code) as float64) / scale;
			index = index + 1;
		}
	}
	if (index < length) {
		const marker: int32 = text.charCodeAt(index) as int32;
		if (marker == "e".code || marker == "E".code) {
			index = index + 1;
			let exponentSign: int32 = 1;
			if (index < length && (text.charCodeAt(index) as int32) == "-".code) {
				exponentSign = -1;
				index = index + 1;
			} else if (index < length && (text.charCodeAt(index) as int32) == "+".code) {
				index = index + 1;
			}
			let exponent: int32 = 0;
			while (index < length) {
				const code: int32 = text.charCodeAt(index) as int32;
				if (code < "0".code || code > "9".code) { break; }
				exponent = exponent * 10 + (code - "0".code);
				index = index + 1;
			}
			for (let step: int32 = 0; step < exponent; step++) {
				value = exponentSign > 0 ? value * 10.0 : value / 10.0;
			}
		}
	}
	return sign * value;
}

test "trimSpaces strips the padding a markdown cell carries" {
	assert trimSpaces("  golden:prim/roundedRect ").equals("golden:prim/roundedRect");
	assert trimSpaces("\t42\t").equals("42");
	assert trimSpaces("   ").equals("");
}

test "parseInt32 reads a plain run of digits" {
	assert parseInt32("0") == 0;
	assert parseInt32(" 9874 ") == 9874;
}

test "parseInt32 refuses what is not a number instead of answering zero" {
	assert parseInt32("") == NOT_A_NUMBER;
	assert parseInt32("-") == NOT_A_NUMBER;
	assert parseInt32("9 874") == NOT_A_NUMBER;
	assert parseInt32("1.5") == NOT_A_NUMBER;
	assert parseInt32("twelve") == NOT_A_NUMBER;
}

test "parseFloat64 keeps the sign" {
	assert parseFloat64("-4312") == -4312.0;
	assert parseFloat64("+7") == 7.0;
}

test "parseFloat64 reads a decimal" {
	assert parseFloat64("4.48") > 4.4799 && parseFloat64("4.48") < 4.4801;
	assert parseFloat64("0") == 0.0;
}

test "parseFloat64 reads an exponent in both directions" {
	assert parseFloat64("1.5e2") == 150.0;
	assert parseFloat64("1.2e-05") < 0.00002;
	assert parseFloat64("1.2e-05") > 0.0;
}
