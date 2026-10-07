// expect: a feature tag is four printable ASCII characters
// flags: -d:voidShaper
import { loadFace } from "../../src/void2d/face";
import { ShapeDirection, shaperBegin, shaperFeature } from "../../src/void2d/shaper";

const face: int32 = try loadFace("assets/font.ttf") catch -1;
shaperBegin(face, ShapeDirection.Ltr);
shaperFeature("\u00e9ab", 1);
console.log("a tag with a byte above ASCII was taken");
