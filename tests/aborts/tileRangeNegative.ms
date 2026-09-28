// expect: setRange(-1, 4) on tile group 1: a range starts at tile 0 or later
import "../../src/sokol/gpu";
import { Scene } from "../../src/void2d/node";
import { scene } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene = scene(rgba(0.0, 0.0, 0.0, 1.0));
const map = s.add(s.tileGroup());
map.setRange(-1, 4);
console.log("a range starting before tile 0 was taken");
