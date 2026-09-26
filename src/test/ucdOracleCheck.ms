import { readFile } from "std/fs";
import {
	ClusterBreak,
	ConjunctBreak,
	GraphemeCursor,
	graphemeProperty,
	startGraphemes,
	breaksBefore,
} from "../void2d/grapheme";
import { breakOpportunity } from "../void2d/textLayout";

const GRAPHEME_ROWS: string = "tests/oracle/ucd/GraphemeBreakTest-18.0.0.txt";
const LINE_ROWS: string = "tests/oracle/ucd/LineBreakTest-18.0.0.txt";
const BREAK: string = "÷";
const NEWLINE: int32 = 10;
const SPACE: int32 = 32;
const SHOWN_FAILURES: int32 = 8;
const LINE_ROWS_AGREEING: int32 = 11398;
const LINE_POSITIONS_AGREEING: int32 = 32774;

struct Row {
	codepoints: Vec<int32>;
	breaks: Vec<boolean>;
}

function hexValue(text: string): int32 {
	let value: int32 = 0;
	for (let i = 0; i < (text.byteLength as int32); i++) {
		value = value * 16 + "0123456789ABCDEF".indexOf(text.byteSlice(i, i + 1));
	}
	return value;
}

function parseRow(line: string): Row {
	const tokens = line.split(" ");
	const codepoints: Vec<int32> = new Array(0);
	const breaks: Vec<boolean> = new Array(0);
	for (let i = 1; i < (tokens.length as int32); i += 2) {
		breaks.push(tokens[i - 1].equals(BREAK));
		codepoints.push(hexValue(tokens[i]));
	}
	return { codepoints: codepoints, breaks: breaks };
}

function rows(path: string): Vec<Row> {
	const out: Vec<Row> = new Array(0);
	const text = readFile(path);
	if (!text.ok) {
		console.log(`ucd oracle: cannot read ${path}`);
		return out;
	}
	for (const line of text.value.split("\n")) {
		if (line.byteLength == 0 || line.startsWith("#")) { continue; }
		out.push(parseRow(line));
	}
	return out;
}

function graphemesAgree(row: Row): boolean {
	let cursor: GraphemeCursor = startGraphemes();
	for (let i = 0; i < (row.codepoints.length as int32); i++) {
		if (breaksBefore(cursor, row.codepoints[i]) != row.breaks[i]) { return false; }
	}
	return true;
}

function lineBreaksDisagree(row: Row): int32 {
	let previous: int32 = -1;
	let inked: boolean = false;
	let disagree: int32 = 0;
	for (let i = 0; i < (row.codepoints.length as int32); i++) {
		const codepoint: int32 = row.codepoints[i];
		if (i > 0) {
			const ours: boolean = previous == NEWLINE || breakOpportunity(previous, codepoint, inked);
			if (ours != row.breaks[i]) { disagree = disagree + 1; }
		}
		if (codepoint == NEWLINE) {
			inked = false;
		} else if (codepoint != SPACE) {
			inked = true;
		}
		previous = codepoint;
	}
	return disagree;
}

function described(row: Row): string {
	let out: string = "";
	for (let i = 0; i < (row.codepoints.length as int32); i++) {
		out += `${row.breaks[i] ? BREAK : "x"} ${row.codepoints[i].toString(16)} `;
	}
	return out;
}

test "the property table agrees with the UCD on one codepoint of every class" {
	assert graphemeProperty(0x0D).cluster == ClusterBreak.CR;
	assert graphemeProperty(0x0A).cluster == ClusterBreak.LF;
	assert graphemeProperty(0x7F).cluster == ClusterBreak.Control;
	assert graphemeProperty(0x0300).cluster == ClusterBreak.Extend;
	assert graphemeProperty(0x200D).cluster == ClusterBreak.ZWJ;
	assert graphemeProperty(0x1F1E6).cluster == ClusterBreak.RegionalIndicator;
	assert graphemeProperty(0x0600).cluster == ClusterBreak.Prepend;
	assert graphemeProperty(0x0903).cluster == ClusterBreak.SpacingMark;
	assert graphemeProperty(0x1100).cluster == ClusterBreak.L;
	assert graphemeProperty(0x1160).cluster == ClusterBreak.V;
	assert graphemeProperty(0x11A8).cluster == ClusterBreak.T;
	assert graphemeProperty(0xAC00).cluster == ClusterBreak.LV;
	assert graphemeProperty(0xAC01).cluster == ClusterBreak.LVT;
	assert graphemeProperty(0x41).cluster == ClusterBreak.Other;
	assert graphemeProperty(0x00A9).pictographic && !graphemeProperty(0x41).pictographic;
	assert graphemeProperty(0x094D).conjunct == ConjunctBreak.Linker;
	assert graphemeProperty(0x0915).conjunct == ConjunctBreak.Consonant;
	assert graphemeProperty(0x0300).conjunct == ConjunctBreak.Extend;
}

test "grapheme boundaries agree with every row of the UCD's GraphemeBreakTest" {
	const all = rows(GRAPHEME_ROWS);
	let agreed: int32 = 0;
	let shown: int32 = 0;
	for (const row of all) {
		if (graphemesAgree(row)) {
			agreed = agreed + 1;
		} else if (shown < SHOWN_FAILURES) {
			shown = shown + 1;
			console.log(`ucd oracle: grapheme row disagrees: ${described(row)}`);
		}
	}
	console.log(`ucd oracle: GraphemeBreakTest ${agreed}/${all.length} rows agree`);
	assert (all.length as int32) > 0 && agreed == (all.length as int32);
}

test "line breaks against the UCD's LineBreakTest, printed as a pass rate" {
	const all = rows(LINE_ROWS);
	let agreed: int32 = 0;
	let positions: int32 = 0;
	let wrong: int32 = 0;
	for (const row of all) {
		const disagree: int32 = lineBreaksDisagree(row);
		if (disagree == 0) { agreed = agreed + 1; }
		wrong = wrong + disagree;
		positions = positions + (row.codepoints.length as int32) - 1;
	}
	console.log(
		`ucd oracle: LineBreakTest ${agreed}/${all.length} rows and ` +
		`${positions - wrong}/${positions} positions agree with void2d's rule`,
	);
	assert agreed == LINE_ROWS_AGREEING && positions - wrong == LINE_POSITIONS_AGREEING;
}
