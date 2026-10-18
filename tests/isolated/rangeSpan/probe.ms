import { env } from "std/process";
import {
	DrawContext2D, PaintIndex, NO_PAINT, currentContext, useContext, retireContext, saveRange,
	noteRange,
} from "../../../src/void2d/displayList";
import { REC_UI_FLOATS } from "../../../src/void2d/instanceLayout";

test "noteRange refuses truncated current and saved UI records" {
	const stream: string = env.get("VOID_NOTE_RANGE_SPAN");
	if (!stream.equals("ui") && !stream.equals("saved")) {
		console.log("Unknown VOID_NOTE_RANGE_SPAN: " + stream);
		unreachable;
	}
	const previous: DrawContext2D = currentContext();
	const c: DrawContext2D = DrawContext2D.create();
	defer useContext(previous);
	defer retireContext(c.id);
	useContext(c);
	while (c.uiInstances.length < 3 * REC_UI_FLOATS) { c.uiInstances.push(1.0); }
	c.uiInstanceTotal = 3;
	const start: PaintIndex = { ...NO_PAINT, uiInstances: 1 };
	const end: PaintIndex = { ...NO_PAINT, uiInstances: 2 };
	saveRange(start, end);
	if (stream.equals("ui")) {
		c.uiInstances = [];
		for (let i: int32 = 0; i < REC_UI_FLOATS + 1; i++) { c.uiInstances.push(1.0); }
	} else {
		c.saved = [1.0];
	}
	c.uiInstances[REC_UI_FLOATS] = 2.0;
	console.log("NOTE_RANGE_BEFORE " + stream);
	noteRange(start, end);
	console.log("NOTE_RANGE_RETURNED " + stream);
	assert c.dirtyUiTotal == 1;
}
