// Void — the iOS app driver demo: a full-screen scene that logs every window event.

import { gfxSetup, dpiScale } from "../sokol/gpu";
import { onAppEvent, AppEvent, AppEventType, setTextInput, setImeRect, safeArea, keyboardHeight } from "../sokol/window";
import { Scene2D, NodeRef } from "../void2d/node";
import { create, presentAt } from "../void2d/scene";
import { setup2d } from "../void2d/draw";
import { rgba } from "../void2d/types";

when (ios) {
	@compile("./iosAppEntry.m");
}

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const scene: Scene2D = Scene2D.create(rgba(0.08, 0.09, 0.12, 1.0));
const dot: NodeRef = scene.rect(80.0, 80.0, rgba(0.2, 0.7, 1.0, 1.0));
let typing: boolean = false;

function log(e: AppEvent): void {
	const name: string = `${e.type as int32}`;
	if (e.type == AppEventType.KeyDown || e.type == AppEventType.KeyUp) {
		console.log(`event ${name} key ${e.keyCode} modifiers ${e.modifiers} repeat ${e.keyRepeat}`);
	} else if (e.type == AppEventType.Char) {
		console.log(`event ${name} char U+${e.charCode.toString(16)}`);
	} else if (e.type == AppEventType.TextInput || e.type == AppEventType.Preedit) {
		console.log(`event ${name} text '${e.text}' cursor ${e.cursor}`);
	} else if (e.type == AppEventType.Resized) {
		const area = safeArea();
		console.log(`event ${name} ${e.framebufferWidth}x${e.framebufferHeight} safe ` +
			`${area.top} ${area.left} ${area.bottom} ${area.right} keyboard ${keyboardHeight()}`);
	} else {
		let points: string = "";
		for (const t of e.touches) {
			points = `${points} [${t.id} ${t.x} ${t.y}${t.changed ? " changed" : ""}]`;
		}
		console.log(`event ${name}${points}`);
	}
}

function handle(e: AppEvent): void {
	log(e);
	if (e.type == AppEventType.TouchesBegan || e.type == AppEventType.TouchesMoved) {
		for (const t of e.touches) {
			if (!t.changed) { continue; }
			const dpi: float32 = dpiScale();
			dot.at(t.x / dpi - 40.0, t.y / dpi - 40.0);
			setImeRect(t.x as int32, t.y as int32, 2, 40);
		}
	}
	if (e.type == AppEventType.TouchesEnded && e.touches.length == 1) {
		typing = !typing;
		setTextInput(typing);
	}
}

function init(): void {
	gfxSetup();
	setup2d();
	scene.add(dot);
	onAppEvent(handle);
}

function frame(): void {
	presentAt(scene, dpiScale());
}

voidRun(1024, 768, init, frame);
