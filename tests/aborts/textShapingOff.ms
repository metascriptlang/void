// expect: void2d: text shaping was asked for without -d:voidShaper
import { setTextShaping } from "../../src/void2d/textLayout";

setTextShaping(true);
console.log("text shaping was turned on with the module off");
