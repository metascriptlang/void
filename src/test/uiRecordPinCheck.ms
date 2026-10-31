import { Color, Transform2D, rgba, identity2d } from "../void2d/types";
import { InstanceMode, uiInstance } from "../void2d/instance";
import { UI_WORDS, REC_UI_FLOATS } from "../void2d/instanceLayout";
import {
	resetContext, currentContext, pushUiInstance, pushGlyphInstance, uiInstanceCount,
} from "../void2d/displayList";
import { packUiInstance } from "../void2d/batcher";
import { Scene2D } from "../void2d/node";
import { paint } from "../void2d/scene";
import { frameEnd } from "../void2d/draw";

function recordedWords(): uint32[] {
	const count: int32 = uiInstanceCount();
	const out: uint32[] = [];
	for (let w: int32 = 0; w < count * UI_WORDS; w++) { out.push(0); }
	const records: Readonly<Span<float32>> = currentContext().uiInstances;
	for (let i: int32 = 0; i < count; i++) {
		packUiInstance(out, i, records[0..count * REC_UI_FLOATS]);
	}
	return out;
}

function digest(words: Readonly<Span<uint32>>): uint32 {
	let hash: uint32 = 2166136261;
	for (const word of words) {
		hash = (((hash ^ word) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
	}
	return hash;
}

const CHANNELS: float32[] = [
	0.0, 1.0, 0.5, 0.25, 0.75, 0.999, 0.001, 0.0019, 0.002, -1.0, 2.0, 0.502, 0.498, 0.1, 0.3,
	-0.0,
];

function channel(k: int32): float32 { return CHANNELS[k % (CHANNELS.length as int32)]; }

function colorAt(k: int32): Color {
	return rgba(channel(k), channel(k + 3), channel(k + 7), channel(k + 11));
}

function pushEdgeRecords(): void {
	const turned: Transform2D = { a: 0.7071, b: 0.7071, c: -0.7071, d: 0.7071, tx: 3.0, ty: -4.0 };
	const modes: InstanceMode[] = [
		InstanceMode.Box, InstanceMode.Shadow, InstanceMode.Glyph, InstanceMode.Image,
		InstanceMode.Underline, InstanceMode.Selection,
	];
	for (let k: int32 = 0; k < 24; k++) {
		const f: float32 = k as float32;
		pushUiInstance({
			...uiInstance(
				modes[k % 6], k % 2 == 0 ? identity2d() : turned, 10.5 * f - 0.0, -3.25 * f,
				1.0e6 * f, 0.125 + f, colorAt(k),
			),
			uvRadii: [0.1 * f, -0.0, 3.4e38, 1.0e-45],
			borders: [f, 0.5, -f, 1.0 / 3.0],
			params: [f * 0.01, -2.5, 7.0],
			params1: [0.0, 1.0, -10.0, 90.0],
			border: colorAt(k + 1),
			extra: colorAt(k + 5),
		}, 2.5, -7.75);
	}
	for (let k: int32 = 0; k < 8; k++) {
		const f: float32 = k as float32;
		pushGlyphInstance(
			k % 2 == 0 ? InstanceMode.Glyph : InstanceMode.Image, k % 3 == 0 ? 1.0 : 0.0,
			k % 2 == 0 ? 0.0 : 1.0, k % 2 == 0 ? turned : identity2d(), 9.0 + f, 11.0 - f, 3.0,
			4.0, 0.125 * f, 0.25, 0.375, 0.5 * f, colorAt(k + 2), 5.0, 7.0,
		);
	}
}

test "UI records of every mode and edge value keep their uploaded words" {
	resetContext();
	pushEdgeRecords();
	assert uiInstanceCount() == 32;
	const words: uint32[] = recordedWords();
	assert words[24] == 0x80004000;
	assert words[UI_WORDS + 24] == 0x7F01BFFF;
	assert digest(words) == 1537905605;
}

test "a scene's UI records keep their uploaded words" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	for (let k: int32 = 0; k < 12; k++) {
		const f: float32 = k as float32;
		const r = s.rect(10.0 + f, 6.0 + 2.0 * f, colorAt(k)).at(4.0 + 13.0 * f, 3.0 + f);
		r.setRotation(0.1 * f).setAlpha(channel(k + 4));
		s.add(r);
	}
	s.paint(200.0, 120.0, 1.25);
	const words: uint32[] = recordedWords();
	frameEnd();
	assert words.length as int32 == 10 * UI_WORDS;
	assert digest(words) == 1289668759;
}
