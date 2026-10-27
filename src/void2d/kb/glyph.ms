import { KB_BLOB_TABLE_ID_GDEF, kbBlobTableData, kbBlobTableLength, kbU16 } from "./blob";
import { kbGlyphClassFromTable } from "./access";
import {
	kbCombiningClass,
	kbDecomposition,
	kbJoiningType,
	kbParentInfo,
	kbSyllabicClass,
	kbSyllabicInfo,
	kbSyllabicPosition,
	kbUnicodeFlags,
	kbUseClass,
} from "./unicode";
import { KbFont, kbCodepointToGlyphId } from "./font";
import {
	KB_UNICODE_FLAG_DEFAULT_IGNORABLE,
	KB_UNICODE_FLAG_NON_SPACING_MARK,
} from "./shapeTables";

export const KB_GLYPH_CLASS_BASE: int32 = 1;
export const KB_GLYPH_CLASS_LIGATURE: int32 = 2;
export const KB_GLYPH_CLASS_MARK: int32 = 3;
export const KB_GLYPH_CLASS_COMPONENT: int32 = 4;

export const KB_DELETED_SORT_KEY: uint32 = 0xFFFFFFFF;

export struct KbGlyph {
	prev: int32;
	next: int32;
	codepoint: uint32;
	id: uint16;
	uid: uint16;
	userIdOrCodepointIndex: int32;
	offsetX: int32;
	offsetY: int32;
	advanceX: int32;
	advanceY: int32;
	attachGlyph: int32;
	configPlusOne: int32;
	decomposition: uint64;
	classValue: uint16;
	markAttachmentClass: uint16;
	flags: uint32;
	parentInfo: uint32;
	bucketedPlusOne: int32;
	sortKey: uint32;
	sortKeyInterval: uint32;
	bucketedBucketIndex: uint16;
	ligatureUid: uint16;
	ligatureComponentIndexPlusOne: uint16;
	ligatureComponentCount: uint16;
	joiningFeature: uint8;
	joiningType: uint8;
	unicodeFlags: uint8;
	syllabicClass: uint8;
	syllabicPosition: uint8;
	useClass: uint8;
	combiningClass: uint8;
	markOrdering: uint8;
}

export struct KbEnabledLookup {
	sequentialLookupIndex: int32;
	value: int32;
}

export class KbGlyphConfig {
	enabledLookupBits: uint32[] = [];
	disabledLookupBits: uint32[] = [];
	nonBinaryEnabledLookups: KbEnabledLookup[] = [];
}

export struct KbGlyphList {
	sentinelPrev: int32;
	sentinelNext: int32;
	oneBeforeFirst: int32;
	onePastLast: int32;
}

export struct KbGlyphClasses {
	classValue: int32;
	markAttachmentClass: int32;
}

export const KB_GLYPH_SENTINEL: int32 = 0;
export const KB_FREE_GLYPH_SENTINEL: int32 = 1;

export class KbGlyphStorage {
	glyphs: KbGlyph[] = [];
	configs: KbGlyphConfig[] = [];

	constructor() {
		this.glyphs.push(kbZeroGlyph());
		let freeSentinel = kbZeroGlyph();
		freeSentinel.prev = KB_FREE_GLYPH_SENTINEL;
		freeSentinel.next = KB_FREE_GLYPH_SENTINEL;
		this.glyphs.push(freeSentinel);
	}
}

export function kbZeroGlyph(): KbGlyph {
	return {
		prev: 0, next: 0, codepoint: 0, id: 0, uid: 0, userIdOrCodepointIndex: 0,
		offsetX: 0, offsetY: 0, advanceX: 0, advanceY: 0, attachGlyph: 0, configPlusOne: 0,
		decomposition: 0, classValue: 0, markAttachmentClass: 0, flags: 0, parentInfo: 0,
		bucketedPlusOne: 0, sortKey: 0, sortKeyInterval: 0, bucketedBucketIndex: 0,
		ligatureUid: 0, ligatureComponentIndexPlusOne: 0, ligatureComponentCount: 0,
		joiningFeature: 0, joiningType: 0, unicodeFlags: 0, syllabicClass: 0,
		syllabicPosition: 0, useClass: 0, combiningClass: 0, markOrdering: 0,
	};
}

export function kbGlyphIsValid(glyph: int32): boolean {
	return glyph != KB_GLYPH_SENTINEL;
}

export function kbGlyphClasses(font: KbFont, id: int32): KbGlyphClasses {
	let result: KbGlyphClasses = { classValue: 0, markAttachmentClass: 0 };
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);
	if (gdef != 0) {
		const classDefinitionOffset = m.kbU16(gdef + 4);
		if (classDefinitionOffset != 0) {
			result.classValue = kbGlyphClassFromTable(m, gdef + classDefinitionOffset, id).classValue;
		}
		const markAttachmentOffset = m.kbU16(gdef + 10);
		if (markAttachmentOffset != 0 && result.classValue == KB_GLYPH_CLASS_MARK) {
			result.markAttachmentClass = kbGlyphClassFromTable(m, gdef + markAttachmentOffset,
				id).classValue;
		}
	}
	return result;
}

export function kbCodepointToGlyph(
	font: KbFont,
	iCodepoint: int32,
	configPlusOne: int32,
	userId: int32,
): KbGlyph {
	const codepoint = ((iCodepoint as int64) & 0xFFFFFFFF) as uint32;

	let result = kbZeroGlyph();
	result.codepoint = codepoint;
	result.configPlusOne = configPlusOne;
	result.userIdOrCodepointIndex = userId;

	result.decomposition = kbDecomposition(codepoint);
	result.joiningType = kbJoiningType(codepoint);
	result.unicodeFlags = kbUnicodeFlags(codepoint);
	const syllabicInfo = kbSyllabicInfo(codepoint);
	result.syllabicClass = kbSyllabicClass(syllabicInfo);
	result.syllabicPosition = kbSyllabicPosition(syllabicInfo);
	result.combiningClass = kbCombiningClass(codepoint);
	result.useClass = kbUseClass(codepoint);
	result.parentInfo = kbParentInfo(codepoint);

	result.id = kbCodepointToGlyphId(font, iCodepoint) as uint16;

	const m: Span<uint8> = font.blob[0..font.blob.length];
	if (m.kbBlobTableLength(KB_BLOB_TABLE_ID_GDEF) != 0) {
		const classes = kbGlyphClasses(font, result.id as int32);
		result.classValue = classes.classValue as uint16;
		result.markAttachmentClass = classes.markAttachmentClass as uint16;
	} else if ((result.unicodeFlags & KB_UNICODE_FLAG_DEFAULT_IGNORABLE) != 0 ||
		(result.unicodeFlags & KB_UNICODE_FLAG_NON_SPACING_MARK) == 0) {
		result.classValue = KB_GLYPH_CLASS_BASE as uint16;
	} else {
		result.classValue = KB_GLYPH_CLASS_MARK as uint16;
	}
	return result;
}

function insertGlyph(
	storage: KbGlyphStorage,
	anchor: int32,
	insertBeforeAnchor: boolean,
	base: KbGlyph,
): int32 {
	let result = storage.glyphs[KB_FREE_GLYPH_SENTINEL].next;
	if (result != KB_FREE_GLYPH_SENTINEL) {
		storage.glyphs[storage.glyphs[result].prev].next = storage.glyphs[result].next;
		storage.glyphs[storage.glyphs[result].next].prev = storage.glyphs[result].prev;
	} else {
		result = storage.glyphs.length as int32;
		storage.glyphs.push(kbZeroGlyph());
	}

	storage.glyphs[result] = base;
	storage.glyphs[result].bucketedPlusOne = 0;

	if (insertBeforeAnchor) {
		storage.glyphs[result].next = anchor;
		storage.glyphs[result].prev = storage.glyphs[anchor].prev;
	} else {
		storage.glyphs[result].prev = anchor;
		storage.glyphs[result].next = storage.glyphs[anchor].next;
	}
	storage.glyphs[storage.glyphs[result].prev].next = result;
	storage.glyphs[storage.glyphs[result].next].prev = result;
	return result;
}

export function kbInsertGlyphBefore(storage: KbGlyphStorage, anchor: int32, base: KbGlyph): int32 {
	return insertGlyph(storage, anchor, true, base);
}

export function kbInsertGlyphAfter(storage: KbGlyphStorage, anchor: int32, base: KbGlyph): int32 {
	return insertGlyph(storage, anchor, false, base);
}

export function kbPushGlyph(
	storage: KbGlyphStorage,
	font: KbFont | null,
	codepoint: int32,
	configPlusOne: int32,
	userId: int32,
): int32 {
	let template = kbZeroGlyph();
	if (font !== null) {
		template = kbCodepointToGlyph(font, codepoint, configPlusOne, userId);
	} else {
		template.codepoint = ((codepoint as int64) & 0xFFFFFFFF) as uint32;
		template.configPlusOne = configPlusOne;
	}
	return kbInsertGlyphBefore(storage, KB_GLYPH_SENTINEL, template);
}

export function kbPushGlyphList(storage: KbGlyphStorage, first: int32, last: int32): KbGlyphList {
	const result: KbGlyphList = {
		sentinelPrev: storage.glyphs[KB_GLYPH_SENTINEL].prev,
		sentinelNext: storage.glyphs[KB_GLYPH_SENTINEL].next,
		oneBeforeFirst: storage.glyphs[first].prev,
		onePastLast: storage.glyphs[last].next,
	};
	storage.glyphs[first].prev = KB_GLYPH_SENTINEL;
	storage.glyphs[last].next = KB_GLYPH_SENTINEL;
	storage.glyphs[KB_GLYPH_SENTINEL].next = first;
	storage.glyphs[KB_GLYPH_SENTINEL].prev = last;
	return result;
}

export function kbPopGlyphList(storage: KbGlyphStorage, list: KbGlyphList): void {
	storage.glyphs[list.oneBeforeFirst].next = storage.glyphs[KB_GLYPH_SENTINEL].next;
	storage.glyphs[list.onePastLast].prev = storage.glyphs[KB_GLYPH_SENTINEL].prev;

	if (KB_GLYPH_SENTINEL != list.oneBeforeFirst) {
		storage.glyphs[KB_GLYPH_SENTINEL].next = list.sentinelNext;
	}
	if (KB_GLYPH_SENTINEL != list.onePastLast) {
		storage.glyphs[KB_GLYPH_SENTINEL].prev = list.sentinelPrev;
	}

	storage.glyphs[storage.glyphs[KB_GLYPH_SENTINEL].prev].next = KB_GLYPH_SENTINEL;
	storage.glyphs[storage.glyphs[KB_GLYPH_SENTINEL].next].prev = KB_GLYPH_SENTINEL;
}

export function kbClearActiveGlyphs(storage: KbGlyphStorage): void {
	const first = storage.glyphs[KB_GLYPH_SENTINEL].next;
	const last = storage.glyphs[KB_GLYPH_SENTINEL].prev;
	if (first != KB_GLYPH_SENTINEL) {
		const freeLast = storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev;
		storage.glyphs[first].prev = freeLast;
		storage.glyphs[last].next = KB_FREE_GLYPH_SENTINEL;
		storage.glyphs[freeLast].next = first;
		storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev = last;
	}
	storage.glyphs[KB_GLYPH_SENTINEL].prev = KB_GLYPH_SENTINEL;
	storage.glyphs[KB_GLYPH_SENTINEL].next = KB_GLYPH_SENTINEL;
}
