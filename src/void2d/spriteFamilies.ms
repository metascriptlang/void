import {
	Painter,
	Pt,
	fillBox,
	fillFractions,
	fillPolygon,
	fillTriangle,
	flipHorizontal,
	insetTriangleRing,
	minDouble,
	offsetSide,
	pathAdd,
	pathCubic,
	pathReset,
	strokeLine,
	strokePath,
	subSat,
} from "./spriteDraw";
import { truncInt } from "./trueType/fontInfo";

enum Align {
	Left,
	Right,
	Upper,
	Lower,
}

enum Corner {
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

const LINE_NONE: int32 = 0;
const LINE_LIGHT: int32 = 1;
const LINE_HEAVY: int32 = 2;
const LINE_DOUBLE: int32 = 3;

const BOX_LINES: uint8[] = [
	0, 1, 0, 1, 0, 2, 0, 2, 1, 0, 1, 0, 2, 0, 2, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 1, 1, 0, 0, 2, 1, 0, 0, 1, 2, 0, 0, 2, 2, 0,
	0, 0, 1, 1, 0, 0, 1, 2, 0, 0, 2, 1, 0, 0, 2, 2,
	1, 1, 0, 0, 1, 2, 0, 0, 2, 1, 0, 0, 2, 2, 0, 0,
	1, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 1, 2, 0, 0, 2,
	1, 1, 1, 0, 1, 2, 1, 0, 2, 1, 1, 0, 1, 1, 2, 0,
	2, 1, 2, 0, 2, 2, 1, 0, 1, 2, 2, 0, 2, 2, 2, 0,
	1, 0, 1, 1, 1, 0, 1, 2, 2, 0, 1, 1, 1, 0, 2, 1,
	2, 0, 2, 1, 2, 0, 1, 2, 1, 0, 2, 2, 2, 0, 2, 2,
	0, 1, 1, 1, 0, 1, 1, 2, 0, 2, 1, 1, 0, 2, 1, 2,
	0, 1, 2, 1, 0, 1, 2, 2, 0, 2, 2, 1, 0, 2, 2, 2,
	1, 1, 0, 1, 1, 1, 0, 2, 1, 2, 0, 1, 1, 2, 0, 2,
	2, 1, 0, 1, 2, 1, 0, 2, 2, 2, 0, 1, 2, 2, 0, 2,
	1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 2, 1, 2,
	2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 2, 1, 2, 1, 1, 2,
	2, 2, 1, 1, 1, 1, 2, 2, 1, 2, 2, 1, 2, 2, 1, 2,
	1, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 3, 0, 3, 3, 0, 3, 0, 0, 3, 1, 0, 0, 1, 3, 0,
	0, 3, 3, 0, 0, 0, 1, 3, 0, 0, 3, 1, 0, 0, 3, 3,
	1, 3, 0, 0, 3, 1, 0, 0, 3, 3, 0, 0, 1, 0, 0, 3,
	3, 0, 0, 1, 3, 0, 0, 3, 1, 3, 1, 0, 3, 1, 3, 0,
	3, 3, 3, 0, 1, 0, 1, 3, 3, 0, 3, 1, 3, 0, 3, 3,
	0, 3, 1, 3, 0, 1, 3, 1, 0, 3, 3, 3, 1, 3, 0, 3,
	3, 1, 0, 1, 3, 3, 0, 3, 1, 3, 1, 3, 3, 1, 3, 1,
	3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0,
	0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0,
	0, 2, 0, 1, 1, 0, 2, 0, 0, 1, 0, 2, 2, 0, 1, 0,
];

const OCTANTS: uint8[] = [
	0x04, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x12,
	0x13, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
	0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2A, 0x2B, 0x2C,
	0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
	0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
	0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x51, 0x52, 0x53,
	0x54, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5D, 0x5E, 0x60, 0x61, 0x62,
	0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E,
	0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
	0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
	0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x91, 0x92, 0x93,
	0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
	0xA1, 0xA2, 0xA3, 0xA4, 0xA6, 0xA7, 0xA8, 0xA9, 0xAB, 0xAC, 0xAD, 0xAE,
	0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB,
	0xBC, 0xBD, 0xBE, 0xBF, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8,
	0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4,
	0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0,
	0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC,
	0xED, 0xEE, 0xEF, 0xF1, 0xF2, 0xF3, 0xF4, 0xF6, 0xF7, 0xF8, 0xF9, 0xFB,
	0xFD, 0xFE,
];

function pt(x: float64, y: float64): Pt {
	return { x: x, y: y };
}

function stopOnUndrawn(range: string, codepoint: int32): never {
	console.error(
		`void2d sprite: code point ${codepoint} is in the ${range} range but has no drawing`,
	);
	unreachable;
}

function blockShade(
	p: Painter, horizontal: Align, vertical: Align,
	widthFraction: float64, heightFraction: float64, shade: uint8,
): void {
	const w: int32 = truncInt(Math.round((p.cellWidth as float64) * widthFraction));
	const h: int32 = truncInt(Math.round((p.cellHeight as float64) * heightFraction));
	const x: int32 = horizontal == Align.Right ? p.cellWidth - w : 0;
	const y: int32 = vertical == Align.Lower ? p.cellHeight - h : 0;
	fillBox(p, x, y, x + w, y + h, shade);
}

function quadrants(
	p: Painter, topLeft: boolean, topRight: boolean, bottomLeft: boolean, bottomRight: boolean,
): void {
	if (topLeft) { fillFractions(p, 0.0, 0.5, 0.0, 0.5); }
	if (topRight) { fillFractions(p, 0.5, 1.0, 0.0, 0.5); }
	if (bottomLeft) { fillFractions(p, 0.0, 0.5, 0.5, 1.0); }
	if (bottomRight) { fillFractions(p, 0.5, 1.0, 0.5, 1.0); }
}

export function drawBlock(codepoint: int32, p: Painter): void {
	const eighth: float64 = 0.125;
	const quarter: float64 = 0.25;
	const threeEighths: float64 = 0.375;
	const half: float64 = 0.5;
	const fiveEighths: float64 = 0.625;
	const threeQuarters: float64 = 0.75;
	const sevenEighths: float64 = 0.875;
	const cw: int32 = p.cellWidth;
	const ch: int32 = p.cellHeight;
	match (codepoint) {
		0x2580 => { blockShade(p, Align.Left, Align.Upper, 1.0, half, 255); },
		0x2581 => { blockShade(p, Align.Left, Align.Lower, 1.0, eighth, 255); },
		0x2582 => { blockShade(p, Align.Left, Align.Lower, 1.0, quarter, 255); },
		0x2583 => { blockShade(p, Align.Left, Align.Lower, 1.0, threeEighths, 255); },
		0x2584 => { blockShade(p, Align.Left, Align.Lower, 1.0, half, 255); },
		0x2585 => { blockShade(p, Align.Left, Align.Lower, 1.0, fiveEighths, 255); },
		0x2586 => { blockShade(p, Align.Left, Align.Lower, 1.0, threeQuarters, 255); },
		0x2587 => { blockShade(p, Align.Left, Align.Lower, 1.0, sevenEighths, 255); },
		0x2588 => { fillBox(p, 0, 0, cw, ch, 255); },
		0x2589 => { blockShade(p, Align.Left, Align.Upper, sevenEighths, 1.0, 255); },
		0x258A => { blockShade(p, Align.Left, Align.Upper, threeQuarters, 1.0, 255); },
		0x258B => { blockShade(p, Align.Left, Align.Upper, fiveEighths, 1.0, 255); },
		0x258C => { blockShade(p, Align.Left, Align.Upper, half, 1.0, 255); },
		0x258D => { blockShade(p, Align.Left, Align.Upper, threeEighths, 1.0, 255); },
		0x258E => { blockShade(p, Align.Left, Align.Upper, quarter, 1.0, 255); },
		0x258F => { blockShade(p, Align.Left, Align.Upper, eighth, 1.0, 255); },
		0x2590 => { blockShade(p, Align.Right, Align.Upper, half, 1.0, 255); },
		0x2591 => { fillBox(p, 0, 0, cw, ch, 0x40); },
		0x2592 => { fillBox(p, 0, 0, cw, ch, 0x80); },
		0x2593 => { fillBox(p, 0, 0, cw, ch, 0xC0); },
		0x2594 => { blockShade(p, Align.Left, Align.Upper, 1.0, eighth, 255); },
		0x2595 => { blockShade(p, Align.Right, Align.Upper, eighth, 1.0, 255); },
		0x2596 => { quadrants(p, false, false, true, false); },
		0x2597 => { quadrants(p, false, false, false, true); },
		0x2598 => { quadrants(p, true, false, false, false); },
		0x2599 => { quadrants(p, true, false, true, true); },
		0x259A => { quadrants(p, true, false, false, true); },
		0x259B => { quadrants(p, true, true, true, false); },
		0x259C => { quadrants(p, true, true, false, true); },
		0x259D => { quadrants(p, false, true, false, false); },
		0x259E => { quadrants(p, false, true, true, false); },
		0x259F => { quadrants(p, false, true, true, true); },
		_ => { stopOnUndrawn("block", codepoint); },
	}
}

function diagonalUpperRightToLowerLeft(p: Painter): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	const slopeX: float64 = minDouble(1.0, w / h);
	const slopeY: float64 = minDouble(1.0, h / w);
	const a: Pt = pt(w + 0.5 * slopeX, -0.5 * slopeY);
	const b: Pt = pt(-0.5 * slopeX, h + 0.5 * slopeY);
	strokeLine(p, a, b, p.boxThickness as float64);
}

function diagonalUpperLeftToLowerRight(p: Painter): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	const slopeX: float64 = minDouble(1.0, w / h);
	const slopeY: float64 = minDouble(1.0, h / w);
	const a: Pt = pt(-0.5 * slopeX, -0.5 * slopeY);
	const b: Pt = pt(w + 0.5 * slopeX, h + 0.5 * slopeY);
	strokeLine(p, a, b, p.boxThickness as float64);
}

function cornerPoints(p: Painter, corner: Corner): Pt[] {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	return match (corner) {
		Corner.TopLeft => [pt(0.0, 0.0), pt(0.0, h), pt(w, 0.0)],
		Corner.TopRight => [pt(0.0, 0.0), pt(w, h), pt(w, 0.0)],
		Corner.BottomLeft => [pt(0.0, 0.0), pt(0.0, h), pt(w, h)],
		Corner.BottomRight => [pt(0.0, h), pt(w, h), pt(w, 0.0)],
	};
}

function cornerTriangle(p: Painter, corner: Corner): void {
	const t: Pt[] = cornerPoints(p, corner);
	fillTriangle(p, t[0], t[1], t[2]);
}

function cornerTriangleOutline(p: Painter, corner: Corner): void {
	const t: Pt[] = cornerPoints(p, corner);
	insetTriangleRing(p, t[0], t[1], t[2], p.boxThickness as float64);
}

function drawArc(p: Painter, corner: Corner): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	const t: float64 = p.boxThickness as float64;
	const centerX: float64 = (subSat(p.cellWidth, p.boxThickness) / 2) as float64 + t / 2.0;
	const centerY: float64 = (subSat(p.cellHeight, p.boxThickness) / 2) as float64 + t / 2.0;
	const r: float64 = minDouble(w, h) / 2.0;
	const s: float64 = 0.25;
	const signX: float64 = (corner == Corner.TopLeft || corner == Corner.BottomLeft) ? -1.0 : 1.0;
	const signY: float64 = (corner == Corner.TopLeft || corner == Corner.TopRight) ? -1.0 : 1.0;
	const startY: float64 = signY < 0.0 ? 0.0 : h;
	const endX: float64 = signX < 0.0 ? 0.0 : w;
	pathReset(p.flat);
	pathAdd(p.flat, centerX, startY);
	const p0: Pt = pt(centerX, centerY + signY * r);
	pathAdd(p.flat, p0.x, p0.y);
	const p1: Pt = pt(centerX, centerY + signY * s * r);
	const p2: Pt = pt(centerX + signX * s * r, centerY);
	const p3: Pt = pt(centerX + signX * r, centerY);
	pathCubic(p.flat, p0, p1, p2, p3);
	if ((endX - p3.x) * signX > 0.0) { pathAdd(p.flat, endX, centerY); }
	strokePath(p, p.flat, t, 255);
}

function powerlineRound(p: Painter, stroked: boolean): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	const k: float64 = (1.4142135623730951 - 1.0) * 4.0 / 3.0;
	const r: float64 = minDouble(w, h / 2.0);
	pathReset(p.flat);
	pathAdd(p.flat, 0.0, 0.0);
	if (stroked) { pathAdd(p.flat, 1.0, 0.0); }
	const a0: Pt = pt(stroked ? 1.0 : 0.0, 0.0);
	pathCubic(p.flat, a0, pt(r * k, 0.0), pt(r, r - r * k), pt(r, r));
	pathAdd(p.flat, r, h - r);
	const b0: Pt = pt(r, h - r);
	const b3: Pt = pt(stroked ? 1.0 : 0.0, h);
	pathCubic(p.flat, b0, pt(r, h - r + r * k), pt(r * k, h), b3);
	if (stroked) { pathAdd(p.flat, 0.0, h); }
	if (!stroked) {
		fillPolygon(p, p.flat.xy, p.flat.n, 255);
		return;
	}
	const t: float64 = p.boxThickness as float64;
	offsetSide(p.flat, t / 2.0, p.inset);
	strokePath(p, p.inset, t, 255);
}

function powerlineChevron(p: Painter): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	pathReset(p.flat);
	pathAdd(p.flat, 0.0, 0.0);
	pathAdd(p.flat, w, h / 2.0);
	pathAdd(p.flat, 0.0, h);
	strokePath(p, p.flat, p.boxThickness as float64, 255);
}

function powerlineDouble(p: Painter): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	const t: float64 = p.boxThickness as float64;
	const top: float64[] = [
		0.0, 0.0, w, 0.0, w / 2.0, h / 2.0 - t / 2.0, 0.0, h / 2.0 - t / 2.0,
	];
	const bottom: float64[] = [
		0.0, h, w, h, w / 2.0, h / 2.0 + t / 2.0, 0.0, h / 2.0 + t / 2.0,
	];
	fillPolygon(p, top, 4, 255);
	fillPolygon(p, bottom, 4, 255);
}

export function drawPowerline(codepoint: int32, p: Painter): void {
	const w: float64 = p.cellWidth as float64;
	const h: float64 = p.cellHeight as float64;
	match (codepoint) {
		0xE0B0 => { fillTriangle(p, pt(0.0, 0.0), pt(w, h / 2.0), pt(0.0, h)); },
		0xE0B1 => { powerlineChevron(p); },
		0xE0B2 => { fillTriangle(p, pt(w, 0.0), pt(0.0, h / 2.0), pt(w, h)); },
		0xE0B3 => {
			powerlineChevron(p);
			flipHorizontal(p);
		},
		0xE0B4 => { powerlineRound(p, false); },
		0xE0B5 => { powerlineRound(p, true); },
		0xE0B6 => {
			powerlineRound(p, false);
			flipHorizontal(p);
		},
		0xE0B7 => {
			powerlineRound(p, true);
			flipHorizontal(p);
		},
		0xE0B8 => { fillTriangle(p, pt(0.0, 0.0), pt(w, h), pt(0.0, h)); },
		0xE0B9 => { diagonalUpperLeftToLowerRight(p); },
		0xE0BA => { fillTriangle(p, pt(w, 0.0), pt(w, h), pt(0.0, h)); },
		0xE0BB => { diagonalUpperRightToLowerLeft(p); },
		0xE0BC => { fillTriangle(p, pt(0.0, 0.0), pt(w, 0.0), pt(0.0, h)); },
		0xE0BD => { diagonalUpperRightToLowerLeft(p); },
		0xE0BE => { fillTriangle(p, pt(0.0, 0.0), pt(w, 0.0), pt(w, h)); },
		0xE0BF => { diagonalUpperLeftToLowerRight(p); },
		0xE0D2 => { powerlineDouble(p); },
		0xE0D4 => {
			powerlineDouble(p);
			flipHorizontal(p);
		},
		_ => { stopOnUndrawn("powerline", codepoint); },
	}
}

export function drawGeometric(codepoint: int32, p: Painter): void {
	match (codepoint) {
		0x25E2 => { cornerTriangle(p, Corner.BottomRight); },
		0x25E3 => { cornerTriangle(p, Corner.BottomLeft); },
		0x25E4 => { cornerTriangle(p, Corner.TopLeft); },
		0x25E5 => { cornerTriangle(p, Corner.TopRight); },
		0x25F8 => { cornerTriangleOutline(p, Corner.TopLeft); },
		0x25F9 => { cornerTriangleOutline(p, Corner.TopRight); },
		0x25FA => { cornerTriangleOutline(p, Corner.BottomLeft); },
		0x25FF => { cornerTriangleOutline(p, Corner.BottomRight); },
		_ => { stopOnUndrawn("geometric", codepoint); },
	}
}

function drawLines(p: Painter, up: int32, right: int32, down: int32, left: int32): void {
	const lightPx: int32 = p.boxThickness;
	const heavyPx: int32 = p.boxThickness * 2;
	const hLightTop: int32 = subSat(p.cellHeight, lightPx) / 2;
	const hLightBottom: int32 = hLightTop + lightPx;
	const hHeavyTop: int32 = subSat(p.cellHeight, heavyPx) / 2;
	const hHeavyBottom: int32 = hHeavyTop + heavyPx;
	const hDoubleTop: int32 = subSat(hLightTop, lightPx);
	const hDoubleBottom: int32 = hLightBottom + lightPx;
	const vLightLeft: int32 = subSat(p.cellWidth, lightPx) / 2;
	const vLightRight: int32 = vLightLeft + lightPx;
	const vHeavyLeft: int32 = subSat(p.cellWidth, heavyPx) / 2;
	const vHeavyRight: int32 = vHeavyLeft + heavyPx;
	const vDoubleLeft: int32 = subSat(vLightLeft, lightPx);
	const vDoubleRight: int32 = vLightRight + lightPx;
	const cw: int32 = p.cellWidth;
	const ch: int32 = p.cellHeight;

	let upBottom: int32;
	if (left == LINE_HEAVY || right == LINE_HEAVY) {
		upBottom = hHeavyBottom;
	} else if (left != right || down == up) {
		upBottom = (left == LINE_DOUBLE || right == LINE_DOUBLE) ? hDoubleBottom : hLightBottom;
	} else if (left == LINE_NONE && right == LINE_NONE) {
		upBottom = hLightBottom;
	} else {
		upBottom = hLightTop;
	}

	let downTop: int32;
	if (left == LINE_HEAVY || right == LINE_HEAVY) {
		downTop = hHeavyTop;
	} else if (left != right || up == down) {
		downTop = (left == LINE_DOUBLE || right == LINE_DOUBLE) ? hDoubleTop : hLightTop;
	} else if (left == LINE_NONE && right == LINE_NONE) {
		downTop = hLightTop;
	} else {
		downTop = hLightBottom;
	}

	let leftRight: int32;
	if (up == LINE_HEAVY || down == LINE_HEAVY) {
		leftRight = vHeavyRight;
	} else if (up != down || left == right) {
		leftRight = (up == LINE_DOUBLE || down == LINE_DOUBLE) ? vDoubleRight : vLightRight;
	} else if (up == LINE_NONE && down == LINE_NONE) {
		leftRight = vLightRight;
	} else {
		leftRight = vLightLeft;
	}

	let rightLeft: int32;
	if (up == LINE_HEAVY || down == LINE_HEAVY) {
		rightLeft = vHeavyLeft;
	} else if (up != down || right == left) {
		rightLeft = (up == LINE_DOUBLE || down == LINE_DOUBLE) ? vDoubleLeft : vLightLeft;
	} else if (up == LINE_NONE && down == LINE_NONE) {
		rightLeft = vLightLeft;
	} else {
		rightLeft = vLightRight;
	}

	if (up == LINE_LIGHT) {
		fillBox(p, vLightLeft, 0, vLightRight, upBottom, 255);
	} else if (up == LINE_HEAVY) {
		fillBox(p, vHeavyLeft, 0, vHeavyRight, upBottom, 255);
	} else if (up == LINE_DOUBLE) {
		const leftBottom: int32 = left == LINE_DOUBLE ? hLightTop : upBottom;
		const rightBottom: int32 = right == LINE_DOUBLE ? hLightTop : upBottom;
		fillBox(p, vDoubleLeft, 0, vLightLeft, leftBottom, 255);
		fillBox(p, vLightRight, 0, vDoubleRight, rightBottom, 255);
	}

	if (right == LINE_LIGHT) {
		fillBox(p, rightLeft, hLightTop, cw, hLightBottom, 255);
	} else if (right == LINE_HEAVY) {
		fillBox(p, rightLeft, hHeavyTop, cw, hHeavyBottom, 255);
	} else if (right == LINE_DOUBLE) {
		const topLeft: int32 = up == LINE_DOUBLE ? vLightRight : rightLeft;
		const bottomLeft: int32 = down == LINE_DOUBLE ? vLightRight : rightLeft;
		fillBox(p, topLeft, hDoubleTop, cw, hLightTop, 255);
		fillBox(p, bottomLeft, hLightBottom, cw, hDoubleBottom, 255);
	}

	if (down == LINE_LIGHT) {
		fillBox(p, vLightLeft, downTop, vLightRight, ch, 255);
	} else if (down == LINE_HEAVY) {
		fillBox(p, vHeavyLeft, downTop, vHeavyRight, ch, 255);
	} else if (down == LINE_DOUBLE) {
		const leftTop: int32 = left == LINE_DOUBLE ? hLightBottom : downTop;
		const rightTop: int32 = right == LINE_DOUBLE ? hLightBottom : downTop;
		fillBox(p, vDoubleLeft, leftTop, vLightLeft, ch, 255);
		fillBox(p, vLightRight, rightTop, vDoubleRight, ch, 255);
	}

	if (left == LINE_LIGHT) {
		fillBox(p, 0, hLightTop, leftRight, hLightBottom, 255);
	} else if (left == LINE_HEAVY) {
		fillBox(p, 0, hHeavyTop, leftRight, hHeavyBottom, 255);
	} else if (left == LINE_DOUBLE) {
		const topRight: int32 = up == LINE_DOUBLE ? vLightLeft : leftRight;
		const bottomRight: int32 = down == LINE_DOUBLE ? vLightLeft : leftRight;
		fillBox(p, 0, hDoubleTop, topRight, hLightTop, 255);
		fillBox(p, 0, hLightBottom, bottomRight, hDoubleBottom, 255);
	}
}

function drawDashHorizontal(p: Painter, count: int32, thickPx: int32, desiredGap: int32): void {
	const gapCount: int32 = count;
	if (p.cellWidth < count + gapCount) {
		const y: int32 = subSat(p.cellHeight, p.boxThickness) / 2;
		fillBox(p, 0, y, p.cellWidth, y + p.boxThickness, 255);
		return;
	}
	const cap: int32 = p.cellWidth / (2 * count);
	const gapWidth: int32 = desiredGap < cap ? desiredGap : cap;
	const totalDash: int32 = p.cellWidth - gapCount * gapWidth;
	const dashWidth: int32 = totalDash / count;
	let extra: int32 = totalDash % count;
	const y: int32 = subSat(p.cellHeight, thickPx) / 2;
	let x: int32 = gapWidth / 2;
	for (let i: int32 = 0; i < count; i++) {
		let x1: int32 = x + dashWidth;
		if (extra > 0) {
			extra--;
			x1++;
		}
		fillBox(p, x, y, x1, y + thickPx, 255);
		x = x1 + gapWidth;
	}
}

function drawDashVertical(p: Painter, count: int32, thickPx: int32, desiredGap: int32): void {
	const gapCount: int32 = count;
	if (p.cellHeight < count + gapCount) {
		const x: int32 = subSat(p.cellWidth, p.boxThickness) / 2;
		fillBox(p, x, 0, x + p.boxThickness, p.cellHeight, 255);
		return;
	}
	const cap: int32 = p.cellHeight / (2 * count);
	const gapHeight: int32 = desiredGap < cap ? desiredGap : cap;
	const totalDash: int32 = p.cellHeight - gapCount * gapHeight;
	const dashHeight: int32 = totalDash / count;
	let extra: int32 = totalDash % count;
	const x: int32 = subSat(p.cellWidth, thickPx) / 2;
	let y: int32 = 0;
	for (let i: int32 = 0; i < count; i++) {
		let y1: int32 = y + dashHeight;
		if (extra > 0) {
			extra--;
			y1++;
		}
		fillBox(p, x, y, x + thickPx, y1, 255);
		y = y1 + gapHeight;
	}
}

function drawDash(codepoint: int32, p: Painter): boolean {
	const light: int32 = p.boxThickness;
	const heavy: int32 = p.boxThickness * 2;
	const wide: int32 = light > 4 ? light : 4;
	match (codepoint) {
		0x2504 => { drawDashHorizontal(p, 3, light, wide); },
		0x2505 => { drawDashHorizontal(p, 3, heavy, wide); },
		0x2506 => { drawDashVertical(p, 3, light, wide); },
		0x2507 => { drawDashVertical(p, 3, heavy, wide); },
		0x2508 => { drawDashHorizontal(p, 4, light, wide); },
		0x2509 => { drawDashHorizontal(p, 4, heavy, wide); },
		0x250A => { drawDashVertical(p, 4, light, wide); },
		0x250B => { drawDashVertical(p, 4, heavy, wide); },
		0x254C => { drawDashHorizontal(p, 2, light, light); },
		0x254D => { drawDashHorizontal(p, 2, heavy, heavy); },
		0x254E => { drawDashVertical(p, 2, light, heavy); },
		0x254F => { drawDashVertical(p, 2, heavy, heavy); },
		_ => { return false; },
	}
	return true;
}

function drawCurved(codepoint: int32, p: Painter): boolean {
	match (codepoint) {
		0x256D => { drawArc(p, Corner.BottomRight); },
		0x256E => { drawArc(p, Corner.BottomLeft); },
		0x256F => { drawArc(p, Corner.TopLeft); },
		0x2570 => { drawArc(p, Corner.TopRight); },
		0x2571 => { diagonalUpperRightToLowerLeft(p); },
		0x2572 => { diagonalUpperLeftToLowerRight(p); },
		0x2573 => {
			diagonalUpperRightToLowerLeft(p);
			diagonalUpperLeftToLowerRight(p);
		},
		_ => { return false; },
	}
	return true;
}

export function drawBox(codepoint: int32, p: Painter): void {
	if (drawDash(codepoint, p) || drawCurved(codepoint, p)) { return; }
	const at: int32 = (codepoint - 0x2500) * 4;
	const up: int32 = BOX_LINES[at] as int32;
	const right: int32 = BOX_LINES[at + 1] as int32;
	const down: int32 = BOX_LINES[at + 2] as int32;
	const left: int32 = BOX_LINES[at + 3] as int32;
	if (up == 0 && right == 0 && down == 0 && left == 0) { stopOnUndrawn("box", codepoint); }
	drawLines(p, up, right, down, left);
}

// False when the cell cannot hold the eight dots with their margins.
export function drawBraille(codepoint: int32, p: Painter): boolean {
	const width: int32 = p.cellWidth;
	const height: int32 = p.cellHeight;
	const quarterWidth: int32 = width / 4;
	const eighthHeight: int32 = height / 8;
	let w: int32 = quarterWidth < eighthHeight ? quarterWidth : eighthHeight;
	let xSpacing: int32 = quarterWidth;
	let ySpacing: int32 = eighthHeight;
	let xMargin: int32 = xSpacing / 2;
	let yMargin: int32 = ySpacing / 2;
	let xLeft: int32 = width - 2 * xMargin - xSpacing - 2 * w;
	let yLeft: int32 = height - 2 * yMargin - 3 * ySpacing - 4 * w;
	if (xLeft >= 2 && yLeft >= 4 && w == 0) {
		w += 1;
		xLeft -= 2;
		yLeft -= 4;
	}
	if (xLeft >= 2 && xMargin == 0) {
		xMargin = 1;
		xLeft -= 2;
	}
	if (yLeft >= 2 && yMargin == 0) {
		yMargin = 1;
		yLeft -= 2;
	}
	if (xLeft >= 1) {
		xSpacing += 1;
		xLeft -= 1;
	}
	if (yLeft >= 3) {
		ySpacing += 1;
		yLeft -= 3;
	}
	if (xLeft >= 2) {
		xMargin += 1;
		xLeft -= 2;
	}
	if (yLeft >= 2) {
		yMargin += 1;
		yLeft -= 2;
	}
	if (xLeft >= 2 && yLeft >= 4) {
		w += 1;
		xLeft -= 2;
		yLeft -= 4;
	}
	if (!(xLeft <= 1 || yLeft <= 1) || 2 * xMargin + 2 * w + xSpacing > width ||
		2 * yMargin + 4 * w + 3 * ySpacing > height) {
		return false;
	}
	const x: int32[] = [xMargin, xMargin + w + xSpacing];
	const y0: int32 = yMargin;
	const y1: int32 = y0 + w + ySpacing;
	const y2: int32 = y1 + w + ySpacing;
	const y3: int32 = y2 + w + ySpacing;
	const y: int32[] = [y0, y1, y2, y3];
	const pattern: int32 = codepoint & 0xFF;
	const column: int32[] = [0, 0, 0, 1, 1, 1, 0, 1];
	const row: int32[] = [0, 1, 2, 0, 1, 2, 3, 3];
	for (let bit: int32 = 0; bit < 8; bit++) {
		if (((pattern >> bit) & 1) != 0) {
			const cx: int32 = x[column[bit]];
			const cy: int32 = y[row[bit]];
			fillBox(p, cx, cy, cx + w, cy + w, 255);
		}
	}
	return true;
}

export function drawSextant(codepoint: int32, p: Painter): void {
	const index: int32 = codepoint - 0x1FB00;
	const bits: int32 = index + index / 0x14 + 1;
	const third: float64 = 1.0 / 3.0;
	const twoThirds: float64 = 2.0 / 3.0;
	if ((bits & 1) != 0) { fillFractions(p, 0.0, 0.5, 0.0, third); }
	if ((bits & 2) != 0) { fillFractions(p, 0.5, 1.0, 0.0, third); }
	if ((bits & 4) != 0) { fillFractions(p, 0.0, 0.5, third, twoThirds); }
	if ((bits & 8) != 0) { fillFractions(p, 0.5, 1.0, third, twoThirds); }
	if ((bits & 16) != 0) { fillFractions(p, 0.0, 0.5, twoThirds, 1.0); }
	if ((bits & 32) != 0) { fillFractions(p, 0.5, 1.0, twoThirds, 1.0); }
}

export function drawOctant(codepoint: int32, p: Painter): void {
	const bits: int32 = OCTANTS[codepoint - 0x1CD00] as int32;
	for (let bit: int32 = 0; bit < 8; bit++) {
		if (((bits >> bit) & 1) == 0) { continue; }
		const left: float64 = (bit & 1) != 0 ? 0.5 : 0.0;
		const right: float64 = (bit & 1) != 0 ? 1.0 : 0.5;
		const top: float64 = ((bit >> 1) as float64) * 0.25;
		fillFractions(p, left, right, top, top + 0.25);
	}
}

function scaledBy(size: int32, numerator: int32, denominator: int32): int32 {
	return (((size as int64) * (numerator as int64)) / (denominator as int64)) as int32;
}

function checkerboard(p: Painter, parity: int32): void {
	const xSize: int32 = 4;
	const ySize: int32 = truncInt(
		Math.round(4.0 * ((p.cellHeight as float64) / (p.cellWidth as float64))),
	);
	for (let x: int32 = 0; x < xSize; x++) {
		const x0: int32 = scaledBy(p.cellWidth, x, xSize);
		const x1: int32 = scaledBy(p.cellWidth, x + 1, xSize);
		for (let y: int32 = 0; y < ySize; y++) {
			const y0: int32 = scaledBy(p.cellHeight, y, ySize);
			const y1: int32 = scaledBy(p.cellHeight, y + 1, ySize);
			if ((x + y) % 2 == parity) { fillBox(p, x0, y0, x1, y1, 255); }
		}
	}
}

export function drawLegacyBlock(codepoint: int32, p: Painter): void {
	const eighth: float64 = 0.125;
	const quarter: float64 = 0.25;
	const threeEighths: float64 = 0.375;
	const half: float64 = 0.5;
	const fiveEighths: float64 = 0.625;
	const threeQuarters: float64 = 0.75;
	const sevenEighths: float64 = 0.875;
	const cw: int32 = p.cellWidth;
	const ch: int32 = p.cellHeight;
	if (codepoint >= 0x1FB70 && codepoint <= 0x1FB75) {
		const n: float64 = (codepoint + 1 - 0x1FB70) as float64;
		fillFractions(p, n / 8.0, (n + 1.0) / 8.0, 0.0, 1.0);
		return;
	}
	if (codepoint >= 0x1FB76 && codepoint <= 0x1FB7B) {
		const n: float64 = (codepoint + 1 - 0x1FB76) as float64;
		fillFractions(p, 0.0, 1.0, n / 8.0, (n + 1.0) / 8.0);
		return;
	}
	match (codepoint) {
		0x1FB7C => {
			blockShade(p, Align.Left, Align.Upper, eighth, 1.0, 255);
			blockShade(p, Align.Left, Align.Lower, 1.0, eighth, 255);
		},
		0x1FB7D => {
			blockShade(p, Align.Left, Align.Upper, eighth, 1.0, 255);
			blockShade(p, Align.Left, Align.Upper, 1.0, eighth, 255);
		},
		0x1FB7E => {
			blockShade(p, Align.Right, Align.Upper, eighth, 1.0, 255);
			blockShade(p, Align.Left, Align.Upper, 1.0, eighth, 255);
		},
		0x1FB7F => {
			blockShade(p, Align.Right, Align.Upper, eighth, 1.0, 255);
			blockShade(p, Align.Left, Align.Lower, 1.0, eighth, 255);
		},
		0x1FB80 => {
			blockShade(p, Align.Left, Align.Upper, 1.0, eighth, 255);
			blockShade(p, Align.Left, Align.Lower, 1.0, eighth, 255);
		},
		0x1FB81 => {
			fillFractions(p, 0.0, 1.0, 0.0, eighth);
			fillFractions(p, 0.0, 1.0, 2.0 / 8.0, 3.0 / 8.0);
			fillFractions(p, 0.0, 1.0, 4.0 / 8.0, 5.0 / 8.0);
			fillFractions(p, 0.0, 1.0, 7.0 / 8.0, 1.0);
		},
		0x1FB82 => { blockShade(p, Align.Left, Align.Upper, 1.0, quarter, 255); },
		0x1FB83 => { blockShade(p, Align.Left, Align.Upper, 1.0, threeEighths, 255); },
		0x1FB84 => { blockShade(p, Align.Left, Align.Upper, 1.0, fiveEighths, 255); },
		0x1FB85 => { blockShade(p, Align.Left, Align.Upper, 1.0, threeQuarters, 255); },
		0x1FB86 => { blockShade(p, Align.Left, Align.Upper, 1.0, sevenEighths, 255); },
		0x1FB87 => { blockShade(p, Align.Right, Align.Upper, quarter, 1.0, 255); },
		0x1FB88 => { blockShade(p, Align.Right, Align.Upper, threeEighths, 1.0, 255); },
		0x1FB89 => { blockShade(p, Align.Right, Align.Upper, fiveEighths, 1.0, 255); },
		0x1FB8A => { blockShade(p, Align.Right, Align.Upper, threeQuarters, 1.0, 255); },
		0x1FB8B => { blockShade(p, Align.Right, Align.Upper, sevenEighths, 1.0, 255); },
		0x1FB8C => { blockShade(p, Align.Left, Align.Upper, half, 1.0, 0x80); },
		0x1FB8D => { blockShade(p, Align.Right, Align.Upper, half, 1.0, 0x80); },
		0x1FB8E => { blockShade(p, Align.Left, Align.Upper, 1.0, half, 0x80); },
		0x1FB8F => { blockShade(p, Align.Left, Align.Lower, 1.0, half, 0x80); },
		0x1FB90 => { fillBox(p, 0, 0, cw, ch, 0x80); },
		0x1FB91 => {
			fillBox(p, 0, 0, cw, ch, 0x80);
			blockShade(p, Align.Left, Align.Upper, 1.0, half, 255);
		},
		0x1FB92 => {
			fillBox(p, 0, 0, cw, ch, 0x80);
			blockShade(p, Align.Left, Align.Lower, 1.0, half, 255);
		},
		0x1FB94 => {
			fillBox(p, 0, 0, cw, ch, 0x80);
			blockShade(p, Align.Right, Align.Upper, half, 1.0, 255);
		},
		0x1FB95 => { checkerboard(p, 0); },
		0x1FB96 => { checkerboard(p, 1); },
		0x1FB97 => {
			fillBox(p, 0, ch / 4, cw, 2 * ch / 4, 255);
			fillBox(p, 0, 3 * ch / 4, cw, ch, 255);
		},
		_ => { stopOnUndrawn("legacy block", codepoint); },
	}
}
