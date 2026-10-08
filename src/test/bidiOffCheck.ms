import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import { textStatus, textWidth } from "../void2d/render";
import {
	Align,
	TextErrorKind,
	TextLayout,
	TextStyle,
	calcTextWidth,
	describe,
} from "../void2d/textLayout";
import { DEFAULT_FONT } from "../void2d/font";
import { rgba } from "../void2d/types";
import { possiblyRtl } from "../void2d/textDirection";

const STYLE: TextStyle = {
	font: DEFAULT_FONT,
	size: 13.0,
	letterSpacing: 0.0,
	lineSpacing: 0.0,
	maxWidth: 0.0,
	align: Align.Left,
};

test "without -d:voidBidi a Hebrew letter is refused by name with its UTF-16 index" {
	const l = TextLayout.layout("ab\u{5D0}c", STYLE);
	assert !l.ok;
	if (!l.ok) {
		assert l.error.kind == TextErrorKind.RightToLeftNeedsBidi;
		assert l.error.index == 2;
		assert l.error.describe() == "right-to-left text at UTF-16 index 2 needs -d:voidBidi";
	}
}

test "the index counts UTF-16 units, so an astral codepoint before the letter counts two" {
	const l = TextLayout.layout("\u{1F600}\u{627}", STYLE);
	assert !l.ok;
	if (!l.ok) { assert l.error.index == 2; }
}

test "an Arabic letter, a right-to-left mark and a right-to-left isolate are all refused" {
	assert !TextLayout.layout("\u{645}", STYLE).ok;
	assert !TextLayout.layout("a\u{200F}", STYLE).ok;
	assert !TextLayout.layout("a\u{2067}b", STYLE).ok;
	assert !calcTextWidth("\u{5D0}", STYLE).ok;
}

test "text with no possibly right-to-left codepoint is laid out as before" {
	assert TextLayout.layout("abc \u{58F} \u{3042} \u{1F600}", STYLE).ok;
	assert TextLayout.layout("", STYLE).ok;
	assert !possiblyRtl(0x58F) && possiblyRtl(0x590) && possiblyRtl(0x8FF) && !possiblyRtl(0x900);
}

test "a label whose text is refused draws nothing, says why, and recovers on new text" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = s.label("\u{5D0}\u{5D1}", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const status = n.textStatus();
	assert !status.ok;
	if (!status.ok) {
		assert status.error.index == 0;
		assert status.error.kind == TextErrorKind.RightToLeftNeedsBidi;
	}
	assert n.textWidth() == 0.0;
	n.setText("abc");
	assert n.textWidth() > 0.0;
	assert n.textStatus().ok;
	n.dispose();
}
