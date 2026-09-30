// expect: shaping break 2 falls inside the surrogate pair at 1
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const breaks: int32[] = [2];
const n = s.label("a😀b", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setShapingBreaks(breaks);
n.sync(identity2d(), false);
console.log(`a label with a shaping break inside a surrogate pair measured ${n.textWidth()}`);
