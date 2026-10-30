export const KB_LOOKUP_PINS: string[] = [
	"fixture 2146993524",
	"assets/font.ttf 3795695653",
	"tests/fonts/NotoSansSC-subset.ttf 3160072673",
	"tests/fonts/cascadiaSubset.ttf 728218293",
	"tests/fonts/ligatureFeatures.ttf 3093330252",
	"tests/fonts/notoSansArabicSubset.ttf 2385709876",
	"tests/fonts/notoSansDevanagariSubset.ttf 3774385563",
	"tests/fonts/notoSansHebrewSubset.ttf 3835060674",
	"tests/fonts/notoSansKhmerSubset.ttf 1107617464",
	"tests/fonts/notoSansThaiSubset.ttf 1123015279",
];

export function kbLookupPinned(name: string): string {
	for (const pin of KB_LOOKUP_PINS) {
		const parts = pin.split(" ");
		if (parts[0] == name) { return parts[1]; }
	}
	return "unpinned";
}
