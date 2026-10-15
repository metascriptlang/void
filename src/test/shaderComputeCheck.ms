// Compute entries: shady's compute1 example (examples/compute1.nim) as a WGSL-style compute stage,
// a storage buffer read and a storage texture written, run on the CPU and pinned as GLSL.

import { glslCompute } from "../shader/emit";
import {
	StorageTexture2d,
	Vec3u,
	access,
	binding,
	builtin,
	format,
	textureDimensions,
	textureStore,
	vec2i,
	vec4f,
} from "../shader/std";

export struct CommandInput {
	@builtin(globalInvocationId) id: Vec3u;
}

// shdc's storage buffer is one flexible array of structs.
export struct Command {
	value: float32;
}

export struct CommandBindings {
	@binding(0) commands: Command[];
	@binding(1) @format(rgba8unorm) @access(write) image: StorageTexture2d;
}

// One invocation per row: each command becomes a pixel's blue channel, as compute1 writes it.
export function commandsToImage(input: CommandInput, b: CommandBindings): void {
	const size = textureDimensions(b.image);
	const y = vec2i(input.id.xy).y;
	for (let x = 0; x < size.x; x++) {
		const value = b.commands[x].value;
		textureStore(b.image, vec2i(x, y), vec4f(0.5, 0.0, value / 255.0, 1.0));
	}
}

test "a compute entry reads the storage buffer and writes each texel of its row" {
	let texels: float32[] = [];
	for (let i = 0; i < 4 * 4 * 2; i++) { texels.push(0.0); }
	const image: StorageTexture2d = { width: 4, height: 2, texels };
	const commands: Command[] = [
		{ value: 0.0 },
		{ value: 51.0 },
		{ value: 102.0 },
		{ value: 255.0 },
	];
	const b: CommandBindings = { commands, image };
	commandsToImage({ id: { x: 0, y: 1, z: 0 } }, b);
	const second = (1 * 4 + 1) * 4;
	assert image.texels[second] == 0.5 && image.texels[second + 2] == 0.2;
	assert image.texels[(1 * 4 + 3) * 4 + 2] == 1.0 && image.texels[2] == 0.0;
}

test "a compute entry is emitted with its workgroup size, storage buffer and storage texture" {
	assert glslCompute(commandsToImage, [32, 1, 1]) ==
		"layout(local_size_x=32, local_size_y=1, local_size_z=1) in;\n" +
		"struct Command {\n" +
		"    float value;\n" +
		"};\n" +
		"layout(binding=0) readonly buffer commandsBuffer {\n" +
		"    Command commands[];\n" +
		"};\n" +
		"layout(binding=1, rgba8) uniform writeonly image2D image;\n" +
		"void main() {\n" +
		"    ivec2 size = imageSize(image);\n" +
		"    int y = ivec2(gl_GlobalInvocationID.xy).y;\n" +
		"    for (int x = 0; x < size.x; x++) {\n" +
		"        float value = commands[x].value;\n" +
		"        imageStore(image, ivec2(x, y), vec4(0.5, 0.0, (value / 255.0), 1.0));\n" +
		"    }\n" +
		"}\n";
}
