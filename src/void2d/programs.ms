// void2d's programs and their vertex layouts registered with the door, in the order
// Program2D numbers them (displayList.ms): vertex, sprite, ui, blur. Locations are shdc's
// ATTR_* slots of shader2d.glsl.
import { DoorAttribute, doorLayout, doorRegisterLayouts, doorRegisterPrograms } from "../gpu/doorGpu.ms";
import { blurShaderModule, spriteShaderModule, uiShaderModule, void2dShaderModule } from "./shader2dModules.ms";
import { SPRITE_FORMATS, UI_FORMATS } from "./instanceLayout.ms";
import { GPUShaderModuleDescriptor, GPUVertexFormat } from "../webgpu/types.ms";

const VERTEX: DoorAttribute[3] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
	{ location: 2, format: "float32x4", buffer: 0 },
];

// The corner at location 0, then the instance lanes scripts/instanceLayout.ms generates, in order.
function instanced(formats: Readonly<Span<GPUVertexFormat>>): DoorAttribute[] {
	const attributes: DoorAttribute[] = [{ location: 0, format: "float32x2", buffer: 0 }];
	for (let i = 0; i < formats.length; i++) {
		attributes.push({ location: (i + 1) as int32, format: formats[i], buffer: 1 });
	}
	return attributes;
}

const BLUR: DoorAttribute[2] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
];

export const layoutBase: int32 = doorRegisterLayouts([
	doorLayout(VERTEX, ["vertex"]),
	doorLayout(instanced(SPRITE_FORMATS), ["vertex", "instance"]),
	doorLayout(instanced(UI_FORMATS), ["vertex", "instance"]),
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
