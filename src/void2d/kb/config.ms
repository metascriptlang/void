import { KbFont } from "./font";
import { KbGlyph, kbZeroGlyph } from "./glyph";
import { KB_OP_LIST_DEFAULT, KbOpList } from "./shapeTables";

export struct KbFeatureOverride {
	tag: uint32;
	value: int32;
}

export struct KbSequentialLookup {
	glyphFilter: uint32;
	skipFlags: uint32;
	lookupIndex: uint16;
}

export struct KbIndicScriptProperties {
	viramaCodepoint: uint32;
	blwfPostOnly: uint8;
	rephPosition: uint8;
	rephEncoding: uint8;
	rightSideMatraPosition: uint8;
	aboveBaseMatraPosition: uint8;
	belowBaseMatraPosition: uint8;
}

export struct KbVariationInfo {
	axisCount: int32;
	instanceCount: int32;
}

export struct KbVariationAxisInfo {
	valid: boolean;
	tag: uint32;
	minimumValue: float32;
	defaultValue: float32;
	maximumValue: float32;
	flags: uint16;
	nameStringId: uint16;
}

export class KbShapeConfig {
	font: KbFont;
	script: uint32 = 0;
	language: uint32 = 0;
	langsys: int64[] = [0, 0];
	opList: KbOpList = KB_OP_LIST_DEFAULT;
	features: uint64[] = [0, 0, 0, 0];
	shaper: uint32 = 0;
	uid: uint32[] = [0, 0, 0, 0];

	indicScriptProperties: KbIndicScriptProperties = {
		viramaCodepoint: 0, blwfPostOnly: 0, rephPosition: 0, rephEncoding: 0,
		rightSideMatraPosition: 0, aboveBaseMatraPosition: 0, belowBaseMatraPosition: 0,
	};
	blwf: int64 = 0;
	pref: int64 = 0;
	pstf: int64 = 0;
	locl: int64 = 0;
	rphf: int64 = 0;
	half: int64 = 0;
	vatu: int64 = 0;

	glyphCount: uint32 = 0;
	lookupCount: uint32 = 0;
	featureStageFirstLookupIndices: uint16[] = [];
	sequentialLookups: KbSequentialLookup[] = [];
	idSequentialLookupMatrix: uint32[] = [];

	virama: KbGlyph = kbZeroGlyph();
	dottedCircle: KbGlyph = kbZeroGlyph();
	whitespace: KbGlyph = kbZeroGlyph();
	nikhahit: KbGlyph = kbZeroGlyph();
	saraAa: KbGlyph = kbZeroGlyph();

	constructor(font: KbFont) {
		this.font = font;
	}
}
