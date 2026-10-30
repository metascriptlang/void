// void2d's programs and their vertex layouts registered with the door, in the order
// Program2D numbers them (displayList.ms): vertex, sprite, ui, blur. Locations are the
// attribute locations shader2dModules.ms reflects.
import { DoorAttribute, doorLayout, doorRegisterLayouts, doorRegisterPrograms } from "../gpu/doorGpu.ms";
import { blurShaderModule, spriteShaderModule, uiShaderModule, void2dShaderModule } from "./shader2dModules.ms";
import {
	INSTANCE_CORNER_LOCATION, SPRITE_FORMATS, SPRITE_LOCATIONS, UI_FORMATS, UI_LOCATIONS,
} from "./instanceLayout.ms";
import { GPUShaderModuleDescriptor, GPUVertexFormat } from "../webgpu/types.ms";

const VERTEX: DoorAttribute[3] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
	{ location: 2, format: "float32x4", buffer: 0 },
];

// The corner, then the instance lanes scripts/instanceLayout.ms generates: formats and locations.
function instanced(
	formats: Readonly<Span<GPUVertexFormat>>,
	locations: Readonly<Span<int32>>,
): DoorAttribute[] {
	const attributes: DoorAttribute[] = [
		{ location: INSTANCE_CORNER_LOCATION, format: "float32x2", buffer: 0 },
	];
	for (let i = 0; i < formats.length; i++) {
		attributes.push({ location: locations[i], format: formats[i], buffer: 1 });
	}
	return attributes;
}

export function spriteAttributes(): DoorAttribute[] {
	return instanced(SPRITE_FORMATS, SPRITE_LOCATIONS);
}

export function uiAttributes(): DoorAttribute[] {
	return instanced(UI_FORMATS, UI_LOCATIONS);
}

const BLUR: DoorAttribute[2] = [
	{ location: 0, format: "float32x2", buffer: 0 },
	{ location: 1, format: "float32x2", buffer: 0 },
];

export const layoutBase: int32 = doorRegisterLayouts([
	doorLayout(VERTEX, ["vertex"]),
	doorLayout(spriteAttributes(), ["vertex", "instance"]),
	doorLayout(uiAttributes(), ["vertex", "instance"]),
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
