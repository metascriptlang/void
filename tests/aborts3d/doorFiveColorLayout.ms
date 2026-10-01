// expect: gpu door: layoutOf takes at most 4 color attachments, given 5
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { ColorAttachment, NO_DEPTH, TargetLayout, layoutOf } from "../../src/gpu/target";

let colors: Vec<ColorAttachment> = [];
for (let i = 0; i < 5; i++) {
	colors.push({
		view: 0, format: PixelFormat.Rgba8, load: LoadAction.Clear,
		clear: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	});
}
const layout: TargetLayout = layoutOf(colors, NO_DEPTH);
console.log(`a layout of five color attachments: ${layout.toString()}`);
