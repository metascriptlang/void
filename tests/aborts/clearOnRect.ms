// expect: clear asked of a Rect node; only a Graphics or a TileGroup can be cleared
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const box = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
box.clear();
console.log("a Rect was cleared");
