// expect: void3d: upload on a palette table that was closed
import { PaletteLut, PaletteError, upload, closePalette } from "../../src/void3d/palette";

const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
if (!made.ok) { unreachable; }
let lut: PaletteLut = made.value;
let alias: PaletteLut = lut;
closePalette(lut);
upload(alias);
console.log("a closed palette table uploaded");
