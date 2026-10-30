export const KB_SHAPE_PINS: string[] = [
	"configFixture 595588359",
	"lookupFixture 76474454",
	"assets/font.ttf 2541815804",
	"tests/fonts/NotoColorEmoji-subset.ttf 3737969273",
	"tests/fonts/NotoSansSC-subset.ttf 2726206676",
	"tests/fonts/cascadiaSubset.ttf 3638912838",
	"tests/fonts/cbdtBroken.ttf 574236544",
	"tests/fonts/cbdtFormats.ttf 294313957",
	"tests/fonts/cbdtMixedDepth.ttf 574236544",
	"tests/fonts/cbdtSynthetic.ttf 574236544",
	"tests/fonts/cbdtUvsLast.ttf 574236544",
	"tests/fonts/cffSynthetic.otf 321912844",
	"tests/fonts/colrForeground.ttf 1937663306",
	"tests/fonts/colrLigature.ttf 2495833724",
	"tests/fonts/colrSynthetic.ttf 1937663306",
	"tests/fonts/colrUnion.ttf 1937663306",
	"tests/fonts/colrV1Only.ttf 1937663306",
	"tests/fonts/ligatureFeatures.ttf 4105129636",
	"tests/fonts/notoSansArabicSubset.ttf 1824083036",
	"tests/fonts/notoSansDevanagariSubset.ttf 3467472993",
	"tests/fonts/notoSansHebrewSubset.ttf 825258752",
	"tests/fonts/notoSansKhmerSubset.ttf 37516816",
	"tests/fonts/notoSansThaiSubset.ttf 652135126",
	"tests/fonts/sbixLoop.ttf 294313957",
	"tests/fonts/sbixSynthetic.ttf 294313957",
	"tests/fonts/shapeFixture.ttf 2874422047",
	"tests/fonts/symbolCollection.ttc 3012247764",
	"tests/fonts/textSymbol.ttf 3012247764",
	"tests/fonts/zeroLineHeight.ttf 2076287322",
	"tests/fonts/zeroThickness.ttf 2076287322",
	"tests/fonts/zeroedDecorations.ttf 4148431809",
];

export function kbShapePinned(name: string): string {
	for (const pin of KB_SHAPE_PINS) {
		const parts = pin.split(" ");
		if (parts[0] == name) { return parts[1]; }
	}
	return "unpinned";
}
