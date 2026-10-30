import { env } from "std/process";
import { gfxSetup } from "../../src/host/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba, blurFilter } from "../../src/void2d/types";
import { voidCaptureExit } from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const card: NodeRef = s.rect(40.0, 40.0, rgba(1.0, 0.0, 0.0, 1.0)).at(10.0, 10.0);
const group: NodeRef = s.group().setLayerSlot(true);
const label: NodeRef = s.label("", 12.0, rgba(1.0, 1.0, 1.0, 1.0)).setLayerSlot(true);
const last: NodeRef = s.group().setLayerSlot(true);
const hidden: NodeRef = s.group().setLayerSlot(true).setVisible(false);
const blurred: NodeRef = s.group().setFilter(blurFilter(1.0));
const filtered: NodeRef = s.group().setLayerSlot(true);
let stage: int32 = 0;
let patches: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL painted slots: ${message}`);
	voidCaptureExit(1);
}

function names(slots: NodeRef[]): string {
	let out: string = "";
	for (const n of slots) {
		const i: int32 = n.id.index;
		const name: string = i == group.id.index ? "group" : i == label.id.index ? "label" :
			i == last.id.index ? "last" : `node ${i}`;
		out = out.length == 0 ? name : `${out} ${name}`;
	}
	return out;
}

function init(): void {
	gfxSetup();
	setup2d();
	s.add(card);
	s.add(group);
	s.add(label);
	s.add(last);
	s.add(hidden);
	blurred.addChild(s.rect(10.0, 10.0, rgba(0.0, 1.0, 0.0, 1.0)));
	blurred.addChild(filtered);
	s.add(blurred);
}

function frame(): void {
	if (stage == 1) { last.setZIndex(-1); }
	if (stage == 2) {
		patches = s.patches;
		card.setColor(rgba(0.0, 0.0, 1.0, 1.0));
	}
	if (env.get("VOID_PAINTED_SLOTS_MISUSE").equals("unprepared")) { s.paintedSlots(); }
	s.prepare(120.0, 100.0, 1.0);
	const slots: NodeRef[] = s.paintedSlots();
	const want: string = stage == 0 ? "group label last" : "last group label";
	if (!names(slots).equals(want)) { fail(`stage ${stage}: '${names(slots)}', want '${want}'`); }
	if (stage == 2 && s.patches != patches + 1) { fail("the colour write did not patch"); }
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	for (const n of slots) { s.drawScreenUntil(n); }
	s.drawScreen();
	endPass();
	commit();
	stage = stage + 1;
	if (stage < 3) { return; }
	console.log("PASS painted slots: paint order, zIndex, hidden and filtered left out, patched frame");
	voidCaptureExit(0);
}

voidRunConfigured(120, 100, 1, 0, init, frame);
