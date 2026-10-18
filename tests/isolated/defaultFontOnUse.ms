// Run in a process of its own (scripts/gate.sh): src/test/index.ms draws in the default font
// before a test there could see it still unloaded.

import {
	Font,
	FontFeature,
	FontStyle,
	SizeAdjust,
	DEFAULT_FONT,
	addFont,
	registerFace,
	resolveFont,
	fontFace,
	defaultFaceLoads,
} from "../../src/void2d/font";

const OWN: string = "tests/fonts/NotoSansSC-subset.ttf";

test "a font the app brings loads no default face, and font 0 loads once on first use" {
	registerFace(OWN, "Own", 400, FontStyle.Normal);
	const added = addFont(OWN);
	assert added.ok;
	if (added.ok) { assert fontFace(added.value) >= 0; }
	const features: FontFeature[] = [];
	const fallbacks: string[] = [];
	const own: Font = {
		family: "Own", weight: 400, style: FontStyle.Normal, features: features,
		fallbacks: fallbacks, sizeAdjust: SizeAdjust.None,
	};
	const resolved = resolveFont(own);
	assert resolved.ok;
	if (resolved.ok) { assert fontFace(resolved.value) >= 0; }
	assert defaultFaceLoads() == 0;
	assert fontFace(DEFAULT_FONT) >= 0;
	assert fontFace(DEFAULT_FONT) >= 0;
	assert defaultFaceLoads() == 1;
}
