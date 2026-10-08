// expect: shaping break 5 falls outside the text's 4 UTF-16 units
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const breaks: int32[] = [5];
const n = s.label("a😀b", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setShapingBreaks(breaks);
n.sync(identity2d(), false);
console.log(`a label with a shaping break outside its text measured ${n.textWidth()}`);
