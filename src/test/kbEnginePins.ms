export const KB_ENGINE_PINS: string[] = [
	"configFixture 3328569625",
	"lookupFixture 890237247",
	"assets/font.ttf 3256859664",
	"tests/fonts/NotoColorEmoji-subset.ttf 2475099733",
	"tests/fonts/NotoSansSC-subset.ttf 3955761845",
	"tests/fonts/cascadiaSubset.ttf 2787540163",
	"tests/fonts/cbdtBroken.ttf 342073655",
	"tests/fonts/cbdtFormats.ttf 56812653",
	"tests/fonts/cbdtMixedDepth.ttf 342073655",
	"tests/fonts/cbdtSynthetic.ttf 342073655",
	"tests/fonts/cbdtUvsLast.ttf 342073655",
	"tests/fonts/cffSynthetic.otf 1560621020",
	"tests/fonts/colrForeground.ttf 2460194116",
	"tests/fonts/colrLigature.ttf 812570502",
	"tests/fonts/colrSynthetic.ttf 2460194116",
	"tests/fonts/colrUnion.ttf 2460194116",
	"tests/fonts/colrV1Only.ttf 2460194116",
	"tests/fonts/ligatureFeatures.ttf 3017591453",
	"tests/fonts/notoSansArabicSubset.ttf 4180393980",
	"tests/fonts/notoSansDevanagariSubset.ttf 2087588200",
	"tests/fonts/notoSansHebrewSubset.ttf 2995655979",
	"tests/fonts/notoSansKhmerSubset.ttf 3034523138",
	"tests/fonts/notoSansThaiSubset.ttf 91887774",
	"tests/fonts/sbixLoop.ttf 56812653",
	"tests/fonts/sbixSynthetic.ttf 56812653",
	"tests/fonts/shapeFixture.ttf 643218260",
	"tests/fonts/symbolCollection.ttc 3298485879",
	"tests/fonts/textSymbol.ttf 3298485879",
	"tests/fonts/zeroLineHeight.ttf 1073240727",
	"tests/fonts/zeroThickness.ttf 1073240727",
	"tests/fonts/zeroedDecorations.ttf 3003727071",
];

export function kbEnginePinned(name: string): string {
	for (const pin of KB_ENGINE_PINS) {
		const parts = pin.split(" ");
		if (parts[0] == name) { return parts[1]; }
	}
	return "unpinned";
}
