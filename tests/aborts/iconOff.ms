// expect: void2d svg: svgMaskParse needs the SVG module; build with -d:voidSvg
import { registerIcon } from "../../src/void2d/icon";

registerIcon("<svg/>");
console.log("an icon was registered with the module off");
