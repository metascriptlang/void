when (macos && voidShaper && voidColourEmoji) {
	import { TextStyle, Align, NO_GLYPH } from "../void2d/textLayout";
	import { FontId, DEFAULT_FONT, addFont, addFallbackFont } from "../void2d/font";
	import { glyphInkBox } from "../void2d/face";
	import { laid } from "./layoutHelpers";

		const EMOJI: string = "/System/Library/Fonts/Apple Color Emoji.ttc";
		const THUMB: string = "\u{1F44D}";
		const THUMB_MEDIUM: string = "\u{1F44D}\u{1F3FD}";
		const FAMILY: string = "\u{1F468}‍\u{1F469}‍\u{1F467}";

		let font: FontId = DEFAULT_FONT;
		let ready: boolean = false;

		function style(): TextStyle {
			if (!ready) {
				font = try addFont("assets/font.ttf") catch DEFAULT_FONT;
				addFallbackFont(font, EMOJI);
				ready = true;
			}
			return {
				font: font, size: 20.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: Align.Left,
			};
		}

		function inked(text: string): int32 {
			const l = laid(text, style());
			let count: int32 = 0;
			for (const g of l.glyphs) {
				if (g.glyph != NO_GLYPH) { count = count + 1; }
			}
			return count;
		}

		test "a skin-tone sequence is one glyph of Apple Color Emoji" {
			assert inked(THUMB_MEDIUM) == 1;
		}

		test "a ZWJ family is one glyph of Apple Color Emoji" {
			assert inked(FAMILY) == 1;
		}

		test "a plain emoji and plain text keep one glyph per codepoint" {
			assert inked(THUMB) == 1;
			assert inked("abc") == 3;
		}

		test "the ligature owns the cluster's first cell, draws in the face's own glyph space and consumes the rest" {
			const l = laid(FAMILY, style());
			const ligature = l.glyphs[0];
			const box = glyphInkBox(ligature.face, ligature.glyph, ligature.size);
			assert box[2] - box[0] > 0.0 && box[3] - box[1] > 0.0;
			assert ligature.shapeStart && ligature.advance == 20.0;
			for (let i = 1; i < (l.glyphs.length as int32); i++) {
				assert l.glyphs[i].glyph == NO_GLYPH && !l.glyphs[i].shapeStart;
			}
			assert l.glyphs[0].glyph != laid(THUMB, style()).glyphs[0].glyph;
		}
}
