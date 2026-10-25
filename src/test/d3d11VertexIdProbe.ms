import { GPUBufferUsage, GPUDevice, GPURenderPipeline, GPURenderPipelineDescriptor, GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { nativeTexture } from "../webgpu/d3d11/backend.ms";
import { GREEN, SIZE, clearingPass, colourTarget, pixel } from "./webgpuFixtures.ms";
import { warpContext, warpDevice, warpReadback } from "./d3d11Warp.h";

@passL("-ld3d11");

// Each vertex is a point in the top row at the column of its SV_VertexID, so the lit column
// says whether the id counts from StartVertexLocation or BaseVertexLocation.
const POINT_HLSL = "float4 vmain(uint v : SV_VertexID) : SV_Position { return float4((float(v) + 0.5) * 2.0 / 64.0 - 1.0, 1.0 - 1.0 / 64.0, 0.0, 1.0); }\nfloat4 fmain() : SV_Target0 { return float4(0.0, 1.0, 0.0, 1.0); }";
const START = 3;
const BASE = 5;

const native = warpDevice();
if (native == null) {
	console.log("d3d11VertexIdProbe: D3D11CreateDevice with D3D_DRIVER_TYPE_WARP failed");
	unreachable;
}
const device = requestDevice({ device: native, context: warpContext(), colorFormat: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 });
let shader: GPUShaderModuleDescriptor = { label: "point", vertexCode: POINT_HLSL, vertexEntryPoint: "vmain", fragmentCode: POINT_HLSL, fragmentEntryPoint: "fmain" };
const module = device.createShaderModule(shader);
let descriptor: GPURenderPipelineDescriptor = { label: "point" };
descriptor.vertex.module = module;
descriptor.fragment.module = module;
descriptor.fragment.targets[0].format = "rgba8unorm";
descriptor.primitive.topology = "point-list";
const pipeline: GPURenderPipeline = device.createRenderPipeline(descriptor);
const indices = device.createBuffer({ label: "indices", size: 4, usage: (GPUBufferUsage.INDEX as int32) | (GPUBufferUsage.COPY_DST as int32) });
device.queue.writeBuffer(indices, 0, [0, 0] as Vec<uint16>);

function litColumns(dev: GPUDevice, indexed: boolean): string {
	const target = colourTarget(dev, 1);
	const encoder = dev.createCommandEncoder();
	const pass = encoder.beginRenderPass(clearingPass(target.createView({ label: null }), { id: 0 }));
	pass.setPipeline(pipeline);
	if (indexed) {
		pass.setIndexBuffer(indices, "uint16", 0);
		pass.drawIndexed(1, 1, 0, BASE, 0);
	} else {
		pass.draw(1, 1, START, 0);
	}
	pass.end();
	dev.queue.submit(encoder.finish());
	let pixels: Vec<uint8> = new Array(SIZE * SIZE * 4);
	if (warpReadback(nativeTexture(target), pixels[0], SIZE, SIZE) != 1) {
		console.log("d3d11VertexIdProbe: the staging readback failed");
		unreachable;
	}
	let lit = "";
	for (let x = 0; x < 8; x++) {
		if (pixel(pixels, x, 0) == GREEN) { lit += ` ${x}`; }
	}
	return lit;
}

console.log(`draw firstVertex ${START}: lit columns${litColumns(device, false)}`);
console.log(`drawIndexed index 0 baseVertex ${BASE}: lit columns${litColumns(device, true)}`);
