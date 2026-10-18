import {
	DrawContext2D,
	PaintIndex,
	NO_PAINT,
	currentContext,
	useContext,
	retireContext,
	saveRange,
	noteRange,
	uploaded,
} from "../../src/void2d/displayList";
import { REC_UI_FLOATS, REC_SPRITE_FLOATS } from "../../src/void2d/instanceLayout";

function rangeContext(ui: int32, sprites: int32, vertices: int32): DrawContext2D {
	const c: DrawContext2D = DrawContext2D.create();
	for (let i: int32 = c.uiInstances.length as int32; i < ui * REC_UI_FLOATS; i++) {
		c.uiInstances.push(0.0);
	}
	for (let i: int32 = c.spriteInstances.length as int32; i < sprites * REC_SPRITE_FLOATS; i++) {
		c.spriteInstances.push(0.0);
	}
	for (let i: int32 = c.vertices.length as int32; i < vertices * 8; i++) {
		c.vertices.push(0.0);
	}
	for (let i: int32 = 0; i < ui * REC_UI_FLOATS; i++) {
		c.uiInstances[i] = (10 + i) as float32;
	}
	for (let i: int32 = 0; i < sprites * REC_SPRITE_FLOATS; i++) {
		c.spriteInstances[i] = (100 + i) as float32;
	}
	for (let i: int32 = 0; i < vertices * 8; i++) {
		c.vertices[i] = (200 + i) as float32;
	}
	c.uiInstanceTotal = ui;
	c.spriteInstanceTotal = sprites;
	c.vertexTotal = vertices;
	return c;
}

test "every changed UI lane preserves saved sprite and vertex cursors" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(1, 1, 1);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 1, spriteInstances: 1, vertices: 1 };
	for (let lane: int32 = 0; lane < REC_UI_FLOATS; lane++) {
		uploaded();
		saveRange(NO_PAINT, end);
		c.uiInstances[lane] = c.uiInstances[lane] + 1.0;
		noteRange(NO_PAINT, end);
		assert c.dirtyUiTotal == 1 && c.dirtyUi[0] == 0 && c.dirtyUi[1] == 1;
		assert !c.dirtySprites && !c.dirtyVertices;
		c.uiInstances[lane] = c.uiInstances[lane] - 1.0;
	}
}

test "early UI change leaves independent sprite and vertex differences visible" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(1, 1, 1);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 1, spriteInstances: 1, vertices: 1 };
	for (let changes: int32 = 0; changes < 4; changes++) {
		uploaded();
		saveRange(NO_PAINT, end);
		c.uiInstances[0] = c.uiInstances[0] + 1.0;
		if ((changes & 1) != 0) { c.spriteInstances[15] = c.spriteInstances[15] + 1.0; }
		if ((changes & 2) != 0) { c.vertices[7] = c.vertices[7] + 1.0; }
		noteRange(NO_PAINT, end);
		assert c.dirtyUiTotal == 1;
		assert c.dirtySprites == ((changes & 1) != 0);
		assert c.dirtyVertices == ((changes & 2) != 0);
	}
}

test "UI comparison scans later records and coalesces adjacent envelopes" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(4, 0, 0);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 3 };
	saveRange(NO_PAINT, end);
	c.uiInstances[0] = -1.0;
	c.uiInstances[2 * REC_UI_FLOATS + 35] = -1.0;
	noteRange(NO_PAINT, end);
	assert c.dirtyUiTotal == 1 && c.dirtyUi[0] == 0 && c.dirtyUi[1] == 3;
	const tail: PaintIndex = { ...NO_PAINT, uiInstances: 4 };
	saveRange(end, tail);
	c.uiInstances[3 * REC_UI_FLOATS + 24] = -1.0;
	noteRange(end, tail);
	assert c.dirtyUiTotal == 1 && c.dirtyUi[0] == 0 && c.dirtyUi[1] == 4;
}

test "nonzero stream starts still save mixed ranges from cursor zero" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(2, 2, 2);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const start: PaintIndex = { ...NO_PAINT, uiInstances: 1, spriteInstances: 1, vertices: 1 };
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 2, spriteInstances: 2, vertices: 2 };
	saveRange(start, end);
	c.uiInstances[REC_UI_FLOATS] = -1.0;
	noteRange(start, end);
	assert c.dirtyUiTotal == 1 && c.dirtyUi[0] == 1 && c.dirtyUi[1] == 2;
	assert !c.dirtySprites && !c.dirtyVertices;
}

test "narrowed saves ignore high-water tails and preserve sticky suffix flags" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(2, 2, 2);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const large: PaintIndex = { ...NO_PAINT, uiInstances: 2, spriteInstances: 2, vertices: 2 };
	const small: PaintIndex = { ...NO_PAINT, spriteInstances: 1, vertices: 1 };
	saveRange(NO_PAINT, large);
	saveRange(NO_PAINT, small);
	noteRange(NO_PAINT, small);
	assert c.dirtyUiTotal == 0 && !c.dirtySprites && !c.dirtyVertices;
	c.spriteInstances[0] = -1.0;
	noteRange(NO_PAINT, small);
	assert c.dirtySprites && !c.dirtyVertices;
	saveRange(NO_PAINT, small);
	c.vertices[7] = -1.0;
	noteRange(NO_PAINT, small);
	assert c.dirtySprites && c.dirtyVertices;
	noteRange(NO_PAINT, NO_PAINT);
	assert c.dirtyUiTotal == 0 && c.dirtySprites && c.dirtyVertices;
}

test "scalar equality keeps signed zeros equal and unchanged NaNs dirty" {
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = rangeContext(1, 0, 0);
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 1 };
	c.uiInstances[0] = 0.0;
	saveRange(NO_PAINT, end);
	c.uiInstances[0] = -0.0;
	noteRange(NO_PAINT, end);
	assert c.dirtyUiTotal == 0;
	c.uiInstances[35] = NaN as float32;
	saveRange(NO_PAINT, end);
	noteRange(NO_PAINT, end);
	assert c.dirtyUiTotal == 1 && c.dirtyUi[0] == 0 && c.dirtyUi[1] == 1;
	uploaded();
	c.uiInstances[0] = NaN as float32;
	saveRange(NO_PAINT, end);
	noteRange(NO_PAINT, end);
	assert c.dirtyUiTotal == 1;
}
