// void2d's programs and their vertex layouts registered with the door, in the order
// Program2D numbers them (displayList.ms): vertex, sprite, ui, blur. Locations are shdc's
// ATTR_* slots of shader2d.glsl.
import { DoorAttribute, doorLayout, doorRegisterLayouts, doorRegisterPrograms } from "../gpu/doorGpu.ms";
import { blurShaderModule, spriteShaderModule, uiShaderModule, void2dShaderModule } from "./shader2dModules.ms";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";

const VERTEX: DoorAttribute[3] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
	{ location: 2, format: "float32x4", buffer: 0 },
];

const SPRITE: DoorAttribute[5] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x4", buffer: 1 },
	{ location: 2, format: "float32x4", buffer: 1 },
	{ location: 3, format: "float32x4", buffer: 1 },
	{ location: 4, format: "float32x4", buffer: 1 },
];

const UI: DoorAttribute[10] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x4", buffer: 1 },
	{ location: 2, format: "float32x4", buffer: 1 },
	{ location: 3, format: "float32x4", buffer: 1 },
	{ location: 4, format: "float32x4", buffer: 1 },
	{ location: 5, format: "float32x4", buffer: 1 },
	{ location: 6, format: "float32x4", buffer: 1 },
	{ location: 7, format: "unorm8x4", buffer: 1 },
	{ location: 8, format: "unorm8x4", buffer: 1 },
	{ location: 9, format: "unorm8x4", buffer: 1 },
];

const BLUR: DoorAttribute[2] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
];

export const layoutBase: int32 = doorRegisterLayouts([
	doorLayout(VERTEX, ["vertex"]),
	doorLayout(SPRITE, ["vertex", "instance"]),
	doorLayout(UI, ["vertex", "instance"]),
	doorLayout(BLUR, ["vertex"]),
]);

function void2dModule(index: int32): GPUShaderModuleDescriptor {
	if (index < 0 || index > 3) {
		console.error(`void2dModule: no program ${index}`);
		unreachable;
	}
	return match (index) {
		0 => void2dShaderModule(),
		1 => spriteShaderModule(),
		2 => uiShaderModule(),
		_ => blurShaderModule(), // 3
	};
}

export const programBase: int32 = doorRegisterPrograms(
	void2dModule,
	[layoutBase, layoutBase + 1, layoutBase + 2, layoutBase + 3],
);
