// The host views of Void: a view id names one host surface for its whole life, and the frame
// sequence the host drives over it. The platform owns the surfaces, addressed by view slot.

import { formatG } from "../math/formatG";

const MAX_VIEWS: int32 = 16;
const SLOT_BITS: int32 = 5;
const SLOT_MASK: int32 = 31;
export const VIEW_LAST_GENERATION: int32 = (1 << 26) - 1;
const NO_VIEW: int32 = 0;

export class ViewsPlatform {
	fail(message: string): never { throw new Error(message); }
	deviceEnsure(): void { throw new Error("ViewsPlatform.deviceEnsure is not provided"); }
	runInit(init: () => void): void { throw new Error("ViewsPlatform.runInit is not provided"); }
	surfaceCreate(slot: int32, native: int64, width: int32, height: int32): boolean { throw new Error("ViewsPlatform.surfaceCreate is not provided"); }
	surfaceResize(slot: int32, width: int32, height: int32): void { throw new Error("ViewsPlatform.surfaceResize is not provided"); }
	surfaceReady(slot: int32): boolean { throw new Error("ViewsPlatform.surfaceReady is not provided"); }
	surfaceAcquire(slot: int32): boolean { throw new Error("ViewsPlatform.surfaceAcquire is not provided"); }
	surfacePresent(slot: int32): void { throw new Error("ViewsPlatform.surfacePresent is not provided"); }
	surfaceDestroy(slot: int32): void { throw new Error("ViewsPlatform.surfaceDestroy is not provided"); }
	surfaceNative(slot: int32): int64 { throw new Error("ViewsPlatform.surfaceNative is not provided"); }
}

class ViewSlot {
	used: boolean = false;
	retired: boolean = false;
	generation: int32 = 0;
	width: int32 = 0;
	height: int32 = 0;
	scale: float32 = 0;
}

export class Views {
	platform: ViewsPlatform;
	lastGeneration: int32;
	slots: ViewSlot[] = [];
	currentView: int32 = NO_VIEW;
	inited: boolean = false;
	deviceMade: boolean = false;
	samples: int32 = 1;
	initClosure: () => void = (): void => {};
	frameClosure: () => void = (): void => {};
	pumpClosure: () => void = (): void => {};

	constructor(platform: ViewsPlatform, lastGeneration: int32 = VIEW_LAST_GENERATION) {
		this.platform = platform;
		this.lastGeneration = lastGeneration;
		for (let i: int32 = 0; i < MAX_VIEWS; i++) { this.slots.push(new ViewSlot()); }
	}

	slotOf(view: int32, operation: string): int32 {
		const index = (view & SLOT_MASK) - 1;
		if (view <= 0 || index < 0 || index >= MAX_VIEWS) {
			this.platform.fail(`${operation}: view ${view} does not exist`);
		}
		const slot = this.slots[index];
		const generation = view >> SLOT_BITS;
		if (slot.used && generation == slot.generation) { return index; }
		if (slot.retired || generation < slot.generation) {
			this.platform.fail(`${operation}: view ${view} was destroyed; a view id names one view only`);
		}
		return this.platform.fail(`${operation}: view ${view} does not exist`);
	}

	currentSlot(operation: string): int32 {
		if (this.currentView == NO_VIEW) {
			this.platform.fail(`${operation} outside a view frame: call it between voidViewFrame's begin and commit`);
		}
		return (this.currentView & SLOT_MASK) - 1;
	}

	register(init: () => void, frame: () => void): void {
		this.initClosure = init;
		this.frameClosure = frame;
	}

	setSampleCount(count: int32): void {
		if (count != 1 && count != 2 && count != 4 && count != 8) {
			this.platform.fail(`voidViewsSetSampleCount(${count}): a swapchain takes 1, 2, 4 or 8 samples`);
		}
		if (this.deviceMade) {
			this.platform.fail(`voidViewsSetSampleCount(${count}) after the first voidViewCreate: the device's pipelines are already made for ${this.samples} samples`);
		}
		this.samples = count;
	}

	sampleCount(): int32 { return this.samples; }

	setMessagePump(pump: () => void): void { this.pumpClosure = pump; }

	pumpMessages(): void { this.pumpClosure(); }

	create(native: int64, width: int32, height: int32, scale: float32): int32 {
		if (width <= 0 || height <= 0 || scale <= 0) {
			this.platform.fail(`voidViewCreate: ${width}x${height} at scale ${formatG(scale as float64)} is not a drawable size`);
		}
		let index: int32 = -1;
		for (let i: int32 = 0; i < MAX_VIEWS; i++) {
			if (!this.slots[i].used && !this.slots[i].retired) { index = i; break; }
		}
		if (index < 0) { this.platform.fail(`voidViewCreate: all ${MAX_VIEWS} views are in use or retired`); }
		this.platform.deviceEnsure();
		this.deviceMade = true;
		if (!this.platform.surfaceCreate(index, native, width, height)) {
			this.platform.fail(`voidViewCreate: the platform could not make a ${width}x${height} surface`);
		}
		const slot = this.slots[index];
		const generation = slot.generation == 0 ? 1 : slot.generation;
		slot.used = true;
		slot.retired = false;
		slot.generation = generation;
		slot.width = width;
		slot.height = height;
		slot.scale = scale;
		if (!this.inited) {
			this.inited = true;
			this.platform.runInit(this.initClosure);
		}
		return (generation << SLOT_BITS) | (index + 1);
	}

	resize(view: int32, width: int32, height: int32, scale: float32): void {
		const index = this.slotOf(view, "voidViewResize");
		const slot = this.slots[index];
		if (this.currentView != NO_VIEW) {
			this.platform.fail(`voidViewResize(${view}) inside the frame of view ${this.currentView}`);
		}
		if (width <= 0 || height <= 0 || scale <= 0) {
			this.platform.fail(`voidViewResize(${view}): ${width}x${height} at scale ${formatG(scale as float64)} is not a drawable size`);
		}
		if (width != slot.width || height != slot.height) { this.platform.surfaceResize(index, width, height); }
		slot.width = width;
		slot.height = height;
		slot.scale = scale;
	}

	frame(view: int32): boolean {
		const index = this.slotOf(view, "voidViewFrame");
		if (this.currentView != NO_VIEW) {
			this.platform.fail(`voidViewFrame(${view}) inside the frame of view ${this.currentView}`);
		}
		this.pumpMessages();
		if (!this.platform.surfaceReady(index)) { return false; }
		if (!this.platform.surfaceAcquire(index)) { return false; }
		this.currentView = view;
		this.frameClosure();
		if (this.currentView != NO_VIEW) {
			this.platform.fail(`the frame closure for view ${view} returned without commit()`);
		}
		return true;
	}

	ready(view: int32): boolean {
		return this.platform.surfaceReady(this.slotOf(view, "voidViewReady"));
	}

	destroy(view: int32): void {
		const index = this.slotOf(view, "voidViewDestroy");
		if (this.currentView != NO_VIEW) {
			this.platform.fail(`voidViewDestroy(${view}) inside the frame of view ${this.currentView}`);
		}
		this.platform.surfaceDestroy(index);
		const slot = this.slots[index];
		const next = slot.generation == this.lastGeneration ? 0 : slot.generation + 1;
		slot.used = false;
		slot.retired = next == 0;
		slot.generation = next;
		slot.width = 0;
		slot.height = 0;
		slot.scale = 0;
	}

	swapChain(view: int32): int64 {
		return this.platform.surfaceNative(this.slotOf(view, "voidViewSwapChain"));
	}

	fbWidth(): int32 { return this.slots[this.currentSlot("fbWidth")].width; }
	fbHeight(): int32 { return this.slots[this.currentSlot("fbHeight")].height; }
	dpiScale(): float32 { return this.slots[this.currentSlot("dpiScale")].scale; }

	currentSurfaceSlot(): int32 { return this.currentSlot("beginPass"); }

	present(): void {
		const index = this.currentSlot("commit");
		this.currentView = NO_VIEW;
		this.platform.surfacePresent(index);
	}

	usedSlot(index: int32): boolean { return this.slots[index].used; }
}
