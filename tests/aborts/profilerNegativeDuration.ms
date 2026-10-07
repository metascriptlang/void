// expect: commit at 3000000 ns is before drawBegin at 9000000 ns
import { frameProfiler, drawBegin, commit } from "../../src/void2d/profiler";

const p = frameProfiler();
p.drawBegin(9000000);
p.commit(3000000);
console.log("a frame ended before it began");
