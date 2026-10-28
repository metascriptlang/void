// The window's app-facing half, shared by the window drivers: the event handler with the getters
// that read the event it was called for, the IME events, the title, the safe area, the keyboard
// and the window requests. The platform owns the native window and its state.

import {
	AppEventType,
	CURSOR_COUNT,
	KeyCode,
	KeysHeld,
	NativeAppEvent,
	NativeTouchPoint,
	blankAppEvent,
} from "../platform/appEvent";

const TITLE_CAPACITY: int32 = 256;
const DEFAULT_TITLE = "Void";

export class AppWindowPlatform {
	fail(message: string): never { throw new Error(message); }
	valid(): boolean { throw new Error("AppWindowPlatform.valid is not provided"); }
	frameCount(): uint64 { throw new Error("AppWindowPlatform.frameCount is not provided"); }
	framebufferWidth(): int32 { throw new Error("AppWindowPlatform.framebufferWidth is not provided"); }
	framebufferHeight(): int32 { throw new Error("AppWindowPlatform.framebufferHeight is not provided"); }
	modifiers(): uint32 { throw new Error("AppWindowPlatform.modifiers is not provided"); }
	scale(): float32 { throw new Error("AppWindowPlatform.scale is not provided"); }
	viewsCurrent(): int32 { throw new Error("AppWindowPlatform.viewsCurrent is not provided"); }
	viewsFbWidth(): int32 { throw new Error("AppWindowPlatform.viewsFbWidth is not provided"); }
	viewsFbHeight(): int32 { throw new Error("AppWindowPlatform.viewsFbHeight is not provided"); }
	viewsDpiScale(): float32 { throw new Error("AppWindowPlatform.viewsDpiScale is not provided"); }
	profileInput(): void { throw new Error("AppWindowPlatform.profileInput is not provided"); }
	setTitle(title: string): void { throw new Error("AppWindowPlatform.setTitle is not provided"); }
	requestQuit(): void { throw new Error("AppWindowPlatform.requestQuit is not provided"); }
	cancelQuit(): void { throw new Error("AppWindowPlatform.cancelQuit is not provided"); }
	frameDuration(): float64 { throw new Error("AppWindowPlatform.frameDuration is not provided"); }
	setClipboard(text: string): void { throw new Error("AppWindowPlatform.setClipboard is not provided"); }
	clipboard(): string { throw new Error("AppWindowPlatform.clipboard is not provided"); }
	setCursor(cursor: int32): void { throw new Error("AppWindowPlatform.setCursor is not provided"); }
	cursor(): int32 { throw new Error("AppWindowPlatform.cursor is not provided"); }
	showMouse(shown: boolean): void { throw new Error("AppWindowPlatform.showMouse is not provided"); }
	mouseShown(): boolean { throw new Error("AppWindowPlatform.mouseShown is not provided"); }
	lockMouse(locked: boolean): void { throw new Error("AppWindowPlatform.lockMouse is not provided"); }
	mouseLocked(): boolean { throw new Error("AppWindowPlatform.mouseLocked is not provided"); }
	toggleFullscreen(): void { throw new Error("AppWindowPlatform.toggleFullscreen is not provided"); }
	isFullscreen(): boolean { throw new Error("AppWindowPlatform.isFullscreen is not provided"); }
	droppedCount(): int32 { throw new Error("AppWindowPlatform.droppedCount is not provided"); }
	droppedPath(index: int32): string { throw new Error("AppWindowPlatform.droppedPath is not provided"); }
	setTextInput(on: boolean): void { throw new Error("AppWindowPlatform.setTextInput is not provided"); }
	setImeRect(x: int32, y: int32, w: int32, h: int32): void { throw new Error("AppWindowPlatform.setImeRect is not provided"); }
}

export class AppWindow {
	platform: AppWindowPlatform;
	handler: (() => void) | null = null;
	event: NativeAppEvent = blankAppEvent(AppEventType.Invalid);
	inEvent: boolean = false;
	text: string = "";
	cursor: int32 = 0;
	safeTop: float32 = 0;
	safeLeft: float32 = 0;
	safeBottom: float32 = 0;
	safeRight: float32 = 0;
	keyboard: float32 = 0;
	title: string = DEFAULT_TITLE;
	titleSet: boolean = false;
	presentMode: int32 = 0;
	keysHeld: KeysHeld = new KeysHeld();

	constructor(platform: AppWindowPlatform) {
		this.platform = platform;
	}

	setHandler(handler: () => void): void { this.handler = handler; }

	handlerSet(): boolean { return this.handler !== null; }

	deliver(e: NativeAppEvent): boolean {
		const handler = this.handler;
		if (handler === null) { return false; }
		this.event = e;
		this.inEvent = true;
		handler();
		this.inEvent = false;
		return true;
	}

	windowEvent(e: NativeAppEvent): void {
		if (
			e.type == AppEventType.KeyDown || e.type == AppEventType.KeyUp ||
			e.type == AppEventType.Char || e.type == AppEventType.MouseDown ||
			e.type == AppEventType.MouseUp || e.type == AppEventType.MouseScroll
		) {
			this.platform.profileInput();
		}
		if (this.deliver(e)) { return; }
		if (e.type == AppEventType.KeyDown && e.keyCode == (KeyCode.Escape as int32)) {
			this.platform.requestQuit();
		}
	}

	current(field: string): NativeAppEvent {
		if (!this.inEvent) {
			this.platform.fail(`voidEvent${field}: read outside the event handler voidSetEventHandler registered`);
		}
		return this.event;
	}

	touchAt(field: string, index: int32): NativeTouchPoint {
		const e = this.current(field);
		if (index < 0 || index >= e.touchCount) {
			this.platform.fail(`voidEvent${field}(${index}): the event has ${e.touchCount} touch points`);
		}
		return e.touches[index];
	}

	eventType(): int32 { return this.current("Type").type as int32; }
	eventKeyCode(): int32 { return this.current("KeyCode").keyCode; }
	eventCharCode(): uint32 { return this.current("CharCode").charCode; }
	eventKeyRepeat(): int32 { return this.current("KeyRepeat").keyRepeat ? 1 : 0; }
	eventModifiers(): uint32 { return this.current("Modifiers").modifiers; }
	eventMouseButton(): int32 { return this.current("MouseButton").mouseButton; }
	eventMouseX(): float32 { return this.current("MouseX").mouseX; }
	eventMouseY(): float32 { return this.current("MouseY").mouseY; }
	eventMouseDx(): float32 { return this.current("MouseDx").mouseDx; }
	eventMouseDy(): float32 { return this.current("MouseDy").mouseDy; }
	eventScrollX(): float32 { return this.current("ScrollX").scrollX; }
	eventScrollY(): float32 { return this.current("ScrollY").scrollY; }
	eventFramebufferWidth(): int32 { return this.current("FramebufferWidth").framebufferWidth; }
	eventFramebufferHeight(): int32 { return this.current("FramebufferHeight").framebufferHeight; }
	eventTouchCount(): int32 { return this.current("TouchCount").touchCount; }
	eventTouchId(index: int32): int64 { return this.touchAt("TouchId", index).identifier as int64; }
	eventTouchX(index: int32): float32 { return this.touchAt("TouchX", index).x; }
	eventTouchY(index: int32): float32 { return this.touchAt("TouchY", index).y; }
	eventTouchChanged(index: int32): int32 { return this.touchAt("TouchChanged", index).changed ? 1 : 0; }

	eventText(): string {
		this.current("Text");
		return this.text;
	}

	eventCursor(): int32 {
		this.current("Cursor");
		return this.cursor;
	}

	deliverText(type: AppEventType, utf8: string, cursor: int32): void {
		let e = blankAppEvent(type);
		e.frameCount = this.platform.frameCount();
		e.framebufferWidth = this.platform.framebufferWidth();
		e.framebufferHeight = this.platform.framebufferHeight();
		this.text = utf8;
		this.cursor = cursor;
		this.deliver(e);
		this.text = "";
		this.cursor = 0;
	}

	setSafeArea(top: float32, left: float32, bottom: float32, right: float32): void {
		this.safeTop = top;
		this.safeLeft = left;
		this.safeBottom = bottom;
		this.safeRight = right;
	}

	setTitle(title: string): void {
		if (title.byteLength() >= TITLE_CAPACITY) {
			this.platform.fail(`voidSetWindowTitle: the title is ${title.byteLength()} bytes; at most ${TITLE_CAPACITY - 1} fit`);
		}
		this.title = title;
		this.titleSet = true;
		if (this.platform.valid()) { this.platform.setTitle(title); }
	}

	setPresentMode(mode: int32): void {
		if (mode != 0 && mode != 1) {
			this.platform.fail(`voidSetPresentMode: ${mode} is neither 0 (AutoVsync) nor 1 (AutoNoVsync)`);
		}
		if (this.platform.valid()) {
			this.platform.fail("voidSetPresentMode: the window already presents; set the mode before voidRun");
		}
		this.presentMode = mode;
	}

	needWindow(what: string): void {
		if (!this.platform.valid()) {
			this.platform.fail(`${what}: the window does not exist yet; call it from the event handler or after init`);
		}
	}

	requestQuit(): void {
		this.needWindow("voidRequestQuit");
		this.platform.requestQuit();
	}

	cancelQuit(): void {
		this.needWindow("voidCancelQuit");
		this.platform.cancelQuit();
	}

	frameDuration(): float64 {
		this.needWindow("voidFrameDuration");
		return this.platform.frameDuration();
	}

	setClipboard(text: string): void {
		this.needWindow("voidSetClipboard");
		this.platform.setClipboard(text);
	}

	clipboard(): string {
		this.needWindow("voidClipboard");
		return this.platform.clipboard();
	}

	setMouseCursor(cursor: int32): void {
		this.needWindow("voidSetMouseCursor");
		if (cursor < 0 || cursor >= CURSOR_COUNT) {
			this.platform.fail(`voidSetMouseCursor: cursor ${cursor} is not a VoidMouseCursor (0..${CURSOR_COUNT - 1})`);
		}
		this.platform.setCursor(cursor);
	}

	mouseCursor(): int32 {
		this.needWindow("voidMouseCursor");
		return this.platform.cursor();
	}

	showMouse(shown: int32): void {
		this.needWindow("voidShowMouse");
		this.platform.showMouse(shown != 0);
	}

	mouseShown(): boolean {
		this.needWindow("voidMouseShown");
		return this.platform.mouseShown();
	}

	lockMouse(locked: int32): void {
		this.needWindow("voidLockMouse");
		this.platform.lockMouse(locked != 0);
	}

	mouseLocked(): boolean {
		this.needWindow("voidMouseLocked");
		return this.platform.mouseLocked();
	}

	setTextInput(on: boolean): void { this.platform.setTextInput(on); }

	setImeRect(x: int32, y: int32, w: int32, h: int32): void { this.platform.setImeRect(x, y, w, h); }

	toggleFullscreen(): void {
		this.needWindow("voidToggleFullscreen");
		this.platform.toggleFullscreen();
	}

	isFullscreen(): boolean {
		this.needWindow("voidIsFullscreen");
		return this.platform.isFullscreen();
	}

	droppedFileCount(): int32 {
		this.needWindow("voidDroppedFileCount");
		return this.platform.droppedCount();
	}

	droppedFilePath(index: int32): string {
		this.needWindow("voidDroppedFilePath");
		if (index < 0 || index >= this.platform.droppedCount()) {
			this.platform.fail(`voidDroppedFilePath: index ${index} of ${this.platform.droppedCount()} dropped files`);
		}
		return this.platform.droppedPath(index);
	}

	fbWidth(): int32 {
		return this.platform.valid() && this.platform.viewsCurrent() == 0
			? this.platform.framebufferWidth()
			: this.platform.viewsFbWidth();
	}

	fbHeight(): int32 {
		return this.platform.valid() && this.platform.viewsCurrent() == 0
			? this.platform.framebufferHeight()
			: this.platform.viewsFbHeight();
	}

	dpiScale(): float32 {
		return this.platform.valid() && this.platform.viewsCurrent() == 0
			? this.platform.scale()
			: this.platform.viewsDpiScale();
	}

	mobileEvent(type: AppEventType): NativeAppEvent {
		let e = blankAppEvent(type);
		e.frameCount = this.platform.frameCount();
		e.modifiers = this.platform.modifiers();
		e.framebufferWidth = this.platform.framebufferWidth();
		e.framebufferHeight = this.platform.framebufferHeight();
		e.windowWidth = (e.framebufferWidth as float32 / this.platform.scale()) as int32;
		e.windowHeight = (e.framebufferHeight as float32 / this.platform.scale()) as int32;
		return e;
	}

	mobileSend(type: AppEventType): void { this.deliver(this.mobileEvent(type)); }

	mobileKey(type: AppEventType, code: int32, repeat: boolean): void {
		this.keysHeld.track(type, code);
		let e = this.mobileEvent(type);
		e.keyCode = code;
		e.keyRepeat = repeat;
		this.deliver(e);
	}

	mobileReleaseKeys(): void {
		this.keysHeld.release((key: int32): void => { this.mobileKey(AppEventType.KeyUp, key, false); });
	}

	tapUnlessHeld(key: KeyCode): void {
		if (this.keysHeld.isDown(key as int32)) { return; }
		this.mobileKey(AppEventType.KeyDown, key as int32, false);
		this.mobileKey(AppEventType.KeyUp, key as int32, false);
	}

	mobileCommit(textInput: int32, utf8: string, codepoints: uint32[]): void {
		if (codepoints.length == 1 && (codepoints[0] == 0x0A || codepoints[0] == 0x0D)) {
			this.tapUnlessHeld(KeyCode.Enter);
			return;
		}
		if (codepoints.length == 1 && codepoints[0] == 0x09) {
			this.tapUnlessHeld(KeyCode.Tab);
			return;
		}
		for (const codepoint of codepoints) {
			if (codepoint < 0x20 || codepoint == 0x7F) { continue; }
			if (textInput != 0) {
				this.deliverText(AppEventType.TextInput, utf8, 0);
				return;
			}
			let e = this.mobileEvent(AppEventType.Char);
			e.charCode = codepoint;
			this.deliver(e);
		}
	}
}
