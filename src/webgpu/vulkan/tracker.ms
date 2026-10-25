export const STAGE_TRANSFER: uint32 = 0x1000;
export const ACCESS_TRANSFER_READ: uint32 = 0x800;
export const LAYOUT_UNDEFINED: int32 = 0;
export const LAYOUT_TRANSFER_SRC: int32 = 6;

export struct BufferRest {
	stages: uint32;
	access: uint32;
}

export struct TextureRest {
	stages: uint32;
	access: uint32;
	layout: int32;
}

export struct ImageBarrier {
	image: uint32;
	sourceAccess: uint32;
	targetAccess: uint32;
	oldLayout: int32;
	newLayout: int32;
}

struct BufferWrite {
	id: uint32;
	stages: uint32;
	access: uint32;
	rest: BufferRest;
}

struct TextureWrite {
	id: uint32;
	stages: uint32;
	access: uint32;
	layout: int32;
	rest: TextureRest;
}

struct TextureCopy {
	id: uint32;
	rest: TextureRest;
}

export struct StateTracker {
	writtenBuffers: Vec<BufferWrite>;
	copyBuffers: Vec<uint32>;
	writtenTextures: Vec<TextureWrite>;
	copyTextures: Vec<TextureCopy>;
	images: Vec<ImageBarrier>;
	sourceStages: uint32;
	targetStages: uint32;
	sourceAccess: uint32;
	targetAccess: uint32;
}

export function newTracker(): StateTracker {
	return {
		writtenBuffers: [],
		copyBuffers: [],
		writtenTextures: [],
		copyTextures: [],
		images: [],
		sourceStages: 0,
		targetStages: 0,
		sourceAccess: 0,
		targetAccess: 0,
	};
}

function writtenBuffer(this t: StateTracker, id: uint32): int32 {
	for (let i: int32 = 0; i < t.writtenBuffers.length; i++) {
		if (t.writtenBuffers[i].id == id) { return i; }
	}
	return -1;
}

function copiedBuffer(this t: StateTracker, id: uint32): int32 {
	for (let i: int32 = 0; i < t.copyBuffers.length; i++) {
		if (t.copyBuffers[i] == id) { return i; }
	}
	return -1;
}

function writtenTexture(this t: StateTracker, id: uint32): int32 {
	for (let i: int32 = 0; i < t.writtenTextures.length; i++) {
		if (t.writtenTextures[i].id == id) { return i; }
	}
	return -1;
}

function copiedTexture(this t: StateTracker, id: uint32): int32 {
	for (let i: int32 = 0; i < t.copyTextures.length; i++) {
		if (t.copyTextures[i].id == id) { return i; }
	}
	return -1;
}

function addImageBarrier(
	ref t: StateTracker,
	image: uint32,
	sourceAccess: uint32,
	targetAccess: uint32,
	oldLayout: int32,
	newLayout: int32,
): void {
	t.images.push({
		image: image,
		sourceAccess: sourceAccess,
		targetAccess: targetAccess,
		oldLayout: oldLayout,
		newLayout: newLayout,
	});
}

function textureDependency(
	ref t: StateTracker,
	image: uint32,
	sourceAccess: uint32,
	targetAccess: uint32,
	oldLayout: int32,
	newLayout: int32,
): void {
	if (oldLayout != newLayout) {
		addImageBarrier(t, image, sourceAccess, targetAccess, oldLayout, newLayout);
		return;
	}
	t.sourceAccess |= sourceAccess;
	t.targetAccess |= targetAccess;
}

export function writeToBuffer(ref t: StateTracker, id: uint32, rest: BufferRest, stages: uint32, access: uint32): void {
	const written = t.writtenBuffer(id);
	const copied = t.copiedBuffer(id);
	if (written >= 0) {
		t.sourceStages |= t.writtenBuffers[written].stages;
		t.sourceAccess |= t.writtenBuffers[written].access;
		t.targetAccess |= access;
		t.writtenBuffers.splice(written, 1);
	} else if (copied >= 0) {
		t.sourceStages |= STAGE_TRANSFER;
		t.copyBuffers.splice(copied, 1);
	} else {
		t.sourceStages |= rest.stages;
	}
	t.targetStages |= stages;
	t.writtenBuffers.push({ id: id, stages: stages, access: access, rest: rest });
}

export function writeToTexture(
	ref t: StateTracker,
	id: uint32,
	rest: TextureRest,
	stages: uint32,
	access: uint32,
	layout: int32,
): void {
	const written = t.writtenTexture(id);
	const copied = t.copiedTexture(id);
	let sourceAccess: uint32 = 0;
	let oldLayout = rest.layout;
	if (written >= 0) {
		t.sourceStages |= t.writtenTextures[written].stages;
		sourceAccess = t.writtenTextures[written].access;
		oldLayout = t.writtenTextures[written].layout;
		t.writtenTextures.splice(written, 1);
	} else if (copied >= 0) {
		t.sourceStages |= STAGE_TRANSFER;
		oldLayout = LAYOUT_TRANSFER_SRC;
		t.copyTextures.splice(copied, 1);
	} else {
		t.sourceStages |= rest.stages;
	}
	t.targetStages |= stages;
	textureDependency(t, id, sourceAccess, access, oldLayout, layout);
	t.writtenTextures.push({ id: id, stages: stages, access: access, layout: layout, rest: rest });
}

export function readFromBuffer(ref t: StateTracker, id: uint32, stages: uint32, access: uint32): void {
	const written = t.writtenBuffer(id);
	if (written >= 0) {
		t.sourceStages |= t.writtenBuffers[written].stages;
		t.targetStages |= stages;
		t.sourceAccess |= t.writtenBuffers[written].access;
		t.targetAccess |= access;
		t.writtenBuffers.splice(written, 1);
		return;
	}
	const copied = t.copiedBuffer(id);
	if (copied >= 0) { t.copyBuffers.splice(copied, 1); }
}

export function copyFromBuffer(ref t: StateTracker, id: uint32): void {
	readFromBuffer(t, id, STAGE_TRANSFER, ACCESS_TRANSFER_READ);
	t.copyBuffers.push(id);
}

export function readFromTexture(
	ref t: StateTracker,
	id: uint32,
	rest: TextureRest,
	stages: uint32,
	access: uint32,
	layout: int32,
): void {
	const written = t.writtenTexture(id);
	const copied = t.copiedTexture(id);
	let sourceAccess: uint32 = 0;
	let oldLayout = rest.layout;
	if (written >= 0) {
		t.sourceStages |= t.writtenTextures[written].stages;
		sourceAccess = t.writtenTextures[written].access;
		oldLayout = t.writtenTextures[written].layout;
		t.writtenTextures.splice(written, 1);
	} else if (copied >= 0) {
		oldLayout = LAYOUT_TRANSFER_SRC;
		if (oldLayout != layout) { t.sourceStages |= STAGE_TRANSFER; }
		t.copyTextures.splice(copied, 1);
	} else if (oldLayout != layout) {
		t.sourceStages |= rest.stages;
	}
	t.targetStages |= stages;
	textureDependency(t, id, sourceAccess, access, oldLayout, layout);
}

export function copyFromTexture(ref t: StateTracker, id: uint32, rest: TextureRest): void {
	readFromTexture(t, id, rest, STAGE_TRANSFER, ACCESS_TRANSFER_READ, LAYOUT_TRANSFER_SRC);
	t.copyTextures.push({ id: id, rest: rest });
}

export function acquireTexture(ref t: StateTracker, id: uint32, rest: TextureRest): void {
	t.writtenTextures.push({ id: id, stages: rest.stages, access: 0, layout: LAYOUT_UNDEFINED, rest: rest });
}

export function initTexture(ref t: StateTracker, id: uint32, rest: TextureRest): void {
	t.targetStages |= rest.stages;
	addImageBarrier(t, id, 0, rest.access, LAYOUT_UNDEFINED, rest.layout);
}

export function pending(this t: StateTracker): boolean {
	return (t.sourceStages | t.targetStages) != 0 || t.images.length > 0;
}

export function cleared(ref t: StateTracker): void {
	t.sourceStages = 0;
	t.targetStages = 0;
	t.sourceAccess = 0;
	t.targetAccess = 0;
	t.images.length = 0;
}

export function endPass(ref t: StateTracker): void {
	for (const write of t.writtenBuffers) {
		t.sourceStages |= write.stages;
		t.targetStages |= write.rest.stages;
		t.sourceAccess |= write.access;
		t.targetAccess |= write.rest.access;
	}
	t.writtenBuffers.length = 0;
	t.copyBuffers.length = 0;
	for (const write of t.writtenTextures) {
		t.sourceStages |= write.stages;
		t.targetStages |= write.rest.stages;
		textureDependency(t, write.id, write.access, write.rest.access, write.layout, write.rest.layout);
	}
	t.writtenTextures.length = 0;
	for (const copy of t.copyTextures) {
		if (copy.rest.layout != LAYOUT_TRANSFER_SRC) {
			t.sourceStages |= STAGE_TRANSFER;
			t.targetStages |= copy.rest.stages;
			addImageBarrier(t, copy.id, 0, copy.rest.access, LAYOUT_TRANSFER_SRC, copy.rest.layout);
		}
	}
	t.copyTextures.length = 0;
}
