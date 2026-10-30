import {
	kbBidirectionalClass,
	kbCombiningClass,
	kbDecomposition,
	kbDecompositionCodepoint,
	kbDecompositionSize,
	kbGraphemeBreakClass,
	kbJoiningType,
	kbLineBreakClass,
	kbMirrorCodepoint,
	kbParentInfo,
	kbParentInfoCount,
	kbParentInfoOffset,
	kbScriptExtension,
	kbScriptExtensionCount,
	kbScriptExtensionOffset,
	kbSyllabicClass,
	kbSyllabicInfo,
	kbSyllabicPosition,
	kbUnicodeFlags,
	kbUseClass,
	kbWordBreakClass,
} from "../void2d/kb/unicode";

export const KB_UNICODE_NAMES: string[] = [
	"decomposition",
	"wordBreak",
	"lineBreak",
	"graphemeBreak",
	"syllabicInfo",
	"flags",
	"bidirectional",
	"joiningType",
	"combiningClass",
	"parentInfo",
	"useClass",
	"scriptExtension",
	"mirror",
	"decompositionSize",
	"decompositionFirst",
	"decompositionSecond",
	"syllabic",
	"parentDeltas",
	"scriptExtensionList",
];

const LAST_PROBE: uint32 = 0x110005;
const HIGH_PROBES: uint32[] = [0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF];

export function kbUnicodeValue(family: int32, codepoint: uint32): uint64 {
	return match (family) {
		0 => kbDecomposition(codepoint),
		1 => kbWordBreakClass(codepoint) as uint64,
		2 => kbLineBreakClass(codepoint) as uint64,
		3 => kbGraphemeBreakClass(codepoint) as uint64,
		4 => kbSyllabicInfo(codepoint) as uint64,
		5 => kbUnicodeFlags(codepoint) as uint64,
		6 => kbBidirectionalClass(codepoint) as uint64,
		7 => kbJoiningType(codepoint) as uint64,
		8 => kbCombiningClass(codepoint) as uint64,
		9 => kbParentInfo(codepoint) as uint64,
		10 => kbUseClass(codepoint) as uint64,
		11 => kbScriptExtension(codepoint) as uint64,
		12 => kbMirrorCodepoint(codepoint) as uint64,
		13 => kbDecompositionSize(kbDecomposition(codepoint)) as uint64,
		14 => kbDecompositionCodepoint(kbDecomposition(codepoint), 0) as uint64,
		15 => kbDecompositionCodepoint(kbDecomposition(codepoint), 1) as uint64,
		16 => {
			const info = kbSyllabicInfo(codepoint);
			return (kbSyllabicClass(info) as uint64) | ((kbSyllabicPosition(info) as uint64) << 8);
		},
		17 => {
			const info = kbParentInfo(codepoint);
			return (kbParentInfoOffset(info) as uint64) |
				((kbParentInfoCount(info) as uint64) << 32);
		},
		18 => {
			const extension = kbScriptExtension(codepoint);
			return (kbScriptExtensionCount(extension) as uint64) |
				((kbScriptExtensionOffset(extension) as uint64) << 8);
		},
		_ => { throw new Error(`no kb unicode family ${family}`); },
	};
}

const FNV_PRIME: uint32 = 16777619;

export function kbFold(hash: uint32, low: uint32, high: uint32): uint32 {
	let next = (hash ^ low) * FNV_PRIME;
	if (high != 0) { next = (next ^ high) * FNV_PRIME; }
	return next;
}

export function kbUnicodeDigest(family: int32): uint32 {
	let hash: uint32 = 2166136261;
	for (let codepoint: uint32 = 0; codepoint <= LAST_PROBE; codepoint++) {
		const value = kbUnicodeValue(family, codepoint);
		hash = kbFold(hash, (value & 0xFFFFFFFF) as uint32, (value >> 32) as uint32);
	}
	for (const codepoint of HIGH_PROBES) {
		const value = kbUnicodeValue(family, codepoint);
		hash = kbFold(hash, (value & 0xFFFFFFFF) as uint32, (value >> 32) as uint32);
	}
	return hash;
}
