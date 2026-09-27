// expect: addChild would put node 1 under node 2, which is inside it
import "../../src/sokol/gpu";
import { Scene } from "../../src/void2d/node";
import { scene } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene = scene(rgba(0.0, 0.0, 0.0, 1.0));
const other = s.group();
const b = other.addChild(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
b.addChild(other);
console.log("a node went under its own child");
