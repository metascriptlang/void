import "../void2d/textOutlineSwitch";
import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { loadFace, glyphIndex, pageTexel } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	GlyphTile,
	PageKind,
	COVERAGE_OUTLINE_PER_PX,
	acquireOutline,
} from "../void2d/glyphAtlas";

const ORACLE_PATH: string = "tests/oracle/outline.json";
const BASE64: string = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const MAE_BOUND: float32 = 0.05;
const P99_BOUND: float32 = 0.5;
const P99_CLOSED_COUNTER_BOUND: float32 = 0.8;
const INK_LOW: float32 = 0.95;
const INK_HIGH: float32 = 1.04;
const FLOOR_MAE_BOUND: float32 = 0.08;
const FLOOR_P99_BOUND: float32 = 0.4;
const CLOSED_COUNTER_SIZE: float32 = 13.0;
const CLOSED_COUNTER_WIDTH: float32 = 3.5;
const OUTLINE_CASES: int32 = 72;
const FLOOR_CASES: int32 = 18;

function require(ok: boolean, what: string): void {
	if (!ok) {
		console.log(`outline oracle: ${what}`);
		unreachable;
	}
}

struct Measure {
	mae: float32;
	p99: float32;
	ink: float32;
	pixels: int32;
}

const atlas: GlyphAtlas = GlyphAtlas.create(1024, 8);
let facePaths: Vec<string> = [];
let faceIds: Vec<int32> = [];

function faceFor(path: string): int32 {
	for (let i: int32 = 0; i < (facePaths.length as int32); i++) {
		if (facePaths[i].equals(path)) { return faceIds[i]; }
	}
	const face: int32 = try loadFace(path) catch -1;
	require(face >= 0, `${path} did not load`);
	facePaths.push(path);
	faceIds.push(face);
	return face;
}

function decode(text: string): Vec<uint8> {
	let out: Vec<uint8> = new Array(0);
	let bits: int32 = 0;
	let held: int32 = 0;
	for (let i: int32 = 0; i < (text.length as int32); i++) {
		const value: int32 = BASE64.indexOf(text.charAt(i)) as int32;
		if (value < 0) { continue; }
		held = (held << 6) | value;
		bits = bits + 6;
		if (bits >= 8) {
			bits = bits - 8;
			out.push(((held >> bits) & 255) as uint8);
		}
	}
	return out;
}

function oracleCases(): JsonValue {
	const text = readFile(ORACLE_PATH);
	if (!text.ok) {
		console.log(`outline oracle: ${ORACLE_PATH} cannot be read`);
		unreachable;
	}
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) {
		console.log(`outline oracle: ${ORACLE_PATH} is not JSON`);
		unreachable;
	}
	return parsed.value.getDynamicField("cases");
}

function oursAt(atlas: GlyphAtlas, t: GlyphTile, x: int32, y: int32): int32 {
	const col: int32 = x - t.left;
	const row: int32 = y - t.top;
	if (col < 0 || row < 0 || col >= t.width || row >= t.height) { return 0; }
	return pageTexel(atlas.pageHandle(t.page), t.x + col, t.y + row);
}

function measureCase(row: JsonValue, plainInstead: boolean): Measure {
	const face: int32 = faceFor(row.getDynamicField("path").asString());
	const glyph: int32 = glyphIndex(face, row.getDynamicField("codepoint").asNumber() as int32);
	const size: float32 = row.getDynamicField("size").asNumber() as float32;
	const variant: int32 = row.getDynamicField("variant").asNumber() as int32;
	const width: float32 = row.getDynamicField("width").asNumber() as float32;
	const exact: int32 = Math.floor(width * COVERAGE_OUTLINE_PER_PX + 0.5) as int32;
	const lane: int32 = plainInstead ? 0 : exact;
	const key: GlyphKey = {
		kind: PageKind.Coverage, face: face, glyph: glyph, sizePx: size, variant: variant,
		outline: lane,
	};
	const acquired = lane == 0 ? atlas.acquire(key) : atlas.acquireOutline(key);
	require(acquired.ok, `no outline tile for glyph ${glyph} at ${size} px`);
	let histogram: Vec<int32> = new Array(256);
	for (let b = 0; b < 256; b++) { histogram[b] = 0; }
	let sumError: float32 = 0.0;
	let touched: int32 = 0;
	let oursInk: float32 = 0.0;
	let oracleInk: float32 = 0.0;
	if (acquired.ok) {
		const t: GlyphTile = atlas.tile(acquired.value);
		const left: int32 = row.getDynamicField("left").asNumber() as int32;
		const top: int32 = row.getDynamicField("top").asNumber() as int32;
		const w: int32 = row.getDynamicField("w").asNumber() as int32;
		const h: int32 = row.getDynamicField("h").asNumber() as int32;
		const data: Vec<uint8> = decode(row.getDynamicField("data").asString());
		require((data.length as int32) == w * h, "an oracle tile is not w * h bytes");
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const want: int32 = data[y * w + x] as int32;
				const got: int32 = oursAt(atlas, t, left + x, top + y);
				oursInk = oursInk + (got as float32);
				oracleInk = oracleInk + (want as float32);
				if (want == 0 && got == 0) { continue; }
				const off: int32 = got > want ? got - want : want - got;
				sumError = sumError + (off as float32) / 255.0;
				histogram[off] = histogram[off] + 1;
				touched = touched + 1;
			}
		}
		require(
			t.left >= left && t.top >= top,
			`our tile ${t.left},${t.top} starts before the oracle window ${left},${top}`,
		);
		require(
			t.left + t.width <= left + w && t.top + t.height <= top + h,
			"our tile ends after the oracle window",
		);
	}
	let p99: float32 = 0.0;
	let seen: int32 = 0;
	for (let b = 0; b < 256; b++) {
		seen = seen + histogram[b];
		if ((seen as float32) >= (touched as float32) * 0.99) {
			p99 = (b as float32) / 255.0;
			break;
		}
	}
	return {
		mae: touched > 0 ? sumError / (touched as float32) : 0.0,
		p99: p99,
		ink: oracleInk > 0.0 ? oursInk / oracleInk : 1.0,
		pixels: touched,
	};
}

function closesCounters(row: JsonValue): boolean {
	return row.getDynamicField("size").asNumber() == CLOSED_COUNTER_SIZE &&
		row.getDynamicField("width").asNumber() == CLOSED_COUNTER_WIDTH;
}

test "the outline tile agrees with Pillow's FreeType stroke union fill" {
	const cases = oracleCases();
	let worstMae: float32 = 0.0;
	let worstP99: float32 = 0.0;
	let worstClosedP99: float32 = 0.0;
	let lowInk: float32 = 9.0;
	let highInk: float32 = 0.0;
	let measured: int32 = 0;
	for (let i: int32 = 0; i < (cases.length() as int32); i++) {
		const row = cases.at(i);
		if (row.getDynamicField("width").asNumber() == 0.0) { continue; }
		const m = measureCase(row, false);
		measured = measured + 1;
		if (m.mae > worstMae) { worstMae = m.mae; }
		if (closesCounters(row)) {
			if (m.p99 > worstClosedP99) { worstClosedP99 = m.p99; }
		} else if (m.p99 > worstP99) {
			worstP99 = m.p99;
		}
		if (m.ink < lowInk) { lowInk = m.ink; }
		if (m.ink > highInk) { highInk = m.ink; }
	}
	console.log(
		`outline oracle: ${measured} cases, worst mae ${worstMae}, worst p99 ${worstP99}, ` +
		`closed-counter p99 ${worstClosedP99}, ink ${lowInk}..${highInk}`,
	);
	assert measured == OUTLINE_CASES;
	assert worstMae <= MAE_BOUND;
	assert worstP99 <= P99_BOUND;
	assert worstClosedP99 <= P99_CLOSED_COUNTER_BOUND;
	assert lowInk >= INK_LOW && highInk <= INK_HIGH;
}

test "the harness floor: the plain fill against Pillow at width zero" {
	const cases = oracleCases();
	let worstMae: float32 = 0.0;
	let worstP99: float32 = 0.0;
	let measured: int32 = 0;
	for (let i: int32 = 0; i < (cases.length() as int32); i++) {
		const row = cases.at(i);
		if (row.getDynamicField("width").asNumber() != 0.0) { continue; }
		const m = measureCase(row, true);
		measured = measured + 1;
		if (m.mae > worstMae) { worstMae = m.mae; }
		if (m.p99 > worstP99) { worstP99 = m.p99; }
	}
	console.log(
		`outline oracle floor: ${measured} cases, worst mae ${worstMae}, worst p99 ${worstP99}`,
	);
	assert measured == FLOOR_CASES;
	assert worstMae <= FLOOR_MAE_BOUND;
	assert worstP99 <= FLOOR_P99_BOUND;
}

test "the control: a plain fill held against the outline oracle fails every wide case" {
	const cases = oracleCases();
	let failing: int32 = 0;
	let wide: int32 = 0;
	for (let i: int32 = 0; i < (cases.length() as int32); i++) {
		const row = cases.at(i);
		if (row.getDynamicField("width").asNumber() < 2.0) { continue; }
		wide = wide + 1;
		const m = measureCase(row, true);
		if (m.mae > MAE_BOUND && m.ink < INK_LOW) { failing = failing + 1; }
	}
	assert wide == 36;
	assert failing == wide;
}
