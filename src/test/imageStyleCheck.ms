import { Color, tile, rgba } from "../void2d/types";
import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import { ObjectFit, imageStyle, fitImage, NO_IMAGE_STYLE } from "../void2d/imageStyle";

function tileClear(): Color { return rgba(0.0, 0.0, 0.0, 1.0); }

function near(a: float32, b: float32): boolean {
	const d: float32 = a > b ? a - b : b - a;
	return d <= 0.00001;
}

test "ObjectFit maps a wide image into square bounds" {
	const t = tile(0, 200.0, 100.0);
	const fill = fitImage(t, 100.0, 100.0, ObjectFit.Fill);
	assert fill.x == 0.0 && fill.y == 0.0 && fill.w == 100.0 && fill.h == 100.0;
	assert fill.u0 == 0.0 && fill.v0 == 0.0 && fill.u1 == 1.0 && fill.v1 == 1.0;

	const contain = fitImage(t, 100.0, 100.0, ObjectFit.Contain);
	assert contain.x == 0.0 && contain.y == 25.0;
	assert contain.w == 100.0 && contain.h == 50.0;

	const cover = fitImage(t, 100.0, 100.0, ObjectFit.Cover);
	assert cover.x == 0.0 && cover.y == 0.0 && cover.w == 100.0 && cover.h == 100.0;
	assert near(cover.u0, 0.25) && near(cover.u1, 0.75);
	assert cover.v0 == 0.0 && cover.v1 == 1.0;
}

test "ObjectFit ScaleDown preserves small images and contains large ones" {
	const small = fitImage(tile(0, 40.0, 20.0), 100.0, 100.0, ObjectFit.ScaleDown);
	assert small.x == 30.0 && small.y == 40.0 && small.w == 40.0 && small.h == 20.0;
	const large = fitImage(tile(0, 200.0, 100.0), 100.0, 100.0, ObjectFit.ScaleDown);
	assert large.x == 0.0 && large.y == 25.0 && large.w == 100.0 && large.h == 50.0;
}

test "ObjectFit None clips from the image origin and advances its UV" {
	const t = tile(0, 200.0, 100.0);
	const fitted = fitImage(t, 100.0, 60.0, ObjectFit.None);
	assert fitted.x == 0.0 && fitted.y == 0.0 && fitted.w == 100.0 && fitted.h == 60.0;
	assert near(fitted.u1, 0.5) && near(fitted.v1, 0.6);
}

test "image styles update in place and dispose returns their side-table slot" {
	const s: Scene2D = Scene2D.create(tileClear());
	const first = s.sprite(tile(0, 32.0, 16.0));
	first.setImageStyle(imageStyle(
		{ topLeft: 1.0, topRight: 2.0, bottomRight: 3.0, bottomLeft: 4.0 },
		false,
		ObjectFit.Fill,
	));
	const slot: int32 = s.payloads[first.id.index];
	first.setImageStyle(imageStyle(
		{ topLeft: 5.0, topRight: 6.0, bottomRight: 7.0, bottomLeft: 8.0 },
		true,
		ObjectFit.Cover,
	));
	assert s.payloads[first.id.index] == slot;
	first.dispose();
	assert s.payloads[first.id.index] == NO_IMAGE_STYLE;

	const second = s.sprite(tile(0, 16.0, 16.0));
	second.setImageStyle(imageStyle(
		{ topLeft: 0.0, topRight: 0.0, bottomRight: 0.0, bottomLeft: 0.0 },
		false,
		ObjectFit.Contain,
	));
	assert s.payloads[second.id.index] == slot;
	second.dispose();

	const notImage = s.graphics();
	assert s.imageStyleOf(notImage.id.index) == NO_IMAGE_STYLE;
}
