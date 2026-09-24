import { label, rect } from "../void2d/node";
import { textLayout, textWidth, textHeight, calcTextWidth, splitText, getBounds } from "../void2d/render";
import { TextLayout } from "../void2d/textLayout";
import { Bounds, rgba, emptyBounds, identity2d } from "../void2d/types";
import { Font, FontFeature, FontStyle, SizeAdjust, registerFace } from "../void2d/font";
import { approx } from "./helpers";

test "textWidth is the width of the layout the label paints" {
	const n = label("fn main() { }", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const direct = TextLayout.layout("fn main() { }", {
		font: 0, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0,
	});
	assert approx(n.textWidth(), direct.width);
	assert approx(n.textHeight(), direct.height);
	assert n.textWidth() != Math.floor(n.textWidth());
}

test "a text change is measured without waiting for a frame" {
	const n = label("a", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const one = n.textWidth();
	n.text = "aaaa";
	n.textDirty = true;
	assert n.textWidth() > one * 3.0;
}

test "calcTextWidth and splitText use the label's font, size and wrap width" {
	const n = label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const fits = n.calcTextWidth("aa bb");
	n.maxWidth = fits;
	assert n.splitText("aa bb cc") == "aa bb\ncc";
	assert approx(n.calcTextWidth("aa bb cc"), TextLayout.layout("aa bb cc", {
		font: 0, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0,
	}).width);
}

test "per-glyph x and line boxes come from the same layout" {
	const n = label("ab\ncd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const l = n.textLayout();
	assert (l.lines.length as int32) == 2;
	assert approx(l.xForByte(1), l.glyphs[1].x);
}

test "text metrics on a node that is not a Label are empty, not a crash" {
	const box = rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
	assert box.textWidth() == 0.0;
}

test "a label's bounds hold the ink that overhangs its line box" {
	registerFace("assets/font.ttf", "Overhang Sans", 400, FontStyle.Normal);
	const features: FontFeature[] = [];
	const fallbacks: string[] = [];
	const italic: Font = {
		family: "Overhang Sans", weight: 400, style: FontStyle.Italic,
		features: features, fallbacks: fallbacks, sizeAdjust: SizeAdjust.None,
	};
	const n = label("ll", 40.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(italic);
	n.sync(identity2d(), false);
	const b = emptyBounds();
	n.getBounds(b);
	assert b.xMax > n.textWidth() + 1.0;
	assert b.yMin <= 0.0;
	assert b.yMax >= n.textHeight();
}
