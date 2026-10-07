// expect: setFrame(3) on an Anim of 3 frames
import "../../src/sokol/gpu";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba, whiteTile } from "../../src/void2d/types";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
s.anim(frames, 10.0).setFrame(3);
console.log("a frame past the end was shown");
