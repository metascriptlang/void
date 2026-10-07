// expect: void2d svg: svgMaskFree: handle 65537 is not a live SVG
// flags: -d:voidSvg
import { svgMaskFree, svgMaskParse } from "../../src/void2d/svgMask";

const svg: string = `<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">`
	+ `<rect width="4" height="4"/></svg>`;
const first = svgMaskParse(svg);
const second = svgMaskParse(svg);
if (first.ok && second.ok) {
	svgMaskFree(first.value);
	const reused = svgMaskParse(svg);
	svgMaskFree(first.value);
	console.log("a freed handle freed another SVG");
}
