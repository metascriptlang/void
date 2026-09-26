// expect: setSelectionRange asked of a Rect node
import "../../src/sokol/gpu";
import { rect } from "../../src/void2d/node";
import { rgba } from "../../src/void2d/types";

const n = rect(40.0, 20.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setSelectionRange({ start: 0, length: 1 }, rgba(0.3, 0.5, 0.9, 0.5));
console.log("a Rect took a selection range");
