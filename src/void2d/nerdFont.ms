import { unpackRanges, rangeValue } from "./unicodeRanges";
import {
	NERD_CONSTRAINTS,
	NERD_RANGES_PACKED,
	NERD_SHIFT,
	NerdAlign,
	NerdConstraint,
	NerdHeight,
	NerdSize,
} from "./nerdFontTable";

export struct CellMetrics {
	cell: float32;
	height: float32;
	baseline: float32;
	iconHeight: float32;
	iconHeightSingle: float32;
}

export struct InkBox {
	x: float32;
	y: float32;
	width: float32;
	height: float32;
}

const FIRST_NERD: int32 = 0x23FB;
const LAST_NERD: int32 = 0xF1AF0;

const SYMBOL_FIT: NerdConstraint = {
	size: NerdSize.Fit, alignVertical: NerdAlign.None, alignHorizontal: NerdAlign.None,
	height: NerdHeight.Cell, padTop: 0.0, padLeft: 0.0, padRight: 0.0, padBottom: 0.0,
	relWidth: 1.0, relHeight: 1.0, relX: 0.0, relY: 0.0, maxXyRatio: 0.0, maxConstraintWidth: 2,
};

let nerdRangesCache: uint32[] = new Array(0);

// Ghostty's cell.zig:231-246 (b58ef1d67) with uucode's block and category list
// (build/uucode_config.zig:128-168).
export function isSymbol(codepoint: int32): boolean {
	if (codepoint < 0x2190) { return false; }
	return codepoint <= 0x21FF ||
		(codepoint >= 0x2460 && codepoint <= 0x24FF) ||
		(codepoint >= 0x2600 && codepoint <= 0x27BF) ||
		(codepoint >= 0xE000 && codepoint <= 0xF8FF) ||
		(codepoint >= 0x1F100 && codepoint <= 0x1F1FF) ||
		(codepoint >= 0x1F300 && codepoint <= 0x1F64F) ||
		(codepoint >= 0x1F680 && codepoint <= 0x1F6FF) ||
		(codepoint >= 0xF0000 && codepoint <= 0xFFFFD) ||
		(codepoint >= 0x100000 && codepoint <= 0x10FFFD);
}

// Ghostty's generic.zig:3488-3500: the Nerd Font entry, else `fit` for a symbol, else nothing.
export function cellConstraint(codepoint: int32): NerdConstraint | null {
	if (codepoint >= FIRST_NERD && codepoint <= LAST_NERD) {
		if (nerdRangesCache.length == 0) {
			nerdRangesCache = unpackRanges(NERD_RANGES_PACKED, NERD_SHIFT);
		}
		const index: int32 = rangeValue(nerdRangesCache, NERD_SHIFT, (1 << NERD_SHIFT) - 1, codepoint);
		if (index != 0) { return NERD_CONSTRAINTS[index]; }
	}
	return isSymbol(codepoint) ? SYMBOL_FIT : null;
}

// Void draws one size per glyph, so a stretch is drawn as the fit that keeps its aspect and its
// alignment, with the negative pads Ghostty clamps for it (Glyph.zig:171-178).
export function uniformEquivalent(c: NerdConstraint): NerdConstraint {
	if (c.size != NerdSize.Stretch) { return c; }
	return {
		...c,
		size: NerdSize.Fit,
		maxXyRatio: 0.0,
		padTop: Math.max(0.0, c.padTop),
		padLeft: Math.max(0.0, c.padLeft),
		padRight: Math.max(0.0, c.padRight),
		padBottom: Math.max(0.0, c.padBottom),
	};
}

function targetHeight(c: NerdConstraint, m: CellMetrics, multiCell: boolean): float32 {
	const pad: float32 = 1.0 - (c.padBottom + c.padTop);
	if (c.height == NerdHeight.Cell) { return pad * m.height; }
	return pad * (multiCell ? m.iconHeight : m.iconHeightSingle);
}

// Glyph.zig:273-358 for the sizes that keep the aspect ratio: one factor for both axes.
function scaleFactor(
	c: NerdConstraint, groupWidth: float32, groupHeight: float32, m: CellMetrics, cells: int32,
): float32 {
	if (c.size == NerdSize.None) { return 1.0; }
	const multiCell: boolean = cells > 1;
	const widthFactor: float32 = ((cells as float32) - (c.padLeft + c.padRight)) * m.cell / groupWidth;
	const heightFactor: float32 = targetHeight(c, m, multiCell) / groupHeight;
	const fits: float32 = Math.min(widthFactor, heightFactor);
	if (c.size == NerdSize.Fit) { return Math.min(1.0, fits); }
	if (c.size == NerdSize.Cover) { return fits; }
	if (multiCell && fits > 1.0) {
		return Math.max(1.0, scaleFactor(c, groupWidth, groupHeight, m, 1));
	}
	return fits;
}

function alignedY(c: NerdConstraint, groupY: float32, groupHeight: float32, m: CellMetrics): float32 {
	if (c.size == NerdSize.None && c.alignVertical == NerdAlign.None) { return groupY; }
	const start: float32 = c.padBottom * m.height;
	const end: float32 = m.height - groupHeight - c.padTop * m.height;
	const middle: float32 = (start + end) / 2.0;
	if (c.alignVertical == NerdAlign.Start) { return start; }
	if (c.alignVertical == NerdAlign.End) { return end; }
	if (c.alignVertical == NerdAlign.None) {
		return end < start ? middle : Math.max(start, Math.min(groupY, end));
	}
	return middle;
}

function alignedX(
	c: NerdConstraint, groupX: float32, groupWidth: float32, m: CellMetrics, cells: int32,
): float32 {
	if (c.size == NerdSize.None && c.alignHorizontal == NerdAlign.None) { return groupX; }
	const start: float32 = c.padLeft * m.cell;
	const end: float32 = (cells as float32) * m.cell - groupWidth - c.padRight * m.cell;
	if (c.alignHorizontal == NerdAlign.Start) { return start; }
	if (c.alignHorizontal == NerdAlign.End) { return Math.max(start, end); }
	if (c.alignHorizontal == NerdAlign.Center) { return Math.max(start, (start + end) / 2.0); }
	if (c.alignHorizontal == NerdAlign.Center1) {
		const first: float32 = m.cell - groupWidth - c.padRight * m.cell;
		return Math.max(start, (start + first) / 2.0);
	}
	return Math.max(start, Math.min(groupX, end));
}

// Ghostty's Glyph.zig:195-261 `constrainInner` over a cell of `m.cell` by `m.height`, whose face
// and cell boxes are one, so `face_y` is 0. `glyph` is the ink box in y-up from the cell's bottom.
export function constrainInk(
	c: NerdConstraint, glyph: InkBox, m: CellMetrics, constraintWidth: int32,
): InkBox {
	const cells: int32 = Math.min(c.maxConstraintWidth, constraintWidth);
	const groupWidth: float32 = glyph.width / c.relWidth;
	const groupHeight: float32 = glyph.height / c.relHeight;
	const groupX: float32 = glyph.x - groupWidth * c.relX;
	const groupY: float32 = glyph.y - groupHeight * c.relY;
	const k: float32 = scaleFactor(c, groupWidth, groupHeight, m, cells);
	const width: float32 = groupWidth * k;
	const height: float32 = groupHeight * k;
	const x: float32 = alignedX(c, groupX + (groupWidth - width) / 2.0, width, m, cells);
	const y: float32 = alignedY(c, groupY + (groupHeight - height) / 2.0, height, m);
	return { x: x + width * c.relX, y: y + height * c.relY, width: k * glyph.width, height: k * glyph.height };
}
