import { Scene2D } from "../../../src/void2d/node";
import { add, paint, isDirty, close } from "../../../src/void2d/scene";
import { frameEnd } from "../../../src/void2d/draw";
import { glyphAtlas, labelTexts } from "../../../src/void2d/labelText";
import { dispose } from "../../../src/void2d/glyphAtlas";
import { addFontBytes } from "../../../src/void2d/font";
import { sfntSourceRead, sfntSourceSize } from "../../../src/void2d/sfntSource";
import { rgba } from "../../../src/void2d/types";

const SOURCE: string = "tests/fonts/sbixSynthetic.ttf";

function frame(s: Scene2D): void {
	s.paint(200.0, 120.0, 1.0);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
}

function uint32At(bytes: uint8[], at: int32): int32 {
	return ((bytes[at] as int32) << 24) | ((bytes[at + 1] as int32) << 16) |
		((bytes[at + 2] as int32) << 8) | (bytes[at + 3] as int32);
}

function isPngSignature(bytes: uint8[], at: int32): boolean {
	const sig: int32[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
	for (let i: int32 = 0; i < 8; i++) {
		if ((bytes[at + i] as int32) != sig[i]) { return false; }
	}
	return true;
}

function withBadPngs(): uint8[] {
	const size = sfntSourceSize(SOURCE);
	const bytes: uint8[] = new Array<uint8>(size > 0 ? size as int32 : 0);
	if (size <= 0 || !sfntSourceRead(SOURCE, 0, bytes)) { return []; }
	let patches: int32 = 0;
	for (let start: int32 = 0; start + 8 <= bytes.length; start++) {
		if (!isPngSignature(bytes, start)) { continue; }
		let cursor: int32 = start + 8;
		while (cursor + 12 <= bytes.length) {
			const length: int32 = uint32At(bytes, cursor);
			const tag: int32 = uint32At(bytes, cursor + 4);
			if (tag == 0x49444154 && length >= 2) {
				bytes[cursor + 8] = 0;
				bytes[cursor + 9] = 0;
				patches++;
				break;
			}
			if (tag == 0x49454E44) { break; }
			cursor += length + 12;
		}
	}
	return patches > 0 ? bytes : [];
}

test "a malformed colour PNG stays incomplete and refused, and no frame retries it" {
	glyphAtlas.dispose();
	defer glyphAtlas.dispose();
	const bad = withBadPngs();
	assert bad.length > 0;
	const loaded = addFontBytes("badPng", bad);
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	defer s.close();
	const label = s.label("\u{1F600}", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(loaded.value);
	const payload: int32 = s.payloads[label.id.index];
	s.add(label);
	for (let i: int32 = 0; i < 4; i++) {
		frame(s);
		assert !labelTexts[payload].placedValid && labelTexts[payload].refused == 1;
		assert labelTexts[payload].placed.length == 0 && !s.isDirty();
	}
}
