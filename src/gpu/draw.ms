import "./door";
import {
	drawMakeStreamBuffer,
	drawDestroyBuffer,
	drawApplyPipeline,
	drawElements,
	DRAW_BINDING_VERTEX_BUFFER,
	DRAW_BINDING_INDEX_BUFFER,
	DRAW_BINDING_VIEW,
	DRAW_BINDING_SAMPLER,
	DRAW_BINDING_LENGTH,
} from "./draw.h";

// Declared, not imported from draw.h, for the reason door.ms gives its Span functions.
extern function drawMakeVertexBuffer(data: Readonly<Span<float32>>): uint32;
extern function drawMakeIndexBuffer(data: Readonly<Span<uint16>>): uint32;
extern function drawMakeIndexBuffer32(data: Readonly<Span<uint32>>): uint32;
extern function drawUpdateBuffer(buffer: uint32, data: Readonly<Span<float32>>): int32;
extern function drawApplyBindings(bindings: Readonly<Span<uint32>>): void;
extern function drawApplyUniforms(slot: int32, data: Readonly<Span<float32>>): void;

export const BINDING_VERTEX_BUFFER: int32 = DRAW_BINDING_VERTEX_BUFFER;
export const BINDING_INDEX_BUFFER: int32 = DRAW_BINDING_INDEX_BUFFER;
export const BINDING_VIEW: int32 = DRAW_BINDING_VIEW;
export const BINDING_SAMPLER: int32 = DRAW_BINDING_SAMPLER;
export const BINDING_LENGTH: int32 = DRAW_BINDING_LENGTH;

export function makeVertexBuffer(data: Readonly<Span<float32>>): uint32 {
	return drawMakeVertexBuffer(data);
}

export function makeIndexBuffer(data: Readonly<Span<uint16>>): uint32 {
	return drawMakeIndexBuffer(data);
}

// The pipeline that draws it selects uint32 indices.
export function makeIndexBuffer32(data: Readonly<Span<uint32>>): uint32 {
	return drawMakeIndexBuffer32(data);
}

export function makeStreamBuffer(floats: int32): uint32 {
	return drawMakeStreamBuffer(floats as int64);
}

// sokol accepts one update per buffer per frame (sokol_gfx.h VALIDATE_UPDATEBUF_ONCE).
export function updateBuffer(buffer: uint32, data: Readonly<Span<float32>>): boolean {
	return drawUpdateBuffer(buffer, data) != 0;
}

export function destroyBuffer(buffer: uint32): void { drawDestroyBuffer(buffer); }

export function applyPipeline(pipeline: uint32): void { drawApplyPipeline(pipeline); }

export function applyBindings(bindings: Readonly<Span<uint32>>): void {
	drawApplyBindings(bindings);
}

export function applyUniforms(slot: int32, data: Readonly<Span<float32>>): void {
	drawApplyUniforms(slot, data);
}

export function draw(base: int32, count: int32, instances: int32): void {
	drawElements(base, count, instances);
}
