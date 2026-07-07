import { scene, setScaleMode, sceneViewMatrix } from "../void2d/scene";
import { ScaleMode, rgba } from "../void2d/types";
import { approx } from "./helpers";

test "scene defaults are Resize mode" {
	const s = scene(rgba(0, 0, 0, 1));
	assert s.scaleMode === ScaleMode.Resize;
	assert s.designW == 0.0;
	assert s.designH == 0.0;
}

test "setScaleMode sets fields" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.LetterBox, 1920.0, 1080.0);
	assert s.scaleMode === ScaleMode.LetterBox;
	assert approx(s.designW, 1920.0);
	assert approx(s.designH, 1080.0);
}

test "Resize mode is identity camera" {
	const s = scene(rgba(0, 0, 0, 1));
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "Stretch mode scales to fill" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Stretch, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 2.0);
	assert approx(m.d, 2.0);
}

test "LetterBox centers with uniform scale" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.LetterBox, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 2.0);
	assert approx(m.d, 2.0);
	assert approx(m.tx, 0.0);
	assert approx(m.ty, 0.0);
}

test "LetterBox portrait centers vertically" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.LetterBox, 300.0, 400.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.5);
	assert approx(m.d, 1.5);
	assert approx(m.tx, 175.0);
	assert approx(m.ty, 0.0);
}

test "Fixed mode centers without scaling" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Fixed, 400.0, 300.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
	assert approx(m.tx, 200.0);
	assert approx(m.ty, 150.0);
}

test "Zoom mode fills and crops" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.Zoom, 400.0, 200.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 3.0);
	assert approx(m.d, 3.0);
}

test "AutoZoom uses integer scale" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.AutoZoom, 200.0, 150.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 4.0);
	assert approx(m.d, 4.0);
}

test "AutoZoom clamps to 1x when too small" {
	const s = scene(rgba(0, 0, 0, 1));
	s.setScaleMode(ScaleMode.AutoZoom, 700.0, 500.0);
	const m = sceneViewMatrix(s, 800.0, 600.0);
	assert approx(m.a, 1.0);
	assert approx(m.d, 1.0);
}
