import { Str, eq, startsWith } from "./text";

export const SVG_NOT_SVG: int32 = -1;
export const SVG_REFUSED: int32 = -2;
export const SVG_NO_SIZE: int32 = -3;
export const SVG_NO_MEMORY: int32 = -4;
export const SVG_BAD_HANDLE: int32 = -5;
export const SVG_BAD_SIZE: int32 = -6;
export const SVG_TOO_LARGE: int32 = -7;

const NAME_SHOWN: int32 = 48;
const ID_BYTES: int32 = 63;
const OPACITY_ON_GROUP: int32 = 1;
const OPACITY_IN_STYLE_RULE: int32 = 2;
const LOWER_LETTERS: string = "abcdefghijklmnopqrstuvwxyz";

const ELEMENTS: string[] = [
	"svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs",
	"linearGradient", "radialGradient", "stop", "style", "title", "desc", "metadata",
];

const DENIED_PROPERTIES: string[] = [
	"clip-path", "clip", "mask", "filter", "marker", "marker-start", "marker-mid", "marker-end",
	"visibility", "vector-effect", "mix-blend-mode", "isolation", "shape-rendering",
	"transform-origin", "transform-box",
];

const CAPS: string[] = ["butt", "round", "square"];
const JOINS: string[] = ["miter", "round", "bevel"];
const FILL_RULES: string[] = ["nonzero", "evenodd"];
const OPACITIES: string[] = ["opacity", "fill-opacity", "stroke-opacity", "stop-opacity"];
const COLOUR_NAMES: string[] = [
	"red", "green", "blue", "yellow", "cyan", "magenta", "black", "grey", "gray", "white",
];

class Scan {
	text: string = "";
	bytes: uint8[] = [];
	lowered: uint8[] = [];
	length: int32 = 0;
	reason: string = "";
	svgCount: int32 = 0;
	opacityRefusedAs: int32 = 0;
	gradientIds: Str[] = [];
	paintRefs: Str[] = [];
}

// isSpace of svgMask.c: the five characters, not \v and not the terminator.
function isBlank(c: int32): boolean {
	return c == 32 || c == 9 || c == 10 || c == 13 || c == 12;
}

function isContinuation(c: int32): boolean {
	return c >= 128 && c < 192;
}

// The reason shows at most NAME_SHOWN bytes of a name, backed up to a character boundary, and
// writes the ASCII upper case letters that a lowered copy changed as their lower case.
function shown(sc: Scan, name: Str): string {
	let n = name.e - name.s;
	if (n > NAME_SHOWN) { n = NAME_SHOWN; }
	while (n > 0 && name.s + n < sc.length && isContinuation(sc.bytes[name.s + n] as int32)) { n -= 1; }
	const end = name.s + n;
	let out = "";
	let run = name.s;
	for (let i = name.s; i < end; i++) {
		const c = name.b[i] as int32;
		if (c != (sc.bytes[i] as int32)) {
			out += sc.text.byteSlice(run, i);
			out += LOWER_LETTERS.byteSlice(c - 97, c - 96);
			run = i + 1;
		}
	}
	out += sc.text.byteSlice(run, end);
	return out;
}

function refuse(sc: Scan, code: int32, kind: string, name: Str, tail: string): int32 {
	sc.reason = kind + shown(sc, name) + tail;
	return code;
}

function notSvg(sc: Scan, what: string): int32 {
	sc.reason = what;
	return SVG_NOT_SVG;
}

function emptyAt(sc: Scan): Str {
	return { b: sc.bytes, s: 0, e: 0 };
}

function inList(name: Str, list: string[]): boolean {
	for (let i: int32 = 0; i < (list.length as int32); i++) {
		if (name.eq(list[i])) { return true; }
	}
	return false;
}

function trim(x: Str): Str {
	let s = x.s;
	let e = x.e;
	while (e > s && isBlank(x.b[s] as int32)) { s += 1; }
	while (e > s && isBlank(x.b[e - 1] as int32)) { e -= 1; }
	return { b: x.b, s: s, e: e };
}

function addSpan(spans: Str[], x: Str): void {
	const n = x.e - x.s;
	spans.push({ b: x.b, s: x.s, e: n > ID_BYTES ? x.s + ID_BYTES : x.e });
}

function sameBytes(a: Str, b: Str): boolean {
	if (a.e - a.s != b.e - b.s) { return false; }
	for (let i: int32 = 0; i < a.e - a.s; i++) {
		if (a.b[a.s + i] != b.b[b.s + i]) { return false; }
	}
	return true;
}

function notePaintReference(sc: Scan, value: Str): void {
	const v = trim(value);
	if (!v.startsWith("url(")) { return; }
	let s = v.s + 4;
	if (s < v.e && v.b[s] == 35) { s += 1; }
	let end = s;
	while (end < v.e && v.b[end] != 41) { end += 1; }
	addSpan(sc.paintRefs, { b: v.b, s: s, e: end });
}

function unresolvedPaintReference(sc: Scan): int32 {
	for (let r: int32 = 0; r < (sc.paintRefs.length as int32); r++) {
		const ref = sc.paintRefs[r];
		let found = false;
		for (let g: int32 = 0; g < (sc.gradientIds.length as int32) && !found; g++) {
			found = sameBytes(sc.gradientIds[g], ref);
		}
		if (!found) { return refuse(sc, SVG_REFUSED, "paint url(#", ref, ") names no gradient"); }
	}
	return 0;
}

function isHex(c: int32): boolean {
	return (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);
}

function isLetter(c: int32): boolean {
	return (c >= 97 && c <= 122) || (c >= 65 && c <= 90);
}

function colourRefused(value: Str): boolean {
	const v = trim(value);
	const length = v.e - v.s;
	if (v.eq("none") || v.eq("currentColor")) { return false; }
	if (v.startsWith("url(") || v.startsWith("rgb(")) { return false; }
	if (length > 0 && v.b[v.s] == 35) {
		if (length != 4 && length != 7) { return true; }
		for (let i: int32 = 1; i < length; i++) {
			if (!isHex(v.b[v.s + i] as int32)) { return true; }
		}
		return false;
	}
	if (length == 0) { return true; }
	for (let i: int32 = 0; i < length; i++) {
		if (!isLetter(v.b[v.s + i] as int32)) { return true; }
	}
	return !inList(v, COLOUR_NAMES);
}

function valueRefused(value: Str, allowed: string[]): boolean {
	return !inList(trim(value), allowed);
}

function hasPercent(x: Str): boolean {
	for (let i = x.s; i < x.e; i++) {
		if (x.b[i] == 37) { return true; }
	}
	return false;
}

function checkProperty(sc: Scan, name: Str, value: Str, isStyleText: boolean): int32 {
	const trimmed = trim(value);
	if (inList(name, DENIED_PROPERTIES)) { return refuse(sc, SVG_REFUSED, "attribute ", name, ""); }
	if (trimmed.eq("inherit")) {
		return refuse(sc, SVG_REFUSED, "attribute ", name, " value inherit");
	}
	if (name.eq("style") && !isStyleText) { return checkDeclarations(sc, value); }
	if (sc.opacityRefusedAs != 0 && name.eq("opacity")) {
		return refuse(
			sc,
			SVG_REFUSED,
			"attribute opacity ",
			emptyAt(sc),
			sc.opacityRefusedAs == OPACITY_ON_GROUP ? "on <g>" : "in a css rule",
		);
	}
	if (name.eq("fill") || name.eq("stroke") || name.eq("stop-color")) {
		if (colourRefused(value)) {
			return refuse(sc, SVG_REFUSED, "attribute ", name, " colour value");
		}
		if (!name.eq("stop-color")) { notePaintReference(sc, value); }
	} else if (inList(name, OPACITIES)) {
		if (hasPercent(value)) {
			return refuse(sc, SVG_REFUSED, "attribute ", name, " as a percentage");
		}
	} else if (name.eq("stroke-linecap")) {
		if (valueRefused(value, CAPS)) {
			return refuse(sc, SVG_REFUSED, "attribute ", name, " value");
		}
	} else if (name.eq("stroke-linejoin")) {
		if (valueRefused(value, JOINS)) {
			return refuse(sc, SVG_REFUSED, "attribute ", name, " value");
		}
	} else if (name.eq("fill-rule")) {
		if (valueRefused(value, FILL_RULES)) {
			return refuse(sc, SVG_REFUSED, "attribute ", name, " value");
		}
	}
	return 0;
}

function checkDeclarations(sc: Scan, text: Str): int32 {
	let i = text.s;
	while (i < text.e) {
		let end = i;
		while (end < text.e && text.b[end] != 59) { end += 1; }
		let colon = i;
		while (colon < end && text.b[colon] != 58) { colon += 1; }
		if (colon < end) {
			const name = trim({ b: text.b, s: i, e: colon });
			const value = trim({ b: text.b, s: colon + 1, e: end });
			const folded: Str = name.e - name.s <= NAME_SHOWN
				? { b: sc.lowered, s: name.s, e: name.e }
				: name;
			const code = checkProperty(sc, folded, value, true);
			if (code != 0) { return code; }
		}
		i = end + 1;
	}
	return 0;
}

function isClassSelector(x: Str): boolean {
	const length = x.e - x.s;
	if (length < 2 || x.b[x.s] != 46) { return false; }
	for (let i: int32 = 1; i < length; i++) {
		const c = x.b[x.s + i] as int32;
		const ok = isLetter(c) || (c >= 48 && c <= 57) || c == 95 || c == 45;
		if (!ok) { return false; }
	}
	return true;
}

function checkSelectors(sc: Scan, from: int32, to: int32): int32 {
	let i = from;
	while (i <= to) {
		let end = i;
		while (end < to && sc.bytes[end] != 44) { end += 1; }
		const part = trim({ b: sc.bytes, s: i, e: end });
		if (!isClassSelector(part)) { return refuse(sc, SVG_REFUSED, "css selector ", part, ""); }
		i = end + 1;
	}
	return 0;
}

function startsAt(sc: Scan, pos: int32, limit: int32, literal: string): boolean {
	const n = literal.byteLength();
	if (pos + n > limit) { return false; }
	for (let k: int32 = 0; k < n; k++) {
		if ((sc.bytes[pos + k] as int32) != literal.byteAt(k)) { return false; }
	}
	return true;
}

// The index of `needle` at or after `from`, or `limit` when it does not occur before it.
function findText(sc: Scan, limit: int32, from: int32, needle: string): int32 {
	const n = needle.byteLength();
	for (let i = from; i + n <= limit; i++) {
		if (startsAt(sc, i, limit, needle)) { return i; }
	}
	return limit;
}

function checkStyleElement(sc: Scan, from: int32, to: int32): int32 {
	let i = from;
	while (i < to) {
		if (isBlank(sc.bytes[i] as int32)) {
			i += 1;
			continue;
		}
		if (startsAt(sc, i, to, "/*")) {
			const close = findText(sc, to, i + 2, "*/");
			if (close == to) { return notSvg(sc, "an unterminated css comment"); }
			i = close + 2;
			continue;
		}
		if (startsAt(sc, i, to, "<![CDATA[")) {
			i += 9;
			continue;
		}
		if (startsAt(sc, i, to, "]]>")) {
			i += 3;
			continue;
		}
		if (sc.bytes[i] == 64) {
			return refuse(sc, SVG_REFUSED, "css at-rule ", { b: sc.bytes, s: i, e: to }, "");
		}
		let open = i;
		while (open < to && sc.bytes[open] != 123) { open += 1; }
		if (open == to) { return notSvg(sc, "a css rule without a block"); }
		let code = checkSelectors(sc, i, open);
		if (code != 0) { return code; }
		let close = open + 1;
		while (close < to && sc.bytes[close] != 125) { close += 1; }
		if (close == to) { return notSvg(sc, "a css block without its closing brace"); }
		sc.opacityRefusedAs = OPACITY_IN_STYLE_RULE;
		code = checkDeclarations(sc, { b: sc.bytes, s: open + 1, e: close });
		sc.opacityRefusedAs = 0;
		if (code != 0) { return code; }
		i = close + 1;
	}
	return 0;
}

// scanTag: the cursor sits on '<'; the result is the status, and the new cursor is left in cursor[0].
function scanTag(sc: Scan, cursor: int32[]): int32 {
	const s = sc.bytes;
	const length = sc.length;
	let i = cursor[0] + 1;
	const nameStart = i;
	while (i < length && !isBlank(s[i] as int32) && s[i] != 47 && s[i] != 62) { i += 1; }
	const name: Str = { b: s, s: nameStart, e: i };
	if (i == nameStart) { return notSvg(sc, "a tag without a name"); }
	if (!inList(name, ELEMENTS)) { return refuse(sc, SVG_REFUSED, "element <", name, ">"); }
	if (name.eq("svg")) {
		sc.svgCount += 1;
		if (sc.svgCount > 1) {
			return refuse(sc, SVG_REFUSED, "element <svg>", emptyAt(sc), " inside <svg>");
		}
	} else if (sc.svgCount == 0) {
		return refuse(sc, SVG_NOT_SVG, "root element <", name, "> is not <svg>");
	}
	let selfClosing = false;
	const isGradient = name.eq("linearGradient") || name.eq("radialGradient");
	sc.opacityRefusedAs = name.eq("g") ? OPACITY_ON_GROUP : 0;
	while (true) {
		while (i < length && isBlank(s[i] as int32)) { i += 1; }
		if (i >= length) { return notSvg(sc, "an unterminated tag"); }
		if (s[i] == 62) {
			i += 1;
			break;
		}
		if (s[i] == 47 && i + 1 < length && s[i + 1] == 62) {
			selfClosing = true;
			i += 2;
			break;
		}
		const attrStart = i;
		while (i < length && !isBlank(s[i] as int32) && s[i] != 61 && s[i] != 47 && s[i] != 62) {
			i += 1;
		}
		const attr: Str = { b: s, s: attrStart, e: i };
		if (i == attrStart) { return notSvg(sc, "a malformed attribute"); }
		while (i < length && isBlank(s[i] as int32)) { i += 1; }
		let value = emptyAt(sc);
		if (i < length && s[i] == 61) {
			i += 1;
			while (i < length && isBlank(s[i] as int32)) { i += 1; }
			if (i >= length || (s[i] != 34 && s[i] != 39)) {
				return refuse(sc, SVG_NOT_SVG, "attribute ", attr, " without a quoted value");
			}
			const quote = s[i];
			i += 1;
			const valueStart = i;
			while (i < length && s[i] != quote) { i += 1; }
			if (i >= length) { return notSvg(sc, "an unterminated attribute value"); }
			value = { b: s, s: valueStart, e: i };
			i += 1;
		}
		const code = checkProperty(sc, attr, value, false);
		if (code != 0) {
			sc.opacityRefusedAs = 0;
			return code;
		}
		if (isGradient && attr.eq("id")) { addSpan(sc.gradientIds, value); }
	}
	sc.opacityRefusedAs = 0;
	if (name.eq("style") && !selfClosing) {
		const close = findText(sc, length, i, "</style");
		if (close == length) { return notSvg(sc, "a <style> element without its end tag"); }
		const code = checkStyleElement(sc, i, close);
		if (code != 0) { return code; }
		i = close;
	}
	cursor[0] = i;
	return 0;
}

export class ScanResult {
	code: int32 = 0;
	reason: string = "";
}

// scan() of svgMask.c over the bytes of `text` up to its first NUL; `bytes` is that prefix.
export function scanSource(text: string, bytes: uint8[]): ScanResult {
	const sc = new Scan();
	sc.text = text;
	sc.bytes = bytes;
	sc.length = bytes.length as int32;
	for (let i: int32 = 0; i < sc.length; i++) {
		const c = bytes[i] as int32;
		sc.lowered.push((c >= 65 && c <= 90 ? c + 32 : c) as uint8);
	}
	const result = new ScanResult();
	result.code = scanAll(sc);
	result.reason = sc.reason;
	return result;
}

function scanAll(sc: Scan): int32 {
	const s = sc.bytes;
	const length = sc.length;
	const cursor: int32[] = [0];
	let i: int32 = 0;
	while (i < length) {
		if (s[i] != 60) {
			i += 1;
			continue;
		}
		if (startsAt(sc, i, length, "<!--")) {
			i = findText(sc, length, i + 4, "-->");
			if (i == length) { return notSvg(sc, "an unterminated comment"); }
			i += 3;
		} else if (startsAt(sc, i, length, "<![CDATA[")) {
			i = findText(sc, length, i + 9, "]]>");
			if (i == length) { return notSvg(sc, "an unterminated CDATA section"); }
			i += 3;
		} else if (startsAt(sc, i, length, "<?")) {
			i = findText(sc, length, i + 2, "?>");
			if (i == length) { return notSvg(sc, "an unterminated processing instruction"); }
			i += 2;
		} else if (startsAt(sc, i, length, "<!")) {
			let depth: int32 = 0;
			i += 2;
			while (i < length && !(s[i] == 62 && depth == 0)) {
				if (s[i] == 91) { depth += 1; }
				if (s[i] == 93) { depth -= 1; }
				i += 1;
			}
			if (i == length) { return notSvg(sc, "an unterminated declaration"); }
			i += 1;
		} else if (startsAt(sc, i, length, "</")) {
			i = findText(sc, length, i + 2, ">");
			if (i == length) { return notSvg(sc, "an unterminated end tag"); }
			i += 1;
		} else {
			cursor[0] = i;
			const code = scanTag(sc, cursor);
			if (code != 0) { return code; }
			i = cursor[0];
		}
	}
	if (sc.svgCount == 0) { return notSvg(sc, "no <svg> element"); }
	return unresolvedPaintReference(sc);
}
