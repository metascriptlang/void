import { Vec2f, Vec4f, builtin, vec4f } from "../shader/std";
import { shaderModule } from "../shader/program";
import "../webgpu/device.ms";
import { openTestDevice } from "./testDevice.ms";

struct PointInput {
	position: Vec2f;
}

struct PointVarying {
	@builtin(position) position: Vec4f;
}

function pointVs(input: PointInput): PointVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function constantFs(): Vec4f {
	return vec4f(0.25, 0.5, 0.75, 1.0);
}

shaderModule(constant, pointVs, constantFs);

const device = openTestDevice();
device.createShaderModule(constantModule);
console.log("probe: the control module loaded");
let garbage = constantModule;
garbage.label = "garbage";
for (let i = 0; i < garbage.vertexBytecode.length; i++) { garbage.vertexBytecode[i] = (garbage.vertexBytecode[i] ^ 0xFF) as uint8; }
device.createShaderModule(garbage);
console.log("probe: the corrupted module loaded");
