// gpu3d.c describeLayout as WebGPU vertex buffer layouts, indexed by gpu3d.ms VertexLayout: one
// buffer, attributes at their shader slots, offsets and stride packed in slot order as sokol_gfx
// computes them when every offset is zero (_sg_pipeline_desc_defaults).

import { GPUVertexBufferLayout, GPUVertexFormat, GPUVertexStepMode, vertexFormatSize } from "../webgpu/types.ms";

export const LAYOUT_COUNT: int32 = 10;

function packed(stepMode: GPUVertexStepMode, formats: GPUVertexFormat[]): GPUVertexBufferLayout[2] {
	let buffers: GPUVertexBufferLayout[2] = [{ arrayStride: 0, stepMode: stepMode }];
	let offset = 0;
	for (let slot = 0; slot < formats.length; slot++) {
		buffers[0].attributes[slot] = { format: formats[slot], offset: offset, shaderLocation: slot };
		offset += vertexFormatSize(formats[slot]);
	}
	buffers[0].arrayStride = offset;
	return buffers;
}

export function gpu3dVertexLayout(layout: int32): GPUVertexBufferLayout[2] {
	if (layout < 0 || layout >= LAYOUT_COUNT) {
		console.error(`gpu3dVertexLayout: no vertex layout ${layout}`);
		unreachable;
	}
	return match (layout) {
		0 => packed("vertex", ["float32x3", "float32x3", "float32x4"]),
		1 => packed("instance", ["float32x4", "float32x4"]),
		2 => packed("instance", ["float32x3", "float32x2", "float32x2", "float32x4", "float32x4"]),
		3 => packed("vertex", ["float32x2"]),
		4 => packed("vertex", ["float32x3", "float32x3", "float32x2", "float32x4"]),
		5 => packed("vertex", ["float32x3", "float32x3", "float32x2", "float32x4", "float32x4"]),
		6 => packed("vertex", ["float32x3", "float32x3", "float32x4", "float32x4", "float32x4"]),
		7 => packed("vertex", ["float32x3", "float32x3", "float32x2", "float32x4", "float32x4", "float32x4"]),
		8 => packed("vertex",
			["float32x3", "float32x3", "float32x2", "float32x4", "float32x4", "float32x4", "float32x4"]),
		_ => packed("instance", ["float32x4", "float32x4", "float32x4", "float32x4"]),
	};
}
