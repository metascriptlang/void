// expect: void2d svg: svgMaskRasterize: handle 65537 is not a live SVG
// flags: -d:voidSvg
import { svgMaskFree, svgMaskParse, svgMaskRasterize } from "../../src/void2d/svgMask";

const parsed = svgMaskParse(
	`<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">`
		+ `<rect width="4" height="4"/></svg>`,
);
if (parsed.ok) {
	svgMaskFree(parsed.value);
	svgMaskRasterize(parsed.value, 4, 4);
	console.log("a freed SVG was rasterized");
}
