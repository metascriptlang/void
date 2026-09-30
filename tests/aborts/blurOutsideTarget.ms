// expect: void2d: blurPass outside beginTarget; the blur draws only into a target
import "../../src/sokol/gpu";
import { begin2d, blurPass } from "../../src/void2d/draw";

begin2d(16.0, 16.0, 1.0);
blurPass(1, 1.0 / 16.0, 0.0);
console.log("a blur was recorded into the screen list");
