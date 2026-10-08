// expect: void2d text outline: setOutline needs the outline module; build with -d:voidTextOutline
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const n = s.label("outlined", 16.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setOutline(2.0, rgba(0.0, 0.0, 0.0, 1.0));
console.log("a label took an outline with the module off");
