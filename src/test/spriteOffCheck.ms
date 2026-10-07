import { glyphIndex, isSpriteFace } from "../void2d/face";
import { addFont, fontFace, codepointFaceFor, Presentation } from "../void2d/font";

const SPRITE_SAMPLES: int32[] = [0x2500, 0x2588, 0x2593, 0x257F, 0x2800, 0xE0B0, 0x1FB00, 0x1CD00];

test "with sprites off a sprite codepoint resolves to the font's own face and glyph" {
	const added = addFont("assets/font.ttf");
	assert added.ok;
	if (!added.ok) { return; }
	const font = added.value;
	const primary: int32 = fontFace(font);
	assert glyphIndex(primary, 0xE0B0) != 0;
	const modes: Presentation[] = [Presentation.Default, Presentation.Text, Presentation.Emoji];
	for (const mode of modes) {
		for (const codepoint of SPRITE_SAMPLES) {
			const resolved = codepointFaceFor(font, codepoint, mode);
			assert resolved.face == primary;
			assert resolved.scale == 1.0;
			assert !isSpriteFace(resolved.face);
			assert glyphIndex(resolved.face, codepoint) == glyphIndex(primary, codepoint);
		}
	}
}
