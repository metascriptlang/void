// expect: void2d: endTarget with no target open; every endTarget closes one beginTarget
import "../../src/sokol/gpu";
import { begin2d, endTarget } from "../../src/void2d/draw";

begin2d(16.0, 16.0, 1.0);
endTarget();
console.log("an endTarget with no target open returned");
