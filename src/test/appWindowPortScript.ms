// A scripted run of the window's app-facing half over a recording platform: the same op stream
// the C appWindow.c ran in the differential, so its transcript digest can be pinned against what
// that C printed. A mobile run is the iOS and Android shells' (stand-in clipboard, cursor and
// mouse state, the voidMobile* events); a desktop run is a window driver's.

import { AppEventType, KeyCode, NativeAppEvent, blankAppEvent } from "../platform/appEvent";
import { AppWindow, AppWindowPlatform } from "../host/appWindow";

const KIND_PLATFORM: int32 = 0;
const KIND_HANDLER: int32 = 1;
const KIND_DELIVER: int32 = 2;
const KIND_TEXT: int32 = 3;
const KIND_OUTSIDE: int32 = 4;
const KIND_SAFE: int32 = 5;
const KIND_TITLE: int32 = 6;
const KIND_REQUEST: int32 = 7;
const KIND_WINDOW_EVENT: int32 = 8;
const KIND_MOBILE_SEND: int32 = 9;
const KIND_MOBILE_KEY: int32 = 10;
const KIND_RELEASE: int32 = 11;
const KIND_COMMIT: int32 = 12;
const KIND_KEY_DOWN: int32 = 13;
const KIND_FRAMEBUFFER: int32 = 14;
const KIND_MOBILE_EVENT: int32 = 15;
const MOBILE_KINDS: int32[] = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];
const DESKTOP_KINDS: int32[] = [0, 1, 2, 3, 4, 5, 6, 7, 8];
const OP_WORDS: int32 = 5;
const FLOATS: float32[] = [0.0, 1.0, -1.5, 0.25, 640.0, 2.0, -0.5, 1234.5, 3.0, 100.0];
const SCALES: float32[] = [1.0, 2.0, 0.5, 3.0];
const DURATIONS: float64[] = [0.0, 0.0166, 0.5];
const SIZES: int32[] = [-1, 0, 1, 64, 640, 1920];
const KEYS: int32[] = [0, 65, 256, 257, 511, 512, -1, 32, 340, 87];
const TEXTS: string[] = ["", "a", "héllo", "日本語", "line\nbreak", "😀"];
const DROPPED: string[] = ["a", "b/c", "日"];
const TITLE_COUNT: int32 = 8;
const FNV_OFFSET: uint64 = 2166136261;
const FNV_PRIME: uint64 = 16777619;

function titleOf(pick: int32): string {
	if (pick == 0) { return ""; }
	if (pick == 1) { return "Void"; }
	if (pick == 2) { return "Void — sokol"; }
	if (pick == 3) { return "a".repeat(254); }
	if (pick == 4) { return "a".repeat(255); }
	if (pick == 5) { return "a".repeat(256); }
	if (pick == 6) { return "日".repeat(85); }
	return "日".repeat(86);
}

function codepointsOf(pick: int32): uint32[] {
	if (pick == 0) { return []; }
	if (pick == 1) { return [10]; }
	if (pick == 2) { return [13]; }
	if (pick == 3) { return [9]; }
	if (pick == 4) { return [65]; }
	if (pick == 5) { return [65, 127, 66]; }
	if (pick == 6) { return [0x1F600]; }
	if (pick == 7) { return [32, 31, 10, 65]; }
	return [10, 10];
}

class Script {
	log: string[] = [];
	mobile: boolean;
	valid: boolean = false;
	frame: uint64 = 0;
	width: int32 = 0;
	height: int32 = 0;
	scale: float32 = 1.0;
	modifiers: uint32 = 0;
	viewsCurrent: int32 = 0;
	viewsWidth: int32 = 0;
	viewsHeight: int32 = 0;
	viewsScale: float32 = 1.0;
	duration: float64 = 0.0;
	clipboard: string = "";
	cursor: int32 = 0;
	shown: boolean = true;
	locked: boolean = false;
	fullscreen: boolean = false;
	quit: boolean = false;
	mask: int32 = 0;
	depth: int32 = 0;

	constructor(mobile: boolean) { this.mobile = mobile; }

	note(line: string): void { if (!this.mobile) { this.log.push(line); } }
}

function thousandths(value: float32): string { return `${Math.round((value as float64) * 1000) as int64}`; }

class ScriptPlatform extends AppWindowPlatform {
	script: Script;

	constructor(script: Script) {
		super();
		this.script = script;
	}

	fail(message: string): never { throw new Error(message); }
	valid(): boolean { return this.script.valid; }
	frameCount(): uint64 { return this.script.frame; }
	framebufferWidth(): int32 {
		return this.script.mobile || this.script.width > 0 ? this.script.width : 1;
	}
	framebufferHeight(): int32 {
		return this.script.mobile || this.script.height > 0 ? this.script.height : 1;
	}
	modifiers(): uint32 { return this.script.modifiers; }
	scale(): float32 { return this.script.scale; }
	viewsCurrent(): int32 { return this.script.viewsCurrent; }
	viewsFbWidth(): int32 { return this.script.viewsWidth; }
	viewsFbHeight(): int32 { return this.script.viewsHeight; }
	viewsDpiScale(): float32 { return this.script.viewsScale; }
	profileInput(): void { this.script.note("P profile"); }
	setTitle(title: string): void { this.script.note(`P setTitle ${title}`); }
	requestQuit(): void { this.script.quit = true; }
	cancelQuit(): void { if (!this.script.mobile) { this.script.quit = false; } }
	frameDuration(): float64 { return this.script.duration; }
	setClipboard(text: string): void {
		this.script.note(`P setClipboard ${text}`);
		this.script.clipboard = text;
	}
	clipboard(): string { return this.script.clipboard; }
	setCursor(cursor: int32): void {
		this.script.note(`P setCursor ${cursor}`);
		this.script.cursor = cursor;
	}
	cursor(): int32 { return this.script.cursor; }
	showMouse(shown: boolean): void {
		this.script.note(`P showMouse ${shown ? 1 : 0}`);
		this.script.shown = shown;
	}
	mouseShown(): boolean { return this.script.shown; }
	lockMouse(locked: boolean): void {
		this.script.note(`P lockMouse ${locked ? 1 : 0}`);
		this.script.locked = locked;
	}
	mouseLocked(): boolean { return this.script.locked; }
	toggleFullscreen(): void {
		if (this.script.mobile) { return; }
		this.script.note("P toggleFullscreen");
		this.script.fullscreen = !this.script.fullscreen;
	}
	isFullscreen(): boolean { return this.script.fullscreen; }
	droppedCount(): int32 { return this.script.mobile ? 0 : DROPPED.length as int32; }
	droppedPath(index: int32): string { return this.script.mobile ? "" : DROPPED[index]; }
}

// The op stream of one seed: OP_WORDS int32 per op, drawn from a Lehmer generator.
export function appWindowScriptOps(seed: int32, count: int32, mobile: boolean): int32[] {
	let state: int64 = seed as int64;
	const kinds = mobile ? MOBILE_KINDS : DESKTOP_KINDS;
	const ops: int32[] = [];
	for (let i: int32 = 0; i < count * OP_WORDS; i++) {
		state = (state * 16807) % 2147483647;
		ops.push((state % 1000003) as int32);
	}
	for (let at: int32 = 0; at < ops.length; at += OP_WORDS) {
		ops[at] = kinds[ops[at] % kinds.length];
	}
	return ops;
}

function attempt(script: Script, label: string, body: () => string): void {
	try {
		script.log.push(`${label} -> ${body()}`);
	} catch (error) {
		script.log.push(`${label} FAIL ${(error as Error).message}`);
	}
}

function eventOf(a: int32, b: int32, c: int32, d: int32, escape: boolean): NativeAppEvent {
	let e = blankAppEvent((a % 26) as AppEventType);
	if (escape) {
		e.type = AppEventType.KeyDown;
		e.keyCode = KeyCode.Escape as int32;
	} else {
		e.keyCode = KEYS[b % KEYS.length];
	}
	e.frameCount = (d * 3) as uint64;
	e.charCode = (c * 31) as uint32;
	e.keyRepeat = ((b >> 4) % 2) == 1;
	e.modifiers = (d % 2048) as uint32;
	e.mouseButton = [0, 1, 2, 256][(c >> 3) % 4];
	e.mouseX = FLOATS[a % 10];
	e.mouseY = FLOATS[b % 10];
	e.mouseDx = FLOATS[c % 10];
	e.mouseDy = FLOATS[d % 10];
	e.scrollX = FLOATS[(a >> 3) % 10];
	e.scrollY = FLOATS[(b >> 3) % 10];
	e.windowWidth = SIZES[(a >> 2) % 6];
	e.windowHeight = SIZES[(b >> 2) % 6];
	e.framebufferWidth = SIZES[(c >> 2) % 6];
	e.framebufferHeight = SIZES[(d >> 2) % 6];
	e.touchCount = (d >> 2) % 9;
	for (let i: int32 = 0; i < 8; i++) {
		e.touches[i].identifier = (a * 7 + i) as uint64;
		e.touches[i].x = FLOATS[(b + i) % 10];
		e.touches[i].y = FLOATS[(c + i) % 10];
		e.touches[i].changed = ((d + i) % 2) == 1;
	}
	return e;
}

function handlerBody(script: Script, window: AppWindow): void {
	const mask = script.mask;
	script.depth++;
	if ((mask & 1) != 0) {
		script.log.push(`H ${window.eventType()} ${window.eventKeyCode()} ${window.eventCharCode()} ${window.eventKeyRepeat()} ${window.eventModifiers()} ${window.eventMouseButton()}`);
	}
	if ((mask & 2) != 0) {
		script.log.push(`H ${thousandths(window.eventMouseX())} ${thousandths(window.eventMouseY())} ${thousandths(window.eventMouseDx())} ${thousandths(window.eventMouseDy())} ${thousandths(window.eventScrollX())} ${thousandths(window.eventScrollY())}`);
	}
	if ((mask & 4) != 0) {
		script.log.push(`H ${window.eventFramebufferWidth()} ${window.eventFramebufferHeight()}`);
	}
	if ((mask & 8) != 0) {
		const count = window.eventTouchCount();
		script.log.push(`H touches ${count}`);
		for (let i: int32 = 0; i < count; i++) {
			script.log.push(`H touch ${i} ${window.eventTouchId(i)} ${thousandths(window.eventTouchX(i))} ${thousandths(window.eventTouchY(i))} ${window.eventTouchChanged(i)}`);
		}
	}
	if ((mask & 16) != 0) {
		attempt(script, "H touch past the end", (): string => `${window.eventTouchX(window.eventTouchCount())}`);
		attempt(script, "H touch before the start", (): string => `${window.eventTouchId(-1)}`);
	}
	if ((mask & 32) != 0) {
		script.log.push(`H cursor ${window.eventCursor()} text ${window.eventText()}`);
	}
	if ((mask & 64) != 0 && script.depth == 1) {
		attempt(script, "H nested deliver", (): string => `${window.deliver(blankAppEvent(AppEventType.Focused)) ? 1 : 0}`);
	}
	if ((mask & 128) != 0) {
		attempt(script, "H request quit", (): string => { window.requestQuit(); return "ok"; });
	}
	script.depth--;
}

function request(script: Script, window: AppWindow, which: int32, arg: int32): void {
	if (which == 0) {
		attempt(script, "requestQuit", (): string => { window.requestQuit(); return "ok"; });
	} else if (which == 1) {
		attempt(script, "cancelQuit", (): string => { window.cancelQuit(); return "ok"; });
	} else if (which == 2) {
		attempt(script, "frameDuration", (): string => `${Math.round(window.frameDuration() * 100000) as int64}`);
	} else if (which == 3) {
		attempt(script, `setClipboard ${arg % 6}`, (): string => { window.setClipboard(TEXTS[arg % 6]); return "ok"; });
	} else if (which == 4) {
		attempt(script, "clipboard", (): string => window.clipboard());
	} else if (which == 5) {
		attempt(script, `setMouseCursor ${arg % 14 - 1}`, (): string => { window.setMouseCursor(arg % 14 - 1); return "ok"; });
	} else if (which == 6) {
		attempt(script, "mouseCursor", (): string => `${window.mouseCursor()}`);
	} else if (which == 7) {
		attempt(script, `showMouse ${arg % 3}`, (): string => { window.showMouse(arg % 3); return "ok"; });
	} else if (which == 8) {
		attempt(script, "mouseShown", (): string => `${window.mouseShown() ? 1 : 0}`);
	} else if (which == 9) {
		attempt(script, `lockMouse ${arg % 3}`, (): string => { window.lockMouse(arg % 3); return "ok"; });
	} else if (which == 10) {
		attempt(script, "mouseLocked", (): string => `${window.mouseLocked() ? 1 : 0}`);
	} else if (which == 11) {
		attempt(script, "toggleFullscreen", (): string => { window.toggleFullscreen(); return "ok"; });
	} else if (which == 12) {
		attempt(script, "isFullscreen", (): string => `${window.isFullscreen() ? 1 : 0}`);
	} else if (which == 13) {
		attempt(script, "droppedFileCount", (): string => `${window.droppedFileCount()}`);
	} else {
		attempt(script, `droppedFilePath ${arg % 6 - 1}`, (): string => window.droppedFilePath(arg % 6 - 1));
	}
	script.log.push(`quit ${script.quit ? 1 : 0}`);
}

function step(script: Script, window: AppWindow, ops: int32[], at: int32): void {
	const kind = ops[at];
	const a = ops[at + 1];
	const b = ops[at + 2];
	const c = ops[at + 3];
	const d = ops[at + 4];
	if (kind == KIND_PLATFORM) {
		script.valid = a % 4 != 0;
		script.frame = (b % 5000) as uint64;
		script.width = SIZES[c % 6];
		script.height = SIZES[d % 6];
		script.scale = SCALES[(a >> 2) % 4];
		script.modifiers = ((b >> 3) % 16) as uint32;
		script.viewsCurrent = (c >> 3) % 3;
		script.viewsWidth = SIZES[(d >> 3) % 6];
		script.viewsHeight = SIZES[(a >> 5) % 6];
		script.viewsScale = SCALES[(b >> 5) % 4];
		script.duration = DURATIONS[(c >> 5) % 3];
		script.log.push(`platform ${script.valid ? 1 : 0} ${script.frame} ${script.width} ${script.height} ${thousandths(script.scale)} ${script.modifiers} ${script.viewsCurrent}`);
	} else if (kind == KIND_HANDLER) {
		script.mask = a % 256;
		window.setHandler((): void => { handlerBody(script, window); });
		script.log.push(`handler ${script.mask} set ${window.handlerSet() ? 1 : 0}`);
	} else if (kind == KIND_DELIVER) {
		attempt(script, "deliver", (): string => `${window.deliver(eventOf(a, b, c, d, false)) ? 1 : 0}`);
	} else if (kind == KIND_TEXT) {
		attempt(script, `text ${24 + a % 2} ${b % 6} ${c % 7 - 3}`, (): string => {
			window.deliverText((24 + a % 2) as AppEventType, TEXTS[b % 6], c % 7 - 3);
			return "ok";
		});
	} else if (kind == KIND_OUTSIDE) {
		const which = a % 4;
		attempt(script, `outside ${which}`, (): string => {
			if (which == 0) { return `${window.eventType()}`; }
			if (which == 1) { return window.eventText(); }
			if (which == 2) { return `${window.eventCursor()}`; }
			return `${window.eventTouchX(0)}`;
		});
	} else if (kind == KIND_SAFE) {
		window.setSafeArea(FLOATS[a % 10], FLOATS[b % 10], FLOATS[c % 10], FLOATS[d % 10]);
		window.keyboard = FLOATS[(a + b) % 10];
		script.log.push(`safe ${thousandths(window.safeTop)} ${thousandths(window.safeLeft)} ${thousandths(window.safeBottom)} ${thousandths(window.safeRight)} keyboard ${thousandths(window.keyboard)}`);
	} else if (kind == KIND_TITLE) {
		attempt(script, `title ${a % TITLE_COUNT}`, (): string => {
			window.setTitle(titleOf(a % TITLE_COUNT));
			return "ok";
		});
		script.log.push(`title ${window.title} set ${window.titleSet ? 1 : 0}`);
	} else if (kind == KIND_REQUEST) {
		request(script, window, a % 15, b);
	} else if (kind == KIND_WINDOW_EVENT) {
		attempt(script, "windowEvent", (): string => {
			window.windowEvent(eventOf(a, b, c, d, d % 3 == 0));
			return "ok";
		});
		script.log.push(`quit ${script.quit ? 1 : 0}`);
	} else if (kind == KIND_MOBILE_SEND) {
		attempt(script, `mobileSend ${a % 26}`, (): string => { window.mobileSend((a % 26) as AppEventType); return "ok"; });
	} else if (kind == KIND_MOBILE_KEY) {
		attempt(script, `mobileKey ${a % 2} ${KEYS[b % 10]} ${c % 2}`, (): string => {
			window.mobileKey(a % 2 == 0 ? AppEventType.KeyDown : AppEventType.KeyUp, KEYS[b % 10], c % 2 == 1);
			return "ok";
		});
	} else if (kind == KIND_RELEASE) {
		attempt(script, "mobileReleaseKeys", (): string => { window.mobileReleaseKeys(); return "ok"; });
	} else if (kind == KIND_COMMIT) {
		attempt(script, `mobileCommit ${a % 2} ${b % 9} ${c % 6}`, (): string => {
			window.mobileCommit(a % 2, TEXTS[c % 6], codepointsOf(b % 9));
			return "ok";
		});
	} else if (kind == KIND_KEY_DOWN) {
		script.log.push(`keyDown ${KEYS[a % 10]} ${window.keysHeld.isDown(KEYS[a % 10]) ? 1 : 0}`);
	} else if (kind == KIND_FRAMEBUFFER) {
		script.log.push(`fb ${window.fbWidth()} ${window.fbHeight()} ${thousandths(window.dpiScale())}`);
	} else if (kind == KIND_MOBILE_EVENT) {
		attempt(script, `mobileEvent ${a % 26}`, (): string => {
			const e = window.mobileEvent((a % 26) as AppEventType);
			return `${e.type as int32} ${e.frameCount} ${e.modifiers} ${e.framebufferWidth} ${e.framebufferHeight} ${e.windowWidth} ${e.windowHeight}`;
		});
	} else {
		throw new Error(`appWindowPortScript: op kind ${kind} is not one of the ${KIND_MOBILE_EVENT + 1} kinds`);
	}
}

// The transcript of one run: every op and what it printed, one line each.
export function appWindowScriptRun(ops: int32[], mobile: boolean): string[] {
	const script = new Script(mobile);
	const window = new AppWindow(new ScriptPlatform(script));
	for (let at: int32 = 0; at < ops.length; at += OP_WORDS) { step(script, window, ops, at); }
	return script.log;
}

export function appWindowScriptDigest(lines: string[]): string {
	let hash: uint64 = FNV_OFFSET;
	for (const line of lines) {
		const text = line + "\n";
		for (let i: int32 = 0; i < text.byteLength(); i++) {
			hash = ((hash ^ (text.byteAt(i) as uint64)) * FNV_PRIME) % 4294967296;
		}
	}
	return `${hash}`;
}
