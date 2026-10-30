import { kbBeginCluster, kbEndCluster } from "./cluster";
import { KB_GLYPH_SENTINEL, kbPopGlyphList, kbPushGlyphList } from "./glyph";
import { kbBeginGsub, kbGposFeatures, kbGposMetrics, kbGsubFeatures, kbPostGposFixup } from "./ops";
import {
	kbFlagJoiningLetters,
	kbNormalize,
	kbNormalizeHangul,
	kbPreNormalizeDottedCircles,
} from "./normalize";
import { KbScratch, kbBucketGlyph, kbFreeGlyphBucket, kbUnbucketGlyph } from "./scratch";
import {
	KB_OP_KIND_BEGIN_CLUSTER,
	KB_OP_KIND_BEGIN_GSUB,
	KB_OP_KIND_END,
	KB_OP_KIND_END_CLUSTER,
	KB_OP_KIND_END_SYLLABLE,
	KB_OP_KIND_FLAG_JOINING_LETTERS,
	KB_OP_KIND_GPOS_FEATURES,
	KB_OP_KIND_GPOS_METRICS,
	KB_OP_KIND_GSUB_FEATURES,
	KB_OP_KIND_GSUB_FEATURES_WITH_USER,
	KB_OP_KIND_NORMALIZE,
	KB_OP_KIND_NORMALIZE_HANGUL,
	KB_OP_KIND_POST_GPOS_FIXUP,
	KB_OP_KIND_PRE_NORMALIZE_DOTTED_CIRCLES,
	KB_SHAPER_DEFAULT,
	KB_UNICODE_FLAG_PART_OF_WORD,
} from "./shapeTables";

// A shaper other than DEFAULT shapes through clusters (kbts_ShapeDirect's complex path).
export function kbShaperIsComplex(shaper: uint32): boolean {
	return shaper != KB_SHAPER_DEFAULT;
}

function step(observe: ((s: KbScratch) => void) | null, s: KbScratch): void {
	if (observe != null) {
		observe(s);
	}
}

function readOp(s: KbScratch, end: uint8): boolean {
	const config = s.config;
	let result = false;

	if (config != null) {
		const ops = config.opList.ops;

		if (s.ip < (ops.length as uint32)) {
			let kind = ops[s.ip as int32];
			s.ip += 1;

			if (kind == KB_OP_KIND_GSUB_FEATURES_WITH_USER || kind == KB_OP_KIND_GSUB_FEATURES ||
				kind == KB_OP_KIND_GPOS_FEATURES) {
				s.featureStagesRead += 1;

				if (kind == KB_OP_KIND_GSUB_FEATURES_WITH_USER) {
					kind = KB_OP_KIND_GSUB_FEATURES;
				}
			}

			s.opKind = kind;
			result = kind != end;
		}
	}

	return result;
}

function executeOp(s: KbScratch, m: Span<uint8>): void {
	const config = s.config;
	if (config == null) {
		return;
	}

	const kind = s.opKind;
	if (kind == KB_OP_KIND_PRE_NORMALIZE_DOTTED_CIRCLES) {
		kbPreNormalizeDottedCircles(s, config);
	} else if (kind == KB_OP_KIND_NORMALIZE) {
		kbNormalize(s, config);
	} else if (kind == KB_OP_KIND_NORMALIZE_HANGUL) {
		kbNormalizeHangul(s, config);
	} else if (kind == KB_OP_KIND_BEGIN_GSUB) {
		kbBeginGsub(s);
	} else if (kind == KB_OP_KIND_GSUB_FEATURES) {
		kbGsubFeatures(s, m, config);
	} else if (kind == KB_OP_KIND_FLAG_JOINING_LETTERS) {
		kbFlagJoiningLetters(s);
	} else if (kind == KB_OP_KIND_GPOS_METRICS) {
		kbGposMetrics(s, m, config);
	} else if (kind == KB_OP_KIND_GPOS_FEATURES) {
		kbGposFeatures(s, m, config);
	} else if (kind == KB_OP_KIND_POST_GPOS_FIXUP) {
		kbPostGposFixup(s, config);
	}
}

// kbts__ShapeDirect. The blob view is a parameter because the engine rewrites the scratch while it is
// read, and the language refuses a view taken from the config inside the same function.
function shapeDirect(
	s: KbScratch,
	m: Span<uint8>,
	runDirection: uint32,
	variationVectorNormalized: int32[] | null,
	observe: ((s: KbScratch) => void) | null,
): void {
	const config = s.config;
	const storage = s.storage;
	const g = storage.glyphs;

	s.variationVectorNormalized = variationVectorNormalized ?? [];
	s.hasVariationVector = variationVectorNormalized != null;

	if (config == null || g[KB_GLYPH_SENTINEL].next == KB_GLYPH_SENTINEL) {
		return;
	}

	s.ip = 0;
	s.featureStagesRead = 0;
	s.opKind = 0;
	s.runDirection = runDirection;
	s.nextGlyphUid = 0;
	s.sequentialLookupIndexIndex = 0;

	for (let lookupIndex = 0; lookupIndex < s.sequentialLookupCount; lookupIndex++) {
		kbFreeGlyphBucket(s, lookupIndex);
	}

	while (readOp(s, KB_OP_KIND_BEGIN_CLUSTER)) {
		executeOp(s, m);
		step(observe, s);
	}

	if (s.opKind == KB_OP_KIND_BEGIN_CLUSTER) {
		const beginClusterSequentialLookupIndexIndex = s.sequentialLookupIndexIndex;
		const beginClusterIp = s.ip;
		const beginClusterFeatureStagesRead = s.featureStagesRead;
		let topLevelGlyph = g[KB_GLYPH_SENTINEL].next;

		for (let lookupIndex = beginClusterSequentialLookupIndexIndex as int32; lookupIndex < s.sequentialLookupCount;
			lookupIndex++) {
			kbFreeGlyphBucket(s, lookupIndex);
		}

		s.clusterAtStartOfWord = true;

		while (topLevelGlyph != KB_GLYPH_SENTINEL) {
			s.ip = beginClusterIp;
			s.featureStagesRead = beginClusterFeatureStagesRead;
			s.sequentialLookupIndexIndex = beginClusterSequentialLookupIndexIndex;

			const oneBeforeFirstClusterGlyph = g[topLevelGlyph].prev;
			const onePastLastClusterGlyph = kbBeginCluster(s, m, config, topLevelGlyph);
			step(observe, s);

			const wordBreak = (g[g[onePastLastClusterGlyph].prev].unicodeFlags & KB_UNICODE_FLAG_PART_OF_WORD) == 0;
			s.cluster = kbPushGlyphList(storage, g[oneBeforeFirstClusterGlyph].next, g[onePastLastClusterGlyph].prev);

			let glyph = g[KB_GLYPH_SENTINEL].next;
			while (glyph != KB_GLYPH_SENTINEL) {
				if (!kbBucketGlyph(s, glyph, beginClusterSequentialLookupIndexIndex as int32)) {
					kbUnbucketGlyph(s, glyph);
				}
				glyph = g[glyph].next;
			}

			while (readOp(s, KB_OP_KIND_END_CLUSTER)) {
				executeOp(s, m);
				step(observe, s);
			}

			kbEndCluster(s, config);
			step(observe, s);

			while (readOp(s, KB_OP_KIND_END_SYLLABLE)) {
				executeOp(s, m);
				step(observe, s);
			}

			g[g[KB_GLYPH_SENTINEL].next].prev = s.cluster.oneBeforeFirst;
			g[g[KB_GLYPH_SENTINEL].prev].next = s.cluster.onePastLast;
			topLevelGlyph = s.cluster.onePastLast;

			kbPopGlyphList(storage, s.cluster);

			s.clusterAtStartOfWord = wordBreak;
		}

		while (readOp(s, KB_OP_KIND_END)) {
			executeOp(s, m);
			step(observe, s);
		}
	}
}

export function kbShapeDirect(
	s: KbScratch,
	m: Span<uint8>,
	runDirection: uint32,
	variationVectorNormalized: int32[] | null,
): void {
	shapeDirect(s, m, runDirection, variationVectorNormalized, null);
}

// The same run, calling observe after every op and cluster step, so a test sees each intermediate state.
export function kbShapeDirectObserved(
	s: KbScratch,
	m: Span<uint8>,
	runDirection: uint32,
	variationVectorNormalized: int32[] | null,
	observe: (s: KbScratch) => void,
): void {
	shapeDirect(s, m, runDirection, variationVectorNormalized, observe);
}
