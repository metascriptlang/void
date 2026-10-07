// expect: void2d shaper: glyph 7 is outside the 1 of the last pass
// flags: -d:voidShaper
import { loadFace } from "../../src/void2d/face";
import {
	ShapeDirection,
	shaperBegin,
	shaperCodepoint,
	shaperEnd,
	shaperGlyph,
} from "../../src/void2d/shaper";

const face: int32 = try loadFace("assets/font.ttf") catch -1;
shaperBegin(face, ShapeDirection.Ltr);
shaperCodepoint(0x41);
const count: int32 = shaperEnd();
console.log(`shaped ${count}`);
shaperGlyph(7);
console.log("a glyph outside the pass was read");
