// expect: wide clusters span two cells, and a label without setForceWidth has none
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const wide: int32[] = [0];
const n = s.label("中", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
n.setWideClusters(wide);
n.sync(identity2d(), false);
console.log(`a wide cluster outside a cell grid measured ${n.textWidth()}`);
