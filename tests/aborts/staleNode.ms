// expect: setX on stale node 1: the handle has generation 1, the row 2
import "../../src/sokol/gpu";
import { Scene } from "../../src/void2d/node";
import { scene } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene = scene(rgba(0.0, 0.0, 0.0, 1.0));
const b = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
b.dispose();
b.setX(1.0);
console.log("a disposed node took a write");
