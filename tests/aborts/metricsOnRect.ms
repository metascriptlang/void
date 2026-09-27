// expect: textWidth asked of a Rect node
import "../../src/sokol/gpu";
import { Scene } from "../../src/void2d/node";
import { scene } from "../../src/void2d/scene";
import { sync } from "../../src/void2d/render";
import { rgba, identity2d } from "../../src/void2d/types";

const s: Scene = scene(rgba(0.0, 0.0, 0.0, 1.0));
const box = s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
box.sync(identity2d(), false);
console.log(`textWidth of a Rect returned ${box.textWidth()}`);
