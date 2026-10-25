import { BindingKind, GPUBindGroupEntry } from "../webgpu/types";
import {
	EncoderState,
	PASS_COMPUTE,
	PASS_RENDER,
	addressesBinding,
	beginPassRefusal,
	createRefusal,
	endPassRefusal,
	finishRefusal,
	groupOfKind,
	inPassRefusal,
	markerRefusal,
	outsidePassRefusal,
	popGroupRefusal,
	pushGroupRefusal,
	shutdownRefusal,
	uniformEntryRefusal,
} from "../webgpu/validate";

function openEncoder(): EncoderState {
	let s: EncoderState = { open: false };
	s.createRefusal();
	return s;
}

function entryAt(offset: int64, size: int64): GPUBindGroupEntry {
	return { binding: 2, offset: offset, size: size };
}

test "a second command encoder is refused while the first is open and allowed after finish" {
	let s = openEncoder();
	assert s.createRefusal() == "createCommandEncoder with the frame's encoder not yet finished";
	assert s.finishRefusal() == "";
	assert s.createRefusal() == "";
}

test "a second encoder is refused with a pass or a debug group open on the first" {
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.createRefusal() != "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.pushGroupRefusal() == "";
	assert s.createRefusal() != "";
}

test "finish names what is still open and a missing encoder" {
	let none: EncoderState = { open: false };
	assert none.finishRefusal() == "finish without createCommandEncoder";
	let render = openEncoder();
	assert render.beginPassRefusal(PASS_RENDER) == "";
	assert render.finishRefusal() == "finish with a render pass still open";
	let compute = openEncoder();
	assert compute.beginPassRefusal(PASS_COMPUTE) == "";
	assert compute.finishRefusal() == "finish with a compute pass still open";
	let groups = openEncoder();
	assert groups.pushGroupRefusal() == "";
	assert groups.pushGroupRefusal() == "";
	assert groups.finishRefusal() == "finish with 2 debug groups still open";
}

test "a pass begins only on an open encoder with no pass open, for either kind" {
	let none: EncoderState = { open: false };
	assert none.beginPassRefusal(PASS_RENDER) == "beginRenderPass without createCommandEncoder";
	assert none.beginPassRefusal(PASS_COMPUTE) == "beginComputePass without createCommandEncoder";
	let s = openEncoder();
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_RENDER) == "beginRenderPass with a pass already open";
	assert s.beginPassRefusal(PASS_COMPUTE) == "beginComputePass with a pass already open";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
}

test "end names the pass kind it closes and the groups the pass left open" {
	let s = openEncoder();
	assert s.endPassRefusal(PASS_RENDER) == "end without an open render pass";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.endPassRefusal(PASS_RENDER) == "end without an open render pass";
	assert s.pushGroupRefusal() == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "end with 1 debug groups still open";
	assert s.popGroupRefusal() == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
}

test "a pass cannot pop a group the encoder pushed before it, and the encoder can after the pass" {
	let s = openEncoder();
	assert s.pushGroupRefusal() == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.popGroupRefusal() == "popDebugGroup without a matching pushDebugGroup";
	assert s.endPassRefusal(PASS_RENDER) == "";
	assert s.popGroupRefusal() == "";
	assert s.popGroupRefusal() == "popDebugGroup without a matching pushDebugGroup";
}

test "debug calls and copies need an open encoder, and copies need no open pass" {
	let none: EncoderState = { open: false };
	assert none.pushGroupRefusal() == "pushDebugGroup without createCommandEncoder";
	assert none.popGroupRefusal() == "popDebugGroup without createCommandEncoder";
	assert none.markerRefusal() == "insertDebugMarker without createCommandEncoder";
	assert none.outsidePassRefusal("copyBufferToBuffer") == "copyBufferToBuffer without createCommandEncoder";
	let s = openEncoder();
	assert s.outsidePassRefusal("resolveQuerySet") == "";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.outsidePassRefusal("resolveQuerySet") == "resolveQuerySet inside a pass";
	assert s.markerRefusal() == "";
}

test "a pass call is refused outside a pass of its kind, naming the call" {
	let s = openEncoder();
	assert s.inPassRefusal(PASS_RENDER, "draw") == "draw outside a render pass";
	assert s.beginPassRefusal(PASS_COMPUTE) == "";
	assert s.inPassRefusal(PASS_RENDER, "setViewport") == "setViewport outside a render pass";
	assert s.inPassRefusal(PASS_COMPUTE, "dispatchWorkgroups") == "";
	assert s.endPassRefusal(PASS_COMPUTE) == "";
	assert s.inPassRefusal(PASS_COMPUTE, "setPipeline") == "setPipeline outside a compute pass";
}

test "a device shuts down only with no pass open" {
	let s = openEncoder();
	assert s.shutdownRefusal() == "";
	assert s.beginPassRefusal(PASS_RENDER) == "";
	assert s.shutdownRefusal() == "shutdown with a render pass still open";
}

test "a bind group entry addresses only the bindings of its own group" {
	assert groupOfKind(BindingKind.Uniform) == 0;
	assert groupOfKind(BindingKind.StorageBuffer) == 1;
	assert addressesBinding(0, 3, 3, BindingKind.Uniform);
	assert !addressesBinding(1, 3, 3, BindingKind.Uniform);
	assert addressesBinding(1, 3, 3, BindingKind.StorageBuffer);
	assert !addressesBinding(0, 3, 3, BindingKind.StorageBuffer);
	assert addressesBinding(1, 3, 3, BindingKind.Texture);
	assert !addressesBinding(0, 3, 3, BindingKind.Sampler);
	assert !addressesBinding(0, 3, 4, BindingKind.Uniform);
}

test "a uniform entry is refused by usage, alignment, overrun and size below its block" {
	assert uniformEntryRefusal(entryAt(256, 0), true, 512, 64, 256) == "";
	assert uniformEntryRefusal(entryAt(256, 0), false, 512, 64, 256) == "bind group entry 2 needs a UNIFORM buffer";
	assert uniformEntryRefusal(entryAt(100, 0), true, 512, 64, 256) == "bind group entry 2 offset 100 is not a multiple of 256";
	assert uniformEntryRefusal(entryAt(512, 0), true, 512, 64, 256) == "bind group entry 2 offset 512 overruns its buffer";
	assert uniformEntryRefusal(entryAt(0, 16), true, 512, 64, 256) == "bind group entry 2 size 16 is below its block of 64";
	assert uniformEntryRefusal(entryAt(0, 16), true, 512, 64, 16) == "bind group entry 2 size 16 is below its block of 64";
}
