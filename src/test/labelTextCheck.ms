import {
	allocateLabelText,
	releaseLabelText,
	shapeLabel,
	placeLabel,
	glyphAtlas,
	glyphRasterizations,
	isPixelExact,
} from "../void2d/labelText";
import { quantizeX, snapBaseline } from "../void2d/glyphAtlas";
import { Transform2D, trs2d, rgba, identity2d } from "../void2d/types";
import { begin2d, frameEnd } from "../void2d/draw";
import { label } from "../void2d/node";
import { renderTargetsAlive } from "../void2d/render";

function shaped(text: string): int32 {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: 0,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: 0.0,
	});
	return index;
}

function isWhole(v: float32): boolean {
	return v == (Math.floor(v) as float32);
}

test "pixel-exact placement puts every glyph sprite on whole device pixels" {
	const index = shaped("void2d, 13 px");
	const world: Transform2D = trs2d(10.3, 7.7, 0.0, 1.0, 1.0);
	const text = placeLabel(index, world, 1.25);
	assert text.pixelExact;
	assert (text.placed.length as int32) > 0;
	for (const p of text.placed) {
		assert isWhole(p.x);
		assert isWhole(p.y);
		assert isWhole(p.w);
		assert isWhole(p.h);
	}
	releaseLabelText(index);
}

test "the placement uses the same quarter-pixel variant and snapped baseline the atlas keys on" {
	const index = shaped("iiii");
	const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const text = placeLabel(index, world, 1.5);
	const g = text.layout.glyphs[1];
	const q = quantizeX(g.x * 1.5);
	const baseline = snapBaseline(text.layout.lines[0].baseline * 1.5);
	const tile = glyphAtlas.tile(text.placed[1].tile);
	assert text.placed[1].x == ((q.whole + tile.left) as float32);
	assert text.placed[1].y == ((baseline + tile.top) as float32);
	releaseLabelText(index);
}

test "a whole-pixel move reuses the placement and rasterizes nothing" {
	const index = shaped("steady state");
	placeLabel(index, trs2d(4.25, 3.0, 0.0, 1.0, 1.0), 1.0);
	const before = glyphRasterizations();
	const moved = placeLabel(index, trs2d(9.25, 12.0, 0.0, 1.0, 1.0), 1.0);
	assert glyphRasterizations() == before;
	assert moved.keyFracX == 0.25;
	releaseLabelText(index);
}

test "a rotated label is the transformed regime, sized by the affine's area scale" {
	const index = shaped("A");
	const world: Transform2D = trs2d(0.0, 0.0, 0.5, 2.0, 2.0);
	assert !isPixelExact(world);
	const text = placeLabel(index, world, 1.0);
	assert !text.pixelExact;
	const tile = glyphAtlas.tile(text.placed[0].tile);
	assert Math.abs(text.placed[0].w * 2.0 - (tile.width as float32)) < 0.001;
	releaseLabelText(index);
}

test "releasing a label drops its tile references" {
	const index = shaped("Qz");
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	const tileIndex = text.placed[0].tile;
	const held = glyphAtlas.tile(tileIndex).refs;
	releaseLabelText(index);
	assert glyphAtlas.tile(tileIndex).refs == held - 1;
}

test "drawing a label fences its glyph page for the frame the bracket belongs to" {
	begin2d(200.0, 100.0, 1.0);
	const frame = glyphAtlas.frame;
	const n = label("fence", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.sync(identity2d(), false);
	n.draw(1.0, 200.0, 100.0);
	const page = glyphAtlas.tile(placeLabel(n.payload, n.cachedWorld, 1.0).placed[0].tile).page;
	assert glyphAtlas.pages[page as int32].drawnFrame == frame;
	frameEnd();
	begin2d(200.0, 100.0, 1.0);
	assert glyphAtlas.frame == frame + 1;
	n.dispose();
}
