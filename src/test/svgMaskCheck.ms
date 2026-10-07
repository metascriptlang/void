import {
	MAX_SVG_MASK_SIDE,
	SvgMaskError,
	SvgMaskRefusal,
	SvgMaskSource,
	svgMaskCompiled,
	svgMaskFree,
	svgMaskLive,
	svgMaskParse,
	svgMaskRasterize,
} from "../void2d/svgMask";

const HEAD: string = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" `
	+ `viewBox="0 0 24 24"`;

function icon(attributes: string, body: string): string {
	return `${HEAD} ${attributes}>${body}</svg>`;
}

function mask(svg: string, side: int32): Vec<uint8> {
	const parsed: Result<SvgMaskSource, SvgMaskRefusal> = svgMaskParse(svg);
	if (!parsed.ok) {
		console.log(`svg refused: ${parsed.error.what}`);
		return new Array(side * side);
	}
	const drawn: Result<Vec<uint8>, SvgMaskRefusal> = svgMaskRasterize(parsed.value, side, side);
	svgMaskFree(parsed.value);
	if (!drawn.ok) {
		console.log(`svg mask refused: ${drawn.error.what}`);
		return new Array(side * side);
	}
	return drawn.value;
}

function refusalOf(svg: string): SvgMaskRefusal {
	const parsed: Result<SvgMaskSource, SvgMaskRefusal> = svgMaskParse(svg);
	if (parsed.ok) {
		svgMaskFree(parsed.value);
		return { error: SvgMaskError.Unparsable, what: "accepted" };
	}
	return parsed.error;
}

function ink(pixels: Vec<uint8>): float32 {
	let total: int32 = 0;
	for (let i: int32 = 0; i < (pixels.length as int32); i++) { total += pixels[i] as int32; }
	return (total as float32) / 255.0;
}

function near(value: float32, expected: float32, tolerance: float32): boolean {
	return Math.abs(value - expected) <= tolerance;
}

test "the module flag is the one the rasterizer is built under" {
	assert svgMaskCompiled();
}

test "a pixel-aligned rect comes out as exactly 255 inside and 0 outside" {
	const m = mask(icon("", `<rect x="4" y="4" width="16" height="16"/>`), 24);
	for (let y: int32 = 0; y < 24; y++) {
		for (let x: int32 = 0; x < 24; x++) {
			const inside: boolean = x >= 4 && x < 20 && y >= 4 && y < 20;
			assert (m[y * 24 + x] as int32) == (inside ? 255 : 0);
		}
	}
}

test "the same rect at twice the size covers twice the extent" {
	const m = mask(icon("", `<rect x="4" y="4" width="16" height="16"/>`), 48);
	for (let y: int32 = 0; y < 48; y++) {
		for (let x: int32 = 0; x < 48; x++) {
			const inside: boolean = x >= 8 && x < 40 && y >= 8 && y < 40;
			assert (m[y * 48 + x] as int32) == (inside ? 255 : 0);
		}
	}
}

test "an edge half way through a pixel covers half of it" {
	const m = mask(icon("", `<rect x="4.5" y="4" width="15.5" height="16"/>`), 24);
	assert Math.abs((m[8 * 24 + 4] as int32) - 128) <= 3;
	assert (m[8 * 24 + 5] as int32) == 255;
	assert (m[8 * 24 + 3] as int32) == 0;
}

test "a circle covers its area to within 1.5 percent and is symmetric" {
	const m = mask(icon("", `<circle cx="12" cy="12" r="8"/>`), 24);
	assert near(ink(m), 3.14159265 * 64.0, 2.5);
	for (let y: int32 = 0; y < 24; y++) {
		for (let x: int32 = 0; x < 24; x++) {
			assert Math.abs((m[y * 24 + x] as int32) - (m[y * 24 + (23 - x)] as int32)) <= 1;
		}
	}
}

test "a stroke with round caps reaches past its end and one with butt caps does not" {
	const line = (cap: string) => icon(
		`fill="none" stroke="#000" stroke-width="4" stroke-linecap="${cap}"`,
		`<path d="M6 12H18"/>`,
	);
	const round = mask(line("round"), 24);
	const butt = mask(line("butt"), 24);
	assert (round[12 * 24 + 5] as int32) == 255;
	assert (butt[12 * 24 + 5] as int32) == 0;
	assert (round[12 * 24 + 4] as int32) > 0 && (round[12 * 24 + 4] as int32) < 255;
	assert near(ink(butt), 48.0, 0.5);
	assert near(ink(round) - ink(butt), 3.14159265 * 4.0, 1.0);
}

test "a zero-length stroke with a round cap is the dot a browser draws" {
	const dot = (cap: string, extra: string) => icon(
		`fill="none" stroke="#000" stroke-width="2" stroke-linecap="${cap}" ${extra}`,
		`<line x1="12" x2="12" y1="16" y2="16"/>`,
	);
	const round = mask(dot("round", ""), 24);
	assert near(ink(round), 3.14159265, 0.45);
	assert (round[15 * 24 + 11] as int32) > 170 && (round[16 * 24 + 12] as int32) > 170;
	assert (round[14 * 24 + 11] as int32) == 0 && (round[15 * 24 + 10] as int32) == 0;
	const faint = mask(dot("round", `stroke-opacity="0.5"`), 24);
	assert near(ink(faint), 3.14159265 * 0.5, 0.3);
}

test "a zero-length stroke with a square cap is a square and with a butt cap is nothing" {
	const dot = (cap: string) => icon(
		`fill="none" stroke="#000" stroke-width="2" stroke-linecap="${cap}"`,
		`<path d="M12 16h0"/>`,
	);
	const square = mask(dot("square"), 24);
	assert ink(square) == 4.0;
	assert (square[15 * 24 + 11] as int32) == 255 && (square[16 * 24 + 12] as int32) == 255;
	assert (square[15 * 24 + 10] as int32) == 0 && (square[17 * 24 + 11] as int32) == 0;
	assert ink(mask(dot("butt"), 24)) == 0.0;
}

test "a dot beside a line keeps both and leaves the line's own caps alone" {
	const svg = icon(
		`fill="none" stroke="#000" stroke-width="2" stroke-linecap="round"`,
		`<path d="M12 4h0M4 20h8"/>`,
	);
	const m = mask(svg, 24);
	assert near(ink(m), 3.14159265 + 16.0 + 3.14159265, 0.8);
	assert (m[3 * 24 + 11] as int32) > 170;
}

test "a hundredth-unit dash with a round cap is a dot wherever it sits on the grid" {
	const dot = (x: string) => icon(
		`fill="none" stroke="#000" stroke-width="2" stroke-linecap="round"`,
		`<path d="M${x} 16h.01"/>`,
	);
	for (const x of ["2", "12", "5.5", "20"]) {
		assert ink(mask(dot(x), 24)) > 2.5;
	}
}

test "a closed loop far smaller than its stroke is a dot, as in Heroicons" {
	const loop = (join: string) => icon(
		`fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" `
			+ `stroke-linejoin="${join}"`,
		`<path d="M8.25 12h.008v.008H8.25v-.008Z"/>`,
	);
	const round = mask(loop("round"), 24);
	assert near(ink(round), 3.14159265 * 0.75 * 0.75, 0.35);
	assert (round[11 * 24 + 8] as int32) > 100 && (round[12 * 24 + 8] as int32) > 100;
	assert (round[11 * 24 + 5] as int32) == 0 && (round[11 * 24 + 10] as int32) == 0;
	const miter = refusalOf(loop("miter"));
	assert miter.error == SvgMaskError.Unsupported;
	assert miter.what == "a stroked path much smaller than its stroke width without round joins";
}

test "a tiny stroke the module cannot draw faithfully is refused by what it is" {
	const gradient = refusalOf(icon(
		`fill="none" stroke="url(#g)" stroke-width="2" stroke-linecap="round"`,
		`<defs><linearGradient id="g"><stop offset="0" stop-color="#000"/>`
			+ `<stop offset="1" stop-color="#fff"/></linearGradient></defs>`
			+ `<line x1="12" x2="12" y1="16" y2="16"/>`,
	));
	assert gradient.error == SvgMaskError.Unsupported;
	assert gradient.what == "a tiny stroked path with a gradient stroke";
	const dashed = refusalOf(icon(
		`fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-dasharray="1 1"`,
		`<line x1="12" x2="12" y1="16" y2="16"/>`,
	));
	assert dashed.what == "a tiny stroked path with a dash array";
}

test "evenodd leaves the inner square a hole where nonzero fills it" {
	const squares = (rule: string) => icon(
		`fill-rule="${rule}"`,
		`<path d="M4 4H20V20H4ZM8 8H16V16H8Z"/>`,
	);
	const nonzero = mask(squares("nonzero"), 24);
	const evenodd = mask(squares("evenodd"), 24);
	assert (nonzero[12 * 24 + 12] as int32) == 255;
	assert (evenodd[12 * 24 + 12] as int32) == 0;
	assert (evenodd[5 * 24 + 5] as int32) == 255;
	assert near(ink(evenodd), 256.0 - 64.0, 0.01);
}

test "the viewBox maps onto the size the author gave and onto any size asked for" {
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" `
		+ `viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16"/></svg>`;
	const parsed = svgMaskParse(svg);
	assert parsed.ok;
	if (!parsed.ok) { return; }
	assert parsed.value.width == 12.0 && parsed.value.height == 12.0;
	svgMaskFree(parsed.value);
	const m = mask(svg, 24);
	assert (m[4 * 24 + 4] as int32) == 255 && (m[19 * 24 + 19] as int32) == 255;
	assert (m[3 * 24 + 4] as int32) == 0 && (m[20 * 24 + 19] as int32) == 0;
}

test "a wide source fits the square it is asked for and sits in its middle" {
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="12" `
		+ `viewBox="0 0 24 12"><rect width="24" height="12"/></svg>`;
	const m = mask(svg, 48);
	assert (m[12 * 48 + 0] as int32) == 255 && (m[35 * 48 + 47] as int32) == 255;
	assert (m[11 * 48 + 0] as int32) == 0 && (m[36 * 48 + 47] as int32) == 0;
}

test "every element the rasterizer would drop is refused by its name" {
	const names: string[] = [
		"use", "clipPath", "mask", "filter", "text", "image", "pattern", "marker", "symbol",
		"switch", "foreignObject", "a", "tspan", "feGaussianBlur", "svg:path",
	];
	for (const name of names) {
		const r = refusalOf(icon("", `<${name}/>`));
		assert r.error == SvgMaskError.Unsupported;
		assert r.what == `element <${name}>`;
	}
}

test "an attribute the rasterizer would ignore is refused by its name, on an element or in style" {
	const denied: string[] = [
		"clip-path", "mask", "filter", "marker-end", "visibility", "vector-effect",
		"mix-blend-mode", "shape-rendering",
	];
	for (const name of denied) {
		const onElement = refusalOf(icon("", `<path ${name}="none" d="M0 0"/>`));
		assert onElement.error == SvgMaskError.Unsupported;
		assert onElement.what == `attribute ${name}`;
		const inStyle = refusalOf(icon("", `<path style="fill:none; ${name}: none" d="M0 0"/>`));
		assert inStyle.error == SvgMaskError.Unsupported;
		assert inStyle.what == `attribute ${name}`;
	}
}

test "a value the rasterizer would read wrongly is refused with the attribute it sits on" {
	const rows: string[][] = [
		[`fill="rgba(0,0,0,0.5)"`, "attribute fill colour value"],
		[`fill="transparent"`, "attribute fill colour value"],
		[`stroke="#00000080"`, "attribute stroke colour value"],
		[`fill="hsl(0, 0%, 0%)"`, "attribute fill colour value"],
		[`stroke-linejoin="miter-clip"`, "attribute stroke-linejoin value"],
		[`stroke-linecap="arrow"`, "attribute stroke-linecap value"],
		[`fill-rule="even-odd"`, "attribute fill-rule value"],
		[`opacity="50%"`, "attribute opacity as a percentage"],
		[`stroke-width="inherit"`, "attribute stroke-width value inherit"],
	];
	for (const row of rows) {
		const r = refusalOf(icon("", `<path ${row[0]} d="M0 0"/>`));
		assert r.error == SvgMaskError.Unsupported;
		assert r.what == row[1];
	}
}

test "a style element keeps simple class selectors and refuses every other selector by text" {
	const ok = mask(
		icon("", `<style>.a, .b-1 { fill: #000 } /* note */</style>`
			+ `<rect class="a" width="24" height="24"/>`),
		24,
	);
	assert (ok[0] as int32) == 255;
	const type = refusalOf(icon("", `<style>path { fill: #000 }</style>`));
	assert type.error == SvgMaskError.Unsupported && type.what == "css selector path";
	const descendant = refusalOf(icon("", `<style>g .a { fill: #000 }</style>`));
	assert descendant.what == "css selector g .a";
	const media = refusalOf(icon("", `<style>@media print { .a { fill: red } }</style>`));
	assert media.what.startsWith("css at-rule @media");
	const inner = refusalOf(icon("", `<style>.a { filter: blur(2px) }</style>`));
	assert inner.what == "attribute filter";
}

test "text that is not an SVG document is unparsable, by what is wrong with it" {
	assert refusalOf("hello").error == SvgMaskError.Unparsable;
	assert refusalOf("hello").what == "no <svg> element";
	assert refusalOf("<g/>").what == "root element <g> is not <svg>";
	assert refusalOf(`${HEAD}><path d="M0 0"`).what == "an unterminated tag";
	assert refusalOf(`${HEAD}><!-- open`).what == "an unterminated comment";
	assert refusalOf(`${HEAD} fill=red></svg>`).what == "attribute fill without a quoted value";
	assert refusalOf("").what == "no <svg> element";
}

test "an svg inside an svg is refused" {
	const r = refusalOf(icon("", `<svg width="4" height="4"/>`));
	assert r.error == SvgMaskError.Unsupported && r.what == "element <svg> inside <svg>";
}

test "a document without a size is NoSize and names the size it read" {
	const r = refusalOf(`<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0"></svg>`);
	assert r.error == SvgMaskError.NoSize;
	assert r.what == "size 0x0";
}

test "a mask size outside 1 to 8192 is BadSize and names the size" {
	const parsed = svgMaskParse(icon("", `<rect width="24" height="24"/>`));
	assert parsed.ok;
	if (!parsed.ok) { return; }
	const sizes: int32[][] = [[0, 24], [24, 0], [-1, 24], [MAX_SVG_MASK_SIDE + 1, 24], [24, 9000]];
	for (const size of sizes) {
		const drawn = svgMaskRasterize(parsed.value, size[0], size[1]);
		assert !drawn.ok;
		if (!drawn.ok) {
			assert drawn.error.error == SvgMaskError.BadSize;
			assert drawn.error.what == `mask size ${size[0]}x${size[1]}, sides run 1 to 8192`;
		}
	}
	svgMaskFree(parsed.value);
}

test "the source string is copied, not parsed in place" {
	const body: string = `<path d="M4 4H20V20H4Z" fill="#000" id="a"/>`
		+ `<path d="M0 0" fill="#fff" id="b"/>`;
	const svg: string = icon("", body);
	const first = mask(svg, 24);
	const second = mask(svg, 24);
	assert svg == icon("", body);
	for (let i: int32 = 0; i < 576; i++) { assert first[i] == second[i]; }
}

test "a refused source and a freed source leave no live image behind" {
	const before: int32 = svgMaskLive();
	refusalOf(icon("", `<use/>`));
	refusalOf("hello");
	const a = svgMaskParse(icon("", `<rect width="4" height="4"/>`));
	const b = svgMaskParse(icon("", `<rect width="8" height="8"/>`));
	assert a.ok && b.ok;
	if (!a.ok || !b.ok) { return; }
	assert svgMaskLive() == before + 2;
	assert a.value.handle != b.value.handle;
	svgMaskFree(a.value);
	assert svgMaskLive() == before + 1;
	const c = svgMaskParse(icon("", `<rect width="2" height="2"/>`));
	assert c.ok;
	if (c.ok) {
		assert c.value.handle == a.value.handle;
		svgMaskFree(c.value);
	}
	svgMaskFree(b.value);
	assert svgMaskLive() == before;
}
