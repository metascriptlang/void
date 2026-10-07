// expect: void2d profiler overlay: the 5x7 font has no glyph for 'c'
// flags: -d:voidProfiler
import { OverlayMode } from "../../src/void2d/profiler";
import { layoutOverlay } from "../../src/void2d/profilerOverlay";

let lines: Vec<string> = new Array(0);
lines.push("cur 1.0 MS");
const layout = layoutOverlay({
	mode: OverlayMode.Minimal,
	lines: lines,
	drawBuckets: new Array(0),
	dirtyBuckets: new Array(0),
});
console.log(`laid out ${layout.rects.length} rects with a character that has no glyph`);
