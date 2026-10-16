// expect: wide cluster 1 does not start a grapheme cluster
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const wide: int32[] = [1];
const n = s.label("é", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setForceWidth(10.0);
n.setWideClusters(wide);
n.sync(identity2d(), false);
console.log(`a label flagging a combining mark wide measured ${n.textWidth()}`);
