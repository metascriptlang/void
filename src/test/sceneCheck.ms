import { Scene2D } from "../void2d/node";
import { setScaleMode, sceneViewMatrix, designFold } from "../void2d/scene";
import { ScaleMode, rgba } from "../void2d/types";
import { approx } from "./helpers";

test "Resize mode is identity camera" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "Resize mode ignores a design size" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Resize, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "Stretch mode scales to fill" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Stretch, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 2.0);
	assert approx(m.d, 2.0);
}

test "LetterBox centers with uniform scale" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.LetterBox, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 2.0);
	assert approx(m.d, 2.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "LetterBox portrait centers on whole scene units, as h2d's checkResize floors" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.LetterBox, 300.0, 400.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.5);
	assert approx(m.d, 1.5);
	assert approx(m.tx, 174.0);
	assert approx(m.ty, 0.0);
}

test "Fixed mode centers without scaling" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Fixed, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 200.0);
	assert approx(m.ty, 150.0);
}

test "Zoom mode fills and crops" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Zoom, 400.0, 200.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 3.0);
	assert approx(m.d, 3.0);
}

test "AutoZoom uses integer scale" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.AutoZoom, 200.0, 150.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 4.0);
	assert approx(m.d, 4.0);
}

test "AutoZoom clamps to 1x when too small" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.AutoZoom, 700.0, 500.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
}

test "the design fold is the view's uniform scale, and one where the scale is not uniform" {
	const s = Scene2D.create(rgba(0, 0, 0, 1));
	const modes: ScaleMode[] = [
		ScaleMode.LetterBox, ScaleMode.Zoom, ScaleMode.AutoZoom, ScaleMode.Stretch,
	];
	for (const mode of modes) {
		s.setScaleMode(mode, 200.0, 125.0);
		const m = sceneViewMatrix(s, 320.0, 200.0);
		assert approx(designFold(s, 320.0, 200.0), m.a) && approx(m.a, m.d);
	}
	s.setScaleMode(ScaleMode.LetterBox, 200.0, 125.0);
	assert approx(designFold(s, 320.0, 200.0), 1.6);
	s.setScaleMode(ScaleMode.Stretch, 200.0, 100.0);
	assert designFold(s, 320.0, 200.0) == 1.0;
	s.setScaleMode(ScaleMode.Fixed, 200.0, 125.0);
	assert designFold(s, 320.0, 200.0) == 1.0;
	s.setScaleMode(ScaleMode.Resize, 200.0, 125.0);
	assert designFold(s, 320.0, 200.0) == 1.0;
}
