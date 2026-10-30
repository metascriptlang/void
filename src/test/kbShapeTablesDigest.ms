import { kbFold } from "./kbUnicodeDigest";
import {
	KB_SCRIPT_TAGS, KB_SCRIPT_SHAPERS, KB_INDIC_SCRIPT_VIRAMA_CODEPOINT,
	KB_INDIC_SCRIPT_BLWF_POST_ONLY, KB_INDIC_SCRIPT_REPH_POSITION, KB_INDIC_SCRIPT_REPH_ENCODING,
	KB_INDIC_SCRIPT_RIGHT_SIDE_MATRA_POSITION, KB_INDIC_SCRIPT_ABOVE_BASE_MATRA_POSITION,
	KB_INDIC_SCRIPT_BELOW_BASE_MATRA_POSITION, KB_INDIC_TRANSITION, KB_MYANMAR_TRANSITION,
	KB_KHMER_TRANSITION, KB_USE_TRANSITION, KB_OP_LIST_DEFAULT, KB_OP_LIST_HANGUL,
	KB_OP_LIST_ARABIC_RCLT, KB_OP_LIST_ARABIC_NO_RCLT, KB_OP_LIST_INDIC, KB_OP_LIST_KHMER,
	KB_OP_LIST_MYANMAR, KB_OP_LIST_TIBETAN, KB_OP_LIST_USE, KB_SHAPER_OP_LISTS,
	KB_SYLLABLE_FEATURE_SET, KB_INVALID_INDIC_PAIRS, KB_INVALID_INDIC_TRIPLE,
	kbInvalidIndicCluster, kbScriptTagToScript, KbOpList
} from "../void2d/kb/shapeTables";

export const KB_SHAPE_TABLE_NAMES: string[] = [
	"scriptTags", "scriptShapers", "indicVirama", "indicBlwfPostOnly", "indicRephPosition",
	"indicRephEncoding", "indicRightMatra", "indicAboveMatra", "indicBelowMatra", "indicTransition",
	"myanmarTransition", "khmerTransition", "useTransition", "opListDefault", "opListHangul",
	"opListArabicRclt", "opListArabicNoRclt", "opListIndic", "opListKhmer", "opListMyanmar",
	"opListTibetan", "opListUse", "shaperOpLists", "syllableFeatureSet", "invalidIndicCluster",
	"scriptTagToScript",
];
export const KB_SHAPE_INVALID_TABLE: int32 = 24;
export const KB_SHAPE_TAG_TABLE: int32 = 25;

function widen8(values: uint8[]): uint64[] {
	let out: uint64[] = [];
	for (const v of values) { out.push(v as uint64); }
	return out;
}

function widen32(values: uint32[]): uint64[] {
	let out: uint64[] = [];
	for (const v of values) { out.push(v as uint64); }
	return out;
}

function opListValues(list: KbOpList): uint64[] {
	let out: uint64[] = [list.totalFeatureCount as uint64, list.stageFeatureCounts.length as uint64];
	for (const count of list.stageFeatureCounts) { out.push(count as uint64); }
	for (const word of list.stageFlags) { out.push(word); }
	out.push(list.ops.length as uint64);
	for (const op of list.ops) { out.push(op as uint64); }
	return out;
}

function shaperOpListValues(): uint64[] {
	let out: uint64[] = [];
	for (const list of KB_SHAPER_OP_LISTS) {
		for (const v of opListValues(list)) { out.push(v); }
	}
	return out;
}

export function kbShapeTableValues(table: int32): uint64[] {
	match (table) {
		0 => { return widen32(KB_SCRIPT_TAGS); },
		1 => { return widen8(KB_SCRIPT_SHAPERS); },
		2 => { return widen32(KB_INDIC_SCRIPT_VIRAMA_CODEPOINT); },
		3 => { return widen8(KB_INDIC_SCRIPT_BLWF_POST_ONLY); },
		4 => { return widen8(KB_INDIC_SCRIPT_REPH_POSITION); },
		5 => { return widen8(KB_INDIC_SCRIPT_REPH_ENCODING); },
		6 => { return widen8(KB_INDIC_SCRIPT_RIGHT_SIDE_MATRA_POSITION); },
		7 => { return widen8(KB_INDIC_SCRIPT_ABOVE_BASE_MATRA_POSITION); },
		8 => { return widen8(KB_INDIC_SCRIPT_BELOW_BASE_MATRA_POSITION); },
		9 => { return widen8(KB_INDIC_TRANSITION); },
		10 => { return widen8(KB_MYANMAR_TRANSITION); },
		11 => { return widen8(KB_KHMER_TRANSITION); },
		12 => { return widen8(KB_USE_TRANSITION); },
		13 => { return opListValues(KB_OP_LIST_DEFAULT); },
		14 => { return opListValues(KB_OP_LIST_HANGUL); },
		15 => { return opListValues(KB_OP_LIST_ARABIC_RCLT); },
		16 => { return opListValues(KB_OP_LIST_ARABIC_NO_RCLT); },
		17 => { return opListValues(KB_OP_LIST_INDIC); },
		18 => { return opListValues(KB_OP_LIST_KHMER); },
		19 => { return opListValues(KB_OP_LIST_MYANMAR); },
		20 => { return opListValues(KB_OP_LIST_TIBETAN); },
		21 => { return opListValues(KB_OP_LIST_USE); },
		22 => { return shaperOpListValues(); },
		23 => { return [...KB_SYLLABLE_FEATURE_SET]; },
		_ => { throw new Error(`no data table ${table}`); },
	}
}

export function kbShapeInvalidInputs(): uint64[] {
	let out: uint64[] = [0, KB_INVALID_INDIC_TRIPLE, KB_INVALID_INDIC_TRIPLE ^ 1];
	out.push(KB_INVALID_INDIC_TRIPLE | ((1 as uint64) << 63));
	for (const pair of KB_INVALID_INDIC_PAIRS) {
		out.push(pair);
		out.push(pair | ((0x41 as uint64) << 42));
		out.push(pair ^ 1);
		out.push(pair + ((1 as uint64) << 21));
		out.push((pair & 0x1FFFFF) | ((pair >> 21) << 22));
	}
	let state: uint64 = 12345;
	for (let i: int32 = 0; i < 2000; i++) {
		state = state * 6364136223846793005 + 1442695040888963407;
		out.push(state >> 1);
	}
	return out;
}

export function kbShapeTagInputs(): uint32[] {
	let out: uint32[] = [0, 0xFFFFFFFF];
	for (const tag of KB_SCRIPT_TAGS) {
		out.push(tag);
		out.push(tag ^ 1);
		out.push(tag ^ 0x20);
	}
	let state: uint32 = 2463534242;
	for (let i: int32 = 0; i < 2000; i++) {
		state = state * 1664525 + 1013904223;
		out.push(state);
	}
	return out;
}

export function kbShapeFunctionValues(table: int32): uint64[] {
	let out: uint64[] = [];
	if (table == KB_SHAPE_INVALID_TABLE) {
		for (const input of kbShapeInvalidInputs()) {
			out.push(kbInvalidIndicCluster(input) ? (1 as uint64) : (0 as uint64));
		}
	} else if (table == KB_SHAPE_TAG_TABLE) {
		for (const input of kbShapeTagInputs()) { out.push(kbScriptTagToScript(input) as uint64); }
	} else {
		throw new Error(`no function table ${table}`);
	}
	return out;
}

export function kbShapeValues(table: int32): uint64[] {
	if (table >= KB_SHAPE_INVALID_TABLE) { return kbShapeFunctionValues(table); }
	return kbShapeTableValues(table);
}

export function kbShapeDigest(values: uint64[]): uint32 {
	let hash: uint32 = 2166136261;
	hash = kbFold(hash, (values.length as uint32) | 0x80000000, 0);
	for (const value of values) {
		hash = kbFold(hash, (value & 0xFFFFFFFF) as uint32, (value >> 32) as uint32);
	}
	return hash;
}
