import {
	KB_GRAPHEME_BREAK_TRANSITION,
	KB_LINE_BREAK_CLASS_ALNEA,
	KB_LINE_BREAK_CLASS_BAEA,
	KB_LINE_BREAK_CLASS_BANEA,
	KB_LINE_BREAK_CLASS_BB,
	KB_LINE_BREAK_CLASS_BK,
	KB_LINE_BREAK_CLASS_CB,
	KB_LINE_BREAK_CLASS_CJ,
	KB_LINE_BREAK_CLASS_CLEA,
	KB_LINE_BREAK_CLASS_CLNEA,
	KB_LINE_BREAK_CLASS_CM,
	KB_LINE_BREAK_CLASS_COUNT,
	KB_LINE_BREAK_CLASS_CPEA,
	KB_LINE_BREAK_CLASS_CPNEA,
	KB_LINE_BREAK_CLASS_CR,
	KB_LINE_BREAK_CLASS_EXEA,
	KB_LINE_BREAK_CLASS_EXNEA,
	KB_LINE_BREAK_CLASS_GLEA,
	KB_LINE_BREAK_CLASS_GLNEA,
	KB_LINE_BREAK_CLASS_HY,
	KB_LINE_BREAK_CLASS_HYPHEN,
	KB_LINE_BREAK_CLASS_IDEA,
	KB_LINE_BREAK_CLASS_INEA,
	KB_LINE_BREAK_CLASS_INNEA,
	KB_LINE_BREAK_CLASS_IS,
	KB_LINE_BREAK_CLASS_LF,
	KB_LINE_BREAK_CLASS_NL,
	KB_LINE_BREAK_CLASS_NSEA,
	KB_LINE_BREAK_CLASS_NSNEA,
	KB_LINE_BREAK_CLASS_ONEA,
	KB_LINE_BREAK_CLASS_OPEA,
	KB_LINE_BREAK_CLASS_OPNEA,
	KB_LINE_BREAK_CLASS_QU,
	KB_LINE_BREAK_CLASS_QUPF,
	KB_LINE_BREAK_CLASS_QUPI,
	KB_LINE_BREAK_CLASS_SOT,
	KB_LINE_BREAK_CLASS_SP,
	KB_LINE_BREAK_CLASS_SY,
	KB_LINE_BREAK_CLASS_WJ,
	KB_LINE_BREAK_CLASS_ZW,
	KB_LINE_BREAK_CLASS_ZWJ,
	KB_SCRIPT_DEFAULT,
	KB_SCRIPT_DEFAULT2,
	KB_SCRIPT_DONT_KNOW,
	KB_WORD_BREAK_CLASS_ALEP,
	KB_WORD_BREAK_CLASS_CR,
	KB_WORD_BREAK_CLASS_EX,
	KB_WORD_BREAK_CLASS_FO,
	KB_WORD_BREAK_CLASS_LF,
	KB_WORD_BREAK_CLASS_NL,
	KB_WORD_BREAK_CLASS_OEP,
	KB_WORD_BREAK_CLASS_SOT,
	KB_WORD_BREAK_CLASS_ZWJ,
	KbLineRules,
	KbWordRules,
	kbLineAllowed,
	kbLineRequired,
	kbLineRules2,
	kbLineRules3,
	kbLineRules4,
	kbWordBits,
	kbWordRules2,
	kbWordRules3,
} from "./breakTables";
import { KB_SCRIPT_EXTENSIONS } from "./unicodeTables";
import {
	kbBidirectionalClass,
	kbGraphemeBreakClass,
	kbLineBreakClass,
	kbMirrorCodepoint,
	kbScriptExtension,
	kbScriptExtensionCount,
	kbScriptExtensionOffset,
	kbUnicodeFlags,
	kbWordBreakClass,
} from "./unicode";
import {
	KB_BREAK_FLAG_DIRECTION,
	KB_BREAK_FLAG_GRAPHEME,
	KB_BREAK_FLAG_LINE_HARD,
	KB_BREAK_FLAG_LINE_SOFT,
	KB_BREAK_FLAG_PARAGRAPH_DIRECTION,
	KB_BREAK_FLAG_SCRIPT,
	KB_BREAK_FLAG_WORD,
	KB_DIRECTION_COUNT,
	KB_DIRECTION_DONT_KNOW,
	KB_DIRECTION_LTR,
	KB_DIRECTION_RTL,
	KB_UNICODE_FLAG_CLOSE_BRACKET,
	KB_UNICODE_FLAG_MIRRORED,
	KB_UNICODE_FLAG_OPEN_BRACKET,
} from "./shapeTables";

export const KB_JAPANESE_LINE_BREAK_STYLE_STRICT: uint8 = 0;
export const KB_JAPANESE_LINE_BREAK_STYLE_NORMAL: uint8 = 1;
export const KB_JAPANESE_LINE_BREAK_STYLE_LOOSE: uint8 = 2;

export const KB_BREAK_CONFIG_FLAG_END_OF_TEXT_GENERATES_HARD_LINE_BREAK: uint32 = 1;

const BREAK_STATE_FLAG_STARTED: uint32 = 1;
const BREAK_STATE_FLAG_END: uint32 = 2;
const BREAK_STATE_FLAG_SAW_R_AFTER_L: uint32 = 8;
const BREAK_STATE_FLAG_SAW_AL_AFTER_LR: uint32 = 0x10;
const BREAK_STATE_FLAG_LAST_WAS_BRACKET: uint32 = 0x20;

const BIDI_NI: uint8 = 0;
const BIDI_BN: uint8 = 1;
const BIDI_L: uint8 = 2;
const BIDI_R: uint8 = 3;
const BIDI_NSM: uint8 = 4;
const BIDI_AL: uint8 = 5;
const BIDI_AN: uint8 = 6;
const BIDI_EN: uint8 = 7;
const BIDI_ES: uint8 = 8;
const BIDI_ET: uint8 = 9;
const BIDI_CS: uint8 = 10;

const GRAPHEME_STATE_COUNT: int32 = 13;
const GRAPHEME_STATE_B0: uint8 = 14;
const GRAPHEME_STATE_B01: uint8 = 15;
const GRAPHEME_STATE_B1: uint8 = 16;
const GRAPHEME_STATE_LAST: uint8 = 28;

const FLUSH_SCRIPT: uint32 = 1;
const FLUSH_DIRECTION_2: uint32 = 2;
const FLUSH_DIRECTION_1: uint32 = 4;
const FLUSH_DIRECTION_PARAGRAPH: uint32 = 8;

const LINE_BREAK_ALLOWED_MASK: uint64 = 0x3F;
const LINE_BREAK_REQUIRED_MASK: uint64 = 0xFC0;
const LINE_BREAK_MASK: uint64 = 0xFFF;

const BREAK_CAPACITY: uint32 = 8;
const BRACKET_CAPACITY: uint32 = 64;
const MAXIMUM_CODEPOINT_SCRIPTS: int32 = 23;
const OUT_OF_RANGE_OFFSET: int32 = -100;

const SET_ET_ES_CS: uint32 = (1 << 9) | (1 << 8) | (1 << 10);
const SET_NI_ET_ES_CS: uint32 = 1 | (1 << 9) | (1 << 8) | (1 << 10);
const SET_R_AN_EN: uint32 = (1 << 3) | (1 << 6) | (1 << 7);

export struct KbBreak {
	position: int32;
	flags: uint32;
	direction: uint32;
	paragraphDirection: uint32;
	script: uint32;
}

export struct KbBracket {
	codepoint: uint32;
	position: uint32;
	direction: uint8;
	script: uint8;
}

export struct KbBreakState {
	breaks: KbBreak[8];
	breakCount: uint32;
	paragraphDirection: uint32;
	userParagraphDirection: uint32;
	currentPosition: uint32;
	paragraphStartPosition: uint32;
	lastScriptBreakPosition: uint32;
	lastDirectionBreakPosition: uint32;
	lastScriptBreakScript: uint8;
	lastDirectionBreakDirection: uint8;
	scriptPositionOffset: int32;
	scriptCount: uint32;
	scriptSet: uint8[23];
	brackets: KbBracket[64];
	bracketCount: uint32;
	flags: uint32;
	flagState: uint32;
	positionOffset2: int32;
	positionOffset3: int32;
	wordBreakHistory: uint32;
	wordBreaks: uint16;
	wordUnbreaks: uint16;
	wordBreak2PositionOffset: int32;
	lineBreaks: uint64;
	lineUnbreaksAsync: uint64;
	lineUnbreaks: uint64;
	lineBreakHistory: uint32;
	lineBreak2PositionOffset: int32;
	lineBreak3PositionOffset: int32;
	lastDirection: uint8;
	bidirectionalClass2: uint8;
	bidirectionalClass1: uint8;
	bidirectional1PositionOffset: int32;
	bidirectional2PositionOffset: int32;
	japaneseLineBreakStyle: uint8;
	configFlags: uint32;
	graphemeBreakState: uint8;
	lastLineBreakClass: uint8;
	lastWordBreakClass: uint8;
	lastWordBreakClassIncludingIgnored: uint8;
}

struct Pending {
	flagState: uint32;
	flushFlags: uint32;
	hardLineBreak: boolean;
	scriptCount: uint32;
	positionOffset2: int32;
	positionOffset3: int32;
	lineBreak2PositionOffset: int32;
	lineBreak3PositionOffset: int32;
	endOfText: boolean;
	startOfText: boolean;
}

function wrapInt16(value: int32): int32 {
	return ((value + 32768) & 0xFFFF) - 32768;
}

function int16Of(value: uint32): int32 {
	return wrapInt16((value & 0xFFFF) as int32);
}

function int32Of(value: uint32): int32 {
	return ((value as int64) - (((value >> 31) as int64) << 32)) as int32;
}

function inSet(value: uint8, set: uint32): boolean {
	return (((1 as uint32) << (value as uint32)) & set) != 0;
}

function graphemeFlags(position: uint32): uint32 {
	return KB_BREAK_FLAG_GRAPHEME << (8 * position);
}

function emptyBreak(): KbBreak {
	return { position: 0, flags: 0, direction: 0, paragraphDirection: 0, script: 0 };
}

function doBreak(
	this ref state: KbBreakState,
	position: int32,
	flags: uint32,
	direction: uint32,
	paragraphDirection: uint32,
	script: uint32,
): void {
	const breakPosition: uint32 = state.currentPosition + (position as uint32);
	if (flags == 0 || breakPosition > state.currentPosition) { return; }
	let found: KbBreak = {
		position: int32Of(breakPosition),
		flags: flags,
		direction: direction,
		paragraphDirection: paragraphDirection,
		script: script,
	};
	if ((flags & KB_BREAK_FLAG_SCRIPT) != 0 && state.lastScriptBreakScript != 0) {
		const lastPosition = state.lastScriptBreakPosition;
		const lastScript = state.lastScriptBreakScript;
		let index = state.bracketCount as int32;
		while (index != 0) {
			if (state.brackets[index - 1].position >= breakPosition) {
				state.brackets[index - 1].script = script as uint8;
			} else if (state.brackets[index - 1].position >= lastPosition) {
				state.brackets[index - 1].script = lastScript;
			} else {
				break;
			}
			index--;
		}
		state.lastScriptBreakPosition = breakPosition;
		state.lastScriptBreakScript = script as uint8;
	}
	if ((flags & KB_BREAK_FLAG_DIRECTION) != 0 && state.lastDirectionBreakDirection != 0) {
		const lastPosition = state.lastDirectionBreakPosition;
		const lastDirection = state.lastDirectionBreakDirection;
		let index = state.bracketCount as int32;
		while (index != 0) {
			if (state.brackets[index - 1].position >= breakPosition) {
				state.brackets[index - 1].direction = direction as uint8;
			} else if (state.brackets[index - 1].position >= lastPosition) {
				state.brackets[index - 1].direction = lastDirection;
			} else {
				break;
			}
			index--;
		}
		state.lastDirectionBreakPosition = breakPosition;
		state.lastDirectionBreakDirection = direction as uint8;
	}
	let matched = false;
	for (let i: int32 = 0; i < (state.breakCount as int32); i++) {
		if (state.breaks[i].position == found.position) {
			state.breaks[i].flags |= found.flags;
			if ((found.flags & KB_BREAK_FLAG_DIRECTION) != 0) {
				state.breaks[i].direction = found.direction;
			}
			if ((found.flags & KB_BREAK_FLAG_PARAGRAPH_DIRECTION) != 0) {
				state.breaks[i].paragraphDirection = found.paragraphDirection;
			}
			if ((found.flags & KB_BREAK_FLAG_SCRIPT) != 0) {
				state.breaks[i].script = found.script;
			}
			matched = true;
			break;
		} else if (state.breaks[i].position < found.position) {
			const swap = state.breaks[i];
			state.breaks[i] = found;
			found = swap;
		} else if (
			(found.flags & KB_BREAK_FLAG_PARAGRAPH_DIRECTION) != 0 &&
			(state.breaks[i].flags & KB_BREAK_FLAG_DIRECTION) != 0 &&
			state.breaks[i].direction == 0
		) {
			state.breaks[i].direction = found.paragraphDirection;
		}
	}
	if (state.breakCount >= BREAK_CAPACITY) {
		throw new Error("kb break buffer is full: the caller must drain kbBreakNext after each codepoint");
	}
	state.breaks[state.breakCount as int32] = found;
	if (!matched) { state.breakCount += 1; }
}

function doLineBreak(this ref state: KbBreakState, position: int32, effective: uint64): void {
	if ((effective & LINE_BREAK_MASK) == 0) { return; }
	let flags: uint32 = 0;
	if ((effective & LINE_BREAK_ALLOWED_MASK) != 0) { flags |= KB_BREAK_FLAG_LINE_SOFT; }
	if ((effective & LINE_BREAK_REQUIRED_MASK) != 0) { flags |= KB_BREAK_FLAG_LINE_HARD; }
	state.doBreak(position, flags, 0, 0, 0);
}

function startParagraph(this ref state: KbBreakState): void {
	const direction = state.userParagraphDirection;
	let startOfTextClass: uint8 = BIDI_NI;
	let flags: uint32 = 0;
	if (direction == KB_DIRECTION_LTR) {
		startOfTextClass = BIDI_L;
	} else if (direction == KB_DIRECTION_RTL) {
		flags = BREAK_STATE_FLAG_SAW_R_AFTER_L;
		startOfTextClass = BIDI_R;
	}
	state.paragraphDirection = (direction & 0xFF) as uint32;
	state.bidirectionalClass1 = startOfTextClass;
	state.flags = flags;
}

function flushDirection(
	this ref state: KbBreakState,
	ref lastDirection: uint8,
	bidirectionalClass: uint8,
	positionOffset: int32,
): void {
	let breakFlags: uint32 = 0;
	let direction: uint32 = KB_DIRECTION_DONT_KNOW;
	match (bidirectionalClass) {
		BIDI_L => {
			breakFlags = KB_BREAK_FLAG_DIRECTION | KB_BREAK_FLAG_PARAGRAPH_DIRECTION;
			direction = KB_DIRECTION_LTR;
		},
		BIDI_R => {
			breakFlags = KB_BREAK_FLAG_DIRECTION | KB_BREAK_FLAG_PARAGRAPH_DIRECTION;
			direction = KB_DIRECTION_RTL;
		},
		BIDI_AN | BIDI_EN => {
			breakFlags = KB_BREAK_FLAG_DIRECTION;
			direction = KB_DIRECTION_LTR;
		},
		BIDI_NI => {
			breakFlags = KB_BREAK_FLAG_DIRECTION;
		},
		_ => {},
	}
	if ((breakFlags & KB_BREAK_FLAG_DIRECTION) != 0 && direction != (lastDirection as uint32)) {
		lastDirection = direction as uint8;
		state.doBreak(positionOffset, KB_BREAK_FLAG_DIRECTION, direction, 0, 0);
	}
	if ((breakFlags & KB_BREAK_FLAG_PARAGRAPH_DIRECTION) != 0 && state.paragraphDirection == 0) {
		const startOfParagraphOffset = int16Of(state.paragraphStartPosition - state.currentPosition);
		state.doBreak(startOfParagraphOffset, KB_BREAK_FLAG_PARAGRAPH_DIRECTION, 0, direction, 0);
		state.paragraphDirection = (direction & 0xFF) as uint32;
	}
}

function lineBreakStage(
	this ref state: KbBreakState,
	ref pending: Pending,
	lineBreakClassIn: uint8,
	lastLineBreakClass: uint8,
): void {
	let lineBreakClass = lineBreakClassIn;
	let lineBreaks: uint64 = state.lineBreaks << 16;
	let lineUnbreaks: uint64 = state.lineUnbreaks << 16;
	let lineUnbreaksAsync: uint64 = state.lineUnbreaksAsync << 16;
	let history = state.lineBreakHistory;
	if (pending.startOfText) {
		history = KB_LINE_BREAK_CLASS_SOT as uint32;
	}
	let absorb = false;
	if (pending.endOfText) {
		lineBreakClass = KB_LINE_BREAK_CLASS_ONEA;
	} else if (lineBreakClass > KB_LINE_BREAK_CLASS_COUNT) {
		if (lineBreakClass == KB_LINE_BREAK_CLASS_CM || lineBreakClass == KB_LINE_BREAK_CLASS_ZWJ) {
			if (lineBreakClass == KB_LINE_BREAK_CLASS_ZWJ) {
				lineUnbreaksAsync |= kbLineRequired(3, 0);
			}
			match (lastLineBreakClass) {
				KB_LINE_BREAK_CLASS_SOT | KB_LINE_BREAK_CLASS_BK | KB_LINE_BREAK_CLASS_CR |
					KB_LINE_BREAK_CLASS_LF | KB_LINE_BREAK_CLASS_NL | KB_LINE_BREAK_CLASS_SP |
					KB_LINE_BREAK_CLASS_ZW => {
					lineBreakClass = KB_LINE_BREAK_CLASS_ALNEA;
				},
				_ => { absorb = true; },
			}
		} else if (lineBreakClass == KB_LINE_BREAK_CLASS_CJ) {
			lineBreakClass = state.japaneseLineBreakStyle == KB_JAPANESE_LINE_BREAK_STYLE_STRICT ?
				KB_LINE_BREAK_CLASS_NSEA : KB_LINE_BREAK_CLASS_IDEA;
		}
	}
	if (!absorb && lastLineBreakClass == lineBreakClass && lineBreakClass == KB_LINE_BREAK_CLASS_SP) {
		absorb = true;
	}
	if (absorb) {
		state.lineBreak2PositionOffset = wrapInt16(state.lineBreak2PositionOffset + pending.positionOffset2);
		state.lineBreak3PositionOffset = wrapInt16(
			state.lineBreak3PositionOffset + wrapInt16(pending.positionOffset3 - pending.positionOffset2),
		);
		state.lineUnbreaksAsync = lineUnbreaksAsync;
		return;
	}
	history = (history << 8) | (lineBreakClass as uint32);
	if (pending.endOfText &&
		(state.configFlags & KB_BREAK_CONFIG_FLAG_END_OF_TEXT_GENERATES_HARD_LINE_BREAK) != 0) {
		lineBreaks |= kbLineRequired(5, 1);
		if ((history & 0xFF00) == ((KB_LINE_BREAK_CLASS_QUPF as uint32) << 8)) {
			lineUnbreaks |= kbLineRequired(3, 2);
		}
	}
	lineBreaks |= kbLineAllowed(0, 0);
	lineBreaks |= kbLineAllowed(0, 1);
	match (lineBreakClass) {
		KB_LINE_BREAK_CLASS_BK | KB_LINE_BREAK_CLASS_CR | KB_LINE_BREAK_CLASS_LF |
			KB_LINE_BREAK_CLASS_NL => {
			lineUnbreaks |= kbLineRequired(4, 1);
			pending.flushFlags |= FLUSH_SCRIPT | FLUSH_DIRECTION_2 | FLUSH_DIRECTION_1 |
				FLUSH_DIRECTION_PARAGRAPH;
			pending.scriptCount = 0;
			pending.hardLineBreak = true;
			lineBreaks |= kbLineRequired(5, 0);
		},
		KB_LINE_BREAK_CLASS_ZW => {
			lineBreaks |= kbLineAllowed(4, 0);
			lineUnbreaks |= kbLineRequired(4, 1);
		},
		KB_LINE_BREAK_CLASS_BB => {
			lineUnbreaks |= kbLineRequired(0, 0);
		},
		KB_LINE_BREAK_CLASS_GLEA | KB_LINE_BREAK_CLASS_GLNEA | KB_LINE_BREAK_CLASS_OPEA |
			KB_LINE_BREAK_CLASS_OPNEA => {
			lineUnbreaks |= kbLineRequired(3, 0);
		},
		KB_LINE_BREAK_CLASS_WJ => {
			lineUnbreaks |= kbLineRequired(3, 0);
			lineUnbreaks |= kbLineRequired(3, 1);
		},
		KB_LINE_BREAK_CLASS_CLEA | KB_LINE_BREAK_CLASS_CLNEA | KB_LINE_BREAK_CLASS_CPEA |
			KB_LINE_BREAK_CLASS_CPNEA | KB_LINE_BREAK_CLASS_EXEA | KB_LINE_BREAK_CLASS_EXNEA |
			KB_LINE_BREAK_CLASS_SY => {
			lineUnbreaks |= kbLineRequired(3, 1);
		},
		KB_LINE_BREAK_CLASS_IS => {
			lineUnbreaks |= kbLineRequired(2, 1);
		},
		KB_LINE_BREAK_CLASS_SP => {
			lineUnbreaks |= kbLineRequired(4, 1);
			lineBreaks |= kbLineAllowed(2, 0);
		},
		KB_LINE_BREAK_CLASS_QU => {
			lineUnbreaks |= kbLineRequired(1, 1);
			lineUnbreaks |= kbLineRequired(1, 0);
		},
		KB_LINE_BREAK_CLASS_QUPI => {
			lineUnbreaks |= kbLineRequired(1, 0);
		},
		KB_LINE_BREAK_CLASS_QUPF => {
			lineUnbreaks |= kbLineRequired(1, 1);
		},
		KB_LINE_BREAK_CLASS_CB => {
			lineBreaks |= kbLineAllowed(1, 0);
			lineBreaks |= kbLineAllowed(1, 1);
		},
		KB_LINE_BREAK_CLASS_BANEA | KB_LINE_BREAK_CLASS_BAEA | KB_LINE_BREAK_CLASS_HYPHEN |
			KB_LINE_BREAK_CLASS_HY | KB_LINE_BREAK_CLASS_NSNEA | KB_LINE_BREAK_CLASS_NSEA |
			KB_LINE_BREAK_CLASS_INNEA | KB_LINE_BREAK_CLASS_INEA => {
			lineUnbreaks |= kbLineRequired(0, 1);
		},
		_ => {},
	}
	let rules: KbLineRules = { breaks: lineBreaks, unbreaks: lineUnbreaks, history: history };
	kbLineRules2(rules);
	kbLineRules3(rules);
	kbLineRules4(rules);
	lineBreaks = rules.breaks;
	lineUnbreaks = rules.unbreaks;
	history = rules.history;
	if (pending.startOfText) {
		lineUnbreaks |= kbLineRequired(5, 1);
		pending.flagState |= graphemeFlags(1);
	}
	const effective: uint64 = lineBreaks & ~(lineUnbreaks | lineUnbreaksAsync);
	state.doLineBreak(
		pending.positionOffset3 + pending.lineBreak3PositionOffset,
		effective >> 48,
	);
	if (pending.endOfText) {
		state.doLineBreak(
			pending.positionOffset2 + pending.lineBreak2PositionOffset,
			effective >> 32,
		);
		let flushed: uint32 = 0;
		if (((effective >> 16) & LINE_BREAK_ALLOWED_MASK) != 0) { flushed |= KB_BREAK_FLAG_LINE_SOFT; }
		if (((effective >> 16) & LINE_BREAK_REQUIRED_MASK) != 0) { flushed |= KB_BREAK_FLAG_LINE_HARD; }
		pending.flagState |= flushed << 8;
	}
	state.lineBreaks = lineBreaks;
	state.lineUnbreaks = lineUnbreaks;
	state.lineBreak2PositionOffset = 0;
	state.lineBreak3PositionOffset = pending.lineBreak2PositionOffset;
	state.lastLineBreakClass = lineBreakClass;
	state.lineBreakHistory = history;
	state.lineUnbreaksAsync = lineUnbreaksAsync;
}

function addCodepoint(
	this ref state: KbBreakState,
	codepoint: uint32,
	positionIncrement: uint32,
	maybeEndOfText: boolean,
): void {
	let bidirectionalClass = kbBidirectionalClass(codepoint);
	const unicodeFlags = kbUnicodeFlags(codepoint);
	const matchingBracket = kbMirrorCodepoint(codepoint);
	const graphemeBreakClass = kbGraphemeBreakClass(codepoint);
	const lineBreakClass = kbLineBreakClass(codepoint);
	let wordBreakClass = kbWordBreakClass(codepoint);
	const scriptExtension = kbScriptExtension(codepoint);
	let codepointScriptCount = kbScriptExtensionCount(scriptExtension);
	let codepointScriptOffset = kbScriptExtensionOffset(scriptExtension);
	const endOfText = codepoint == 3 && maybeEndOfText;
	const startOfText = (state.flags & BREAK_STATE_FLAG_STARTED) == 0;
	let lastLineBreakClass = state.lastLineBreakClass;
	let wordBreakHistory = state.wordBreakHistory;
	let lastWordBreakClass = state.lastWordBreakClass;
	let wordBreak2PositionOffset = state.wordBreak2PositionOffset;
	const lastWordBreakClassIncludingIgnored = state.lastWordBreakClassIncludingIgnored;
	const positionOffset2 = state.positionOffset2;
	const positionOffset3 = state.positionOffset3;
	let flags = state.flags;
	let lastDirection = state.lastDirection;
	let scriptPositionOffset = state.scriptPositionOffset;
	let scriptCount = state.scriptCount;
	const scriptCountAtBeginningOfUpdate = scriptCount;
	const breakScript = state.scriptSet[0] as uint32;
	let bidirectional1PositionOffset = state.bidirectional1PositionOffset;
	let bidirectional2 = state.bidirectionalClass2;
	let bidirectional1 = state.bidirectionalClass1;
	let pending: Pending = {
		flagState: state.flagState << 8,
		flushFlags: 0,
		hardLineBreak: false,
		scriptCount: scriptCount,
		positionOffset2: positionOffset2,
		positionOffset3: positionOffset3,
		lineBreak2PositionOffset: state.lineBreak2PositionOffset,
		lineBreak3PositionOffset: state.lineBreak3PositionOffset,
		endOfText: endOfText,
		startOfText: startOfText,
	};
	if (startOfText) {
		lastLineBreakClass = KB_LINE_BREAK_CLASS_SOT;
		wordBreakHistory = KB_WORD_BREAK_CLASS_SOT as uint32;
		lastWordBreakClass = KB_WORD_BREAK_CLASS_SOT;
	}
	if ((unicodeFlags & KB_UNICODE_FLAG_MIRRORED) == KB_UNICODE_FLAG_OPEN_BRACKET) {
		if (state.bracketCount < BRACKET_CAPACITY) {
			const slot = state.bracketCount as int32;
			state.bracketCount += 1;
			state.brackets[slot].codepoint = codepoint;
			state.brackets[slot].position = state.currentPosition;
			state.brackets[slot].direction = KB_DIRECTION_DONT_KNOW as uint8;
			state.brackets[slot].script = KB_SCRIPT_DONT_KNOW as uint8;
			if (scriptCount != 0) { state.brackets[slot].script = state.scriptSet[0]; }
			state.flags |= BREAK_STATE_FLAG_LAST_WAS_BRACKET;
		}
	} else if ((unicodeFlags & KB_UNICODE_FLAG_MIRRORED) == KB_UNICODE_FLAG_CLOSE_BRACKET) {
		if (state.bracketCount != 0) {
			let found = -1;
			for (let i: int32 = 0; i < (state.bracketCount as int32); i++) {
				const at = (state.bracketCount as int32) - 1 - i;
				if (state.brackets[at].codepoint == matchingBracket) {
					found = at;
					break;
				}
			}
			if (found >= 0) {
				let bracketScript = state.brackets[found].script;
				if (bracketScript == 0 && scriptCount != 0) { bracketScript = state.scriptSet[0]; }
				bidirectionalClass = state.brackets[found].direction;
				codepointScriptCount = 1;
				codepointScriptOffset = bracketScript as uint32;
				state.bracketCount = found as uint32;
			}
		}
	}

	state.lineBreakStage(pending, lineBreakClass, lastLineBreakClass);
	scriptCount = pending.scriptCount;

	if (endOfText) { pending.flushFlags |= FLUSH_SCRIPT; }
	if (codepointScriptCount < 2) {
		const codepointScript = codepointScriptOffset as uint8;
		const known = (codepointScript as uint32) != KB_SCRIPT_DONT_KNOW &&
			(codepointScript as uint32) != KB_SCRIPT_DEFAULT &&
			(codepointScript as uint32) != KB_SCRIPT_DEFAULT2;
		if (known) {
			let scriptSetMatch = false;
			for (let i: int32 = 0; i < (scriptCount as int32); i++) {
				if (state.scriptSet[i] == codepointScript) { scriptSetMatch = true; }
			}
			if (!scriptSetMatch) { pending.flushFlags |= FLUSH_SCRIPT; }
			scriptCount = 1;
			state.scriptSet[0] = codepointScript;
		}
	} else {
		let newScriptCount: int32 = 0;
		let codepointScriptIndex: int32 = 0;
		let scriptIndex: int32 = 0;
		while (scriptIndex < (scriptCount as int32) && codepointScriptIndex < (codepointScriptCount as int32)) {
			const codepointScript = KB_SCRIPT_EXTENSIONS[(codepointScriptOffset as int32) + codepointScriptIndex];
			const script = state.scriptSet[scriptIndex];
			if (codepointScript < script) {
				codepointScriptIndex += 1;
			} else if (script < codepointScript) {
				scriptIndex += 1;
			} else {
				state.scriptSet[newScriptCount] = script;
				newScriptCount += 1;
				codepointScriptIndex += 1;
				scriptIndex += 1;
			}
		}
		if (newScriptCount == 0) {
			pending.flushFlags |= FLUSH_SCRIPT;
			for (let i: int32 = 0; i < (codepointScriptCount as int32); i++) {
				state.scriptSet[i] = KB_SCRIPT_EXTENSIONS[(codepointScriptOffset as int32) + i];
			}
			scriptCount = codepointScriptCount;
		} else {
			scriptCount = newScriptCount as uint32;
		}
	}

	if (endOfText) { bidirectionalClass = BIDI_NI; }
	let skipDirection = bidirectionalClass == BIDI_BN;
	if (!skipDirection) {
		let treatAsAn = false;
		match (bidirectionalClass) {
			BIDI_NSM => { bidirectionalClass = bidirectional1; },
			BIDI_L => {
				flags &= 0xFFFFFFFF ^ (BREAK_STATE_FLAG_SAW_R_AFTER_L | BREAK_STATE_FLAG_SAW_AL_AFTER_LR);
			},
			BIDI_R => {
				flags |= BREAK_STATE_FLAG_SAW_R_AFTER_L;
				flags &= 0xFFFFFFFF ^ BREAK_STATE_FLAG_SAW_AL_AFTER_LR;
			},
			BIDI_AL => {
				flags |= BREAK_STATE_FLAG_SAW_AL_AFTER_LR | BREAK_STATE_FLAG_SAW_R_AFTER_L;
				bidirectionalClass = BIDI_R;
			},
			BIDI_EN => {
				if ((flags & BREAK_STATE_FLAG_SAW_AL_AFTER_LR) != 0) {
					bidirectionalClass = BIDI_AN;
					treatAsAn = true;
				} else {
					if (bidirectional2 == BIDI_EN && (bidirectional1 == BIDI_ES || bidirectional1 == BIDI_CS)) {
						bidirectional1 = BIDI_EN;
					}
					if (state.paragraphDirection != 0 && (flags & BREAK_STATE_FLAG_SAW_R_AFTER_L) == 0) {
						bidirectionalClass = BIDI_L;
					}
				}
			},
			BIDI_AN => { treatAsAn = true; },
			BIDI_ET => {
				if (bidirectional1 == BIDI_EN) { bidirectionalClass = BIDI_EN; }
			},
			_ => {},
		}
		if (treatAsAn && bidirectional2 == BIDI_AN && bidirectional1 == BIDI_CS) {
			bidirectional1 = BIDI_AN;
		}
		if (inSet(bidirectional1, SET_ET_ES_CS)) { bidirectional1 = BIDI_NI; }
		if (bidirectional1 == BIDI_NI) {
			if (!pending.hardLineBreak && inSet(bidirectionalClass, SET_NI_ET_ES_CS)) {
				skipDirection = true;
			} else if (
				(bidirectional2 == BIDI_R || bidirectionalClass == BIDI_R) &&
				inSet(bidirectional2, SET_R_AN_EN) &&
				inSet(bidirectionalClass, SET_R_AN_EN)
			) {
				bidirectional1 = BIDI_R;
			} else if (bidirectional2 == BIDI_L && bidirectionalClass == BIDI_L) {
				bidirectional1 = BIDI_L;
			} else if (state.paragraphDirection == KB_DIRECTION_LTR) {
				bidirectional1 = BIDI_L;
			} else if (state.paragraphDirection == KB_DIRECTION_RTL) {
				bidirectional1 = BIDI_R;
			}
		}
		if (!skipDirection) {
			pending.flushFlags |= FLUSH_DIRECTION_2 | FLUSH_DIRECTION_1;
			if (endOfText) { pending.flushFlags |= FLUSH_DIRECTION_1; }
		}
	}
	if (skipDirection) {
		state.bidirectional1PositionOffset = wrapInt16(
			state.bidirectional1PositionOffset - int16Of(positionIncrement),
		);
	}

	if (endOfText && !startOfText) {
		pending.flagState |= graphemeFlags(1);
		state.graphemeBreakState = 0;
	} else {
		let next = KB_GRAPHEME_BREAK_TRANSITION[
			(graphemeBreakClass as int32) * GRAPHEME_STATE_COUNT + (state.graphemeBreakState as int32)
		];
		if (next == GRAPHEME_STATE_B01) {
			pending.flagState |= graphemeFlags(1) | graphemeFlags(0);
			next = 0;
		} else if (next == GRAPHEME_STATE_B0) {
			pending.flagState |= graphemeFlags(0);
			next = 0;
		} else if (next >= GRAPHEME_STATE_B1 && next <= GRAPHEME_STATE_LAST) {
			pending.flagState |= graphemeFlags(1);
			next -= GRAPHEME_STATE_B1;
		}
		state.graphemeBreakState = next;
	}

	if (
		(wordBreakClass == KB_WORD_BREAK_CLASS_EX || wordBreakClass == KB_WORD_BREAK_CLASS_FO ||
			wordBreakClass == KB_WORD_BREAK_CLASS_ZWJ) &&
		!(lastWordBreakClass == KB_WORD_BREAK_CLASS_SOT || lastWordBreakClass == KB_WORD_BREAK_CLASS_CR ||
			lastWordBreakClass == KB_WORD_BREAK_CLASS_LF || lastWordBreakClass == KB_WORD_BREAK_CLASS_NL)
	) {
		wordBreak2PositionOffset = wrapInt16(wordBreak2PositionOffset + positionOffset2);
		state.wordBreak2PositionOffset = wordBreak2PositionOffset;
	} else {
		let wordBreaks: uint32 = (state.wordBreaks as uint32) << 4;
		wordBreakHistory = (wordBreakHistory << 8) | (wordBreakClass as uint32);
		wordBreaks |= kbWordBits(0, 1) | kbWordBits(0, 0);
		if (startOfText) { wordBreaks |= kbWordBits(2, 1); }
		let rules: KbWordRules = {
			unbreaks: (state.wordUnbreaks as uint32) << 4,
			history: wordBreakHistory,
		};
		if (wordBreakClass == KB_WORD_BREAK_CLASS_CR || wordBreakClass == KB_WORD_BREAK_CLASS_LF ||
			wordBreakClass == KB_WORD_BREAK_CLASS_NL) {
			wordBreaks |= kbWordBits(1, 1) | kbWordBits(1, 0);
		} else if (wordBreakClass == KB_WORD_BREAK_CLASS_OEP || wordBreakClass == KB_WORD_BREAK_CLASS_ALEP) {
			if (lastWordBreakClassIncludingIgnored == KB_WORD_BREAK_CLASS_ZWJ) {
				rules.unbreaks |= kbWordBits(0, 1);
			}
		}
		kbWordRules2(rules, wordBreak2PositionOffset);
		kbWordRules3(rules);
		wordBreakHistory = rules.history;
		const effective = wordBreaks & (0xFFFFFFFF ^ rules.unbreaks);
		if ((effective & kbWordBits(2, 2)) != 0) {
			state.doBreak(positionOffset2 + wordBreak2PositionOffset, KB_BREAK_FLAG_WORD, 0, 0, 0);
		}
		if (endOfText) { pending.flagState |= KB_BREAK_FLAG_WORD << 8; }
		state.wordBreaks = wordBreaks as uint16;
		state.wordUnbreaks = rules.unbreaks as uint16;
		state.lastWordBreakClass = wordBreakClass;
		state.wordBreak2PositionOffset = 0;
		state.wordBreakHistory = wordBreakHistory;
	}
	state.lastWordBreakClassIncludingIgnored = wordBreakClass;

	if ((pending.flushFlags & FLUSH_SCRIPT) != 0) {
		if (scriptCountAtBeginningOfUpdate != 0) {
			state.doBreak(scriptPositionOffset, KB_BREAK_FLAG_SCRIPT, 0, 0, breakScript);
			scriptPositionOffset = 0;
		}
		if (pending.hardLineBreak) { scriptPositionOffset = int16Of(positionIncrement); }
	}
	if ((pending.flushFlags & FLUSH_DIRECTION_1) != 0) {
		let direction = lastDirection;
		state.flushDirection(direction, bidirectional1, bidirectional1PositionOffset);
		lastDirection = direction;
	}
	if ((pending.flushFlags & FLUSH_DIRECTION_PARAGRAPH) != 0) {
		bidirectional1 = 0;
		lastDirection = 0;
		state.paragraphStartPosition = state.currentPosition + 1;
		state.startParagraph();
		if (state.userParagraphDirection == KB_DIRECTION_DONT_KNOW) {
			state.doBreak(1, KB_BREAK_FLAG_PARAGRAPH_DIRECTION, 0, KB_DIRECTION_DONT_KNOW, 0);
		}
	}

	scriptPositionOffset = wrapInt16(scriptPositionOffset - int16Of(positionIncrement));

	const flagState = pending.flagState;
	state.doBreak(positionOffset3, (flagState >> 24) & 0xFF, 0, 0, 0);
	if (endOfText) {
		state.doBreak(positionOffset2, (flagState >> 16) & 0xFF, 0, 0, 0);
		state.doBreak(0, (flagState >> 8) & 0xFF, 0, 0, 0);
		state.doBreak(int32Of(positionIncrement), flagState & 0xFF, 0, 0, 0);
	}
	state.flagState = flagState;
	flags |= BREAK_STATE_FLAG_STARTED;
	if (endOfText) { flags |= BREAK_STATE_FLAG_END; }
	state.flags = flags;
	state.positionOffset2 = wrapInt16(0 - int16Of(positionIncrement));
	state.positionOffset3 = wrapInt16(positionOffset2 - int16Of(positionIncrement));
	state.currentPosition += positionIncrement;
	if ((pending.flushFlags & FLUSH_DIRECTION_2) != 0) {
		state.bidirectionalClass2 = bidirectional1;
		state.bidirectionalClass1 = bidirectionalClass;
		state.bidirectional1PositionOffset = wrapInt16(0 - int16Of(positionIncrement));
	}
	state.lastDirection = lastDirection;
	state.scriptPositionOffset = scriptPositionOffset;
	state.scriptCount = scriptCount;
}

export function kbBreakBegin(
	paragraphDirection: uint32,
	japaneseLineBreakStyle: uint8,
	configFlags: uint32,
): KbBreakState {
	let state: KbBreakState = {
		breaks: [],
		breakCount: 0,
		paragraphDirection: paragraphDirection & 0xFF,
		userParagraphDirection: paragraphDirection & 0xFF,
		currentPosition: 0,
		paragraphStartPosition: 0,
		lastScriptBreakPosition: 0,
		lastDirectionBreakPosition: 0,
		lastScriptBreakScript: 0,
		lastDirectionBreakDirection: 0,
		scriptPositionOffset: 0,
		scriptCount: 0,
		scriptSet: [],
		brackets: [],
		bracketCount: 0,
		flags: 0,
		flagState: 0,
		positionOffset2: OUT_OF_RANGE_OFFSET,
		positionOffset3: OUT_OF_RANGE_OFFSET,
		wordBreakHistory: 0,
		wordBreaks: 0,
		wordUnbreaks: 0,
		wordBreak2PositionOffset: OUT_OF_RANGE_OFFSET,
		lineBreaks: 0,
		lineUnbreaksAsync: 0,
		lineUnbreaks: 0,
		lineBreakHistory: 0,
		lineBreak2PositionOffset: OUT_OF_RANGE_OFFSET,
		lineBreak3PositionOffset: OUT_OF_RANGE_OFFSET,
		lastDirection: KB_DIRECTION_COUNT as uint8,
		bidirectionalClass2: 0,
		bidirectionalClass1: 0,
		bidirectional1PositionOffset: OUT_OF_RANGE_OFFSET,
		bidirectional2PositionOffset: 0,
		japaneseLineBreakStyle: japaneseLineBreakStyle,
		configFlags: configFlags,
		graphemeBreakState: 0,
		lastLineBreakClass: 0,
		lastWordBreakClass: 0,
		lastWordBreakClassIncludingIgnored: 0,
	};
	state.startParagraph();
	if (paragraphDirection != 0) {
		state.doBreak(0, KB_BREAK_FLAG_PARAGRAPH_DIRECTION, 0, paragraphDirection, 0);
	}
	return state;
}

export function kbBreakEnd(this ref state: KbBreakState): void {
	state.addCodepoint(3, 0, true);
}

export function kbBreakAddCodepoint(
	this ref state: KbBreakState,
	codepoint: int32,
	positionIncrement: int32,
	endOfText: boolean,
): void {
	state.addCodepoint(codepoint as uint32, positionIncrement as uint32, false);
	if (endOfText) { state.kbBreakEnd(); }
}

export function kbBreakNext(this ref state: KbBreakState, out found: KbBreak): boolean {
	if (state.breakCount == 0) {
		found = emptyBreak();
		return false;
	}
	state.breakCount -= 1;
	found = state.breaks[state.breakCount as int32];
	return true;
}
