// Void Dawn/WebGPU — GPU object classes wrapping Dawn C bridge

@include("./dawn.h")
@link("../../deps/sdl3webgpu/sdl3webgpu.o")
@passC("-Ideps/dawn/include")
@passC("-I/opt/homebrew/opt/sdl3/include")
@passC("-Ideps/sdl3webgpu")
@passL("-Ldeps/dawn/lib")
@passL("-L/opt/homebrew/opt/sdl3/lib")
@passL("-lwebgpu_dawn")
@passL("-lSDL3")
@passL("-Wl,-rpath,deps/dawn/lib")
@passL("-Wl,-rpath,/opt/homebrew/opt/sdl3/lib")
@passL("-framework QuartzCore")
@passL("-framework Metal")
@passL("-framework Cocoa")
@passL("-framework IOKit")
@passL("-framework IOSurface")
@passL("-lobjc")

import {
	void_gpu_create_instance, void_gpu_create_surface,
	void_gpu_request_adapter, void_gpu_request_device,
	void_gpu_get_queue, void_gpu_configure_surface,
	void_gpu_create_shader, void_gpu_create_render_pipeline,
	void_gpu_create_render_pipeline_1vb,
	void_gpu_create_render_pipeline_ext,
	void_gpu_create_buffer, void_gpu_buffer_get_mapped_range,
	void_gpu_buffer_unmap, void_gpu_buffer_write_floats,
	void_gpu_mapped_write_float,
	void_gpu_mapped_write_u16, void_gpu_mapped_write_u32,
	void_gpu_queue_write_buffer,
	void_gpu_create_bind_group_layout_1buf,
	void_gpu_create_bind_group_1buf,
	void_gpu_create_pipeline_layout_1bg,
	void_gpu_create_depth_texture, void_gpu_create_texture_view,
	void_gpu_get_current_texture_view,
	void_gpu_create_command_encoder,
	void_gpu_begin_render_pass,
	void_gpu_begin_render_pass_depth,
	void_gpu_render_pass_set_pipeline,
	void_gpu_render_pass_set_vertex_buffer,
	void_gpu_render_pass_set_index_buffer,
	void_gpu_render_pass_set_bind_group,
	void_gpu_render_pass_draw,
	void_gpu_render_pass_draw_indexed,
	void_gpu_end_render_pass,
	void_gpu_finish_encoder,
	void_gpu_submit, void_gpu_present,
	void_gpu_release_instance, void_gpu_release_surface,
	void_gpu_release_adapter, void_gpu_release_device,
	void_gpu_release_queue, void_gpu_release_shader,
	void_gpu_release_pipeline, void_gpu_release_command_encoder,
	void_gpu_release_command_buffer, void_gpu_release_texture_view,
	void_gpu_release_buffer, void_gpu_release_texture,
	void_gpu_release_bind_group_layout, void_gpu_release_bind_group,
	void_gpu_release_pipeline_layout, void_gpu_release_sampler,
	void_gpu_render_pass_set_viewport,
	void_gpu_render_pass_set_scissor_rect,
	void_gpu_create_texture, void_gpu_queue_write_texture,
	void_gpu_create_sampler,
	void_gpu_create_bind_group_layout_1tex_1samp,
	void_gpu_create_bind_group_1tex_1samp,
	void_gpu_create_pipeline_layout_2bg,
	void_gpu_create_render_pipeline_ext2,
	void_gen_checkerboard
} from "./dawn.h"

import { GPUColorDict } from "./types"

import {
	GPUShaderModuleDescriptor,
	GPURenderPipelineDescriptor,
	GPURenderPassDescriptor,
	GPURenderPassColorAttachment,
	GPURenderPassDepthStencilAttachment,
	GPUCanvasConfiguration,
	GPUBufferDescriptor,
	GPUVertexBufferLayout,
	GPUBindGroupLayoutEntry,
	GPUBindGroupEntry,
	GPUDepthStencilState
} from "./descriptors"

// --- GPUTextureView ---

export class GPUTextureView {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_texture_view(this._handle);
	}
}

// --- GPUBindGroupLayout ---

export class GPUBindGroupLayout {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_bind_group_layout(this._handle);
	}
}

// --- GPUBindGroup ---

export class GPUBindGroup {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_bind_group(this._handle);
	}
}

// --- GPUPipelineLayout ---

export class GPUPipelineLayout {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_pipeline_layout(this._handle);
	}
}

// --- GPUSampler ---

export class GPUSampler {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_sampler(this._handle);
	}
}

// --- GPUBuffer ---

export class GPUBuffer {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	getMappedRange(offset: uint64, size: uint64): unknown {
		return void_gpu_buffer_get_mapped_range(this._handle, offset, size);
	}

	unmap(): void {
		void_gpu_buffer_unmap(this._handle);
	}

	writeFloats(data: unknown, count: uint32): void {
		void_gpu_buffer_write_floats(this._handle, data, count);
	}

	mappedWriteFloat(mapped: unknown, index: uint32, value: float32): void {
		void_gpu_mapped_write_float(mapped, index, value);
	}

	mappedWriteU16(mapped: unknown, index: uint32, value: uint16): void {
		void_gpu_mapped_write_u16(mapped, index, value);
	}

	mappedWriteU32(mapped: unknown, index: uint32, value: uint32): void {
		void_gpu_mapped_write_u32(mapped, index, value);
	}

	release(): void {
		void_gpu_release_buffer(this._handle);
	}
}

// --- GPUTexture ---

export class GPUTexture {
	_handle: unknown;
	_isView: int32;

	constructor(handle: unknown, isView: int32) {
		this._handle = handle;
		this._isView = isView;
	}

	createView(): GPUTextureView {
		if (this._isView === 1) {
			// Surface texture: handle IS already a texture view
			return new GPUTextureView(this._handle);
		}
		// Regular texture: create a view from it
		const viewHandle = void_gpu_create_texture_view(this._handle);
		return new GPUTextureView(viewHandle);
	}

	release(): void {
		if (this._isView === 0) {
			void_gpu_release_texture(this._handle);
		}
	}
}

// --- GPUCommandBuffer ---

export class GPUCommandBuffer {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_command_buffer(this._handle);
	}
}

// --- GPURenderPassEncoder ---

export class GPURenderPassEncoder {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	setPipeline(pipeline: GPURenderPipeline): void {
		void_gpu_render_pass_set_pipeline(this._handle, pipeline._handle);
	}

	setVertexBuffer(slot: uint32, buffer: GPUBuffer): void {
		void_gpu_render_pass_set_vertex_buffer(this._handle, slot, buffer._handle, 0, 0);
	}

	setIndexBuffer(buffer: GPUBuffer, format: uint32): void {
		void_gpu_render_pass_set_index_buffer(this._handle, buffer._handle, format, 0, 0);
	}

	setBindGroup(index: uint32, bindGroup: GPUBindGroup): void {
		void_gpu_render_pass_set_bind_group(this._handle, index, bindGroup._handle);
	}

	draw(vertexCount: uint32): void {
		void_gpu_render_pass_draw(this._handle, vertexCount);
	}

	drawIndexed(indexCount: uint32): void {
		void_gpu_render_pass_draw_indexed(this._handle, indexCount, 1, 0, 0, 0);
	}

	setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
		void_gpu_render_pass_set_viewport(this._handle, x, y, width, height, minDepth, maxDepth);
	}

	setScissorRect(x: uint32, y: uint32, width: uint32, height: uint32): void {
		void_gpu_render_pass_set_scissor_rect(this._handle, x, y, width, height);
	}

	end(): void {
		void_gpu_end_render_pass(this._handle);
	}
}

// --- GPUCommandEncoder ---

export class GPUCommandEncoder {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	beginRenderPass(descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
		const attachment = descriptor.colorAttachments[0];
		const tv = attachment.view as GPUTextureView;
		const handle = void_gpu_begin_render_pass(
			this._handle,
			tv._handle,
			attachment.clearR,
			attachment.clearG,
			attachment.clearB,
			attachment.clearA
		);
		return new GPURenderPassEncoder(handle);
	}

	beginRenderPassDepth(descriptor: GPURenderPassDescriptor, depthView: GPUTextureView): GPURenderPassEncoder {
		const attachment = descriptor.colorAttachments[0];
		const tv = attachment.view as GPUTextureView;
		const handle = void_gpu_begin_render_pass_depth(
			this._handle,
			tv._handle,
			attachment.clearR,
			attachment.clearG,
			attachment.clearB,
			attachment.clearA,
			depthView._handle
		);
		return new GPURenderPassEncoder(handle);
	}

	finish(): GPUCommandBuffer {
		const handle = void_gpu_finish_encoder(this._handle);
		return new GPUCommandBuffer(handle);
	}

	release(): void {
		void_gpu_release_command_encoder(this._handle);
	}
}

// --- GPURenderPipeline ---

export class GPURenderPipeline {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_pipeline(this._handle);
	}
}

// --- GPUShaderModule ---

export class GPUShaderModule {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	release(): void {
		void_gpu_release_shader(this._handle);
	}
}

// --- GPUQueue ---

export class GPUQueue {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	submit(commandBuffers: Array<GPUCommandBuffer>): void {
		for (const cmd of commandBuffers) {
			void_gpu_submit(this._handle, cmd._handle);
		}
	}

	writeBuffer(buffer: GPUBuffer, offset: uint64, data: unknown, size: uint64): void {
		void_gpu_queue_write_buffer(this._handle, buffer._handle, offset, data, size);
	}

	writeTexture(texture: GPUTexture, data: unknown, dataSize: uint64, bytesPerRow: uint32, width: uint32, height: uint32): void {
		void_gpu_queue_write_texture(this._handle, texture._handle, data, dataSize, bytesPerRow, width, height);
	}

	release(): void {
		void_gpu_release_queue(this._handle);
	}
}

// --- GPUDevice ---

export class GPUDevice {
	_handle: unknown;
	_queueHandle: unknown;

	constructor(handle: unknown, queueHandle: unknown) {
		this._handle = handle;
		this._queueHandle = queueHandle;
	}

	getQueue(): GPUQueue {
		return new GPUQueue(this._queueHandle);
	}

	createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
		const handle = void_gpu_create_shader(this._handle, descriptor.code);
		return new GPUShaderModule(handle);
	}

	createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
		const vertex = descriptor.vertex;
		const sm = vertex.module as GPUShaderModule;
		const shaderHandle = sm._handle;
		const vsEntry = vertex.entryPoint;
		var fsEntry = "fs";
		const frag = descriptor.fragment;
		if (frag !== null) {
			fsEntry = frag.entryPoint;
		}

		const buffers = vertex.buffers;
		if (buffers.length > 0) {
			const buf = buffers[0];
			const attrs = buf.attributes;
			var fmt0: uint32 = 0;
			var off0: uint64 = 0;
			var loc0: uint32 = 0;
			var fmt1: uint32 = 0;
			var off1: uint64 = 0;
			var loc1: uint32 = 0;
			const ac = attrs.length;
			if (ac > 0) {
				fmt0 = attrs[0].format;
				off0 = attrs[0].offset;
				loc0 = attrs[0].shaderLocation;
			}
			if (ac > 1) {
				fmt1 = attrs[1].format;
				off1 = attrs[1].offset;
				loc1 = attrs[1].shaderLocation;
			}
			const handle = void_gpu_create_render_pipeline_1vb(
				this._handle, shaderHandle, vsEntry, fsEntry,
				buf.arrayStride, ac as uint32,
				fmt0, off0, loc0,
				fmt1, off1, loc1
			);
			return new GPURenderPipeline(handle);
		}

		const handle = void_gpu_create_render_pipeline(
			this._handle,
			shaderHandle,
			vsEntry,
			fsEntry
		);
		return new GPURenderPipeline(handle);
	}

	createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer {
		const handle = void_gpu_create_buffer(
			this._handle, descriptor.size, descriptor.usage,
			descriptor.mappedAtCreation
		);
		return new GPUBuffer(handle);
	}

	createBindGroupLayout1Buf(binding: uint32, visibility: uint32, minBindingSize: uint64): GPUBindGroupLayout {
		const handle = void_gpu_create_bind_group_layout_1buf(
			this._handle, binding, visibility, minBindingSize);
		return new GPUBindGroupLayout(handle);
	}

	createBindGroup1Buf(layout: GPUBindGroupLayout, binding: uint32, buffer: GPUBuffer, offset: uint64, size: uint64): GPUBindGroup {
		const handle = void_gpu_create_bind_group_1buf(
			this._handle, layout._handle, binding, buffer._handle, offset, size);
		return new GPUBindGroup(handle);
	}

	createPipelineLayout1BG(bindGroupLayout: GPUBindGroupLayout): GPUPipelineLayout {
		const handle = void_gpu_create_pipeline_layout_1bg(this._handle, bindGroupLayout._handle);
		return new GPUPipelineLayout(handle);
	}

	createDepthTexture(width: uint32, height: uint32): GPUTexture {
		const handle = void_gpu_create_depth_texture(this._handle, width, height);
		return new GPUTexture(handle, 0);
	}

	createTexture(width: uint32, height: uint32, format: uint32, usage: uint32, mipLevelCount: uint32): GPUTexture {
		const handle = void_gpu_create_texture(this._handle, width, height, format, usage, mipLevelCount);
		return new GPUTexture(handle, 0);
	}

	createSampler(addressMode: uint32, magFilter: uint32, minFilter: uint32): GPUSampler {
		const handle = void_gpu_create_sampler(this._handle, addressMode, magFilter, minFilter);
		return new GPUSampler(handle);
	}

	createBindGroupLayout1Tex1Samp(texBinding: uint32, texVisibility: uint32, sampBinding: uint32, sampVisibility: uint32): GPUBindGroupLayout {
		const handle = void_gpu_create_bind_group_layout_1tex_1samp(
			this._handle, texBinding, texVisibility, sampBinding, sampVisibility);
		return new GPUBindGroupLayout(handle);
	}

	createBindGroup1Tex1Samp(layout: GPUBindGroupLayout, texBinding: uint32, textureView: GPUTextureView, sampBinding: uint32, sampler: GPUSampler): GPUBindGroup {
		const handle = void_gpu_create_bind_group_1tex_1samp(
			this._handle, layout._handle, texBinding, textureView._handle, sampBinding, sampler._handle);
		return new GPUBindGroup(handle);
	}

	createPipelineLayout2BG(bg0: GPUBindGroupLayout, bg1: GPUBindGroupLayout): GPUPipelineLayout {
		const handle = void_gpu_create_pipeline_layout_2bg(this._handle, bg0._handle, bg1._handle);
		return new GPUPipelineLayout(handle);
	}

	createRenderPipelineExt2(
		shader: GPUShaderModule, vsEntry: string, fsEntry: string,
		pipelineLayout: GPUPipelineLayout,
		stride: uint64, attrCount: uint32,
		fmt0: uint32, off0: uint64, loc0: uint32,
		fmt1: uint32, off1: uint64, loc1: uint32,
		fmt2: uint32, off2: uint64, loc2: uint32,
		hasDepth: int32, cullMode: uint32,
		hasBlend: int32,
		blendColorSrc: uint32, blendColorDst: uint32, blendColorOp: uint32,
		blendAlphaSrc: uint32, blendAlphaDst: uint32, blendAlphaOp: uint32
	): GPURenderPipeline {
		const handle = void_gpu_create_render_pipeline_ext2(
			this._handle, shader._handle, vsEntry, fsEntry,
			pipelineLayout._handle,
			stride, attrCount,
			fmt0, off0, loc0,
			fmt1, off1, loc1,
			fmt2, off2, loc2,
			hasDepth, cullMode,
			hasBlend,
			blendColorSrc, blendColorDst, blendColorOp,
			blendAlphaSrc, blendAlphaDst, blendAlphaOp
		);
		return new GPURenderPipeline(handle);
	}

	createRenderPipelineExt(
		shader: GPUShaderModule, vsEntry: string, fsEntry: string,
		pipelineLayout: GPUPipelineLayout,
		stride: uint64, attrCount: uint32,
		fmt0: uint32, off0: uint64, loc0: uint32,
		fmt1: uint32, off1: uint64, loc1: uint32,
		hasDepth: int32, cullMode: uint32
	): GPURenderPipeline {
		const handle = void_gpu_create_render_pipeline_ext(
			this._handle, shader._handle, vsEntry, fsEntry,
			pipelineLayout._handle,
			stride, attrCount,
			fmt0, off0, loc0,
			fmt1, off1, loc1,
			hasDepth, cullMode
		);
		return new GPURenderPipeline(handle);
	}

	createCommandEncoder(): GPUCommandEncoder {
		const handle = void_gpu_create_command_encoder(this._handle);
		return new GPUCommandEncoder(handle);
	}

	release(): void {
		void_gpu_release_queue(this._queueHandle);
		void_gpu_release_device(this._handle);
	}
}

// --- GPUAdapter ---

export class GPUAdapter {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	requestDevice(): GPUDevice {
		const deviceHandle = void_gpu_request_device(this._handle);
		const queueHandle = void_gpu_get_queue(deviceHandle);
		return new GPUDevice(deviceHandle, queueHandle);
	}

	release(): void {
		void_gpu_release_adapter(this._handle);
	}
}

// --- GPUCanvasContext ---

export class GPUCanvasContext {
	_surfaceHandle: unknown;

	constructor(surfaceHandle: unknown) {
		this._surfaceHandle = surfaceHandle;
	}

	configure(config: GPUCanvasConfiguration): void {
		const dev = config.device as GPUDevice;
		void_gpu_configure_surface(this._surfaceHandle, dev._handle, config.width, config.height);
	}

	getCurrentTexture(): GPUTexture {
		const handle = void_gpu_get_current_texture_view(this._surfaceHandle);
		return new GPUTexture(handle, 1);
	}

	present(): void {
		void_gpu_present(this._surfaceHandle);
	}

	release(): void {
		void_gpu_release_surface(this._surfaceHandle);
	}
}

// --- GPUInstance (entry point) ---

export class GPUInstance {
	_handle: unknown;

	constructor(handle: unknown) {
		this._handle = handle;
	}

	createSurface(window: unknown): GPUCanvasContext {
		const surfaceHandle = void_gpu_create_surface(this._handle, window);
		return new GPUCanvasContext(surfaceHandle);
	}

	requestAdapter(surface: GPUCanvasContext): GPUAdapter {
		const adapterHandle = void_gpu_request_adapter(this._handle, surface._surfaceHandle);
		return new GPUAdapter(adapterHandle);
	}

	release(): void {
		void_gpu_release_instance(this._handle);
	}
}

export function createGPUInstance(): GPUInstance {
	const handle = void_gpu_create_instance();
	return new GPUInstance(handle);
}

export function genCheckerboard(dest: unknown, size: uint32, r1: uint32, g1: uint32, b1: uint32, r2: uint32, g2: uint32, b2: uint32): void {
	void_gen_checkerboard(dest, size, r1, g1, b1, r2, g2, b2);
}
