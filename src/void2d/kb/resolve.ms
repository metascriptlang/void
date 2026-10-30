import { kbBoundsFail, kbS16, kbU16, kbU32, kbU8 } from "./blob";
import { kbUnpackValueRecord } from "./access";
import { KbScratch } from "./scratch";

const FIXED_2_14_SCALE: float32 = 0.00006103515625;

export struct KbResolvedValueRecord {
	placementX: int32;
	placementY: int32;
	advanceX: int32;
	advanceY: int32;
}

export struct KbAnchorXy {
	x: int32;
	y: int32;
}

export function kbWrapS16(value: int32): int32 {
	return ((value & 0xFFFF) ^ 0x8000) - 0x8000;
}

export function kbRound32(x: float32): int32 {
	if (!(x >= -2147483648.0 && x < 2147483648.0)) {
		throw kbBoundsFail("float out of int32 range in Round32", 0);
	}
	let result = x as int32;
	let resultF = result as float32;
	if (resultF != x && x < 0) {
		result -= 1;
		resultF -= 1;
	}
	if ((x - resultF) >= 0.5) {
		result += 1;
	}
	return result;
}

function halfWordDelta(byte: int32): int32 {
	return byte >= 0x80 ? byte - 0x100 : byte;
}

export function kbFixed2_14ToFloat(x: int32): float32 {
	return (x as float32) * FIXED_2_14_SCALE;
}

export function kbItemVariationStoreDelta(
	m: Readonly<Span<uint8>>,
	store: int64,
	deltaSetOuterIndex: int64,
	deltaSetInnerIndex: int64,
	variationVectorNormalized: int32[],
): float32 {
	let result: float32 = 0;

	const regionList = store + m.kbU32(store + 2);
	const axisCount = m.kbU16(regionList) as int64;
	const regionAxisCoordinates = regionList + 4;
	if (axisCount > (variationVectorNormalized.length as int64)) {
		throw kbBoundsFail("variation vector shorter than the region axis count", axisCount);
	}

	const data = store + m.kbU32(store + 8 + deltaSetOuterIndex * 4);
	const wordDeltaCount = m.kbU16(data + 2) as int64;
	const regionIndexCount = m.kbU16(data + 4) as int64;

	const regionIndices = data + 6;
	const deltas = regionIndices + regionIndexCount * 2;
	const wordDeltas = deltas + deltaSetInnerIndex * (wordDeltaCount + regionIndexCount);
	const halfWordDeltas = wordDeltas + wordDeltaCount * 2;

	for (let regionIndexIndex: int64 = 0; regionIndexIndex < regionIndexCount; regionIndexIndex++) {
		const regionIndex = m.kbU16(regionIndices + regionIndexIndex * 2) as int64;
		const regionCoords = regionAxisCoordinates + regionIndex * axisCount * 6;

		const regionDelta = regionIndexIndex < wordDeltaCount ?
			m.kbS16(wordDeltas + regionIndexIndex * 2) as float32 :
			halfWordDelta(m.kbU8(halfWordDeltas + (regionIndexIndex - wordDeltaCount))) as float32;

		let regionFactor: float32 = 1;

		for (let axisIndex: int64 = 0; axisIndex < axisCount; axisIndex++) {
			const inputFixed = variationVectorNormalized[axisIndex];

			const regionAxis = regionCoords + axisIndex * 6;
			const lowFixed = m.kbS16(regionAxis);
			const peakFixed = m.kbS16(regionAxis + 2);
			const highFixed = m.kbS16(regionAxis + 4);

			if (peakFixed != 0 &&
				lowFixed <= peakFixed &&
				peakFixed <= highFixed &&
				!(lowFixed < 0 && highFixed > 0 && peakFixed != 0) &&
				inputFixed != peakFixed) {
				let axisFactor: float32 = 0;

				if (inputFixed >= lowFixed && inputFixed <= highFixed) {
					const inputFloat = kbFixed2_14ToFloat(inputFixed);
					const peakFloat = kbFixed2_14ToFloat(peakFixed);

					if (inputFixed < peakFixed) {
						const lowFloat = kbFixed2_14ToFloat(lowFixed);
						axisFactor = (inputFloat - lowFloat) / (peakFloat - lowFloat);
					} else {
						const highFloat = kbFixed2_14ToFloat(highFixed);
						axisFactor = (highFloat - inputFloat) / (highFloat - peakFloat);
					}
				}

				regionFactor *= axisFactor;
			}

			if (regionFactor == 0) {
				break;
			}
		}

		result += regionDelta * regionFactor;
	}

	return result;
}

function resolveDevice(s: KbScratch, device: int64): float32 {
	const m: Span<uint8> = s.font.blob[0..s.font.blob.length];
	if (!s.hasVariationVector || m.kbU16(device + 4) != 0x8000 || s.gdefItemVariationStore == 0) {
		return 0;
	}
	return kbItemVariationStoreDelta(m, s.gdefItemVariationStore, m.kbU16(device) as int64,
		m.kbU16(device + 2) as int64, s.variationVectorNormalized);
}

function adjustedByDevice(s: KbScratch, value: int32, device: int64): int32 {
	return kbWrapS16(value + kbWrapS16(kbRound32(resolveDevice(s, device))));
}

function adjustedByOptionalDevice(s: KbScratch, value: int32, device: int64): int32 {
	return device != 0 ? adjustedByDevice(s, value, device) : value;
}

export function kbResolveValueRecord(
	s: KbScratch,
	parent: int64,
	format: int32,
	record: int64,
): KbResolvedValueRecord {
	const m: Span<uint8> = s.font.blob[0..s.font.blob.length];
	const unpacked = kbUnpackValueRecord(m, parent, format, record);
	return {
		placementX: adjustedByOptionalDevice(s, unpacked.placementX, unpacked.placementXDevice),
		placementY: adjustedByOptionalDevice(s, unpacked.placementY, unpacked.placementYDevice),
		advanceX: adjustedByOptionalDevice(s, unpacked.advanceX, unpacked.advanceXDevice),
		advanceY: adjustedByOptionalDevice(s, unpacked.advanceY, unpacked.advanceYDevice),
	};
}

export function kbResolveAnchorXy(s: KbScratch, anchor: int64): KbAnchorXy {
	const m: Span<uint8> = s.font.blob[0..s.font.blob.length];
	const x = m.kbS16(anchor + 2);
	const y = m.kbS16(anchor + 4);
	if (m.kbU16(anchor) != 3) { return { x, y }; }
	return {
		x: x + anchorDeviceDelta(s, anchor, m.kbU16(anchor + 6)),
		y: y + anchorDeviceDelta(s, anchor, m.kbU16(anchor + 8)),
	};
}

function anchorDeviceDelta(s: KbScratch, anchor: int64, deviceOffset: int32): int32 {
	return deviceOffset != 0 ? kbRound32(resolveDevice(s, anchor + deviceOffset)) : 0;
}
