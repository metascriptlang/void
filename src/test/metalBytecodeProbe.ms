import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";
import { metalSystemDevice } from "./metalDevice.h";

@compile("./metalDevice.m");

const VERTEX_MSL = "#include <metal_stdlib>\nusing namespace metal;\nstruct Out { float4 position [[position]]; };\nvertex Out vmain() { Out out; out.position = float4(0.0, 0.0, 0.0, 1.0); return out; }\n";
const FRAGMENT_MSL = "#include <metal_stdlib>\nusing namespace metal;\nfragment float4 fmain() { return float4(1.0); }\n";

const device = requestDevice({ device: metalSystemDevice(), context: null, colorFormat: "rgba8unorm", depthFormat: "depth32float", sampleCount: 1 });
let shader: GPUShaderModuleDescriptor = { label: "control", vertexCode: VERTEX_MSL, vertexEntryPoint: "vmain", fragmentCode: FRAGMENT_MSL, fragmentEntryPoint: "fmain" };
device.createShaderModule(shader);
console.log("probe: the control module loaded");
shader.label = "garbage";
shader.fragmentBytecode = [0x4d, 0x54, 0x4c, 0x42, 1, 2, 3, 4] as Vec<uint8>;
device.createShaderModule(shader);
console.log("probe: the corrupted module loaded");
