import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { loadFace } from "../void2d/face";
import {
	ShapeDirection,
	shaperBegin,
	shaperCodepoint,
	shaperEnd,
	shaperFeature,
	shaperGlyph,
} from "../void2d/shaper";

const ORACLE_PATH: string = "tests/oracle/shapeFull.json";
const PENDING_PATH: string = "tests/PENDING.md";
const NO_PLANT: int32 = 0;
const PLANT_GLYPH: int32 = 1;
const PLANT_CLUSTER: int32 = 2;
const PLANT_OFFSET: int32 = 3;
const COMPARE_VALUES: int32 = 0;
const COMPARE_ALL: int32 = 1;
const COMPARE_CLUSTERS: int32 = 2;

let facePaths: Vec<string> = [];
let faceIds: Vec<int32> = [];
let valuesCompared: int32 = 0;

function faceFor(path: string): int32 {
	for (let i: int32 = 0; i < (facePaths.length as int32); i++) {
		if (facePaths[i].equals(path)) { return faceIds[i]; }
	}
	const face: int32 = try loadFace(path) catch -1;
	if (face < 0) {
		console.log(`shape oracle: ${path} did not load`);
		unreachable;
	}
	facePaths.push(path);
	faceIds.push(face);
	return face;
}

function directionOf(code: int32): ShapeDirection {
	return match (code) {
		1 => ShapeDirection.Ltr,
		2 => ShapeDirection.Rtl,
		_ => ShapeDirection.Unknown,
	};
}

function differs(what: string, expected: int32, actual: int32): string {
	valuesCompared = valuesCompared + 1;
	return expected == actual ? "" : `${what} ${actual}, oracle ${expected}`;
}

function rowDiff(row: JsonValue, plant: int32, compare: int32): string {
	const face: int32 = faceFor(row.getDynamicField("path").asString());
	shaperBegin(face, directionOf(row.getDynamicField("direction").asNumber() as int32));
	const features = row.getDynamicField("features");
	for (let f: int32 = 0; f < (features.length() as int32); f++) {
		const feature = features.at(f);
		shaperFeature(feature.at(0).asString(), feature.at(1).asNumber() as int32);
	}
	const codepoints = row.getDynamicField("codepoints");
	for (let c: int32 = 0; c < (codepoints.length() as int32); c++) {
		shaperCodepoint(codepoints.at(c).asNumber() as int32);
	}
	const count: int32 = shaperEnd();
	const expected = row.getDynamicField("glyphs");
	const expectedCount: int32 = expected.length() as int32;
	if (compare == COMPARE_CLUSTERS && expectedCount != count) { return ""; }
	let first: string = differs("glyph count", expectedCount, count);
	if (first.length > 0) { return first; }
	const rtl: boolean = row.getDynamicField("runDirection").asString().equals("rtl");
	for (let g: int32 = 0; g < count; g++) {
		const want = expected.at(g);
		const got = shaperGlyph(g);
		const where: string = `glyph ${g}`;
		const plantedGlyph: int32 = (plant == PLANT_GLYPH && g == 0) ? 1 : 0;
		const plantedCluster: int32 = (plant == PLANT_CLUSTER && g == 0) ? 1 : 0;
		const plantedOffset: int32 = (plant == PLANT_OFFSET && g == 0) ? 1 : 0;
		if (compare != COMPARE_CLUSTERS) {
			first = differs(`${where} id`, (want.at(0).asNumber() as int32) + plantedGlyph, got.glyph);
			if (first.length > 0) { return first; }
		}
		if (compare != COMPARE_VALUES) {
			first = differs(
				`${where} cluster`, (want.at(1).asNumber() as int32) + plantedCluster, got.index,
			);
			if (first.length > 0) { return first; }
		}
		if (compare == COMPARE_CLUSTERS) { continue; }
		first = differs(`${where} advanceX`, want.at(2).asNumber() as int32, got.advanceX);
		if (first.length > 0) { return first; }
		first = differs(`${where} advanceY`, want.at(3).asNumber() as int32, got.advanceY);
		if (first.length > 0) { return first; }
		first = differs(
			`${where} offsetX`, (want.at(4).asNumber() as int32) + plantedOffset, got.offsetX,
		);
		if (first.length > 0) { return first; }
		first = differs(`${where} offsetY`, want.at(5).asNumber() as int32, got.offsetY);
		if (first.length > 0) { return first; }
		const direction: ShapeDirection = rtl ? ShapeDirection.Rtl : ShapeDirection.Ltr;
		first = differs(`${where} run direction`, direction as int32, got.direction as int32);
		if (first.length > 0) { return first; }
	}
	return "";
}

function oracleRows(): JsonValue {
	const text = readFile(ORACLE_PATH);
	if (!text.ok) {
		console.log(`shape oracle: ${ORACLE_PATH} cannot be read`);
		unreachable;
	}
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) {
		console.log(`shape oracle: ${ORACLE_PATH} is not JSON`);
		unreachable;
	}
	return parsed.value.getDynamicField("rows");
}

function judge(id: string, kind: string, diff: string, listed: boolean): int32 {
	const entry: string = `${kind}:${id}`;
	if (diff.length > 0 && !listed) {
		console.log(`shape oracle: ${id} differs (${diff}); ${PENDING_PATH} has no ${entry}`);
		return 1;
	}
	if (diff.length == 0 && listed) {
		console.log(`shape oracle: ${id} agrees but ${PENDING_PATH} still lists ${entry}`);
		return 1;
	}
	return 0;
}

test "every oracle row is shaped as HarfBuzz does, or its divergence is listed" {
	const rows = oracleRows();
	const pendingText = readFile(PENDING_PATH);
	if (!pendingText.ok) {
		console.log(`shape oracle: ${PENDING_PATH} cannot be read`);
		unreachable;
	}
	const pending: string = pendingText.value;
	const total: int32 = rows.length() as int32;
	assert total > 0;
	valuesCompared = 0;
	let agreeing: int32 = 0;
	let glyphsAgreeing: int32 = 0;
	let listed: int32 = 0;
	let wrong: int32 = 0;
	for (let r: int32 = 0; r < total; r++) {
		const row = rows.at(r);
		const id: string = row.getDynamicField("id").asString();
		const glyphDiff: string = rowDiff(row, NO_PLANT, COMPARE_VALUES);
		const clusterDiff: string = rowDiff(row, NO_PLANT, COMPARE_CLUSTERS);
		const glyphListed: boolean = pending.includes(`| shape:${id} |`);
		const clusterListed: boolean = pending.includes(`| shape-cluster:${id} |`);
		if (glyphDiff.length == 0) { glyphsAgreeing = glyphsAgreeing + 1; }
		if (glyphDiff.length == 0 && clusterDiff.length == 0) { agreeing = agreeing + 1; }
		wrong = wrong + judge(id, "shape", glyphDiff, glyphListed);
		wrong = wrong + judge(id, "shape-cluster", clusterDiff, clusterListed);
		if (glyphListed || clusterListed) { listed = listed + 1; }
	}
	console.log(
		`shape oracle: HarfBuzz full ${agreeing}/${total} rows agree, ${glyphsAgreeing}/${total} ` +
		`on glyphs, advances and offsets, ${listed} listed, ${valuesCompared} values compared`,
	);
	assert wrong == 0;
}

test "a wrong glyph id, cluster or offset in the snapshot is caught row by row" {
	const rows = oracleRows();
	for (const plant of [PLANT_GLYPH, PLANT_CLUSTER, PLANT_OFFSET]) {
		let caught: int32 = 0;
		let tried: int32 = 0;
		for (let r: int32 = 0; r < (rows.length() as int32); r++) {
			const row = rows.at(r);
			if (rowDiff(row, NO_PLANT, COMPARE_ALL).length > 0) { continue; }
			if (row.getDynamicField("glyphs").length() == 0) { continue; }
			tried = tried + 1;
			if (rowDiff(row, plant, COMPARE_ALL).length > 0) { caught = caught + 1; }
		}
		assert tried > 0;
		assert caught == tried;
	}
}

struct Pass {
	text: string;
	first: ShapeDirection;
	mixed: boolean;
}

function passOf(row: JsonValue, direction: ShapeDirection): Pass {
	const face: int32 = faceFor(row.getDynamicField("path").asString());
	shaperBegin(face, direction);
	const features = row.getDynamicField("features");
	for (let f: int32 = 0; f < (features.length() as int32); f++) {
		const feature = features.at(f);
		shaperFeature(feature.at(0).asString(), feature.at(1).asNumber() as int32);
	}
	const codepoints = row.getDynamicField("codepoints");
	for (let c: int32 = 0; c < (codepoints.length() as int32); c++) {
		shaperCodepoint(codepoints.at(c).asNumber() as int32);
	}
	const count: int32 = shaperEnd();
	let out: Pass = { text: "", first: ShapeDirection.Unknown, mixed: false };
	for (let g: int32 = 0; g < count; g++) {
		const got = shaperGlyph(g);
		if (g == 0) { out.first = got.direction; }
		if (got.direction != out.first) { out.mixed = true; }
		out.text += `${got.glyph},${got.advanceX},${got.advanceY},${got.offsetX},` +
			`${got.offsetY},${got.index},${got.codepoint},${got.direction as int32};`;
	}
	return out;
}

test "a pass forced to the direction auto mode chose gives the glyphs auto mode gave" {
	const rows = oracleRows();
	let compared: int32 = 0;
	let mixed: int32 = 0;
	for (let r: int32 = 0; r < (rows.length() as int32); r++) {
		const row = rows.at(r);
		const auto: Pass = passOf(row, ShapeDirection.Unknown);
		if (auto.text.length == 0) { continue; }
		if (auto.mixed) {
			mixed = mixed + 1;
			continue;
		}
		const forced: Pass = passOf(row, auto.first);
		if (!forced.text.equals(auto.text)) {
			const id: string = row.getDynamicField("id").asString();
			console.log(`shape oracle: ${id} differs when forced`);
			console.log(`  auto   ${auto.text}`);
			console.log(`  forced ${forced.text}`);
		}
		assert forced.text.equals(auto.text);
		compared = compared + 1;
	}
	console.log(
		`shape oracle: ${compared} rows give the same glyphs forced and auto, ` +
		`${mixed} mix directions`,
	);
	assert compared > 60;
}
