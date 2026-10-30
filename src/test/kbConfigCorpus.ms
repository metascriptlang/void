import { KbFontBoundsError } from "../void2d/kb/blob";
import { KbFeatureOverride, KbShapeConfig } from "../void2d/kb/config";
import { KbFont } from "../void2d/kb/font";
import { KbGlyph, KbGlyphConfig } from "../void2d/kb/glyph";
import {
	kbGetVariationAxisInfo,
	kbGetVariationInfo,
	kbNormalizeVariationVector,
	kbPlaceGlyphConfig,
	kbPlaceShapeConfig,
} from "../void2d/kb/shapeConfig";
import {
	KB_LANGUAGE_DONT_KNOW,
	KB_LANGUAGE_ENGLISH,
	KB_LANGUAGE_HINDI,
	KB_LANGUAGE_ROMANIAN,
	KB_LANGUAGE_SERBIAN,
	KB_LANGUAGE_THAI,
	KB_LANGUAGE_TURKISH,
	KB_LANGUAGE_URDU,
	KB_LANGUAGE_VIETNAMESE,
} from "../void2d/kb/languages";
import {
	KB_SCRIPT_ARABIC,
	KB_SCRIPT_BENGALI,
	KB_SCRIPT_BRAHMI,
	KB_SCRIPT_DEFAULT,
	KB_SCRIPT_DEVANAGARI,
	KB_SCRIPT_DONT_KNOW,
	KB_SCRIPT_HANGUL,
	KB_SCRIPT_HEBREW,
	KB_SCRIPT_KHMER,
	KB_SCRIPT_LAO,
	KB_SCRIPT_LATIN,
	KB_SCRIPT_MYANMAR,
	KB_SCRIPT_SYRIAC,
	KB_SCRIPT_THAI,
} from "../void2d/kb/shapeTables";
import { KbRng } from "./kbLookupCorpus";
import { kbUint32Bits } from "./kbLookupDrive";

export const KB_CONFIG_SCRIPTS: uint32[] = [
	KB_SCRIPT_DONT_KNOW, KB_SCRIPT_DEFAULT, KB_SCRIPT_LATIN, KB_SCRIPT_ARABIC, KB_SCRIPT_SYRIAC,
	KB_SCRIPT_DEVANAGARI, KB_SCRIPT_BENGALI, KB_SCRIPT_THAI, KB_SCRIPT_LAO, KB_SCRIPT_HEBREW,
	KB_SCRIPT_MYANMAR, KB_SCRIPT_KHMER, KB_SCRIPT_HANGUL, KB_SCRIPT_BRAHMI,
];

export const KB_CONFIG_LANGUAGES: uint32[] = [
	KB_LANGUAGE_DONT_KNOW, KB_LANGUAGE_ENGLISH, KB_LANGUAGE_TURKISH, KB_LANGUAGE_ROMANIAN,
	KB_LANGUAGE_HINDI, KB_LANGUAGE_THAI, KB_LANGUAGE_URDU, KB_LANGUAGE_VIETNAMESE,
	KB_LANGUAGE_SERBIAN,
];

export const KB_CONFIG_BLOB_SEED: int64 = 0;

export struct KbConfigCase {
	script: uint32;
	language: uint32;
	vector: int32;
}

export function kbFeatureTag(text: string): uint32 {
	return (text.charCodeAt(0) | (text.charCodeAt(1) << 8) | (text.charCodeAt(2) << 16) |
		(text.charCodeAt(3) << 24)) as uint32;
}

function overrideSet(spec: string): KbFeatureOverride[] {
	let result: KbFeatureOverride[] = [];
	if (spec == "") { return result; }
	for (const item of spec.split(" ")) {
		const parts = item.split("=");
		result.push({ tag: kbFeatureTag(parts[0]), value: parseInt(parts[1]) as int32 });
	}
	return result;
}

export function kbConfigOverrideSets(): KbFeatureOverride[][] {
	let cv = "";
	for (let n = 1; n <= 20; n++) { cv += `cv${n < 10 ? "0" : ""}${n}=1 `; }
	return [
		overrideSet(""),
		overrideSet("ss01=1"),
		overrideSet("liga=0 kern=0 calt=0"),
		overrideSet("ss02=3 ss05=2 ccmp=0"),
		overrideSet("locl=0 init=1 fina=0 isol=1 medi=2"),
		overrideSet(cv + "ss01=0 ss02=0 mark=0"),
		overrideSet("zzzz=1 liga=1 rlig=0 clig=0"),
		overrideSet("liga=0 liga=1 ss03=1 ss03=0"),
	];
}

export function kbConfigCases(scripts: uint32[], vectorCount: int32): KbConfigCase[] {
	let cases: KbConfigCase[] = [];
	for (const script of scripts) {
		for (const language of KB_CONFIG_LANGUAGES) {
			cases.push({ script, language, vector: -1 });
		}
		for (let v: int32 = 0; v < vectorCount; v++) {
			cases.push({ script, language: KB_CONFIG_LANGUAGES[v % (KB_CONFIG_LANGUAGES.length as int32)],
				vector: v });
		}
	}
	return cases;
}

export function kbConfigVectors(font: KbFont): float32[][] {
	const axisCount = kbGetVariationInfo(font).axisCount;
	let vectors: float32[][] = [];
	if (axisCount == 0) {
		vectors.push([0.5]);
		return vectors;
	}
	const limit = axisCount > 40 ? 40 : axisCount;
	const rng = new KbRng(0x51ED + (axisCount as uint32));
	for (let pattern: int32 = 0; pattern < 10; pattern++) {
		let vector: float32[] = [];
		for (let i: int32 = 0; i < limit; i++) {
			const info = kbGetVariationAxisInfo(font, i);
			const low = info.minimumValue;
			const mid = info.defaultValue;
			const high = info.maximumValue;
			const span = high - low;
			let value: float32 = mid;
			if (pattern == 1) { value = low; }
			else if (pattern == 2) { value = high; }
			else if (pattern == 3) { value = (low + mid) * 0.5; }
			else if (pattern == 4) { value = (mid + high) * 0.5; }
			else if (pattern == 5) { value = low - span * 0.25; }
			else if (pattern == 6) { value = high + span * 0.25; }
			else if (pattern == 7) { value = (i % 2 == 0) ? low : high; }
			else if (pattern >= 8) { value = low + span * ((rng.below(1001) as float32) / 1000.0); }
			vector.push(value);
		}
		vectors.push(vector);
	}
	return vectors;
}

function wrap32(value: int64): int32 {
	return (((value & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000) as int32;
}

function lowWord(value: uint64): int32 {
	return wrap32((value & 0xFFFFFFFF) as int64);
}

function highWord(value: uint64): int32 {
	return wrap32((value >> 32) as int64);
}

function dumpGlyph(out: int32[], g: KbGlyph): void {
	out.push(g.id as int32);
	out.push(wrap32(g.codepoint as int64));
	out.push(g.uid as int32);
	out.push(g.userIdOrCodepointIndex);
	out.push(g.offsetX);
	out.push(g.offsetY);
	out.push(g.advanceX);
	out.push(g.advanceY);
	out.push(g.attachGlyph != 0 ? 1 : 0);
	out.push(g.configPlusOne != 0 ? 1 : 0);
	out.push(lowWord(g.decomposition));
	out.push(highWord(g.decomposition));
	out.push(g.classValue as int32);
	out.push(g.markAttachmentClass as int32);
	out.push(wrap32(g.flags as int64));
	out.push(wrap32(g.parentInfo as int64));
	out.push(wrap32(g.sortKey as int64));
	out.push(wrap32(g.sortKeyInterval as int64));
	out.push(g.ligatureUid as int32);
	out.push(g.ligatureComponentIndexPlusOne as int32);
	out.push(g.ligatureComponentCount as int32);
	out.push(g.joiningFeature as int32);
	out.push(g.joiningType as int32);
	out.push(g.unicodeFlags as int32);
	out.push(g.syllabicClass as int32);
	out.push(g.syllabicPosition as int32);
	out.push(g.useClass as int32);
	out.push(g.combiningClass as int32);
	out.push(g.markOrdering as int32);
}

export function kbConfigDump(config: KbShapeConfig): int32[] {
	let out: int32[] = [];
	for (let i = 0; i < 4; i++) { out.push(wrap32(config.uid[i] as int64)); }
	out.push(wrap32(config.script as int64));
	out.push(wrap32(config.language as int64));
	out.push(wrap32(config.langsys[0]));
	out.push(wrap32(config.langsys[1]));
	const stages = config.opList.stageFeatureCounts.length as int32;
	out.push(wrap32(config.opList.totalFeatureCount as int64));
	out.push(stages);
	out.push(4);
	for (let s = 0; s < stages; s++) {
		out.push(wrap32(config.opList.stageFeatureCounts[s] as int64));
		for (let w = 0; w < 4; w++) {
			const flag = config.opList.stageFlags[s * 4 + w];
			out.push(lowWord(flag));
			out.push(highWord(flag));
		}
	}
	out.push(config.opList.ops.length as int32);
	for (const op of config.opList.ops) { out.push(op as int32); }
	for (let w = 0; w < 4; w++) {
		out.push(lowWord(config.features[w]));
		out.push(highWord(config.features[w]));
	}
	out.push(wrap32(config.shaper as int64));
	const props = config.indicScriptProperties;
	out.push(wrap32(props.viramaCodepoint as int64));
	out.push(props.blwfPostOnly as int32);
	out.push(props.rephPosition as int32);
	out.push(props.rephEncoding as int32);
	out.push(props.rightSideMatraPosition as int32);
	out.push(props.aboveBaseMatraPosition as int32);
	out.push(props.belowBaseMatraPosition as int32);
	out.push(wrap32(config.blwf));
	out.push(wrap32(config.pref));
	out.push(wrap32(config.pstf));
	out.push(wrap32(config.locl));
	out.push(wrap32(config.rphf));
	out.push(wrap32(config.half));
	out.push(wrap32(config.vatu));
	out.push(wrap32(config.glyphCount as int64));
	out.push(wrap32(config.lookupCount as int64));
	out.push(1);
	for (const index of config.featureStageFirstLookupIndices) { out.push(index as int32); }
	out.push(config.sequentialLookups.length as int32);
	for (const lookup of config.sequentialLookups) {
		out.push(wrap32(lookup.glyphFilter as int64));
		out.push(wrap32(lookup.skipFlags as int64));
		out.push(lookup.lookupIndex as int32);
	}
	out.push(config.idSequentialLookupMatrix.length as int32);
	dumpGlyph(out, config.virama);
	dumpGlyph(out, config.dottedCircle);
	dumpGlyph(out, config.whitespace);
	dumpGlyph(out, config.nikhahit);
	dumpGlyph(out, config.saraAa);
	return out;
}

export function kbGlyphConfigDump(config: KbGlyphConfig): int32[] {
	let out: int32[] = [];
	out.push(config.enabledLookupBits.length as int32);
	for (const word of config.enabledLookupBits) { out.push(wrap32(word as int64)); }
	for (const word of config.disabledLookupBits) { out.push(wrap32(word as int64)); }
	out.push(config.nonBinaryEnabledLookups.length as int32);
	for (const lookup of config.nonBinaryEnabledLookups) {
		out.push(lookup.sequentialLookupIndex);
		out.push(lookup.value);
	}
	return out;
}

export function kbConfigNormalized(font: KbFont, vector: float32[]): int32[] {
	const axisCount = kbGetVariationInfo(font).axisCount;
	let normalized: int32[] = [];
	const slots = axisCount > 32 ? axisCount : 32;
	for (let i: int32 = 0; i < slots; i++) { normalized.push(0); }
	kbNormalizeVariationVector(font, vector, normalized);
	return normalized;
}

export function kbConfigAxisDump(font: KbFont, axis: int32): int32[] {
	const info = kbGetVariationAxisInfo(font, axis);
	return [
		info.valid ? 1 : 0,
		wrap32(info.tag as int64),
		(info.minimumValue * 65536.0) as int32,
		(info.defaultValue * 65536.0) as int32,
		(info.maximumValue * 65536.0) as int32,
		info.flags as int32,
		info.nameStringId as int32,
	];
}

export function kbConfigDigestStep(h: uint32, dump: int32[]): uint32 {
	let result = h;
	result = (result ^ (dump.length as uint32)) * 16777619;
	for (let i: int32 = 0; i < dump.length; i++) {
		result = (result ^ kbUint32Bits(dump[i])) * 16777619;
	}
	return result;
}

export function kbConfigMatrixDigest(h: uint32, config: KbShapeConfig): uint32 {
	let result = h;
	for (const word of config.idSequentialLookupMatrix) {
		result = (result ^ word) * 16777619;
	}
	return result;
}

export function kbConfigPlaceOrUb(
	font: KbFont,
	script: uint32,
	language: uint32,
	vector: float32[] | null,
): KbShapeConfig | null {
	try {
		return kbPlaceShapeConfig(font, script, language, vector, KB_CONFIG_BLOB_SEED);
	} catch (e) {
		if (e instanceof KbFontBoundsError) { return null; }
		throw e;
	}
}

export function kbConfigDigestOf(
	font: KbFont,
	scripts: uint32[],
	extraVectors: float32[][],
): uint32 {
	let h: uint32 = 2166136261;
	const axisCount = kbGetVariationInfo(font).axisCount;
	h = kbConfigDigestStep(h, [axisCount, kbGetVariationInfo(font).instanceCount]);
	for (let axis: int32 = 0; axis < axisCount && axis < 64; axis++) {
		h = kbConfigDigestStep(h, kbConfigAxisDump(font, axis));
	}
	let vectors = kbConfigVectors(font);
	for (const vector of extraVectors) { vectors.push(vector); }
	for (const vector of vectors) {
		h = kbConfigDigestStep(h, kbConfigNormalized(font, vector));
	}

	const sets = kbConfigOverrideSets();
	for (const item of kbConfigCases(scripts, vectors.length as int32)) {
		const vector: float32[] | null = item.vector < 0 ? null : vectors[item.vector];
		const config = kbConfigPlaceOrUb(font, item.script, item.language, vector);
		if (config === null) {
			h = kbConfigDigestStep(h, [-1]);
			continue;
		}
		let dump = kbConfigDump(config);
		dump[0] = 0;
		h = kbConfigDigestStep(h, dump);
		h = kbConfigMatrixDigest(h, config);
		for (const overrides of sets) {
			h = kbConfigDigestStep(h, kbGlyphConfigDump(kbPlaceGlyphConfig(config, overrides)));
		}
	}
	return h;
}
