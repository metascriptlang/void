import { lineBreakPacked } from "../void2d/lineBreak";
import { graphemePacked } from "../void2d/grapheme";
import { bidiClassOf, bracketCode, mirrorOf } from "../void2d/bidi";

function fold(hash: uint32, value: int32): uint32 {
	return (((hash ^ (value as uint32)) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
}

// Pinned from the C classifiers: lineBreak.c, grapheme.c and bidiClass.c returned these values
// for every code point from -2 to 0x110001, over the tables the C headers held.
test "the classifiers over every code point keep their recorded digest" {
	let hash: uint32 = 2166136261;
	for (let c = -2; c <= 0x110001; c++) {
		hash = fold(hash, lineBreakPacked(c));
		hash = fold(hash, graphemePacked(c));
		hash = fold(hash, bidiClassOf(c) as int32);
		hash = fold(hash, bracketCode(c));
		hash = fold(hash, mirrorOf(c));
	}
	assert hash == 1552595492;
}
