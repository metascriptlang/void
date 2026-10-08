import {
	BidiClass,
	bidiClassOf,
	bracketCode,
	mirrorOf,
} from "../void2d/bidi";
import { possiblyRtl } from "../void2d/textDirection";

test "the class of sampled codepoints, and the defaults of unassigned blocks" {
	assert bidiClassOf(0x41) == BidiClass.L;
	assert bidiClassOf(0x05D0) == BidiClass.R;
	assert bidiClassOf(0x0627) == BidiClass.AL;
	assert bidiClassOf(0x0660) == BidiClass.AN;
	assert bidiClassOf(0x0030) == BidiClass.EN;
	assert bidiClassOf(0x200F) == BidiClass.R;
	assert bidiClassOf(0x202E) == BidiClass.RLO;
	assert bidiClassOf(0x2067) == BidiClass.RLI;
	assert bidiClassOf(0x2069) == BidiClass.PDI;
	assert bidiClassOf(0x0300) == BidiClass.NSM;
	assert bidiClassOf(0x05FF) == BidiClass.R;
	assert bidiClassOf(0x07BF) == BidiClass.AL;
	assert bidiClassOf(0x20CF) == BidiClass.ET;
	assert bidiClassOf(0xFFFE) == BidiClass.BN;
	assert bidiClassOf(0x10FFFF) == BidiClass.BN;
}

test "paired brackets: the canonical equivalents of U+2329 and U+232A pair with U+3008 and U+3009" {
	assert bracketCode(0x41) == 0;
	assert bracketCode(0x28) == ((0x28 << 1) | 1);
	assert bracketCode(0x29) == (0x28 << 1);
	assert bracketCode(0x2329) == ((0x3008 << 1) | 1);
	assert bracketCode(0x232A) == (0x3008 << 1);
	assert bracketCode(0x3009) == (0x3008 << 1);
}

test "mirror pairs are symmetric, exact and exclude the best-fit rows" {
	assert mirrorOf(0x28) == 0x29;
	assert mirrorOf(0x29) == 0x28;
	assert mirrorOf(0x3C) == 0x3E;
	assert mirrorOf(0x2208) == 0x220B;
	assert mirrorOf(0x2209) == 0;
	assert mirrorOf(0x220C) == 0;
	assert mirrorOf(0x41) == 0;
	let pairs: int32 = 0;
	for (let c = 0; c <= 0x10FFFF; c++) {
		const mirror: int32 = mirrorOf(c);
		if (mirror == 0) { continue; }
		pairs = pairs + 1;
		assert mirrorOf(mirror) == c;
	}
	console.log(`bidi oracle: ${pairs} exact mirror codepoints, each the mirror of its mirror`);
	assert pairs == 364;
}

test "every bracket closes the pair its opening codepoint opens" {
	let opening: int32 = 0;
	let closing: int32 = 0;
	for (let c = 0; c <= 0x10FFFF; c++) {
		const code: int32 = bracketCode(c);
		if (code == 0) { continue; }
		if ((code & 1) == 1) { opening = opening + 1; } else { closing = closing + 1; }
		assert bidiClassOf(c) == BidiClass.ON;
	}
	console.log(`bidi oracle: ${opening} opening and ${closing} closing paired brackets`);
	assert opening == 65 && closing == 65;
}

test "possiblyRtl holds every codepoint whose class can make text right to left" {
	let held: int32 = 0;
	let extra: int32 = 0;
	for (let c = 0; c <= 0x10FFFF; c++) {
		const cls: BidiClass = bidiClassOf(c);
		const rightToLeft: boolean = cls == BidiClass.R || cls == BidiClass.AL ||
			cls == BidiClass.AN || cls == BidiClass.RLE || cls == BidiClass.RLO ||
			cls == BidiClass.RLI || cls == BidiClass.FSI;
		if (rightToLeft) {
			assert possiblyRtl(c);
			held = held + 1;
		} else if (possiblyRtl(c)) {
			extra = extra + 1;
		}
	}
	console.log(`bidi oracle: possiblyRtl holds ${held} right-to-left codepoints and ${extra} others`);
	assert held > 0;
}
