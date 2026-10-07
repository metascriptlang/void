// expect: void2d shaper: shaperBegin needs the shaper module; build with -d:voidShaper
import { shaperBegin, ShapeDirection } from "../../src/void2d/shaper";

shaperBegin(0, ShapeDirection.Ltr);
console.log("the shaper began with the module off");
