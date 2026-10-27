import { kbFontFromMemory, kbFontIsValid } from "../void2d/kb/font";
import { kbLookupDigestOf } from "./kbLookupCorpus";

export const KB_LOOKUP_WANT: int32 = 96;

export function kbLookupDigestOfBytes(
	bytes: uint8[],
	fontIndex: int32,
	words: string[],
	seeds: int32,
	perSeed: int32,
): uint32 {
	const font = kbFontFromMemory(bytes[0..bytes.length], fontIndex);
	if (!kbFontIsValid(font)) { return 0; }
	return kbLookupDigestOf(font, words, seeds, perSeed, KB_LOOKUP_WANT);
}
