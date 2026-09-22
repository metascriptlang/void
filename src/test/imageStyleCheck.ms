import { tile } from "../void2d/types";
import { graphics, sprite, setImageStyle, dispose } from "../void2d/node";
import { cornerRadii } from "../void2d/boxStyle";
import { ObjectFit, imageStyle, fitImage, NO_IMAGE_STYLE } from "../void2d/imageStyle";

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
	const first = sprite(tile(0, 32.0, 16.0));
	first.setImageStyle(imageStyle(cornerRadii(1.0, 2.0, 3.0, 4.0), false, ObjectFit.Fill));
	const slot: int32 = first.payload;
	first.setImageStyle(imageStyle(cornerRadii(5.0, 6.0, 7.0, 8.0), true, ObjectFit.Cover));
	assert first.payload == slot;
	first.dispose();
	assert first.payload == NO_IMAGE_STYLE;

	const second = sprite(tile(0, 16.0, 16.0));
	second.setImageStyle(imageStyle(cornerRadii(0.0, 0.0, 0.0, 0.0), false, ObjectFit.Contain));
	assert second.payload == slot;
	second.dispose();

	const notImage = graphics();
	assert notImage.payload == NO_IMAGE_STYLE;
}
