// The lookups over the generated Unicode tables (tests/oracle/ucd.py): a table of packed
// ranges, (start << shift) | value, or a table of key and value pairs.

import { Buffer } from "std/core/buffer";

export function unpackRanges(packed: string, shift: uint32): uint32[] {
	const bytes = Buffer.fromString(packed, "base64");
	const mask: uint32 = (1 << shift) - 1;
	let out: uint32[] = new Array(0);
	let start: uint32 = 0;
	let word: uint32 = 0;
	let position: uint32 = 0;
	for (let i = 0; i < bytes.byteLength(); i++) {
		const byte = bytes.byteAt(i) as uint32;
		word |= (byte & 0x7F) << position;
		if ((byte & 0x80) != 0) {
			position += 7;
			continue;
		}
		start += word >> shift;
		out.push((start << shift) | (word & mask));
		word = 0;
		position = 0;
	}
	return out;
}

export function rangeValue(
	table: Readonly<Span<uint32>>,
	shift: uint32,
	mask: uint32,
	codepoint: int32,
): int32 {
	let lo: int32 = 0;
	let hi: int32 = table.length as int32 - 1;
	while (lo < hi) {
		const mid: int32 = (lo + hi + 1) >> 1;
		if ((table[mid] >> shift) as int32 <= codepoint) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	return (table[lo] & mask) as int32;
}

export function pairValue(table: Readonly<Span<uint32>>, codepoint: int32): int32 {
	let lo: int32 = 0;
	let hi: int32 = (table.length as int32 >> 1) - 1;
	while (lo <= hi) {
		const mid: int32 = (lo + hi) >> 1;
		const key = table[mid * 2] as int32;
		if (key == codepoint) { return table[mid * 2 + 1] as int32; }
		if (key < codepoint) { lo = mid + 1; } else { hi = mid - 1; }
	}
	return 0;
}
