// expect: 4:1 segment 'brighten': its first parameter 'c' is the phase struct it reads and returns, and Vec4f is no author struct
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec4f } from "../../src/shader/std";
function brighten(c: Vec4f): Vec4f { return c * c; }
console.log(glslSegmentIr(brighten));
