// expect: both sides must be zero or more
// flags: -d:voidSvg
import { registerIcon } from "../../src/void2d/icon";
import { Scene2D } from "../../src/void2d/node";
import "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";

const registered = registerIcon(
	`<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">` +
		`<rect width="4" height="4"/></svg>`,
);
const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
if (registered.ok) {
	s.icon(registered.value, -1.0, 8.0, rgba(1.0, 1.0, 1.0, 1.0));
	console.log("an icon of negative width was made");
}
