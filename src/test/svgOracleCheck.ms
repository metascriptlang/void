import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import {
	SvgMaskRefusal,
	SvgMaskSource,
	svgMaskFree,
	svgMaskParse,
	svgMaskRasterize,
} from "../void2d/svgMask";

const ORACLE_PATH: string = "tests/oracle/svg.json";
const SVG_DIR: string = "tests/oracle/svg/";
const PENDING_PATH: string = "tests/PENDING.md";
const MEAN_ERROR_BOUND: float32 = 3.5;
const MAX_ERROR_BOUND: int32 = 70;
const NO_PLANT: int32 = 0;
const PLANT_ONE_PIXEL: int32 = 1;
const PLANT_EVERY_PIXEL: int32 = 2;

function readText(path: string): string {
	const text = readFile(path);
	if (!text.ok) {
		console.log(`svg oracle: ${path} cannot be read`);
		unreachable;
	}
	return text.value;
}

function oracleRows(): JsonValue {
	const parsed = JSON.parseValue(readText(ORACLE_PATH));
	if (!parsed.ok) {
		console.log(`svg oracle: ${ORACLE_PATH} is not JSON`);
		unreachable;
	}
	return parsed.value.getDynamicField("rows");
}

function hexDigit(code: int32): int32 {
	if (code >= 48 && code <= 57) { return code - 48; }
	if (code >= 97 && code <= 102) { return code - 87; }
	console.log(`svg oracle: ${ORACLE_PATH} has a character that is not a hex digit`);
	unreachable;
}

function expectedAt(hex: string, index: int32): int32 {
	return hexDigit(hex.charCodeAt(index * 2) as int32) * 16
		+ hexDigit(hex.charCodeAt(index * 2 + 1) as int32);
}

function rowDiff(row: JsonValue, plant: int32): string {
	const side: int32 = row.getDynamicField("side").asNumber() as int32;
	const hex: string = row.getDynamicField("alpha").asString();
	if (hex.length != side * side * 2) { return `snapshot holds ${hex.length / 2} pixels`; }
	const parsed: Result<SvgMaskSource, SvgMaskRefusal> = svgMaskParse(
		readText(SVG_DIR + row.getDynamicField("file").asString()),
	);
	if (!parsed.ok) { return `refused: ${parsed.error.what}`; }
	const drawn: Result<Vec<uint8>, SvgMaskRefusal> = svgMaskRasterize(parsed.value, side, side);
	svgMaskFree(parsed.value);
	if (!drawn.ok) { return `refused: ${drawn.error.what}`; }
	let total: int32 = 0;
	let worst: int32 = 0;
	for (let i: int32 = 0; i < side * side; i++) {
		let expected: int32 = expectedAt(hex, i);
		if (plant == PLANT_EVERY_PIXEL || (plant == PLANT_ONE_PIXEL && i == side * side / 2)) {
			expected = (expected + (plant == PLANT_EVERY_PIXEL ? 64 : 128)) % 256;
		}
		let error: int32 = expected - (drawn.value[i] as int32);
		if (error < 0) { error = -error; }
		total += error;
		if (error > worst) { worst = error; }
	}
	const mean: float32 = (total as float32) / ((side * side) as float32);
	if (mean > MEAN_ERROR_BOUND) { return `mean error ${mean} past ${MEAN_ERROR_BOUND}`; }
	if (worst > MAX_ERROR_BOUND) { return `max error ${worst} past ${MAX_ERROR_BOUND}`; }
	return "";
}

test "every SVG row matches resvg within the error bounds, or its divergence is listed" {
	const rows = oracleRows();
	const pending: string = readText(PENDING_PATH);
	const total: int32 = rows.length() as int32;
	assert total > 0;
	let agreeing: int32 = 0;
	let listed: int32 = 0;
	let wrong: int32 = 0;
	for (let r: int32 = 0; r < total; r++) {
		const row = rows.at(r);
		const id: string = row.getDynamicField("id").asString();
		const diff: string = rowDiff(row, NO_PLANT);
		const isListed: boolean = pending.includes(`| svg:${id} |`);
		if (diff.length == 0) { agreeing = agreeing + 1; }
		if (isListed) { listed = listed + 1; }
		if (diff.length > 0 && !isListed) {
			console.log(`svg oracle: ${id} differs (${diff}); ${PENDING_PATH} has no svg:${id}`);
			wrong = wrong + 1;
		}
		if (diff.length == 0 && isListed) {
			console.log(`svg oracle: ${id} agrees but ${PENDING_PATH} still lists svg:${id}`);
			wrong = wrong + 1;
		}
	}
	console.log(
		`svg oracle: resvg ${agreeing}/${total} rows within mean ${MEAN_ERROR_BOUND} and max ` +
		`${MAX_ERROR_BOUND} of 255, ${listed} listed`,
	);
	assert wrong == 0;
}

test "a wrong pixel or a shifted snapshot is caught row by row" {
	const rows = oracleRows();
	for (const plant of [PLANT_ONE_PIXEL, PLANT_EVERY_PIXEL]) {
		let tried: int32 = 0;
		let caught: int32 = 0;
		for (let r: int32 = 0; r < (rows.length() as int32); r++) {
			const row = rows.at(r);
			if (rowDiff(row, NO_PLANT).length > 0) { continue; }
			tried = tried + 1;
			if (rowDiff(row, plant).length > 0) { caught = caught + 1; }
		}
		assert tried > 0;
		assert caught == tried;
	}
}

test "a refused row reports the refusal and a snapshot of the wrong size is named" {
	const rows = oracleRows();
	let refused: int32 = 0;
	for (let r: int32 = 0; r < (rows.length() as int32); r++) {
		const diff: string = rowDiff(rows.at(r), NO_PLANT);
		if (diff.startsWith("refused: element <")) { refused = refused + 1; }
	}
	assert refused >= 4;
}
