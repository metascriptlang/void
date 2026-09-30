import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import { textLayout, textWidth, textHeight, calcTextWidth, splitText, getBounds } from "../void2d/render";
import { Align, TextLayout } from "../void2d/textLayout";
import { Bounds2D, rgba, emptyBounds, identity2d } from "../void2d/types";
import {
	DEFAULT_FONT,
	Font,
	FontFeature,
	FontStyle,
	SizeAdjust,
	registerFace,
	resolveFont,
} from "../void2d/font";
import { approx } from "./helpers";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

test "textWidth is the width of the layout the label paints" {
	const n = s.label("fn main() { }", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const direct = TextLayout.layout("fn main() { }", {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	assert approx(n.textWidth(), direct.width);
	assert approx(n.textHeight(), direct.height);
	assert n.textWidth() != Math.floor(n.textWidth());
}

test "a text change is measured without waiting for a frame" {
	const n = s.label("a", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const one = n.textWidth();
	n.setText("aaaa");
	assert n.textWidth() > one * 3.0;
}

test "calcTextWidth and splitText use the label's font, size and wrap width" {
	const n = s.label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const fits = n.calcTextWidth("aa bb");
	n.setMaxWidth(fits);
	assert n.splitText("aa bb cc") == "aa bb\ncc";
	assert approx(n.calcTextWidth("aa bb cc"), TextLayout.layout("aa bb cc", {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	}).width);
}

test "per-glyph x and line boxes come from the same layout" {
	const n = s.label("ab\ncd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const l = n.textLayout();
	assert (l.lines.length as int32) == 2;
	assert approx(l.xForIndex(1), l.glyphs[1].x);
}


test "a label's bounds hold the ink that overhangs its line box" {
	registerFace("assets/font.ttf", "Overhang Sans", 400, FontStyle.Normal);
	const features: FontFeature[] = [];
	const fallbacks: string[] = [];
	const italic: Font = {
		family: "Overhang Sans", weight: 400, style: FontStyle.Italic,
		features: features, fallbacks: fallbacks, sizeAdjust: SizeAdjust.None,
	};
	const resolved = resolveFont(italic);
	assert resolved.ok;
	if (!resolved.ok) { return; }
	const n = s.label("ll", 40.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(resolved.value);
	n.sync(identity2d(), false);
	let b = emptyBounds();
	n.getBounds(b);
	assert b.xMax > n.textWidth() + 1.0;
	assert b.yMin <= 0.0;
	assert b.yMax >= n.textHeight();
}
