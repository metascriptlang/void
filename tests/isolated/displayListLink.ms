import { DrawContext2D, retireContext } from "../../src/void2d/displayList";

test "display list links without Scene or glyphAtlas consumer imports" {
	const c: DrawContext2D = DrawContext2D.create();
	defer retireContext(c.id);
	assert c.id >= 0;
}
