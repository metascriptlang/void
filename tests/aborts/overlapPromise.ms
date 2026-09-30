// expect: node 1 promised setNoOverlap, but its children 2 and 3 overlap
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import { paint } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const list = s.add(s.group());
list.addChild(s.rect(40.0, 20.0, rgba(1.0, 0.0, 0.0, 1.0)));
list.addChild(s.rect(40.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)).at(0.0, 10.0));
list.setNoOverlap(true);
s.paint(200.0, 100.0, 1.0);
console.log("two overlapping children were drawn in lanes");
