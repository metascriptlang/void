// expect reserveScreenBlock: void3d: ProbePass.reserve found no room for a block it was checked
// expect addScreenMaterial: void3d: ProbePass.reserve could not add its screen material
// expect stopOnFailedWrite: void3d: ProbePass.draw could not write its uniform block: Released
import { argv } from "std/process";
import { Program } from "../../../src/void3d/gpu3d";
import { TypedBlock } from "../../../src/void3d/material";
import { OutlineWidthParams } from "../../../src/void3d/post3d";
import { DrawContext } from "../../../src/void3d/draw";
import { UniformError, stopOnFailedWrite } from "../../../src/void3d/uniformPool";
import { screenState, reserveScreenBlock, addScreenMaterial } from "../../../src/void3d/screenFx";

function run(name: string): void {
	let context: DrawContext = DrawContext.withUniformCapacity(4);
	if (name == "reserveScreenBlock") {
		let empty: DrawContext = DrawContext.withUniformCapacity(0);
		const _block: TypedBlock<OutlineWidthParams> =
			reserveScreenBlock<OutlineWidthParams>(empty, 0, "ProbePass.reserve");
	} else if (name == "addScreenMaterial") {
		const block: TypedBlock<OutlineWidthParams> =
			reserveScreenBlock<OutlineWidthParams>(context, 0, "ProbePass.reserve");
		const _first = addScreenMaterial(
			context, Program.OutlineWidth, screenState(), block.block, "ProbePass.reserve",
		);
		const _second = addScreenMaterial(
			context, Program.OutlineWidth, screenState(), block.block, "ProbePass.reserve",
		);
	} else if (name == "stopOnFailedWrite") {
		stopOnFailedWrite("ProbePass.draw", UniformError.Released);
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
