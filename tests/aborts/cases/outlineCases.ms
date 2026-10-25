// flags: -d:voidTextOutline
// expect outlineNegative: void2d text outline: setOutline width -1 is not zero or above
import { argv } from "std/process";
import "../../../src/sokol/gpu";
import { Scene2D } from "../../../src/void2d/node";
import "../../../src/void2d/scene";
import { rgba } from "../../../src/void2d/types";

function run(name: string): void {
	if (name == "outlineNegative") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const n = s.label("outlined", 16.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setOutline(-1.0, rgba(0.0, 0.0, 0.0, 1.0));
		console.log("a label took a negative outline");
	} else {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
