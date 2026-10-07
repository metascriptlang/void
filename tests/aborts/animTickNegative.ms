// expect: time only moves forward
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba, whiteTile } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
s.add(s.anim(frames, 10.0));
s.tick(-0.5);
console.log("time ran backwards");
