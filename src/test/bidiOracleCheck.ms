import { readFile } from "std/fs";
import { sha256, toHex } from "std/crypto/sha256";
import {
	BidiClass,
	bidiClassOf,
	bracketCode,
	removedByX9,
	reorderLine,
	resetLineEnds,
	resolveLevels,
} from "../void2d/bidi";
import { TextDirection } from "../void2d/textDirection";

const BIDI_TEST: string = "deps/ucd/BidiTest.txt";
const BIDI_CHARACTER_TEST: string = "deps/ucd/BidiCharacterTest.txt";
const PINS: string = "tests/oracle/ucd/bidiConformance.sha256";
const BIDI_TEST_LINES: int32 = 490846;
const BIDI_TEST_CASES: int32 = 770241;
const BIDI_CHARACTER_ROWS: int32 = 91707;
const SHOWN_FAILURES: int32 = 8;
const REMOVED: int32 = -1;
const NAME_KEYS: int32[23] = [
	0x4c, 0x52, 0x4c41, 0x4e45, 0x5345, 0x5445, 0x4e41, 0x5343, 0x4d534e, 0x4e42, 0x42,
	0x53, 0x5357, 0x4e4f, 0x45524c, 0x4f524c, 0x454c52, 0x4f4c52, 0x464450, 0x49524c,
	0x494c52, 0x495346, 0x494450,
];

function blank(c: int32): boolean {
	return c == 32 || c == 9 || c == 13;
}

function digitValue(c: int32): int32 {
	if (c >= 48 && c <= 57) { return c - 48; }
	if (c >= 65 && c <= 70) { return c - 55; }
	if (c >= 97 && c <= 102) { return c - 87; }
	return -1;
}

function lineEnd(bytes: Readonly<Span<char>>, at: int32): int32 {
	const total: int32 = bytes.length as int32;
	let end: int32 = at;
	while (end < total && ((bytes[end] as uint8) as int32) != 10) { end = end + 1; }
	return end;
}

function byteAt(bytes: Readonly<Span<char>>, at: int32): int32 {
	return (bytes[at] as uint8) as int32;
}

function emptied(ref values: Vec<int32>): void {
	while ((values.length as int32) > 0) { values.pop(); }
}

function colonAfter(bytes: Readonly<Span<char>>, from: int32, end: int32): int32 {
	let at: int32 = from;
	while (at < end && byteAt(bytes, at) != 58) { at = at + 1; }
	return at;
}

function nameKey(bytes: Readonly<Span<char>>, from: int32, to: int32): int32 {
	let key: int32 = 0;
	for (let i = from; i < to; i++) { key = key | (byteAt(bytes, i) << ((i - from) * 8)); }
	return key;
}

function classNamed(bytes: Readonly<Span<char>>, from: int32, to: int32): BidiClass {
	const key: int32 = nameKey(bytes, from, to);
	for (let k = 0; k < 23; k++) {
		if (NAME_KEYS[k] == key) { return k as BidiClass; }
	}
	console.log(`bidi oracle: unknown class name at byte ${from}`);
	unreachable;
}

function numbers(bytes: Readonly<Span<char>>, from: int32, end: int32, ref out: Vec<int32>): void {
	let at: int32 = from;
	while (at < end) {
		if (blank(byteAt(bytes, at))) {
			at = at + 1;
			continue;
		}
		if (byteAt(bytes, at) == 120) {
			out.push(REMOVED);
			at = at + 1;
			continue;
		}
		let value: int32 = 0;
		while (at < end && digitValue(byteAt(bytes, at)) >= 0) {
			value = value * 10 + digitValue(byteAt(bytes, at));
			at = at + 1;
		}
		out.push(value);
	}
}

function agrees(
	classes: Readonly<Span<BidiClass>>,
	brackets: Readonly<Span<int32>>,
	expectedLevels: Readonly<Span<int32>>,
	expectedOrder: Readonly<Span<int32>>,
	direction: TextDirection,
	expectedParagraph: int32,
): boolean {
	const count: int32 = classes.length as int32;
	let resolved: Vec<int32> = new Array(0);
	const paragraph: int32 = resolveLevels(classes, brackets, direction, resolved);
	if (expectedParagraph >= 0 && paragraph != expectedParagraph) { return false; }
	resetLineEnds(classes, paragraph, 0, count, resolved);
	let keptLevels: Vec<int32> = new Array(0);
	let keptIndex: Vec<int32> = new Array(0);
	if ((expectedLevels.length as int32) != count) { return false; }
	for (let i = 0; i < count; i++) {
		if (removedByX9(classes[i])) {
			if (expectedLevels[i] != REMOVED) { return false; }
			continue;
		}
		if (resolved[i] != expectedLevels[i]) { return false; }
		keptLevels.push(resolved[i]);
		keptIndex.push(i);
	}
	const kept: int32 = keptLevels.length as int32;
	if ((expectedOrder.length as int32) != kept) { return false; }
	let order: Vec<int32> = new Array(0);
	reorderLine(keptLevels, 0, kept, order);
	for (let v = 0; v < kept; v++) {
		if (keptIndex[order[v]] != expectedOrder[v]) { return false; }
	}
	return true;
}

function described(
	classes: Readonly<Span<BidiClass>>,
	levels: Readonly<Span<int32>>,
	direction: TextDirection,
): string {
	let out: string = `${direction.toString()}:`;
	for (let i = 0; i < (classes.length as int32); i++) { out += ` ${classes[i].toString()}`; }
	out += " | levels";
	for (const level of levels) { out += ` ${level}`; }
	return out;
}

struct Verdict {
	rows: int32;
	cases: int32;
	agreed: int32;
}

const FILE_MISSING: int32 = -1;

function missing(path: string): void {
	console.log(`bidi oracle: ${path} is missing: run setup.sh`);
}

function bidiTestVerdict(): Verdict {
	const text = readFile(BIDI_TEST);
	if (!text.ok) {
		missing(BIDI_TEST);
		return { rows: FILE_MISSING, cases: 0, agreed: 0 };
	}
	const bytes: Readonly<Span<char>> = text.value;
	const total: int32 = bytes.length as int32;
	let rows: int32 = 0;
	let cases: int32 = 0;
	let agreed: int32 = 0;
	let shown: int32 = 0;
	let expectedLevels: Vec<int32> = new Array(0);
	let expectedOrder: Vec<int32> = new Array(0);
	let at: int32 = 0;
	while (at < total) {
		const end: int32 = lineEnd(bytes, at);
		const first: int32 = at < end ? byteAt(bytes, at) : 10;
		if (first == 64) {
			const colon: int32 = colonAfter(bytes, at, end);
			if (byteAt(bytes, at + 1) == 76) {
				emptied(expectedLevels);
				numbers(bytes, colon + 1, end, expectedLevels);
			} else {
				emptied(expectedOrder);
				numbers(bytes, colon + 1, end, expectedOrder);
			}
		} else if (first != 35 && first != 10 && first != 13) {
			let classes: Vec<BidiClass> = new Array(0);
			const noBrackets: Vec<int32> = new Array(0);
			let cursor: int32 = at;
			while (cursor < end && byteAt(bytes, cursor) != 59) {
				if (blank(byteAt(bytes, cursor))) {
					cursor = cursor + 1;
					continue;
				}
				let stop: int32 = cursor;
				while (stop < end && !blank(byteAt(bytes, stop)) && byteAt(bytes, stop) != 59) {
					stop = stop + 1;
				}
				classes.push(classNamed(bytes, cursor, stop));
				cursor = stop;
			}
			let bits: Vec<int32> = new Array(0);
			numbers(bytes, cursor + 1, end, bits);
			rows = rows + 1;
			for (let bit = 0; bit < 3; bit++) {
				if ((bits[0] & (1 << bit)) == 0) { continue; }
				const direction: TextDirection = match (bit) {
					0 => TextDirection.Auto,
					1 => TextDirection.Ltr,
					_ => TextDirection.Rtl,
				};
				cases = cases + 1;
				if (agrees(classes, noBrackets, expectedLevels, expectedOrder, direction, -1)) {
					agreed = agreed + 1;
				} else if (shown < SHOWN_FAILURES) {
					shown = shown + 1;
					console.log(
						`bidi oracle: BidiTest case disagrees: ` +
						`${described(classes, expectedLevels, direction)}`,
					);
				}
			}
		}
		at = end + 1;
	}
	return { rows: rows, cases: cases, agreed: agreed };
}

function bidiCharacterVerdict(): Verdict {
	const text = readFile(BIDI_CHARACTER_TEST);
	if (!text.ok) {
		missing(BIDI_CHARACTER_TEST);
		return { rows: FILE_MISSING, cases: 0, agreed: 0 };
	}
	const bytes: Readonly<Span<char>> = text.value;
	const total: int32 = bytes.length as int32;
	let rows: int32 = 0;
	let agreed: int32 = 0;
	let shown: int32 = 0;
	let at: int32 = 0;
	while (at < total) {
		const end: int32 = lineEnd(bytes, at);
		const first: int32 = at < end ? byteAt(bytes, at) : 10;
		if (first != 35 && first != 10 && first != 13) {
			let fields: Vec<int32> = new Array(0);
			fields.push(at);
			for (let i = at; i < end; i++) {
				if (byteAt(bytes, i) == 59) { fields.push(i + 1); }
			}
			fields.push(end + 1);
			let classes: Vec<BidiClass> = new Array(0);
			let brackets: Vec<int32> = new Array(0);
			let expectedLevels: Vec<int32> = new Array(0);
			let expectedOrder: Vec<int32> = new Array(0);
			let cursor: int32 = fields[0];
			while (cursor < fields[1] - 1) {
				if (blank(byteAt(bytes, cursor))) {
					cursor = cursor + 1;
					continue;
				}
				let value: int32 = 0;
				while (cursor < fields[1] - 1 && digitValue(byteAt(bytes, cursor)) >= 0) {
					value = value * 16 + digitValue(byteAt(bytes, cursor));
					cursor = cursor + 1;
				}
				classes.push(bidiClassOf(value));
				brackets.push(bracketCode(value));
			}
			let direction: Vec<int32> = new Array(0);
			numbers(bytes, fields[1], fields[2] - 1, direction);
			let paragraph: Vec<int32> = new Array(0);
			numbers(bytes, fields[2], fields[3] - 1, paragraph);
			numbers(bytes, fields[3], fields[4] - 1, expectedLevels);
			numbers(bytes, fields[4], fields[5] - 1, expectedOrder);
			const mode: TextDirection = match (direction[0]) {
				0 => TextDirection.Ltr,
				1 => TextDirection.Rtl,
				_ => TextDirection.Auto,
			};
			rows = rows + 1;
			if (agrees(classes, brackets, expectedLevels, expectedOrder, mode, paragraph[0])) {
				agreed = agreed + 1;
			} else if (shown < SHOWN_FAILURES) {
				shown = shown + 1;
				console.log(
					`bidi oracle: BidiCharacterTest row disagrees at byte ${at}: ` +
					`${described(classes, expectedLevels, mode)}`,
				);
			}
		}
		at = end + 1;
	}
	return { rows: rows, cases: rows, agreed: agreed };
}

test "the BiDi conformance files are the pinned ones" {
	const pins = readFile(PINS);
	assert pins.ok;
	let checked: int32 = 0;
	for (const line of pins.value.split("\n")) {
		if (line.byteLength == 0 || line.startsWith("#")) { continue; }
		const parts = line.trim().split("  ");
		assert (parts.length as int32) == 2;
		const path: string = `deps/ucd/${parts[1]}`;
		const file = readFile(path);
		if (!file.ok) {
			missing(path);
			assert file.ok;
			continue;
		}
		const raw: Readonly<Span<char>> = file.value;
		let data: Vec<uint8> = new Array(0);
		for (let i = 0; i < (raw.length as int32); i++) { data.push(raw[i] as uint8); }
		const digest: string = sha256(data).toHex();
		if (!digest.equals(parts[0])) {
			console.log(
				`bidi oracle: ${path} is ${digest}, the pin is ${parts[0]}: run setup.sh`,
			);
		}
		assert digest.equals(parts[0]);
		checked = checked + 1;
	}
	console.log(`bidi oracle: ${checked} conformance files match their sha256 pins`);
	assert checked == 2;
}

test "levels and order agree with every case of the UCD's BidiTest" {
	const verdict: Verdict = bidiTestVerdict();
	console.log(
		`bidi oracle: BidiTest ${verdict.agreed}/${verdict.cases} cases agree ` +
		`(${verdict.rows} rows)`,
	);
	assert verdict.rows == BIDI_TEST_LINES && verdict.cases == BIDI_TEST_CASES;
	assert verdict.agreed == verdict.cases;
}

test "levels, paragraph level and order agree with every row of the UCD's BidiCharacterTest" {
	const verdict: Verdict = bidiCharacterVerdict();
	console.log(`bidi oracle: BidiCharacterTest ${verdict.agreed}/${verdict.rows} rows agree`);
	assert verdict.rows == BIDI_CHARACTER_ROWS;
	assert verdict.agreed == verdict.rows;
}


test "a paragraph separator inside the layout paragraph ends the embeddings, starts no paragraph" {
	const noBrackets: Vec<int32> = new Array(0);
	const embedded: Vec<BidiClass> = [
		BidiClass.LRE, BidiClass.L, BidiClass.B, BidiClass.L,
	];
	let levels: Vec<int32> = new Array(0);
	assert resolveLevels(embedded, noBrackets, TextDirection.Ltr, levels) == 0;
	assert levels[1] == 2 && levels[2] == 0 && levels[3] == 0;
	const kept: Vec<BidiClass> = [BidiClass.R, BidiClass.B, BidiClass.L];
	let again: Vec<int32> = new Array(0);
	assert resolveLevels(kept, noBrackets, TextDirection.Auto, again) == 1;
	assert again[0] == 1 && again[1] == 1 && again[2] == 2;
}
