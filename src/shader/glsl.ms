// The GLSL surface a shader function is written against, with the meaning GLSL gives it, so the
// same function runs on the CPU. The glsl macro (./emit.ms) emits a call to anything declared here
// under the declaration's own name.

export struct Vec2 {
	x: float32;
	y: float32;
}

export struct Vec3 {
	x: float32;
	y: float32;
	z: float32;
	get xy(): Vec2 { return { x: this.x, y: this.y }; }
}

export struct Vec4 {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
	get xy(): Vec2 { return { x: this.x, y: this.y }; }
	get xyz(): Vec3 { return { x: this.x, y: this.y, z: this.z }; }
	get rgb(): Vec3 { return { x: this.x, y: this.y, z: this.z }; }
}

export struct IVec2 {
	x: int32;
	y: int32;
}

export function vec2(x: float32, y: float32): Vec2 { return { x, y }; }
export function vec3(x: float32, y: float32, z: float32): Vec3 { return { x, y, z }; }
export function vec4(x: float32, y: float32, z: float32, w: float32): Vec4 { return { x, y, z, w }; }
export function vec4(v: Vec3, w: float32): Vec4 { return { x: v.x, y: v.y, z: v.z, w }; }
export function ivec2(x: int32, y: int32): IVec2 { return { x, y }; }
export function ivec2(v: Vec2): IVec2 { return { x: v.x as int32, y: v.y as int32 }; }

export function `+`(this a: IVec2, b: IVec2): IVec2 { return { x: a.x + b.x, y: a.y + b.y }; }
export function `-`(this a: IVec2, b: IVec2): IVec2 { return { x: a.x - b.x, y: a.y - b.y }; }

export function clamp(v: int32, low: int32, high: int32): int32 { return Math.min(Math.max(v, low), high); }
export function clamp(v: IVec2, low: IVec2, high: IVec2): IVec2 {
	return { x: clamp(v.x, low.x, high.x), y: clamp(v.y, low.y, high.y) };
}

// gl_FragCoord, taken as an entry parameter so a CPU caller hands it in like any other input.
export struct FragCoord {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
	get xy(): Vec2 { return { x: this.x, y: this.y }; }
}

// RGBA texels, row 0 first: texelFetch's (x, y) is texels[(y * width + x) * 4].
export struct Texture2D {
	width: int32;
	height: int32;
	texels: float32[];
}

export struct Sampler {
	nearest: boolean;
}

export struct Sampler2D {
	texture: Texture2D;
	sampler: Sampler;
}

export function sampler2D(texture: Texture2D, sampler: Sampler): Sampler2D { return { texture, sampler }; }

export function textureSize(s: Sampler2D, lod: int32): IVec2 {
	if (lod != 0) { unreachable "textureSize: the CPU texture has no mip levels"; }
	return { x: s.texture.width, y: s.texture.height };
}

export function texelFetch(s: Sampler2D, p: IVec2, lod: int32): Vec4 {
	if (lod != 0) { unreachable "texelFetch: the CPU texture has no mip levels"; }
	if (p.x < 0 || p.y < 0 || p.x >= s.texture.width || p.y >= s.texture.height) {
		unreachable "texelFetch: the texel is outside the texture";
	}
	const at = (p.y * s.texture.width + p.x) * 4;
	const t = s.texture.texels;
	return { x: t[at], y: t[at + 1], z: t[at + 2], w: t[at + 3] };
}
