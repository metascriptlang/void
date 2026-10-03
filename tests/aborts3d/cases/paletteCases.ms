// expect closed.fill: void3d: fill on a palette table that was closed
// expect closed.releaseGpu: void3d: releaseGpu on a palette table that was closed
// expect closed.closePalette: void3d: closePalette on a palette table that was closed
import { argv } from "std/process";
import {
	PaletteLut,
	PaletteError,
	fill,
	releaseGpu,
	closePalette,
} from "../../../src/void3d/palette";

function closedTable(): PaletteLut {
	const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
	if (!made.ok) { unreachable; }
	let lut: PaletteLut = made.value;
	closePalette(lut);
	return lut;
}

function run(name: string): void {
	let colors: Vec<uint32> = [0xFF000000, 0xFFFFFFFF];
	if (name == "closed.fill") {
		const _r: Result<int32, PaletteError> = fill(closedTable(), colors);
	} else if (name == "closed.releaseGpu") {
		releaseGpu(closedTable());
	} else if (name == "closed.closePalette") {
		closePalette(closedTable());
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
