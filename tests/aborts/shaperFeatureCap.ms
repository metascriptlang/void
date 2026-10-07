// expect: more than 32 feature overrides in one pass
// flags: -d:voidShaper
import { loadFace } from "../../src/void2d/face";
import { ShapeDirection, shaperBegin, shaperFeature } from "../../src/void2d/shaper";

const face: int32 = try loadFace("assets/font.ttf") catch -1;
shaperBegin(face, ShapeDirection.Ltr);
for (let i: int32 = 0; i < 33; i++) {
	shaperFeature(`ft${i < 10 ? "0" : ""}${i}`, 1);
}
console.log("the feature cap was passed");
