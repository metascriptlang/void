// expect: shaping break 2 falls inside the surrogate pair at 1
import "../../src/sokol/gpu";
import { label } from "../../src/void2d/node";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const breaks: int32[] = [2];
const n = label("a😀b", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setShapingBreaks(breaks);
n.sync(identity2d(), false);
console.log(`a label with a shaping break inside a surrogate pair measured ${n.textWidth()}`);
