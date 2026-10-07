// expect: present at 5000000 ns before the frame was drawn and committed
import { frameProfiler, present } from "../../src/void2d/profiler";

const p = frameProfiler();
p.present(5000000, 6000000);
console.log("a present was recorded with no frame");
