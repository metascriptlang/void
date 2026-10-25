// flags: -d:voidSvg
// expect iconNegativeSize: both sides must be zero or more
// expect iconSetOnRect: setIcon asked of a Rect node
// expect iconSetUnregistered: void2d icon: setIcon: icon 7 is not registered
// expect iconUnregistered: void2d icon: scene.icon: icon 7 is not registered
// expect svgMaskReusedHandle: void2d svg: svgMaskFree: handle 65537 is not a live SVG
// expect svgMaskStaleHandle: void2d svg: svgMaskRasterize: handle 65537 is not a live SVG
import { argv } from "std/process";
import "../../../src/sokol/gpu";
import { IconId, registerIcon } from "../../../src/void2d/icon";
import { Scene2D } from "../../../src/void2d/node";
import "../../../src/void2d/scene";
import { rgba } from "../../../src/void2d/types";
import { svgMaskFree, svgMaskParse, svgMaskRasterize } from "../../../src/void2d/svgMask";

function run(name: string): void {
	if (name == "iconNegativeSize") {
		const registered = registerIcon(
			`<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">` +
				`<rect width="4" height="4"/></svg>`,
		);
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		if (registered.ok) {
			s.icon(registered.value, -1.0, 8.0, rgba(1.0, 1.0, 1.0, 1.0));
			console.log("an icon of negative width was made");
		}
	} else if (name == "iconSetOnRect") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const r = registerIcon(
			`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">` +
			`<rect width="8" height="8"/></svg>`,
		);
		if (r.ok) { s.rect(40.0, 20.0, rgba(1.0, 1.0, 1.0, 1.0)).setIcon(r.value); }
		console.log("a Rect took an icon");
	} else if (name == "iconSetUnregistered") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const r = registerIcon(
			`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">` +
			`<rect width="8" height="8"/></svg>`,
		);
		if (r.ok) { s.icon(r.value, 24.0, 24.0, rgba(1.0, 1.0, 1.0, 1.0)).setIcon(7 as IconId); }
		console.log("an icon was switched to one nobody registered");
	} else if (name == "iconUnregistered") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		s.icon(7 as IconId, 24.0, 24.0, rgba(1.0, 1.0, 1.0, 1.0));
		console.log("an icon nobody registered was drawn");
	} else if (name == "svgMaskReusedHandle") {
		const svg: string = `<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">`
			+ `<rect width="4" height="4"/></svg>`;
		const first = svgMaskParse(svg);
		const second = svgMaskParse(svg);
		if (first.ok && second.ok) {
			svgMaskFree(first.value);
			const reused = svgMaskParse(svg);
			svgMaskFree(first.value);
			console.log("a freed handle freed another SVG");
		}
	} else if (name == "svgMaskStaleHandle") {
		const parsed = svgMaskParse(
			`<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">`
				+ `<rect width="4" height="4"/></svg>`,
		);
		if (parsed.ok) {
			svgMaskFree(parsed.value);
			svgMaskRasterize(parsed.value, 4, 4);
			console.log("a freed SVG was rasterized");
		}
	} else {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
