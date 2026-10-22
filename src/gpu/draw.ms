import "./door";
import {
	DOOR_BUFFER_INDEX,
	DOOR_BUFFER_STREAM,
	DOOR_BUFFER_VERTEX,
	doorApplyBindings,
	doorApplyPipeline,
	doorApplyUniformsOf,
	doorDestroyBuffer,
	doorDraw,
	doorMakeBuffer,
	doorMakeBufferOf,
	doorUpdateBufferOf,
} from "./doorGpu.ms";
import {
	DOOR_BINDING_INDEX_BUFFER,
	DOOR_BINDING_LENGTH,
	DOOR_BINDING_SAMPLER,
	DOOR_BINDING_VERTEX_BUFFER,
	DOOR_BINDING_VIEW,
} from "./doorWords.h";

export const BINDING_VERTEX_BUFFER: int32 = DOOR_BINDING_VERTEX_BUFFER;
export const BINDING_INDEX_BUFFER: int32 = DOOR_BINDING_INDEX_BUFFER;
export const BINDING_VIEW: int32 = DOOR_BINDING_VIEW;
export const BINDING_SAMPLER: int32 = DOOR_BINDING_SAMPLER;
export const BINDING_LENGTH: int32 = DOOR_BINDING_LENGTH;

export function makeVertexBuffer(data: Readonly<Span<float32>>): uint32 {
	return doorMakeBufferOf(DOOR_BUFFER_VERTEX, data);
}

export function makeIndexBuffer(data: Readonly<Span<uint16>>): uint32 {
	return doorMakeBufferOf(DOOR_BUFFER_INDEX, data);
}

// The pipeline that draws it selects uint32 indices.
export function makeIndexBuffer32(data: Readonly<Span<uint32>>): uint32 {
	return doorMakeBufferOf(DOOR_BUFFER_INDEX, data);
}

export function makeStreamBuffer(floats: int32): uint32 {
	return doorMakeBuffer(DOOR_BUFFER_VERTEX | DOOR_BUFFER_STREAM, [], (floats as int64) * 4);
}

// One update per buffer per frame, from its start, as sokol's sg_update_buffer allows.
export function updateBuffer(buffer: uint32, data: Readonly<Span<float32>>): boolean {
	return doorUpdateBufferOf(buffer, data) != 0;
}

export function destroyBuffer(buffer: uint32): void { doorDestroyBuffer(buffer); }

export function applyPipeline(pipeline: uint32): void { doorApplyPipeline(pipeline); }

export function applyBindings(bindings: Readonly<Span<uint32>>): void {
	doorApplyBindings(bindings, []);
}

export function applyUniforms(slot: int32, data: Readonly<Span<float32>>): void {
	doorApplyUniformsOf(slot, data);
}

export function draw(base: int32, count: int32, instances: int32): void {
	doorDraw(base, count, instances);
}
