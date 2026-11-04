import "../../src/host/gpu";
import { Scene2D } from "../../src/void2d/node";
import { add, close, paint } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";
import { glyphRasterizations } from "../../src/void2d/labelText";

function uiScene(): Scene2D {
	const scene = Scene2D.create(rgba(0.08, 0.09, 0.11, 1.0));
	for (let row: int32 = 0; row < 100; row++) {
		for (let column: int32 = 0; column < 100; column++) {
			const card = scene.rect(11.8, 6.2, rgba(0.2, 0.3, 0.5, 1.0))
				.at((column as float32) * 12.8, (row as float32) * 7.2);
			card.addChild(scene.label(
				String(row * 100 + column), 6.0, rgba(1.0, 1.0, 1.0, 1.0),
			));
			scene.add(card);
		}
	}
	return scene;
}

for (let run: int32 = 0; run < 6; run++) {
	const rasterizations = glyphRasterizations();
	const start = performance.now();
	const scene = uiScene();
	const constructed = performance.now();
	scene.paint(1280.0, 720.0, 1.0);
	const painted = performance.now();
	console.log(`FIRST_PAINT run=${run} constructMs=${constructed - start} ` +
		`paintMs=${painted - constructed} constructToPaintMs=${painted - start} ` +
		`rasterizations=${glyphRasterizations() - rasterizations}`);
	scene.close();
}
