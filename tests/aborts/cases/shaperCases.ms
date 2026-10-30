// flags: -d:voidShaper
// expect shaperFeatureCap: more than 32 feature overrides in one pass
// expect shaperGlyphOutside: void2d shaper: glyph 7 is outside the 1 of the last pass
// expect shaperRtl: void2d: right-to-left text at UTF-16 index 0 needs -d:voidBidi
// expect shaperTagNonAscii: a feature tag is four printable ASCII characters
import { argv } from "std/process";
import { loadFace } from "../../../src/void2d/face";
import { ShapeDirection, shaperBegin, shaperCodepoint, shaperEnd, shaperFeature, shaperGlyph } from "../../../src/void2d/shaper";
import { Align, TextLayout, describe } from "../../../src/void2d/textLayout";
import { addFont } from "../../../src/void2d/font";

function arabicRtl(): int32 {
	const added = addFont("tests/fonts/notoSansArabicSubset.ttf");
	if (!added.ok) {
		console.log("the Arabic subset did not load");
		return 1;
	}
	const l = TextLayout.layout("\u{645}\u{631}\u{62D}\u{628}\u{627}", {
		font: added.value, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	});
	if (!l.ok) {
		console.log(`void2d: ${l.error.describe()}`);
		return 1;
	}
	console.log(`Arabic text was laid out left to right, ${l.value.width} wide`);
	return 0;
}

function run(name: string): void {
	if (name == "shaperFeatureCap") {
		const face: int32 = try loadFace("assets/font.ttf") catch -1;
		shaperBegin(face, ShapeDirection.Ltr);
		for (let i: int32 = 0; i < 33; i++) {
			shaperFeature(`ft${i < 10 ? "0" : ""}${i}`, 1);
		}
		console.log("the feature cap was passed");
	} else if (name == "shaperGlyphOutside") {
		const face: int32 = try loadFace("assets/font.ttf") catch -1;
		shaperBegin(face, ShapeDirection.Ltr);
		shaperCodepoint(0x41);
		const count: int32 = shaperEnd();
		console.log(`shaped ${count}`);
		shaperGlyph(7);
		console.log("a glyph outside the pass was read");
	} else if (name == "shaperRtl") {
		const code: int32 = arabicRtl();
		if (code != 0) { process.exit(code); }
	} else if (name == "shaperTagNonAscii") {
		const face: int32 = try loadFace("assets/font.ttf") catch -1;
		shaperBegin(face, ShapeDirection.Ltr);
		shaperFeature("\u00e9ab", 1);
		console.log("a tag with a byte above ASCII was taken");
	} else {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
