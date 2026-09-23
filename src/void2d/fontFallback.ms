import { loadFace, glyphIndex } from "./face";

const NOT_LOADED: int32 = -1;
const LOAD_FAILED: int32 = -2;

struct Fallback {
	primary: int32;
	path: string;
	face: int32;
}

const fallbacks: Fallback[] = [];
let resolved: Map<uint64, int32> = new Map<uint64, int32>();
let fallbackLoads: int32 = 0;
let coverageProbes: int32 = 0;

export function addFallback(primary: int32, path: string): void {
	fallbacks.push({ primary: primary, path: path, face: NOT_LOADED });
	resolved = new Map<uint64, int32>();
}

export function fallbackFacesLoaded(): int32 {
	return fallbackLoads;
}

export function fallbackProbes(): int32 {
	return coverageProbes;
}

function loadedFace(index: int32): int32 {
	if (fallbacks[index].face == NOT_LOADED) {
		const face: int32 = loadFace(fallbacks[index].path);
		fallbackLoads = fallbackLoads + 1;
		if (face < 0) {
			console.log(`void2d: fallback font ${fallbacks[index].path} did not load; it is skipped`);
			fallbacks[index].face = LOAD_FAILED;
		} else {
			fallbacks[index].face = face;
		}
	}
	return fallbacks[index].face;
}

export function faceForCodepoint(primary: int32, codepoint: int32): int32 {
	const key: uint64 = ((primary as uint64) << 32) | (codepoint as uint64);
	const hit = resolved.get(key);
	if (hit.present) { return hit.value; }
	coverageProbes = coverageProbes + 1;
	let face: int32 = primary;
	if (glyphIndex(primary, codepoint) == 0) {
		for (let i = 0; i < (fallbacks.length as int32); i++) {
			if (fallbacks[i].primary != primary) { continue; }
			const candidate: int32 = loadedFace(i);
			if (candidate >= 0 && glyphIndex(candidate, codepoint) != 0) {
				face = candidate;
				break;
			}
		}
	}
	resolved.set(key, face);
	return face;
}
