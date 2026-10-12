import { Scene2D, NodeRef } from "../void2d/node";
import { add, paint, isDirty, close } from "../void2d/scene";
import { frameEnd } from "../void2d/draw";
import { labelTexts, glyphAtlas } from "../void2d/labelText";
import { xForIndex } from "../void2d/render";
import { dispose, pageCount } from "../void2d/glyphAtlas";
import { rgba } from "../void2d/types";

function frame(s: Scene2D): void {
	s.paint(8000.0, 4000.0, 1.0);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
}

function payload(n: NodeRef): int32 { return n.scene.payloads[n.id.index]; }

function restoreAtlas(pageSize: int32, maxPages: int32): void {
	glyphAtlas.dispose();
	glyphAtlas.pageSize = pageSize;
	glyphAtlas.maxPages = maxPages;
}

test "permanent TooLarge refuses rendering without a self-scheduled dirty loop" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("H", 1024.0, rgba(1.0, 1.0, 1.0, 1.0));
	s.add(label);
	let dirtyFrames: int32 = 0;
	for (let i: int32 = 0; i < 4; i++) {
		frame(s);
		const entry = labelTexts[payload(label)];
		assert !entry.placedValid && entry.refused == 1;
		assert entry.placed.length == 0 && entry.layout.glyphs.length == 1;
		if (s.isDirty()) { dirtyFrames++; }
		console.log(`retry permanent frame ${i}: dirty=${s.isDirty()} refused=${entry.refused}`);
	}
	assert dirtyFrames == 0;
}

test "a refused middle glyph preserves partial placements and exact caret layout" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label(" H ", 1024.0, rgba(1.0, 1.0, 1.0, 1.0));
	label.setCursorIndex(2, rgba(1.0, 0.0, 0.0, 1.0));
	s.add(label);
	frame(s);
	const entry = labelTexts[payload(label)];
	console.log(
		`retry partial: layout=${entry.layout.glyphs.length} placed=${entry.placed.length} ` +
		`refused=${entry.refused} cursor=${entry.cursorX}`,
	);
	assert !entry.placedValid && entry.refused == 1;
	assert entry.layout.glyphs.length == 3 && entry.placed.length == 2;
	assert entry.placed[1].x == entry.layout.glyphs[2].x;
	assert entry.cursorX == label.xForIndex(2);
	const caret: float32 = entry.cursorX;
	const tail: float32 = entry.placed[1].x;
	label.setColor(rgba(0.0, 1.0, 0.0, 1.0));
	frame(s);
	const repainted = labelTexts[payload(label)];
	assert !repainted.placedValid && repainted.refused == 1;
	assert repainted.placed.length == 2;
	assert repainted.cursorX == caret && repainted.placed[1].x == tail;
	assert !s.isDirty();
}

test "real Full remains dirty until the held page is freed, then the same label recovers" {
	glyphAtlas.dispose();
	const pageSize: int32 = glyphAtlas.pageSize;
	const maxPages: int32 = glyphAtlas.maxPages;
	glyphAtlas.pageSize = 32;
	glyphAtlas.maxPages = 1;
	defer restoreAtlas(pageSize, maxPages);
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const holder = s.label("M", 38.0, rgba(1.0, 1.0, 1.0, 1.0));
	const blocked = s.label("H", 38.0, rgba(1.0, 1.0, 1.0, 1.0)).at(100.0, 0.0);
	s.add(holder);
	s.add(blocked);
	frame(s);
	const held = labelTexts[payload(holder)];
	const refused = labelTexts[payload(blocked)];
	console.log(`retry capacity: held=${held.placed.length} refused=${refused.refused} ` +
		`pages=${glyphAtlas.pageCount()} dirty=${s.isDirty()}`);
	assert held.placedValid && held.placed.length == 1;
	assert glyphAtlas.pageCount() == 1;
	assert !refused.placedValid && refused.refused == 1;
	assert s.isDirty();
	frame(s);
	assert s.isDirty() && !labelTexts[payload(blocked)].placedValid;
	holder.dispose();
	frame(s);
	const recovered = labelTexts[payload(blocked)];
	assert recovered.placedValid && recovered.refused == 0 && recovered.placed.length == 1;
	assert !s.isDirty();
	assert glyphAtlas.pageCount() == 1;
}

test "a permanent refusal is re-evaluated after a real text style change" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("H", 1024.0, rgba(1.0, 1.0, 1.0, 1.0));
	s.add(label);
	frame(s);
	assert !labelTexts[payload(label)].placedValid && !s.isDirty();
	label.setTextStyle({ ...labelTexts[payload(label)].style, size: 38.0 });
	assert s.isDirty();
	frame(s);
	const recovered = labelTexts[payload(label)];
	assert recovered.placedValid && recovered.refused == 0;
	assert recovered.placed.length == 1 && recovered.placed[0].w > 0.0;
	assert !s.isDirty();
}

test "a visible partial Full placement and caret survive a colour repaint" {
	glyphAtlas.dispose();
	const pageSize: int32 = glyphAtlas.pageSize;
	const maxPages: int32 = glyphAtlas.maxPages;
	glyphAtlas.pageSize = 32;
	glyphAtlas.maxPages = 1;
	defer restoreAtlas(pageSize, maxPages);
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("M H", 38.0, rgba(1.0, 1.0, 1.0, 1.0));
	label.setCursorIndex(3, rgba(1.0, 0.0, 0.0, 1.0));
	s.add(label);
	frame(s);
	const entry = labelTexts[payload(label)];
	assert !entry.placedValid && entry.refused == 1 && s.isDirty();
	assert entry.layout.glyphs.length == 3 && entry.placed.length == 2;
	assert entry.placed[0].w > 0.0 && entry.placed[0].h > 0.0;
	assert entry.placed[1].w == 0.0 && entry.placed[1].h == 0.0;
	assert entry.cursorX == label.xForIndex(3);
	const caret: float32 = entry.cursorX;
	const visibleX: float32 = entry.placed[0].x;
	const visibleWidth: float32 = entry.placed[0].w;
	label.setColor(rgba(0.0, 1.0, 0.0, 1.0));
	frame(s);
	const repainted = labelTexts[payload(label)];
	assert !repainted.placedValid && repainted.refused == 1 && s.isDirty();
	assert repainted.placed.length == 2;
	assert repainted.cursorX == caret && repainted.placed[0].x == visibleX;
	assert repainted.placed[0].w == visibleWidth;
	label.setText("M");
	frame(s);
	assert labelTexts[payload(label)].placedValid && !s.isDirty();
}

when (voidTextOutline) {
	test "a permanent outline refusal preserves visible fill without an idle retry loop" {
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		defer s.close();
		const label = s.label("H", 38.0, rgba(1.0, 1.0, 1.0, 1.0));
		label.setOutline(1024.0, rgba(1.0, 0.0, 0.0, 1.0));
		s.add(label);
		frame(s);
		const entry = labelTexts[payload(label)];
		assert !entry.placedValid && entry.refused == 1;
		assert entry.placed.length == 1 && entry.placed[0].w > 0.0;
		assert entry.placedOutline.length == 0 && !s.isDirty();
		label.setOutline(0.0, rgba(1.0, 0.0, 0.0, 1.0));
		frame(s);
		assert labelTexts[payload(label)].placedValid && !s.isDirty();
	}

	test "a later permanent outline refusal cannot erase an earlier Full retry" {
		glyphAtlas.dispose();
		const pageSize: int32 = glyphAtlas.pageSize;
		const maxPages: int32 = glyphAtlas.maxPages;
		glyphAtlas.pageSize = 32;
		glyphAtlas.maxPages = 1;
		defer restoreAtlas(pageSize, maxPages);
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		defer s.close();
		const holder = s.label("M", 38.0, rgba(1.0, 1.0, 1.0, 1.0));
		const label = s.label("H M", 38.0, rgba(1.0, 1.0, 1.0, 1.0));
		label.setOutline(1024.0, rgba(1.0, 0.0, 0.0, 1.0));
		s.add(holder);
		s.add(label);
		frame(s);
		const entry = labelTexts[payload(label)];
		assert !entry.placedValid && entry.refused == 2 && s.isDirty();
		assert entry.placed.length == 2 && entry.placed[1].w > 0.0;
		assert entry.placedOutline.length == 0;
		frame(s);
		assert !labelTexts[payload(label)].placedValid && s.isDirty();
		holder.dispose();
		label.setText("H");
		frame(s);
		const recovered = labelTexts[payload(label)];
		assert !recovered.placedValid && recovered.refused == 1 && !s.isDirty();
		assert recovered.placed.length == 1 && recovered.placed[0].w > 0.0;
	}
}
