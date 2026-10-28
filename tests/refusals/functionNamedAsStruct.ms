// expect: 4:1 function 'Shaded' is named as the struct 'Shaded'; a struct's name is its hook site's
import { glslSegmentIr } from "../../src/shader/emit";
import { Shaded as Phase } from "./parts/shadedPhase";
function Shaded(shaded: Phase): Phase {
	return shaded;
}
console.log(glslSegmentIr(Shaded));
