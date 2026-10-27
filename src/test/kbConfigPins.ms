export const KB_CONFIG_PINS: string[] = [
	"fixture 771273611",
	"assets/font.ttf 2691594186",
	"tests/fonts/NotoSansSC-subset.ttf 3956556639",
	"tests/fonts/cascadiaSubset.ttf 446111807",
	"tests/fonts/ligatureFeatures.ttf 358307263",
	"tests/fonts/notoSansArabicSubset.ttf 891375177",
	"tests/fonts/notoSansDevanagariSubset.ttf 498573539",
	"tests/fonts/notoSansHebrewSubset.ttf 1863567385",
	"tests/fonts/notoSansKhmerSubset.ttf 1818110731",
	"tests/fonts/notoSansThaiSubset.ttf 683049317",
];

export function kbConfigPinned(name: string): string {
	for (const pin of KB_CONFIG_PINS) {
		const parts = pin.split(" ");
		if (parts[0] == name) { return parts[1]; }
	}
	return "unpinned";
}
