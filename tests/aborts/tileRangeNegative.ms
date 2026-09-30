// expect: setRange(-1, 4) on tile group 1: a range starts at tile 0 or later
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const map = s.add(s.tileGroup());
map.setRange(-1, 4);
console.log("a range starting before tile 0 was taken");
