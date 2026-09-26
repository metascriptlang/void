import { void2dLineBreakClass } from "./lineBreak.h";

export enum LineClass {
	AL,
	BK,
	CR,
	LF,
	NL,
	SP,
	ZW,
	ZWJ,
	CM,
	WJ,
	GL,
	EX,
	CL,
	CP,
	SY,
	OP,
	QU,
	IS,
	NS,
	B2,
	BA,
	BB,
	HY,
	HH,
	CB,
	IN,
	NU,
	HL,
	PR,
	PO,
	ID,
	EB,
	EM,
	JL,
	JV,
	JT,
	H2,
	H3,
	RI,
	AK,
	AP,
	AS,
	VF,
	VI,
}

export struct LineProperty {
	cls: LineClass;
	eastAsian: boolean;
	initialQuote: boolean;
	finalQuote: boolean;
	unassignedPictograph: boolean;
}

struct Unit {
	property: LineProperty;
	dottedCircle: boolean;
}

const DOTTED_CIRCLE: int32 = 0x25CC;

export function lineProperty(codepoint: int32): LineProperty {
	const packed: int32 = void2dLineBreakClass(codepoint);
	return {
		cls: (packed & 63) as LineClass,
		eastAsian: (packed & 64) != 0,
		initialQuote: (packed & 128) != 0,
		finalQuote: (packed & 256) != 0,
		unassignedPictograph: (packed & 512) != 0,
	};
}

function isHardBreak(c: LineClass): boolean {
	return c == LineClass.BK || c == LineClass.CR || c == LineClass.LF || c == LineClass.NL;
}

function carriesMarks(c: LineClass): boolean {
	return !isHardBreak(c) && c != LineClass.SP && c != LineClass.ZW;
}

function isAlphabetic(c: LineClass): boolean {
	return c == LineClass.AL || c == LineClass.HL;
}

function isHyphen(c: LineClass): boolean {
	return c == LineClass.HY || c == LineClass.HH;
}

function isKorean(c: LineClass): boolean {
	return match (c) {
		LineClass.JL | LineClass.JV | LineClass.JT | LineClass.H2 | LineClass.H3 => true,
		_ => false,
	};
}

function opensInitialQuote(c: LineClass): boolean {
	return match (c) {
		LineClass.BK | LineClass.CR | LineClass.LF | LineClass.NL | LineClass.OP => true,
		LineClass.QU | LineClass.GL | LineClass.SP | LineClass.ZW => true,
		_ => false,
	};
}

function closesFinalQuote(c: LineClass): boolean {
	return match (c) {
		LineClass.SP | LineClass.GL | LineClass.WJ | LineClass.CL | LineClass.QU => true,
		LineClass.CP | LineClass.EX | LineClass.IS | LineClass.SY | LineClass.ZW => true,
		LineClass.BK | LineClass.CR | LineClass.LF | LineClass.NL => true,
		_ => false,
	};
}

function startsHyphenatedWord(c: LineClass): boolean {
	return match (c) {
		LineClass.BK | LineClass.CR | LineClass.LF | LineClass.NL | LineClass.SP => true,
		LineClass.ZW | LineClass.CB | LineClass.GL => true,
		_ => false,
	};
}

function classAt(units: Span<Unit>, k: int32): LineClass {
	return units[k].property.cls;
}

function eastAsianAt(units: Span<Unit>, k: int32): boolean {
	return units[k].property.eastAsian;
}

function beforeSpaces(units: Span<Unit>, k: int32): int32 {
	let at: int32 = k;
	while (at >= 0 && classAt(units, at) == LineClass.SP) { at = at - 1; }
	return at;
}

function numberEndsAt(units: Span<Unit>, k: int32): boolean {
	let at: int32 = k;
	while (at >= 0 && (classAt(units, at) == LineClass.SY || classAt(units, at) == LineClass.IS)) {
		at = at - 1;
	}
	return at >= 0 && classAt(units, at) == LineClass.NU;
}

function aksaraBase(units: Span<Unit>, k: int32): boolean {
	const c: LineClass = classAt(units, k);
	return c == LineClass.AK || c == LineClass.AS || units[k].dottedCircle;
}

function quoteBreak(units: Span<Unit>, j: int32, count: int32): boolean {
	const a: LineClass = classAt(units, j - 1);
	const b: LineClass = classAt(units, j);
	if (b == LineClass.QU && !units[j].property.initialQuote) { return false; }
	if (a == LineClass.QU && !units[j - 1].property.finalQuote) { return false; }
	if (b == LineClass.QU && !eastAsianAt(units, j - 1)) { return false; }
	if (b == LineClass.QU && (j + 1 >= count || !eastAsianAt(units, j + 1))) { return false; }
	if (a == LineClass.QU && !eastAsianAt(units, j)) { return false; }
	if (a == LineClass.QU && (j == 1 || !eastAsianAt(units, j - 2))) { return false; }
	return true;
}

function numericBreak(units: Span<Unit>, j: int32, count: int32): boolean {
	const a: LineClass = classAt(units, j - 1);
	const b: LineClass = classAt(units, j);
	if (b == LineClass.PO || b == LineClass.PR) {
		const closes: boolean = a == LineClass.CL || a == LineClass.CP;
		if (closes && numberEndsAt(units, j - 2)) { return false; }
		if (numberEndsAt(units, j - 1)) { return false; }
	}
	if (a == LineClass.PO || a == LineClass.PR) {
		if (b == LineClass.NU) { return false; }
		const opens: boolean = b == LineClass.OP;
		if (opens && j + 1 < count && classAt(units, j + 1) == LineClass.NU) { return false; }
		const opensDecimal: boolean = opens && j + 2 < count &&
			classAt(units, j + 1) == LineClass.IS && classAt(units, j + 2) == LineClass.NU;
		if (opensDecimal) { return false; }
	}
	if (b == LineClass.NU) {
		if (a == LineClass.HY || a == LineClass.IS || numberEndsAt(units, j - 1)) { return false; }
	}
	return true;
}

function aksaraBreak(units: Span<Unit>, j: int32, count: int32): boolean {
	const a: LineClass = classAt(units, j - 1);
	const b: LineClass = classAt(units, j);
	if (a == LineClass.AP && aksaraBase(units, j)) { return false; }
	if (aksaraBase(units, j - 1) && (b == LineClass.VF || b == LineClass.VI)) { return false; }
	const afterVirama: boolean = a == LineClass.VI && j >= 2 && aksaraBase(units, j - 2);
	if (afterVirama && (b == LineClass.AK || units[j].dottedCircle)) { return false; }
	const beforeFinal: boolean = j + 1 < count && classAt(units, j + 1) == LineClass.VF;
	if (aksaraBase(units, j - 1) && aksaraBase(units, j) && beforeFinal) { return false; }
	return true;
}

// UAX #14 LB11-LB31 between units j - 1 and j, in the order the standard applies them.
function unitBreak(units: Span<Unit>, j: int32, count: int32): boolean {
	const a: LineClass = classAt(units, j - 1);
	const b: LineClass = classAt(units, j);
	if (b == LineClass.WJ || a == LineClass.WJ || a == LineClass.GL) { return false; }
	if (b == LineClass.GL && a != LineClass.SP && !isHyphen(a)) { return false; }
	const closing: boolean = b == LineClass.EX || b == LineClass.CL || b == LineClass.CP;
	if (closing || b == LineClass.SY) { return false; }
	const spaced: int32 = beforeSpaces(units, j - 1);
	if (spaced >= 0 && classAt(units, spaced) == LineClass.OP) { return false; }
	const initial: boolean = spaced >= 0 && classAt(units, spaced) == LineClass.QU &&
		units[spaced].property.initialQuote;
	if (initial && (spaced == 0 || opensInitialQuote(classAt(units, spaced - 1)))) { return false; }
	if (b == LineClass.QU && units[j].property.finalQuote) {
		if (j + 1 >= count || closesFinalQuote(classAt(units, j + 1))) { return false; }
	}
	const nextIsNumber: boolean = j + 1 < count && classAt(units, j + 1) == LineClass.NU;
	if (a == LineClass.SP && b == LineClass.IS && nextIsNumber) { return true; }
	if (b == LineClass.IS) { return false; }
	if (b == LineClass.NS && spaced >= 0) {
		const closed: LineClass = classAt(units, spaced);
		if (closed == LineClass.CL || closed == LineClass.CP) { return false; }
	}
	if (b == LineClass.B2 && spaced >= 0 && classAt(units, spaced) == LineClass.B2) {
		return false;
	}
	if (a == LineClass.SP) { return true; }
	if (!quoteBreak(units, j, count)) { return false; }
	if (b == LineClass.CB || a == LineClass.CB) { return true; }
	if (isHyphen(a) && isAlphabetic(b)) {
		if (j == 1 || startsHyphenatedWord(classAt(units, j - 2))) { return false; }
	}
	if (b == LineClass.BA || b == LineClass.HH || b == LineClass.HY || b == LineClass.NS) {
		return false;
	}
	if (a == LineClass.BB) { return false; }
	const hebrewHyphen: boolean = isHyphen(a) && j >= 2 && classAt(units, j - 2) == LineClass.HL;
	if (hebrewHyphen && b != LineClass.HL) { return false; }
	if (a == LineClass.SY && b == LineClass.HL) { return false; }
	if (b == LineClass.IN) { return false; }
	if (isAlphabetic(a) && b == LineClass.NU) { return false; }
	if (a == LineClass.NU && isAlphabetic(b)) { return false; }
	const ideographic: boolean = a == LineClass.ID || a == LineClass.EB || a == LineClass.EM;
	if (a == LineClass.PR && (b == LineClass.ID || b == LineClass.EB || b == LineClass.EM)) {
		return false;
	}
	if (ideographic && b == LineClass.PO) { return false; }
	const affix: boolean = a == LineClass.PR || a == LineClass.PO;
	if (affix && isAlphabetic(b)) { return false; }
	if (isAlphabetic(a) && (b == LineClass.PR || b == LineClass.PO)) { return false; }
	if (!numericBreak(units, j, count)) { return false; }
	const hangul: boolean = b == LineClass.JV || b == LineClass.H2 || b == LineClass.H3;
	if (a == LineClass.JL && (b == LineClass.JL || hangul)) { return false; }
	const vowel: boolean = a == LineClass.JV || a == LineClass.H2;
	if (vowel && (b == LineClass.JV || b == LineClass.JT)) { return false; }
	if ((a == LineClass.JT || a == LineClass.H3) && b == LineClass.JT) { return false; }
	if (isKorean(a) && b == LineClass.PO) { return false; }
	if (a == LineClass.PR && isKorean(b)) { return false; }
	if (isAlphabetic(a) && isAlphabetic(b)) { return false; }
	if (!aksaraBreak(units, j, count)) { return false; }
	if (a == LineClass.IS && isAlphabetic(b)) { return false; }
	const word: boolean = isAlphabetic(a) || a == LineClass.NU;
	if (word && b == LineClass.OP && !eastAsianAt(units, j)) { return false; }
	const closedWord: boolean = isAlphabetic(b) || b == LineClass.NU;
	if (a == LineClass.CP && !eastAsianAt(units, j - 1) && closedWord) { return false; }
	if (a == LineClass.RI && b == LineClass.RI) {
		let run: int32 = 0;
		let at: int32 = j - 1;
		while (at >= 0 && classAt(units, at) == LineClass.RI) {
			run = run + 1;
			at = at - 1;
		}
		return run % 2 == 0;
	}
	const emojiBase: boolean = a == LineClass.EB || units[j - 1].property.unassignedPictograph;
	if (b == LineClass.EM && emojiBase) { return false; }
	return true;
}

// Whether a line may break before each codepoint (UAX #14, UCD 18.0.0); never before the first.
export function lineBreaks(codepoints: Span<int32>): Vec<boolean> {
	const count: int32 = codepoints.length as int32;
	const original: Vec<LineClass> = new Array(0);
	const absorbed: Vec<boolean> = new Array(0);
	const unitOf: Vec<int32> = new Array(0);
	const units: Vec<Unit> = new Array(0);
	for (let i = 0; i < count; i++) {
		const p: LineProperty = lineProperty(codepoints[i]);
		const combining: boolean = p.cls == LineClass.CM || p.cls == LineClass.ZWJ;
		const joins: boolean = combining && i > 0 && carriesMarks(original[i - 1]);
		original.push(p.cls);
		absorbed.push(joins);
		if (!joins) {
			units.push({
				property: combining ? { ...p, cls: LineClass.AL } : p,
				dottedCircle: codepoints[i] == DOTTED_CIRCLE,
			});
		}
		unitOf.push((units.length as int32) - 1);
	}
	const breaks: Vec<boolean> = new Array(0);
	const unitCount: int32 = units.length as int32;
	for (let i = 0; i < count; i++) {
		if (i == 0) {
			breaks.push(false);
			continue;
		}
		const before: LineClass = original[i - 1];
		const after: LineClass = original[i];
		if (before == LineClass.BK) {
			breaks.push(true);
		} else if (before == LineClass.CR && after == LineClass.LF) {
			breaks.push(false);
		} else if (isHardBreak(before)) {
			breaks.push(true);
		} else if (isHardBreak(after) || after == LineClass.SP || after == LineClass.ZW) {
			breaks.push(false);
		} else if (afterZeroWidthSpace(original, i)) {
			breaks.push(true);
		} else if (before == LineClass.ZWJ || absorbed[i]) {
			breaks.push(false);
		} else {
			breaks.push(unitBreak(units, unitOf[i], unitCount));
		}
	}
	return breaks;
}

function afterZeroWidthSpace(original: Span<LineClass>, i: int32): boolean {
	let at: int32 = i - 1;
	while (at >= 0 && original[at] == LineClass.SP) { at = at - 1; }
	return at >= 0 && original[at] == LineClass.ZW;
}
