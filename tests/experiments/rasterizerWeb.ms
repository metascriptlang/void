// The demo with FreeType light hinting installed as the glyph rasterizer, so the web builds
// carry FreeType and their size against the plain demo is the FreeType wasm delta
// (docs/VOID2D.md P3, "The rasterizer"). scripts/experiment-rasterizer.sh --wasm builds it.

import { init2d, frame2d } from "../../src/examples/renderer2d";
import { void2dFreetypeInstall } from "./freetypeRaster.h";

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	void2dFreetypeInstall(1);
	voidRun(800, 600, init2d, frame2d);
	return 0;
}

main();
