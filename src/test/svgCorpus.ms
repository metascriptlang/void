import { SVG_FIXTURE_TEXTS } from "./svgFixtures";

// Documents for the SVG port: the repo's fixtures, hand-written edge cases, then documents grown
// from a seed, each one independent of the others so one index reproduces one document.

const EDGE_DOCS: string[] = [
	"",
	"hello",
	"<g/>",
	"<svg/>",
	"<svg width=\"0\" height=\"0\"></svg>",
	"<svg width=\"-5\" height=\"10\"></svg>",
	"<svg width=\"1234567\" height=\"10\"></svg>",
	"<svg width=\"0.00001\" height=\"12.3456789\"></svg>",
	"<svg width=\"100000.5\" height=\"2e7\"></svg>",
	"<svg width=\"1e-7\" height=\"123456.7\"></svg>",
	"<svg viewBox=\"0 0 24 24\"><path d=\"M4 4h16v16H4z\"/></svg>",
	"<svg viewBox=\"0 0 24\"><path d=\"M4 4h16v16H4z\"/></svg>",
	"<svg viewBox=\"0 0\" width=\"20\" height=\"20\"><rect width=\"10\" height=\"10\"/></svg>",
	"<svg viewBox=\"0,0,10,10\" preserveAspectRatio=\"xMinYMax slice\"><rect width=\"20\" height=\"5\"/></svg>",
	"<svg viewBox=\"0 0 10 10\" width=\"30\" height=\"10\" preserveAspectRatio=\"xMaxYMid meet\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>",
	"<svg viewBox=\"0 0 10 10\" width=\"30\" height=\"10\" preserveAspectRatio=\"none\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>",
	"<svg><path d=\"M1 1 L1 1\" stroke=\"red\" stroke-width=\"10\" stroke-linecap=\"round\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M10 10 L10 10\" stroke=\"red\" stroke-width=\"10\" stroke-linecap=\"square\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M10 10 L10 10\" stroke=\"red\" stroke-width=\"10\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M10 10 L10 10z\" stroke=\"red\" stroke-width=\"10\" stroke-linejoin=\"round\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M10 10 L10 10\" stroke=\"red\" stroke-dasharray=\"1 1\" stroke-width=\"10\" stroke-linecap=\"round\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"g\"><stop offset=\"0\" stop-color=\"red\"/><stop offset=\"1\" stop-color=\"blue\"/></linearGradient></defs><path d=\"M10 10 L10 10\" stroke=\"url(#g)\" stroke-width=\"10\" stroke-linecap=\"round\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=\"url(#nope)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><g opacity=\"0.5\"><path d=\"M2 2h16v16H2z\"/></g></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" opacity=\"50%\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=\"banana\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=\"#12\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" filter=\"url(#f)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-linecap=\"arrow\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=\"inherit\"/></svg>",
	"<svg width=\"20\" height=\"20\"><svg></svg></svg>",
	"<svg width=\"20\" height=\"20\"><foo/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=red></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\"",
	"<svg width=\"20\" height=\"20\"><!-- open",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" fill=\"red></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{fill:red}</style><path class=\"a\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a,.b{fill:red;stroke:#00f;stroke-width:3}.b{fill:none}</style><path class=\"a b\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{opacity:.5}</style><path class=\"a\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>path{fill:red}</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>g .a{fill:red}</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>@media print{.a{fill:red}}</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{filter:blur(1)}</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>/* c */.a{fill:red}</style><path class=\"a\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>/* open .a{fill:red}</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{fill:red</style></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{fill:red}</svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{stroke:red;stroke-width:6;stroke-dasharray:4 2}.b{stroke-linejoin:round;stroke-linecap:round}</style><path class=\"a b\" fill=\"none\" d=\"M3 3L17 3L10 17z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{fill:red}.a{fill:blue}</style><path class=\"a\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><style>.a{style:fill:red}</style><path class=\"a\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path style=\"FILL:red;Stroke-Width:3\" stroke=\"blue\" d=\"M2 2h16v16H2z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" display=\"none\"/><path d=\"M5 5h10v10H5z\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" paint-order=\"stroke\" stroke=\"red\" stroke-width=\"5\" fill=\"blue\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" paint-order=\"stroke fill markers\" stroke=\"red\" stroke-width=\"5\" fill=\"blue\" fill-opacity=\".5\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2,2 h16 v16 H2 z m3,3 h5 v5 h-5 z\" fill-rule=\"evenodd\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 C 10 2 18 6 18 18 S 2 18 2 10 Q 5 5 10 10 T 18 2\" stroke=\"red\" fill=\"none\" stroke-width=\"2\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 10 a8 8 0 1 1 16 0 a8 8 0 1 1 -16 0\" /></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 10a8 8 0 0116 0a8 8 0 01-16 0\" /></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 10 A 0 8 0 0 1 16 0 A 8 8 30 1 0 3 3 A 3 3 0 0 0 3 3 z\" stroke=\"blue\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 L5\" /><path d=\"M 4 4 foo 5 5\" /><path d=\"L 1 1 2 2\" /></svg>",
	"<svg width=\"20\" height=\"20\"><rect x=\"2\" y=\"2\" width=\"16\" height=\"16\" rx=\"4\"/><rect width=\"0\" height=\"4\"/><rect width=\"8\" height=\"8\" ry=\"3\" x=\"1e0\" y=\"+1\"/></svg>",
	"<svg width=\"20\" height=\"20\"><circle r=\"-3\"/><circle cx=\"10\" cy=\"10\" r=\"5\" stroke=\"red\" stroke-width=\"3\"/><ellipse cx=\"10\" cy=\"10\" rx=\"8\" ry=\"3\" stroke=\"blue\" fill=\"none\"/></svg>",
	"<svg width=\"20\" height=\"20\"><line x1=\"2\" y1=\"2\" x2=\"18\" y2=\"18\" stroke=\"red\" stroke-width=\"4\" stroke-linecap=\"square\"/><polyline points=\"2,18 10,4 18,18\" stroke=\"blue\" fill=\"none\"/><polygon points=\"3 3 17 3 10 12\"/></svg>",
	"<svg width=\"20\" height=\"20\"><polyline points=\"1 2 3\"/><polygon points=\"\"/><polyline points=\"1,1,2,2,3,3,4\" stroke=\"red\"/></svg>",
	"<svg width=\"20\" height=\"20\"><g transform=\"translate(10 10) rotate(45) scale(.5, 2) skewX(10) skewY(-5)\"><rect x=\"-5\" y=\"-5\" width=\"10\" height=\"10\"/></g></svg>",
	"<svg width=\"20\" height=\"20\"><g transform=\"matrix(1 0 0 1 3 3) matrix(1 2 3)\"><rect width=\"10\" height=\"10\"/></g></svg>",
	"<svg width=\"20\" height=\"20\"><g transform=\"rotate(30 10 10)\"><rect x=\"3\" y=\"3\" width=\"14\" height=\"14\"/></g><g transform=\"scale(0)\"><rect width=\"5\" height=\"5\"/></g></svg>",
	"<svg width=\"20\" height=\"20\"><g transform=\"translate(5)bogus scale(2)\"><rect width=\"5\" height=\"5\"/></g></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"red\"/><stop offset=\"1\" stop-color=\"blue\" stop-opacity=\".2\"/></linearGradient></defs><rect width=\"20\" height=\"20\" fill=\"url(#g)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><radialGradient id=\"r\" cx=\"50%\" cy=\"50%\" r=\"50%\"><stop offset=\"0%\" stop-opacity=\"1\"/><stop offset=\"50%\" stop-opacity=\".5\"/><stop offset=\"100%\" stop-opacity=\"0\"/></radialGradient></defs><circle cx=\"10\" cy=\"10\" r=\"9\" fill=\"url(#r)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"a\" xlink:href=\"#b\"/><linearGradient id=\"b\"><stop offset=\".3\" stop-opacity=\"0\"/><stop offset=\".1\" stop-opacity=\"1\"/></linearGradient></defs><rect width=\"20\" height=\"20\" fill=\"url(#a)\" stroke=\"url(#b)\" stroke-width=\"3\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"a\" gradientUnits=\"userSpaceOnUse\" x1=\"2\" x2=\"18\" gradientTransform=\"rotate(20)\"><stop offset=\"0\"/><stop offset=\"1\" stop-opacity=\".3\"/></linearGradient></defs><rect width=\"20\" height=\"20\" fill=\"url(#a)\" fill-opacity=\".8\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"a\"><stop offset=\"0.5\"/></linearGradient></defs><rect width=\"20\" height=\"20\" fill=\"url(#a)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"a\"/></defs><rect width=\"20\" height=\"20\" fill=\"url(#a)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><linearGradient id=\"a\" xlink:href=\"#a\"/></defs><rect width=\"20\" height=\"20\" fill=\"url(#a)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-width=\"3\" stroke-dasharray=\"5\" stroke-dashoffset=\"-3\"/><path d=\"M2 18h16\" stroke=\"blue\" stroke-dasharray=\"4 2 1\" stroke-dashoffset=\"2\" stroke-linecap=\"round\"/><path d=\"M2 10h16\" stroke=\"blue\" stroke-dasharray=\"0\"/><path d=\"M2 6h16\" stroke=\"blue\" stroke-dasharray=\"none\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2L18 2L2 12\" stroke=\"red\" stroke-width=\"4\" stroke-miterlimit=\"1\" fill=\"none\"/><path d=\"M2 12L18 12L2 18\" stroke=\"blue\" stroke-width=\"4\" stroke-miterlimit=\"10\" stroke-linejoin=\"bevel\" fill=\"none\"/><path d=\"M2 5L18 5L10 15\" stroke=\"blue\" stroke-width=\"4\" stroke-linejoin=\"round\" stroke-linecap=\"round\" fill=\"none\"/></svg>",
	"<svg width=\"20em\" height=\"2in\"><rect width=\"10mm\" height=\"1cm\"/></svg>",
	"<svg width=\"50%\" height=\"20pt\" viewBox=\"0 0 30 30\"><rect width=\"1pc\" height=\"5ex\"/></svg>",
	"<?xml version=\"1.0\"?><!DOCTYPE svg [<!ENTITY a \"b\">]><svg width=\"20\" height=\"20\"><!-- c --><![CDATA[x]]><title>t</title><rect width=\"20\" height=\"20\"/></svg>",
	"<svg width='20' height='20'><rect width='10' height='10' fill='#0f0'/></svg>",
	"<svg width=\"20\" height=\"20\"><rect width=\"10\" height=\"10\" fill=\"#0f0\" fill=\"none\"/></svg>",
	"<svg width=\"20\" height=\"20\"><rect width=\"10\" height=\"10\" /></svg>junk<svg/>",
	"<svg width=\"20\" height=\"20\"><rect  width = \"10\"  height=\"10\" ></rect></svg>",
	"<svg width=\"20\" height=\"20\"><rect width=\"10\" height /></svg>",
	"<svg width=\"20\" height=\"20\"><rect width=10 height=\"10\" /></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-width=\"0.001\"/><path d=\"M2 2h16\" stroke=\"red\" stroke-width=\"0.02\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 2 2\" stroke=\"red\" stroke-width=\"0.5\" stroke-linecap=\"round\"/><path d=\"M5 5\" stroke=\"red\" stroke-width=\"0.5\"/><path d=\"M5 5z\" stroke=\"red\" stroke-width=\"4\" stroke-linejoin=\"round\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M-1e5 -1e5 L1e5 1e5 L-1e5 1e5z\" stroke=\"red\" stroke-width=\"3\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 C 1e30 0 0 1e30 18 18\" stroke=\"red\" stroke-width=\"3\" fill=\"none\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 L 18 18 NaN 5 5\" stroke=\"red\"/><path d=\"M 99999999999999999999 5 L 5 99999999999999999999.5e-3\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M1.2.3.4 5e 5e+ 6\" /><path d=\"M 1e400 1 L 1 1e-400\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2 h-1 v-1 h1 v1z H 5 V 5 z\" fill=\"red\"/></svg>",
	"<svg width=\"20\" height=\"20\" style=\"fill:red\"><g style=\"stroke:blue;stroke-width:2\" fill=\"none\"><path d=\"M2 2h16v16\"/></g></svg>",
	"<svg width=\"20\" height=\"20\" font-size=\"10\"><rect width=\"1em\" height=\"2ex\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" id=\"i\" class=\"missing a b c\" stroke-opacity=\"2\" fill-opacity=\"-1\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-width=\"-3\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-width=\"2\" fill=\"none\" transform=\"scale(1 0)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><path d=\"M2 2h16v16H2z\" stroke=\"red\" stroke-width=\"2\" fill=\"none\" transform=\"matrix(1 2 2 4 0 0)\"/></svg>",
	"<svg width=\"20\" height=\"20\"><defs><path d=\"M2 2h16v16H2z\"/></defs><rect width=\"5\" height=\"5\"/></svg>",
	"<svg width=\"20\" height=\"20\"><desc>d</desc><metadata/><title/></svg>",
];

class Rng {
	state: uint32 = 0;
}

function seeded(index: int32): Rng {
	const r = new Rng();
	r.state = ((index as uint32) * 2654435761 + 12345) | 1;
	for (let i: int32 = 0; i < 4; i++) { next(r); }
	return r;
}

function next(r: Rng): uint32 {
	let x = r.state;
	x = x ^ (x << 13);
	x = x ^ (x >> 17);
	x = x ^ (x << 5);
	r.state = x;
	return x;
}

function below(r: Rng, n: int32): int32 {
	return (next(r) % (n as uint32)) as int32;
}

function between(r: Rng, lo: int32, hi: int32): int32 {
	return lo + below(r, hi - lo + 1);
}

function chance(r: Rng, percent: int32): boolean {
	return below(r, 100) < percent;
}

function pick(r: Rng, items: string[]): string {
	return items[below(r, items.length as int32)];
}

function num(r: Rng, lo: int32, hi: int32): string {
	const kind = below(r, 12);
	const v = between(r, lo, hi);
	if (kind < 5) { return `${v}`; }
	if (kind < 8) { return `${v}.${between(r, 0, 99)}`; }
	if (kind == 8) { return `.${between(r, 1, 99)}`; }
	if (kind == 9) { return `${v}e${between(r, -1, 1)}`; }
	if (kind == 10) { return `-${between(r, 0, hi)}.${between(r, 0, 9)}`; }
	return `+${between(r, 0, hi)}`;
}

function sep(r: Rng): string {
	const k = below(r, 8);
	if (k < 4) { return " "; }
	if (k < 6) { return ","; }
	if (k == 6) { return ", "; }
	return "  ";
}

const COMMANDS: string[] = [
	"M", "m", "L", "l", "H", "h", "V", "v", "C", "c", "S", "s", "Q", "q", "T", "t", "A", "a", "Z", "z",
];

function argCount(cmd: string): int32 {
	if (cmd == "H" || cmd == "h" || cmd == "V" || cmd == "v") { return 1; }
	if (cmd == "M" || cmd == "m" || cmd == "L" || cmd == "l" || cmd == "T" || cmd == "t") { return 2; }
	if (cmd == "Q" || cmd == "q" || cmd == "S" || cmd == "s") { return 4; }
	if (cmd == "C" || cmd == "c") { return 6; }
	if (cmd == "A" || cmd == "a") { return 7; }
	return 0;
}

function pathData(r: Rng, span: int32): string {
	let d = chance(r, 90) ? pick(r, ["M", "m", "M", "M"]) + num(r, 0, span) + sep(r) + num(r, 0, span) : "";
	const segments = between(r, 1, 7);
	for (let i: int32 = 0; i < segments; i++) {
		const cmd = pick(r, COMMANDS);
		d += (chance(r, 70) ? " " : "") + cmd;
		const n = argCount(cmd);
		const repeats = chance(r, 20) ? 2 : 1;
		for (let rep: int32 = 0; rep < repeats; rep++) {
			for (let k: int32 = 0; k < n; k++) {
				if ((cmd == "A" || cmd == "a") && (k == 3 || k == 4)) {
					d += (k == 3 ? " " : (chance(r, 50) ? " " : "")) + `${below(r, 2)}`;
					if (k == 3) { d += chance(r, 50) ? " " : ""; }
				} else if ((cmd == "A" || cmd == "a") && (k == 0 || k == 1)) {
					d += (k == 0 ? " " : sep(r)) + num(r, 0, span / 2 + 1);
				} else {
					d += (k == 0 ? " " : sep(r)) + num(r, -span / 4, span);
				}
			}
			if (rep + 1 < repeats) { d += sep(r); }
		}
	}
	if (chance(r, 5)) { d += pick(r, [" x", " #", " 1e", " -", " .", " 3 4 5"]); }
	return d;
}

const COLOURS: string[] = [
	"red", "blue", "#f00", "#00ff80", "#ABCDEF", "black", "white", "currentColor", "rgb(10,20,30)", "gray",
];

function paintValue(r: Rng, withGradients: boolean): string {
	if (withGradients && chance(r, 30)) { return pick(r, ["url(#g1)", "url(#g2)", "url(#g3)", "url(#g1)"]); }
	if (chance(r, 25)) { return "none"; }
	return pick(r, COLOURS);
}

function transformValue(r: Rng): string {
	let t = "";
	const n = between(r, 1, 3);
	for (let i: int32 = 0; i < n; i++) {
		const k = below(r, i == 0 ? 6 : 7);
		if (k == 0) {
			t += `translate(${num(r, -8, 8)}${chance(r, 70) ? sep(r) + num(r, -8, 8) : ""})`;
		} else if (k == 1) {
			t += `scale(${num(r, 0, 3)}${chance(r, 50) ? sep(r) + num(r, 0, 3) : ""})`;
		} else if (k == 2) {
			t += `rotate(${num(r, -90, 90)}${chance(r, 40) ? sep(r) + num(r, 0, 20) + sep(r) + num(r, 0, 20) : ""})`;
		} else if (k == 3) {
			t += `skewX(${between(r, -40, 40)})`;
		} else if (k == 4) {
			t += `skewY(${between(r, -40, 40)})`;
		} else if (k == 5) {
			t += `matrix(${num(r, -2, 2)} ${num(r, -2, 2)} ${num(r, -2, 2)} ${num(r, -2, 2)} ${num(r, -5, 5)} ${num(r, -5, 5)})`;
		} else {
			t += `matrix(1 2 3)`;
		}
		t += chance(r, 50) ? " " : "";
	}
	return t;
}

function styleAttrs(r: Rng, gradients: boolean, onGroup: boolean): string {
	let a = "";
	if (chance(r, 70)) { a += ` fill="${paintValue(r, gradients)}"`; }
	if (chance(r, 60)) { a += ` stroke="${paintValue(r, gradients)}"`; }
	if (chance(r, 50)) { a += ` stroke-width="${num(r, 0, 6)}"`; }
	if (chance(r, 30)) { a += ` stroke-linecap="${pick(r, ["butt", "round", "square"])}"`; }
	if (chance(r, 30)) { a += ` stroke-linejoin="${pick(r, ["miter", "round", "bevel"])}"`; }
	if (chance(r, 15)) { a += ` stroke-miterlimit="${num(r, 0, 8)}"`; }
	if (chance(r, 25)) {
		a += ` stroke-dasharray="${num(r, 1, 6)}${chance(r, 60) ? sep(r) + num(r, 1, 6) : ""}${chance(r, 20) ? sep(r) + num(r, 1, 4) : ""}"`;
		if (chance(r, 50)) { a += ` stroke-dashoffset="${num(r, -6, 12)}"`; }
	}
	if (chance(r, 20)) { a += ` fill-rule="${pick(r, ["nonzero", "evenodd"])}"`; }
	if (!onGroup && chance(r, 20)) { a += ` opacity="${pick(r, ["0.5", ".25", "1", "0", "0.9"])}"`; }
	if (chance(r, 15)) { a += ` fill-opacity="${pick(r, ["0.5", ".25", "1", "0"])}"`; }
	if (chance(r, 15)) { a += ` stroke-opacity="${pick(r, ["0.5", ".75", "1"])}"`; }
	if (chance(r, 20)) { a += ` transform="${transformValue(r)}"`; }
	if (chance(r, 10)) { a += ` class="${pick(r, ["a", "b", "a b", "c a", "zz"])}"`; }
	if (chance(r, 8)) { a += ` style="${pick(r, ["fill:red", "stroke:blue;stroke-width:2", "fill:none; stroke:#0a0", "opacity:.5"])}"`; }
	if (chance(r, 4)) { a += ` display="none"`; }
	if (chance(r, 6)) {
		a += ` paint-order="${pick(r, ["stroke", "normal", "stroke fill markers", "markers fill stroke", "fill markers stroke"])}"`;
	}
	return a;
}

function shapeElement(r: Rng, span: int32, gradients: boolean): string {
	const k = below(r, 9);
	const s = styleAttrs(r, gradients, false);
	if (k < 3) { return `<path d="${pathData(r, span)}"${s}/>`; }
	if (k == 3) {
		return `<rect x="${num(r, 0, span / 2)}" y="${num(r, 0, span / 2)}" width="${num(r, 0, span)}" height="${num(r, 0, span)}"${chance(r, 40) ? ` rx="${num(r, 0, 6)}"` : ""}${chance(r, 25) ? ` ry="${num(r, 0, 6)}"` : ""}${s}/>`;
	}
	if (k == 4) {
		return `<circle cx="${num(r, 0, span)}" cy="${num(r, 0, span)}" r="${num(r, 0, span / 2)}"${s}/>`;
	}
	if (k == 5) {
		return `<ellipse cx="${num(r, 0, span)}" cy="${num(r, 0, span)}" rx="${num(r, 0, span / 2)}" ry="${num(r, 0, span / 2)}"${s}/>`;
	}
	if (k == 6) {
		return `<line x1="${num(r, 0, span)}" y1="${num(r, 0, span)}" x2="${num(r, 0, span)}" y2="${num(r, 0, span)}"${s}/>`;
	}
	let points = "";
	const n = between(r, 1, 6);
	for (let i: int32 = 0; i < n; i++) {
		points += (i > 0 ? sep(r) : "") + num(r, 0, span) + sep(r) + num(r, 0, span);
	}
	return `<${k == 7 ? "polyline" : "polygon"} points="${points}"${s}/>`;
}

function stopsBlock(r: Rng): string {
	let out = "";
	const n = between(r, 0, 4);
	for (let i: int32 = 0; i < n; i++) {
		out += `<stop offset="${pick(r, ["0", "0.25", "50%", ".5", "1", "100%", "2", "-1", "0.75"])}"`;
		if (chance(r, 70)) { out += ` stop-color="${pick(r, COLOURS)}"`; }
		if (chance(r, 60)) { out += ` stop-opacity="${pick(r, ["1", "0.5", "0", ".25", "0.8"])}"`; }
		out += "/>";
	}
	return out;
}

function defsBlock(r: Rng): string {
	let d = "<defs>";
	d += `<linearGradient id="g1"${chance(r, 50) ? ` x1="${num(r, 0, 20)}" y1="${num(r, 0, 20)}" x2="${num(r, 0, 20)}" y2="${num(r, 0, 20)}"` : ""}${chance(r, 50) ? ` gradientUnits="userSpaceOnUse"` : ""}${chance(r, 30) ? ` gradientTransform="${transformValue(r)}"` : ""}>${stopsBlock(r)}</linearGradient>`;
	d += `<radialGradient id="g2"${chance(r, 50) ? ` cx="${pick(r, ["50%", "10", "0.3"])}" cy="${pick(r, ["50%", "12", "0.6"])}" r="${pick(r, ["50%", "9", "0.7"])}"` : ""}${chance(r, 50) ? ` gradientUnits="userSpaceOnUse"` : ""}>${stopsBlock(r)}</radialGradient>`;
	d += `<linearGradient id="g3" xlink:href="#g1"/>`;
	d += "</defs>";
	return d;
}

function styleBlock(r: Rng): string {
	return `<style>.a{fill:${pick(r, COLOURS)};stroke:${pick(r, COLOURS)};stroke-width:${num(r, 0, 4)}} .b,.c{stroke-dasharray:3 2;fill:none}</style>`;
}

function generated(index: int32): string {
	const r = seeded(index);
	const spans: int32[] = [8, 24, 24, 48];
	const span = spans[below(r, 4)];
	let head = "<svg xmlns=\"http://www.w3.org/2000/svg\"";
	if (chance(r, 85)) { head += ` width="${pick(r, [`${span}`, `${span}px`, `${span * 2}`, "1in", "20", `${span}.5`])}"`; }
	if (chance(r, 85)) { head += ` height="${pick(r, [`${span}`, `${span}px`, `${span}`, "30", `${span / 2 + 1}`])}"`; }
	if (chance(r, 75)) {
		head += ` viewBox="${pick(r, [`0 0 ${span} ${span}`, `0 0 ${span} ${span}`, `-4 -4 ${span + 8} ${span + 8}`, `0,0,${span},${span / 2 + 1}`, `2 3 ${span} ${span}`])}"`;
		if (chance(r, 40)) {
			head += ` preserveAspectRatio="${pick(r, ["none", "xMinYMin meet", "xMidYMid slice", "xMaxYMax", "xMinYMax slice", "xMidYMin"])}"`;
		}
	}
	let body = "";
	const gradients = chance(r, 35);
	if (gradients) { body += defsBlock(r); }
	if (chance(r, 20)) { body += styleBlock(r); }
	const count = between(r, 1, 4);
	for (let i: int32 = 0; i < count; i++) {
		if (chance(r, 20)) {
			body += `<g${chance(r, 60) ? ` transform="${transformValue(r)}"` : ""}${styleAttrs(r, gradients, true)}>`;
			const inner = between(r, 1, 3);
			for (let j: int32 = 0; j < inner; j++) { body += shapeElement(r, span, gradients); }
			body += "</g>";
		} else {
			body += shapeElement(r, span, gradients);
		}
	}
	return `${head}>${body}</svg>`;
}

export function corpusFixtureCount(): int32 {
	return SVG_FIXTURE_TEXTS.length as int32;
}

export function corpusEdgeCount(): int32 {
	return EDGE_DOCS.length as int32;
}

// Document `index` of the corpus: fixtures first, then the edge cases, then the generated ones.
export function corpusDoc(index: int32): string {
	const fixtures = SVG_FIXTURE_TEXTS.length as int32;
	if (index < fixtures) { return SVG_FIXTURE_TEXTS[index]; }
	const edges = EDGE_DOCS.length as int32;
	if (index < fixtures + edges) { return EDGE_DOCS[index - fixtures]; }
	return generated(index - fixtures - edges);
}

