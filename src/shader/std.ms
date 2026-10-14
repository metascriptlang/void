// What a shader function is written against, named as TypeGPU names it (docs/VOCABULARY.md) and
// meaning on the CPU what the GPU computes. The glsl macro (./emit.ms) knows a call into this
// module by the module, and emits it under the GLSL spelling of the declaration's name.

export struct Vec2f {
	x: float32;
	y: float32;
}

export struct Vec4f {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
}

export struct Vec2i {
	x: int32;
	y: int32;
}

export function vec2i(x: int32, y: int32): Vec2i { return { x, y }; }
export function vec2i(v: Vec2f): Vec2i { return { x: v.x as int32, y: v.y as int32 }; }

export function `-`(this a: Vec2i, b: Vec2i): Vec2i { return { x: a.x - b.x, y: a.y - b.y }; }

export function clamp(v: Vec2i, low: Vec2i, high: Vec2i): Vec2i {
	return {
		x: Math.min(Math.max(v.x, low.x), high.x),
		y: Math.min(Math.max(v.y, low.y), high.y),
	};
}

// Field decorators of a stage's structs, named as WGSL names its attributes: `@builtin(position)`,
// `@location(1)` on an output, `@binding(3)` on a binding. `@sampleType` and `@samplerType` give
// a texture or sampler the binding type WebGPU's layout needs (`unfilterable_float`,
// `nonfiltering`). `@feature(CUTOUT)` marks a boolean as the program key feature of that name.
export function builtin(): void {}
export function location(): void {}
export function binding(): void {}
export function sampleType(): void {}
export function samplerType(): void {}
export function feature(): void {}

export struct Texture2d {
	width: int32;
	height: int32;
	texels: float32[];
}

export struct Sampler {
	nearest: boolean;
}

// WGSL's textureDimensions and textureLoad take no sampler. These do: sokol-shdc cannot fetch
// without one (src/shader/CLAUDE.md, "shdc's own limits"). The size is signed, as the texel
// coordinate it bounds is (docs/VOCABULARY.md, "A name brings its meaning").
export function textureDimensions(texture: Texture2d, sampler: Sampler, level: int32): Vec2i {
	if (level != 0) { unreachable "textureDimensions: the CPU texture has no mip levels"; }
	return { x: texture.width, y: texture.height };
}

export function textureLoad(texture: Texture2d, sampler: Sampler, at: Vec2i, level: int32): Vec4f {
	if (level != 0) { unreachable "textureLoad: the CPU texture has no mip levels"; }
	if (at.x < 0 || at.y < 0 || at.x >= texture.width || at.y >= texture.height) {
		unreachable "textureLoad: the texel is outside the texture";
	}
	const first = (at.y * texture.width + at.x) * 4;
	const t = texture.texels;
	return { x: t[first], y: t[first + 1], z: t[first + 2], w: t[first + 3] };
}
