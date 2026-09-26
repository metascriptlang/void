import { readFile } from "std/fs";
import { loadFace, faceMetrics, decorationMetrics, faceHeights } from "../void2d/face";
import { DEFAULT_FONT, addFont } from "../void2d/font";
import { TextLayout } from "../void2d/textLayout";

const METRICS_PATH: string = "tests/oracle/metrics.json";
const SHAPE_PATH: string = "tests/oracle/shape.json";
const UNIT_TOLERANCE: float64 = 0.05;

let mismatches: int32 = 0;
let compared: int32 = 0;

function agree(where: string, name: string, expected: float64, actual: float64): void {
	compared = compared + 1;
	if (Math.abs(expected - actual) > UNIT_TOLERANCE) {
		mismatches = mismatches + 1;
		console.log(`font oracle: ${where} ${name}: oracle ${expected}, void ${actual}`);
	}
}

test "font and decoration metrics agree with fontTools, broken tables included" {
	const text = readFile(METRICS_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const fonts = parsed.value.getDynamicField("fonts");
	mismatches = 0;
	compared = 0;
	const count: int32 = fonts.length() as int32;
	for (let i: int32 = 0; i < count; i++) {
		const row = fonts.at(i);
		const path: string = row.getDynamicField("path").asString();
		const face = try loadFace(path) catch -1;
		assert face >= 0;
		const em: float32 = row.getDynamicField("unitsPerEm").asNumber() as float32;
		const v = faceMetrics(face, em);
		const d = decorationMetrics(face, em);
		const h = faceHeights(face);
		const expect = (name: string): float64 => row.getDynamicField(name).asNumber();
		agree(path, "ascent", expect("ascent"), v.ascent as float64);
		agree(path, "descent", expect("descent"), v.descent as float64);
		agree(path, "lineGap", expect("lineGap"), v.lineGap as float64);
		agree(path, "underlineTop", expect("underlineTop"), d.underlineTop as float64);
		agree(path, "underlineThickness", expect("underlineThickness"), d.underlineThickness as float64);
		agree(path, "strikethroughTop", expect("strikethroughTop"), d.strikethroughTop as float64);
		agree(path, "strikethroughThickness", expect("strikethroughThickness"), d.strikethroughThickness as float64);
		agree(path, "icWidth", expect("icWidth"), (h.icWidth * em) as float64);
		agree(path, "exHeight", expect("exHeight"), (h.exHeight * em) as float64);
		agree(path, "capHeight", expect("capHeight"), (h.capHeight * em) as float64);
		agree(path, "icWidthEstimate", expect("icWidthEstimate"), (h.icWidthEstimate * em) as float64);
		agree(path, "exHeightEstimate", expect("exHeightEstimate"), (h.exHeightEstimate * em) as float64);
		agree(path, "capHeightEstimate", expect("capHeightEstimate"), (h.capHeightEstimate * em) as float64);
		agree(path, "lineHeight", expect("lineHeight"), (h.lineHeight * em) as float64);
	}
	console.log(`font oracle: fontTools metrics ${count} fonts, ${compared - mismatches}/${compared} values agree`);
	assert count > 0;
	assert mismatches == 0;
}

test "cmap glyph ids and kerned pen positions agree with HarfBuzz, GSUB off" {
	const text = readFile(SHAPE_PATH);
	assert text.ok;
	const parsed = JSON.parseValue(text.value);
	assert parsed.ok;
	const rows = parsed.value.getDynamicField("rows");
	mismatches = 0;
	compared = 0;
	const count: int32 = rows.length() as int32;
	for (let i: int32 = 0; i < count; i++) {
		const row = rows.at(i);
		const path: string = row.getDynamicField("path").asString();
		const sample: string = row.getDynamicField("text").asString();
		const em: float32 = row.getDynamicField("unitsPerEm").asNumber() as float32;
		const glyphs = row.getDynamicField("glyphs");
		const xs = row.getDynamicField("x");
		const l = TextLayout.layout(sample, {
			font: try addFont(path) catch DEFAULT_FONT,
			size: em,
			letterSpacing: 0.0,
			lineSpacing: 0.0,
			maxWidth: 0.0,
			align: 0.0,
		});
		const expected: int32 = glyphs.length() as int32;
		if ((l.glyphs.length as int32) != expected) {
			mismatches = mismatches + 1;
			console.log(`font oracle: "${sample}" has ${l.glyphs.length} glyphs in void, ${expected} in HarfBuzz`);
			continue;
		}
		for (let g: int32 = 0; g < expected; g++) {
			agree(`"${sample}" glyph ${g}`, "id", glyphs.at(g).asNumber(), l.glyphs[g].glyph as float64);
			agree(`"${sample}" glyph ${g}`, "x", xs.at(g).asNumber(), l.glyphs[g].x as float64);
		}
	}
	console.log(`font oracle: HarfBuzz kerning ${count} rows, ${compared - mismatches}/${compared} values agree`);
	assert count > 0;
	assert mismatches == 0;
}
