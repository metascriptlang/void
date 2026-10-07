// expect: void2d svg: svgMaskParse needs the SVG module; build with -d:voidSvg
import { svgMaskParse } from "../../src/void2d/svgMask";

svgMaskParse("<svg/>");
console.log("an SVG was parsed with the module off");
