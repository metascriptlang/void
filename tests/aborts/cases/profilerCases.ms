// flags: -d:voidProfiler
// expect overlayNoGlyph: void2d profiler overlay: the 5x7 font has no glyph for 'c'
import { argv } from "std/process";
import { OverlayMode } from "../../../src/void2d/profiler";
import { layoutOverlay } from "../../../src/void2d/profilerOverlay";

function run(name: string): void {
	if (name == "overlayNoGlyph") {
		let lines: Vec<string> = new Array(0);
		lines.push("cur 1.0 MS");
		const layout = layoutOverlay({
			mode: OverlayMode.Minimal,
			lines: lines,
			drawBuckets: new Array(0),
			dirtyBuckets: new Array(0),
		});
		console.log(`laid out ${layout.rects.length} rects with a character that has no glyph`);
	} else {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
