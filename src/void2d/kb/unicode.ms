import {
	KB_BIDIRECTIONAL_CLASS_DATA,
	KB_BIDIRECTIONAL_CLASS_PAGES,
	KB_COMBINING_CLASS_DATA,
	KB_COMBINING_CLASS_PAGES,
	KB_DECOMPOSITION_DATA,
	KB_DECOMPOSITION_PAGES,
	KB_FLAGS_DATA,
	KB_FLAGS_PAGES,
	KB_GRAPHEME_BREAK_CLASS_DATA,
	KB_GRAPHEME_BREAK_CLASS_PAGES,
	KB_JOINING_TYPE_DATA,
	KB_JOINING_TYPE_PAGES,
	KB_LINE_BREAK_CLASS_DATA,
	KB_LINE_BREAK_CLASS_PAGES,
	KB_MIRROR_CODEPOINT_DATA,
	KB_MIRROR_CODEPOINT_PAGES,
	KB_PARENT_INFO_DATA,
	KB_PARENT_INFO_PAGES,
	KB_SCRIPT_EXTENSION_DATA,
	KB_SCRIPT_EXTENSION_PAGES,
	KB_SYLLABIC_INFO_DATA,
	KB_SYLLABIC_INFO_PAGES,
	KB_USE_CLASS_DATA,
	KB_USE_CLASS_PAGES,
	KB_WORD_BREAK_CLASS_DATA,
	KB_WORD_BREAK_CLASS_PAGES,
} from "./unicodeTables";

const KB_UNICODE_LIMIT: uint32 = 1114110;

export function kbDecomposition(codepoint: uint32): uint64 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 195104 ?
		(KB_DECOMPOSITION_PAGES[codepoint / 16] as uint32) * 16 : 16;
	return KB_DECOMPOSITION_DATA[page | (codepoint & 15)];
}

export function kbWordBreakClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 918016 ?
		(KB_WORD_BREAK_CLASS_PAGES[codepoint / 128] as uint32) * 128 : 7296;
	return KB_WORD_BREAK_CLASS_DATA[page | (codepoint & 127)];
}

export function kbLineBreakClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 918016 ?
		(KB_LINE_BREAK_CLASS_PAGES[codepoint / 128] as uint32) * 128 : 256;
	return KB_LINE_BREAK_CLASS_DATA[page | (codepoint & 127)];
}

export function kbGraphemeBreakClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 921600 ?
		(KB_GRAPHEME_BREAK_CLASS_PAGES[codepoint / 128] as uint32) * 128 : 256;
	return KB_GRAPHEME_BREAK_CLASS_DATA[page | (codepoint & 127)];
}

export function kbSyllabicInfo(codepoint: uint32): uint16 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 125280 ?
		(KB_SYLLABIC_INFO_PAGES[codepoint / 32] as uint32) * 32 : 0;
	return KB_SYLLABIC_INFO_DATA[page | (codepoint & 31)];
}

export function kbUnicodeFlags(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 1048704 ?
		(KB_FLAGS_PAGES[codepoint / 128] as uint32) * 128 : 256;
	return KB_FLAGS_DATA[page | (codepoint & 127)];
}

export function kbBidirectionalClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 1048704 ?
		(KB_BIDIRECTIONAL_CLASS_PAGES[codepoint / 128] as uint32) * 128 : 7296;
	return KB_BIDIRECTIONAL_CLASS_DATA[page | (codepoint & 127)];
}

export function kbJoiningType(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 918016 ?
		(KB_JOINING_TYPE_PAGES[codepoint / 128] as uint32) * 128 : 0;
	return KB_JOINING_TYPE_DATA[page | (codepoint & 127)];
}

export function kbCombiningClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 125280 ?
		(KB_COMBINING_CLASS_PAGES[codepoint / 32] as uint32) * 32 : 0;
	return KB_COMBINING_CLASS_DATA[page | (codepoint & 31)];
}

export function kbParentInfo(codepoint: uint32): uint32 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 119232 ?
		(KB_PARENT_INFO_PAGES[codepoint / 16] as uint32) * 16 : 0;
	return KB_PARENT_INFO_DATA[page | (codepoint & 15)];
}

export function kbUseClass(codepoint: uint32): uint8 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 125280 ?
		(KB_USE_CLASS_PAGES[codepoint / 32] as uint32) * 32 : 0;
	return KB_USE_CLASS_DATA[page | (codepoint & 31)];
}

export function kbScriptExtension(codepoint: uint32): uint16 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 918016 ?
		(KB_SCRIPT_EXTENSION_PAGES[codepoint / 128] as uint32) * 128 : 7808;
	return KB_SCRIPT_EXTENSION_DATA[page | (codepoint & 127)];
}

export function kbMirrorCodepoint(codepoint: uint32): uint32 {
	if (codepoint >= KB_UNICODE_LIMIT) { return 0; }
	const page: uint32 = codepoint < 65408 ?
		(KB_MIRROR_CODEPOINT_PAGES[codepoint / 32] as uint32) * 32 : 0;
	return KB_MIRROR_CODEPOINT_DATA[page | (codepoint & 31)];
}

export function kbDecompositionSize(decomposition: uint64): uint32 {
	return (decomposition & 3) as uint32;
}

export function kbDecompositionCodepoint(decomposition: uint64, index: uint32): uint32 {
	const shift: uint64 = index != 0 ? 23 : 2;
	return ((decomposition >> shift) & 0x1FFFFF) as uint32;
}

export function kbSyllabicClass(syllabicInfo: uint16): uint8 {
	return (syllabicInfo & 0xFF) as uint8;
}

export function kbSyllabicPosition(syllabicInfo: uint16): uint8 {
	return (syllabicInfo >> 8) as uint8;
}

export function kbParentInfoOffset(parentInfo: uint32): uint32 {
	return parentInfo & 0xFFFF;
}

export function kbParentInfoCount(parentInfo: uint32): uint32 {
	return parentInfo >> 16;
}

export function kbScriptExtensionCount(scriptExtension: uint16): uint32 {
	return (scriptExtension & 0x1F) as uint32;
}

export function kbScriptExtensionOffset(scriptExtension: uint16): uint32 {
	return (scriptExtension >> 5) as uint32;
}
