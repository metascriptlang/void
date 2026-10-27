import { FontInfo, getCoverageIndex, getGlyphClass, i16At, u16At, u32At } from "../trueType";
import { hasTag } from "../trueType/fontInfo";

const MAX_KERN_LOOKUPS: int32 = 32;

function bitCount(value: int32): int32 {
	let v = value;
	let n: int32 = 0;
	while (v != 0) {
		n += v & 1;
		v = v >> 1;
	}
	return n;
}

function pickScript(data: Readonly<Span<uint8>>, scriptList: int64): int64 {
	const count = data.u16At(scriptList);
	let latn: int64 = -1;
	for (let i: int32 = 0; i < count; i++) {
		const record: int64 = scriptList + 2 + 6 * (i as int64);
		if (data.hasTag(record, "DFLT")) { return scriptList + data.u16At(record + 4); }
		if (data.hasTag(record, "latn")) { latn = scriptList + data.u16At(record + 4); }
	}
	if (latn >= 0) { return latn; }
	return count > 0 ? scriptList + data.u16At(scriptList + 6) : -1;
}

function addKernLookup(ref lookups: int32[], lookup: int32): void {
	for (let i: int32 = 0; i < (lookups.length as int32); i++) {
		if (lookups[i] == lookup) { return; }
	}
	if ((lookups.length as int32) == MAX_KERN_LOOKUPS) {
		console.error(`void2d: more than ${MAX_KERN_LOOKUPS} GPOS kern lookups; the rest are ignored`);
		return;
	}
	lookups.push(lookup);
	let at: int32 = (lookups.length as int32) - 1;
	while (at > 0 && lookups[at - 1] > lookup) {
		lookups[at] = lookups[at - 1];
		at--;
	}
	lookups[at] = lookup;
}

function addKernFeature(
	data: Readonly<Span<uint8>>, ref lookups: int32[], featureList: int64, featureIndex: int32,
): void {
	if (featureIndex < 0 || featureIndex >= data.u16At(featureList)) { return; }
	const record: int64 = featureList + 2 + 6 * (featureIndex as int64);
	if (!data.hasTag(record, "kern")) { return; }
	const feature: int64 = featureList + data.u16At(record + 4);
	const count = data.u16At(feature + 2);
	for (let i: int32 = 0; i < count; i++) {
		addKernLookup(lookups, data.u16At(feature + 4 + 2 * (i as int64)));
	}
}

export function findKernLookups(info: FontInfo): int32[] {
	let lookups: int32[] = [];
	if (info.gpos == 0) { return lookups; }
	const data = info.data;
	const gpos: int64 = info.gpos as int64;
	if (data.u16At(gpos) != 1) { return lookups; }
	const script = pickScript(data, gpos + data.u16At(gpos + 4));
	if (script < 0 || data.u16At(script) == 0) { return lookups; }
	const langSys: int64 = script + data.u16At(script);
	const featureList: int64 = gpos + data.u16At(gpos + 6);
	const required = data.u16At(langSys + 2);
	if (required != 0xFFFF) { addKernFeature(data, lookups, featureList, required); }
	const features = data.u16At(langSys + 4);
	for (let i: int32 = 0; i < features; i++) {
		addKernFeature(data, lookups, featureList, data.u16At(langSys + 6 + 2 * (i as int64)));
	}
	return lookups;
}

function pairAdvance(
	data: Readonly<Span<uint8>>, table: int64, left: int32, right: int32, ref applied: boolean,
): int32 {
	applied = false;
	if (getCoverageIndex(data, table + data.u16At(table + 2), left) < 0) { return 0; }
	const format = data.u16At(table);
	const valueFormat1 = data.u16At(table + 4);
	const valueFormat2 = data.u16At(table + 6);
	const size1 = bitCount(valueFormat1 & 0xFF) * 2;
	const size2 = bitCount(valueFormat2 & 0xFF) * 2;
	const xAdvanceAt = bitCount(valueFormat1 & 0x3) * 2;
	const hasXAdvance = (valueFormat1 & 0x4) != 0;
	if (format == 1) {
		const coverage = getCoverageIndex(data, table + data.u16At(table + 2), left);
		if (coverage >= data.u16At(table + 8)) { return 0; }
		const pairSet: int64 = table + data.u16At(table + 10 + 2 * (coverage as int64));
		const count = data.u16At(pairSet);
		const stride = 2 + size1 + size2;
		let lo: int32 = 0;
		let hi: int32 = count - 1;
		while (lo <= hi) {
			const mid = (lo + hi) >> 1;
			const record: int64 = pairSet + 2 + (stride as int64) * (mid as int64);
			const second = data.u16At(record);
			if (right < second) {
				hi = mid - 1;
			} else if (right > second) {
				lo = mid + 1;
			} else {
				applied = true;
				return hasXAdvance ? data.i16At(record + 2 + xAdvanceAt) : 0;
			}
		}
		return 0;
	}
	if (format == 2) {
		const class1 = getGlyphClass(data, table + data.u16At(table + 8), left);
		const class2 = getGlyphClass(data, table + data.u16At(table + 10), right);
		const class1Count = data.u16At(table + 12);
		const class2Count = data.u16At(table + 14);
		if (class1 < 0 || class2 < 0 || class1 >= class1Count || class2 >= class2Count) { return 0; }
		applied = true;
		const record: int64 = table + 16 + ((class1 * class2Count + class2) as int64) * ((size1 + size2) as int64);
		return hasXAdvance ? data.i16At(record + xAdvanceAt) : 0;
	}
	return 0;
}

export function gposKern(info: FontInfo, lookups: Readonly<Span<int32>>, left: int32, right: int32): int32 {
	const data = info.data;
	const gpos: int64 = info.gpos as int64;
	const lookupList: int64 = gpos + data.u16At(gpos + 8);
	let total: int32 = 0;
	for (let i: int32 = 0; i < (lookups.length as int32); i++) {
		const lookup: int64 = lookupList + data.u16At(lookupList + 2 + 2 * (lookups[i] as int64));
		const kind = data.u16At(lookup);
		const subtables = data.u16At(lookup + 4);
		for (let s: int32 = 0; s < subtables; s++) {
			let table: int64 = lookup + data.u16At(lookup + 6 + 2 * (s as int64));
			if (kind == 9) {
				if (data.u16At(table + 2) != 2) { continue; }
				table = table + data.u32At(table + 4);
			} else if (kind != 2) {
				continue;
			}
			let applied: boolean = false;
			total += pairAdvance(data, table, left, right, applied);
			if (applied) { break; }
		}
	}
	return total;
}
