// What a shader function is written against, named as TypeGPU names it (docs/VOCABULARY.md) and
// meaning on the CPU what the GPU computes. The glsl macro (./emit.ms) knows a call into this
// module by the module, and emits it under the GLSL spelling of the declaration's name.

import { Wrap } from "../gpu/state";

export struct Vec2f {
	x: float32;
	y: float32;
}

export struct Vec3f {
	x: float32;
	y: float32;
	z: float32;
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
	get r(): float32 { return this.x; }
	get g(): float32 { return this.y; }
	get b(): float32 { return this.z; }
}

export struct Vec4f {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
	get zw(): Vec2f { return { x: this.z, y: this.w }; }
	get xyz(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get rgb(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get r(): float32 { return this.x; }
	get g(): float32 { return this.y; }
	get b(): float32 { return this.z; }
	get a(): float32 { return this.w; }
}

export struct Vec2i {
	x: int32;
	y: int32;
}

export struct Mat2x2f {
	columns: Vec2f[2];
}

export struct Mat3x3f {
	columns: Vec3f[3];
}

export struct Mat4x4f {
	columns: Vec4f[4];
}

export function vec2f(x: float32, y: float32): Vec2f { return { x, y }; }
export function vec2f(v: Vec2i): Vec2f { return { x: v.x as float32, y: v.y as float32 }; }
export function vec3f(x: float32, y: float32, z: float32): Vec3f { return { x, y, z }; }
export function vec3f(s: float32): Vec3f { return { x: s, y: s, z: s }; }
export function vec4f(x: float32, y: float32, z: float32, w: float32): Vec4f {
	return { x, y, z, w };
}
export function vec4f(s: float32): Vec4f { return { x: s, y: s, z: s, w: s }; }
export function vec4f(v: Vec3f, w: float32): Vec4f { return { x: v.x, y: v.y, z: v.z, w }; }
export function vec2i(x: int32, y: int32): Vec2i { return { x, y }; }
export function vec2i(v: Vec2f): Vec2i { return { x: v.x as int32, y: v.y as int32 }; }

export function mat2x2f(c0: Vec2f, c1: Vec2f): Mat2x2f { return { columns: [c0, c1] }; }
export function mat3x3f(c0: Vec3f, c1: Vec3f, c2: Vec3f): Mat3x3f {
	return { columns: [c0, c1, c2] };
}
export function mat4x4f(c0: Vec4f, c1: Vec4f, c2: Vec4f, c3: Vec4f): Mat4x4f {
	return { columns: [c0, c1, c2, c3] };
}

// GLSL's mat3(m): WGSL has no constructor from a wider matrix, so the name is Void's.
export function upperLeft3x3(m: Mat4x4f): Mat3x3f {
	return mat3x3f(m.columns[0].xyz, m.columns[1].xyz, m.columns[2].xyz);
}

export function `+`(this a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
}
export function `-`(this a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}
export function `*`(this a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.x * b.x, y: a.y * b.y, z: a.z * b.z };
}
export function `/`(this a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.x / b.x, y: a.y / b.y, z: a.z / b.z };
}
export function `+`(this a: Vec3f, s: float32): Vec3f {
	return { x: a.x + s, y: a.y + s, z: a.z + s };
}
export function `-`(this a: Vec3f, s: float32): Vec3f {
	return { x: a.x - s, y: a.y - s, z: a.z - s };
}
export function `*`(this a: Vec3f, s: float32): Vec3f {
	return { x: a.x * s, y: a.y * s, z: a.z * s };
}
export function `/`(this a: Vec3f, s: float32): Vec3f {
	return { x: a.x / s, y: a.y / s, z: a.z / s };
}
export function `*`(this s: float32, a: Vec3f): Vec3f { return a * s; }
export function `-`(this a: Vec3f): Vec3f { return { x: -a.x, y: -a.y, z: -a.z }; }
export function `+`(this a: Vec2f, b: Vec2f): Vec2f { return { x: a.x + b.x, y: a.y + b.y }; }
export function `*`(this a: Vec2f, b: Vec2f): Vec2f { return { x: a.x * b.x, y: a.y * b.y }; }
export function `*`(this a: Vec2f, s: float32): Vec2f { return { x: a.x * s, y: a.y * s }; }
export function `-`(this a: Vec2i, b: Vec2i): Vec2i { return { x: a.x - b.x, y: a.y - b.y }; }

export function `*`(this m: Mat2x2f, v: Vec2f): Vec2f {
	return m.columns[0] * v.x + m.columns[1] * v.y;
}
export function `*`(this m: Mat3x3f, v: Vec3f): Vec3f {
	return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z;
}
export function `*`(this m: Mat4x4f, v: Vec4f): Vec4f {
	const c = m.columns;
	return {
		x: c[0].x * v.x + c[1].x * v.y + c[2].x * v.z + c[3].x * v.w,
		y: c[0].y * v.x + c[1].y * v.y + c[2].y * v.z + c[3].y * v.w,
		z: c[0].z * v.x + c[1].z * v.y + c[2].z * v.z + c[3].z * v.w,
		w: c[0].w * v.x + c[1].w * v.y + c[2].w * v.z + c[3].w * v.w,
	};
}
export function `*`(this a: Mat4x4f, b: Mat4x4f): Mat4x4f {
	const c = b.columns;
	return mat4x4f(a * c[0], a * c[1], a * c[2], a * c[3]);
}

export function max(a: float32, b: float32): float32 { return a < b ? b : a; }
export function max(a: Vec3f, b: Vec3f): Vec3f {
	return { x: max(a.x, b.x), y: max(a.y, b.y), z: max(a.z, b.z) };
}
export function min(a: float32, b: float32): float32 { return b < a ? b : a; }
export function min(a: Vec3f, b: Vec3f): Vec3f {
	return { x: min(a.x, b.x), y: min(a.y, b.y), z: min(a.z, b.z) };
}

export function clamp(v: float32, low: float32, high: float32): float32 {
	return min(max(v, low), high);
}
export function clamp(v: Vec3f, low: Vec3f, high: Vec3f): Vec3f { return min(max(v, low), high); }
export function clamp(v: Vec2i, low: Vec2i, high: Vec2i): Vec2i {
	return {
		x: Math.min(Math.max(v.x, low.x), high.x),
		y: Math.min(Math.max(v.y, low.y), high.y),
	};
}

export function mix(a: float32, b: float32, t: float32): float32 { return a * (1.0 - t) + b * t; }
export function mix(a: Vec3f, b: Vec3f, t: float32): Vec3f { return a * (1.0 - t) + b * t; }

export function pow(base: float32, exponent: float32): float32 {
	if (base < 0.0 || (base == 0.0 && exponent <= 0.0)) {
		unreachable "pow: the GPU result is undefined for a negative base, or 0 to a power <= 0";
	}
	return Math.pow(base, exponent) as float32;
}
export function pow(base: Vec3f, exponent: Vec3f): Vec3f {
	return {
		x: pow(base.x, exponent.x),
		y: pow(base.y, exponent.y),
		z: pow(base.z, exponent.z),
	};
}

export function dot(a: Vec3f, b: Vec3f): float32 { return a.x * b.x + a.y * b.y + a.z * b.z; }
export function cross(a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}
export function length(v: Vec3f): float32 { return Math.sqrt(dot(v, v)) as float32; }
export function normalize(v: Vec3f): Vec3f { return v / length(v); }

// WGSL's operand order: the value when false comes first.
export function select(f: float32, t: float32, cond: boolean): float32 { return cond ? t : f; }
export function select(f: Vec3f, t: Vec3f, cond: boolean): Vec3f { return cond ? t : f; }

// Field decorators of a stage's structs, named as WGSL names its attributes: `@builtin(position)`,
// `@location(1)` on an output, `@binding(3)` on a binding. `@sampleType` and `@samplerType` give
// a texture or sampler the binding type WebGPU's layout needs (`unfilterable_float`,
// `nonfiltering`). `@feature(CUTOUT)` marks a boolean as the program key feature of that name.
// `@access(read_write)` lets a compute entry write a storage buffer or texture (WGSL's access
// mode), and `@format(rgba8unorm)` is a storage texture's texel format.
export function builtin(): void {}
export function location(): void {}
export function binding(): void {}
export function sampleType(): void {}
export function samplerType(): void {}
export function feature(): void {}
export function access(): void {}
export function format(): void {}

// WGSL's discard: the fragment writes nothing. Like TypeGPU's, it has no CPU meaning.
export function discard(): never {
	unreachable "discard: a fragment is discarded only on the GPU";
}

export struct Texture2d {
	width: int32;
	height: int32;
	texels: float32[];
}

// The sampler a void3d texture is drawn with (src/gpu/door.c doorMakeSampler): one filter for
// magnifying and minifying, one wrap for both axes, no mip levels.
export struct Sampler {
	nearest: boolean;
	wrap: Wrap;
}

// WGSL's textureDimensions and textureLoad take no sampler. These do: sokol-shdc cannot fetch
// without one (src/shader/CLAUDE.md, "shdc's own limits"). The size is signed, as the texel
// coordinate it bounds is (docs/VOCABULARY.md, "A name brings its meaning").
// WGSL's texture_storage_2d: a compute entry writes it texel by texel (textureStore). Its texel
// format is the binding's @format, so on the CPU it holds four floats per texel like Texture2d.
export struct StorageTexture2d {
	width: int32;
	height: int32;
	texels: float32[];
}

export function textureDimensions(texture: StorageTexture2d): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(texture: StorageTexture2d, at: Vec2i, value: Vec4f): void {
	if (at.x < 0 || at.y < 0 || at.x >= texture.width || at.y >= texture.height) {
		unreachable "textureStore: the texel is outside the texture";
	}
	const first = (at.y * texture.width + at.x) * 4;
	texture.texels[first] = value.x;
	texture.texels[first + 1] = value.y;
	texture.texels[first + 2] = value.z;
	texture.texels[first + 3] = value.w;
}

export function textureDimensions(texture: Texture2d, sampler: Sampler, level: int32): Vec2i {
	if (level != 0) { unreachable "textureDimensions: the CPU texture has no mip levels"; }
	return { x: texture.width, y: texture.height };
}

export function textureLoad(texture: Texture2d, sampler: Sampler, at: Vec2i, level: int32): Vec4f {
	if (level != 0) { unreachable "textureLoad: the CPU texture has no mip levels"; }
	if (at.x < 0 || at.y < 0 || at.x >= texture.width || at.y >= texture.height) {
		unreachable "textureLoad: the texel is outside the texture";
	}
	return texelAt(texture, at.x, at.y);
}

function texelAt(texture: Texture2d, x: int32, y: int32): Vec4f {
	const first = (y * texture.width + x) * 4;
	const t = texture.texels;
	return { x: t[first], y: t[first + 1], z: t[first + 2], w: t[first + 3] };
}

// The Vulkan specification's "Wrapping Operation", on a texel index.
function wrapped(i: int32, size: int32, wrap: Wrap): int32 {
	return match (wrap) {
		Wrap.Clamp => Math.min(Math.max(i, 0), size - 1),
		Wrap.Repeat => (i % size + size) % size,
		Wrap.Mirror => mirrored((i % (2 * size) + 2 * size) % (2 * size) - size, size),
	};
}

function mirrored(a: int32, size: int32): int32 { return size - 1 - (a >= 0 ? a : -(1 + a)); }

function texelIndex(at: float32): int32 {
	const i = Math.floor(at);
	if (!(Math.abs(i) < 1.0e9)) {
		unreachable "textureSample: the coordinate is not finite, or past any texel index";
	}
	return i as int32;
}

function lerp(a: Vec4f, b: Vec4f, t: float32): Vec4f {
	return {
		x: a.x + (b.x - a.x) * t,
		y: a.y + (b.y - a.y) * t,
		z: a.z + (b.z - a.z) * t,
		w: a.w + (b.w - a.w) * t,
	};
}

// WGSL's textureSample on a texture of one mip level, as void3d's are.
export function textureSample(texture: Texture2d, sampler: Sampler, uv: Vec2f): Vec4f {
	const w = texture.width;
	const h = texture.height;
	const wrap = sampler.wrap;
	if (sampler.nearest) {
		const x = wrapped(texelIndex(uv.x * (w as float32)), w, wrap);
		return texelAt(texture, x, wrapped(texelIndex(uv.y * (h as float32)), h, wrap));
	}
	const u: float32 = uv.x * (w as float32) - 0.5;
	const v: float32 = uv.y * (h as float32) - 0.5;
	const i = texelIndex(u);
	const j = texelIndex(v);
	const x0 = wrapped(i, w, wrap);
	const x1 = wrapped(i + 1, w, wrap);
	const y0 = wrapped(j, h, wrap);
	const y1 = wrapped(j + 1, h, wrap);
	const a: float32 = u - (i as float32);
	const b: float32 = v - (j as float32);
	const top = lerp(texelAt(texture, x0, y0), texelAt(texture, x1, y0), a);
	return lerp(top, lerp(texelAt(texture, x0, y1), texelAt(texture, x1, y1), a), b);
}
