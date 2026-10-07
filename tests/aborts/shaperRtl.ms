// expect: void2d: right-to-left text at UTF-16 index 0 needs BiDi
// flags: -d:voidShaper
import { Align, TextLayout } from "../../src/void2d/textLayout";
import { addFont } from "../../src/void2d/font";

function main(): int32 {
	const added = addFont("tests/fonts/notoSansArabicSubset.ttf");
	if (!added.ok) {
		console.log("the Arabic subset did not load");
		return 1;
	}
	const l = TextLayout.layout("\u{645}\u{631}\u{62D}\u{628}\u{627}", {
		font: added.value, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	});
	console.log(`Arabic text was laid out left to right, ${l.width} wide`);
	return 0;
}

process.exit(main());
