// What a shader function is written against, named as TypeGPU names it (docs/VOCABULARY.md) and
// meaning on the CPU what the GPU computes. The glsl macro (./emit.ms) knows a call into this
// module by the module, and emits it under the GLSL spelling of the declaration's name.

import { Wrap } from "../gpu/state";

export struct Vec2f {
	x: float32;
	y: float32;
	get xx(): Vec2f { return { x: this.x, y: this.x }; }
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
	get yx(): Vec2f { return { x: this.y, y: this.x }; }
	get yy(): Vec2f { return { x: this.y, y: this.y }; }
	get xxx(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get xxy(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get xyx(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get xyy(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get yxx(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get yxy(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get yyx(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get yyy(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get xxxx(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get xxxy(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get xxyx(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get xxyy(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get xyxx(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get xyxy(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get xyyx(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get xyyy(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get yxxx(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get yxxy(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get yxyx(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get yxyy(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get yyxx(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get yyxy(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get yyyx(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get yyyy(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
	get r(): float32 { return this.x; }
	get g(): float32 { return this.y; }
	get rr(): Vec2f { return { x: this.x, y: this.x }; }
	get rg(): Vec2f { return { x: this.x, y: this.y }; }
	get gr(): Vec2f { return { x: this.y, y: this.x }; }
	get gg(): Vec2f { return { x: this.y, y: this.y }; }
	get rrr(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get rrg(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get rgr(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get rgg(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get grr(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get grg(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get ggr(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get ggg(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get rrrr(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get rrrg(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get rrgr(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get rrgg(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get rgrr(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get rgrg(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get rggr(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get rggg(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get grrr(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get grrg(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get grgr(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get grgg(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get ggrr(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get ggrg(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get gggr(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get gggg(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
}

export struct Vec3f {
	x: float32;
	y: float32;
	z: float32;
	get xx(): Vec2f { return { x: this.x, y: this.x }; }
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
	get xz(): Vec2f { return { x: this.x, y: this.z }; }
	get yx(): Vec2f { return { x: this.y, y: this.x }; }
	get yy(): Vec2f { return { x: this.y, y: this.y }; }
	get yz(): Vec2f { return { x: this.y, y: this.z }; }
	get zx(): Vec2f { return { x: this.z, y: this.x }; }
	get zy(): Vec2f { return { x: this.z, y: this.y }; }
	get zz(): Vec2f { return { x: this.z, y: this.z }; }
	get xxx(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get xxy(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get xxz(): Vec3f { return { x: this.x, y: this.x, z: this.z }; }
	get xyx(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get xyy(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get xyz(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get xzx(): Vec3f { return { x: this.x, y: this.z, z: this.x }; }
	get xzy(): Vec3f { return { x: this.x, y: this.z, z: this.y }; }
	get xzz(): Vec3f { return { x: this.x, y: this.z, z: this.z }; }
	get yxx(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get yxy(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get yxz(): Vec3f { return { x: this.y, y: this.x, z: this.z }; }
	get yyx(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get yyy(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get yyz(): Vec3f { return { x: this.y, y: this.y, z: this.z }; }
	get yzx(): Vec3f { return { x: this.y, y: this.z, z: this.x }; }
	get yzy(): Vec3f { return { x: this.y, y: this.z, z: this.y }; }
	get yzz(): Vec3f { return { x: this.y, y: this.z, z: this.z }; }
	get zxx(): Vec3f { return { x: this.z, y: this.x, z: this.x }; }
	get zxy(): Vec3f { return { x: this.z, y: this.x, z: this.y }; }
	get zxz(): Vec3f { return { x: this.z, y: this.x, z: this.z }; }
	get zyx(): Vec3f { return { x: this.z, y: this.y, z: this.x }; }
	get zyy(): Vec3f { return { x: this.z, y: this.y, z: this.y }; }
	get zyz(): Vec3f { return { x: this.z, y: this.y, z: this.z }; }
	get zzx(): Vec3f { return { x: this.z, y: this.z, z: this.x }; }
	get zzy(): Vec3f { return { x: this.z, y: this.z, z: this.y }; }
	get zzz(): Vec3f { return { x: this.z, y: this.z, z: this.z }; }
	get xxxx(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get xxxy(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get xxxz(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.z }; }
	get xxyx(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get xxyy(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get xxyz(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.z }; }
	get xxzx(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.x }; }
	get xxzy(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.y }; }
	get xxzz(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.z }; }
	get xyxx(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get xyxy(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get xyxz(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.z }; }
	get xyyx(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get xyyy(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get xyyz(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.z }; }
	get xyzx(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.x }; }
	get xyzy(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.y }; }
	get xyzz(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.z }; }
	get xzxx(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.x }; }
	get xzxy(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.y }; }
	get xzxz(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.z }; }
	get xzyx(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.x }; }
	get xzyy(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.y }; }
	get xzyz(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.z }; }
	get xzzx(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.x }; }
	get xzzy(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.y }; }
	get xzzz(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.z }; }
	get yxxx(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get yxxy(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get yxxz(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.z }; }
	get yxyx(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get yxyy(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get yxyz(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.z }; }
	get yxzx(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.x }; }
	get yxzy(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.y }; }
	get yxzz(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.z }; }
	get yyxx(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get yyxy(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get yyxz(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.z }; }
	get yyyx(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get yyyy(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
	get yyyz(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.z }; }
	get yyzx(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.x }; }
	get yyzy(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.y }; }
	get yyzz(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.z }; }
	get yzxx(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.x }; }
	get yzxy(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.y }; }
	get yzxz(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.z }; }
	get yzyx(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.x }; }
	get yzyy(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.y }; }
	get yzyz(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.z }; }
	get yzzx(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.x }; }
	get yzzy(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.y }; }
	get yzzz(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.z }; }
	get zxxx(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.x }; }
	get zxxy(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.y }; }
	get zxxz(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.z }; }
	get zxyx(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.x }; }
	get zxyy(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.y }; }
	get zxyz(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.z }; }
	get zxzx(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.x }; }
	get zxzy(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.y }; }
	get zxzz(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.z }; }
	get zyxx(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.x }; }
	get zyxy(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.y }; }
	get zyxz(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.z }; }
	get zyyx(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.x }; }
	get zyyy(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.y }; }
	get zyyz(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.z }; }
	get zyzx(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.x }; }
	get zyzy(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.y }; }
	get zyzz(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.z }; }
	get zzxx(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.x }; }
	get zzxy(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.y }; }
	get zzxz(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.z }; }
	get zzyx(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.x }; }
	get zzyy(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.y }; }
	get zzyz(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.z }; }
	get zzzx(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.x }; }
	get zzzy(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.y }; }
	get zzzz(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.z }; }
	get r(): float32 { return this.x; }
	get g(): float32 { return this.y; }
	get b(): float32 { return this.z; }
	get rr(): Vec2f { return { x: this.x, y: this.x }; }
	get rg(): Vec2f { return { x: this.x, y: this.y }; }
	get rb(): Vec2f { return { x: this.x, y: this.z }; }
	get gr(): Vec2f { return { x: this.y, y: this.x }; }
	get gg(): Vec2f { return { x: this.y, y: this.y }; }
	get gb(): Vec2f { return { x: this.y, y: this.z }; }
	get br(): Vec2f { return { x: this.z, y: this.x }; }
	get bg(): Vec2f { return { x: this.z, y: this.y }; }
	get bb(): Vec2f { return { x: this.z, y: this.z }; }
	get rrr(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get rrg(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get rrb(): Vec3f { return { x: this.x, y: this.x, z: this.z }; }
	get rgr(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get rgg(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get rgb(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get rbr(): Vec3f { return { x: this.x, y: this.z, z: this.x }; }
	get rbg(): Vec3f { return { x: this.x, y: this.z, z: this.y }; }
	get rbb(): Vec3f { return { x: this.x, y: this.z, z: this.z }; }
	get grr(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get grg(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get grb(): Vec3f { return { x: this.y, y: this.x, z: this.z }; }
	get ggr(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get ggg(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get ggb(): Vec3f { return { x: this.y, y: this.y, z: this.z }; }
	get gbr(): Vec3f { return { x: this.y, y: this.z, z: this.x }; }
	get gbg(): Vec3f { return { x: this.y, y: this.z, z: this.y }; }
	get gbb(): Vec3f { return { x: this.y, y: this.z, z: this.z }; }
	get brr(): Vec3f { return { x: this.z, y: this.x, z: this.x }; }
	get brg(): Vec3f { return { x: this.z, y: this.x, z: this.y }; }
	get brb(): Vec3f { return { x: this.z, y: this.x, z: this.z }; }
	get bgr(): Vec3f { return { x: this.z, y: this.y, z: this.x }; }
	get bgg(): Vec3f { return { x: this.z, y: this.y, z: this.y }; }
	get bgb(): Vec3f { return { x: this.z, y: this.y, z: this.z }; }
	get bbr(): Vec3f { return { x: this.z, y: this.z, z: this.x }; }
	get bbg(): Vec3f { return { x: this.z, y: this.z, z: this.y }; }
	get bbb(): Vec3f { return { x: this.z, y: this.z, z: this.z }; }
	get rrrr(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get rrrg(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get rrrb(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.z }; }
	get rrgr(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get rrgg(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get rrgb(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.z }; }
	get rrbr(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.x }; }
	get rrbg(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.y }; }
	get rrbb(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.z }; }
	get rgrr(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get rgrg(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get rgrb(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.z }; }
	get rggr(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get rggg(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get rggb(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.z }; }
	get rgbr(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.x }; }
	get rgbg(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.y }; }
	get rgbb(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.z }; }
	get rbrr(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.x }; }
	get rbrg(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.y }; }
	get rbrb(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.z }; }
	get rbgr(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.x }; }
	get rbgg(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.y }; }
	get rbgb(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.z }; }
	get rbbr(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.x }; }
	get rbbg(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.y }; }
	get rbbb(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.z }; }
	get grrr(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get grrg(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get grrb(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.z }; }
	get grgr(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get grgg(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get grgb(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.z }; }
	get grbr(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.x }; }
	get grbg(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.y }; }
	get grbb(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.z }; }
	get ggrr(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get ggrg(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get ggrb(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.z }; }
	get gggr(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get gggg(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
	get gggb(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.z }; }
	get ggbr(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.x }; }
	get ggbg(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.y }; }
	get ggbb(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.z }; }
	get gbrr(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.x }; }
	get gbrg(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.y }; }
	get gbrb(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.z }; }
	get gbgr(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.x }; }
	get gbgg(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.y }; }
	get gbgb(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.z }; }
	get gbbr(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.x }; }
	get gbbg(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.y }; }
	get gbbb(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.z }; }
	get brrr(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.x }; }
	get brrg(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.y }; }
	get brrb(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.z }; }
	get brgr(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.x }; }
	get brgg(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.y }; }
	get brgb(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.z }; }
	get brbr(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.x }; }
	get brbg(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.y }; }
	get brbb(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.z }; }
	get bgrr(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.x }; }
	get bgrg(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.y }; }
	get bgrb(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.z }; }
	get bggr(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.x }; }
	get bggg(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.y }; }
	get bggb(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.z }; }
	get bgbr(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.x }; }
	get bgbg(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.y }; }
	get bgbb(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.z }; }
	get bbrr(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.x }; }
	get bbrg(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.y }; }
	get bbrb(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.z }; }
	get bbgr(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.x }; }
	get bbgg(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.y }; }
	get bbgb(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.z }; }
	get bbbr(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.x }; }
	get bbbg(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.y }; }
	get bbbb(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.z }; }
}

export struct Vec4f {
	x: float32;
	y: float32;
	z: float32;
	w: float32;
	get xx(): Vec2f { return { x: this.x, y: this.x }; }
	get xy(): Vec2f { return { x: this.x, y: this.y }; }
	get xz(): Vec2f { return { x: this.x, y: this.z }; }
	get xw(): Vec2f { return { x: this.x, y: this.w }; }
	get yx(): Vec2f { return { x: this.y, y: this.x }; }
	get yy(): Vec2f { return { x: this.y, y: this.y }; }
	get yz(): Vec2f { return { x: this.y, y: this.z }; }
	get yw(): Vec2f { return { x: this.y, y: this.w }; }
	get zx(): Vec2f { return { x: this.z, y: this.x }; }
	get zy(): Vec2f { return { x: this.z, y: this.y }; }
	get zz(): Vec2f { return { x: this.z, y: this.z }; }
	get zw(): Vec2f { return { x: this.z, y: this.w }; }
	get wx(): Vec2f { return { x: this.w, y: this.x }; }
	get wy(): Vec2f { return { x: this.w, y: this.y }; }
	get wz(): Vec2f { return { x: this.w, y: this.z }; }
	get ww(): Vec2f { return { x: this.w, y: this.w }; }
	get xxx(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get xxy(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get xxz(): Vec3f { return { x: this.x, y: this.x, z: this.z }; }
	get xxw(): Vec3f { return { x: this.x, y: this.x, z: this.w }; }
	get xyx(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get xyy(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get xyz(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get xyw(): Vec3f { return { x: this.x, y: this.y, z: this.w }; }
	get xzx(): Vec3f { return { x: this.x, y: this.z, z: this.x }; }
	get xzy(): Vec3f { return { x: this.x, y: this.z, z: this.y }; }
	get xzz(): Vec3f { return { x: this.x, y: this.z, z: this.z }; }
	get xzw(): Vec3f { return { x: this.x, y: this.z, z: this.w }; }
	get xwx(): Vec3f { return { x: this.x, y: this.w, z: this.x }; }
	get xwy(): Vec3f { return { x: this.x, y: this.w, z: this.y }; }
	get xwz(): Vec3f { return { x: this.x, y: this.w, z: this.z }; }
	get xww(): Vec3f { return { x: this.x, y: this.w, z: this.w }; }
	get yxx(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get yxy(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get yxz(): Vec3f { return { x: this.y, y: this.x, z: this.z }; }
	get yxw(): Vec3f { return { x: this.y, y: this.x, z: this.w }; }
	get yyx(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get yyy(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get yyz(): Vec3f { return { x: this.y, y: this.y, z: this.z }; }
	get yyw(): Vec3f { return { x: this.y, y: this.y, z: this.w }; }
	get yzx(): Vec3f { return { x: this.y, y: this.z, z: this.x }; }
	get yzy(): Vec3f { return { x: this.y, y: this.z, z: this.y }; }
	get yzz(): Vec3f { return { x: this.y, y: this.z, z: this.z }; }
	get yzw(): Vec3f { return { x: this.y, y: this.z, z: this.w }; }
	get ywx(): Vec3f { return { x: this.y, y: this.w, z: this.x }; }
	get ywy(): Vec3f { return { x: this.y, y: this.w, z: this.y }; }
	get ywz(): Vec3f { return { x: this.y, y: this.w, z: this.z }; }
	get yww(): Vec3f { return { x: this.y, y: this.w, z: this.w }; }
	get zxx(): Vec3f { return { x: this.z, y: this.x, z: this.x }; }
	get zxy(): Vec3f { return { x: this.z, y: this.x, z: this.y }; }
	get zxz(): Vec3f { return { x: this.z, y: this.x, z: this.z }; }
	get zxw(): Vec3f { return { x: this.z, y: this.x, z: this.w }; }
	get zyx(): Vec3f { return { x: this.z, y: this.y, z: this.x }; }
	get zyy(): Vec3f { return { x: this.z, y: this.y, z: this.y }; }
	get zyz(): Vec3f { return { x: this.z, y: this.y, z: this.z }; }
	get zyw(): Vec3f { return { x: this.z, y: this.y, z: this.w }; }
	get zzx(): Vec3f { return { x: this.z, y: this.z, z: this.x }; }
	get zzy(): Vec3f { return { x: this.z, y: this.z, z: this.y }; }
	get zzz(): Vec3f { return { x: this.z, y: this.z, z: this.z }; }
	get zzw(): Vec3f { return { x: this.z, y: this.z, z: this.w }; }
	get zwx(): Vec3f { return { x: this.z, y: this.w, z: this.x }; }
	get zwy(): Vec3f { return { x: this.z, y: this.w, z: this.y }; }
	get zwz(): Vec3f { return { x: this.z, y: this.w, z: this.z }; }
	get zww(): Vec3f { return { x: this.z, y: this.w, z: this.w }; }
	get wxx(): Vec3f { return { x: this.w, y: this.x, z: this.x }; }
	get wxy(): Vec3f { return { x: this.w, y: this.x, z: this.y }; }
	get wxz(): Vec3f { return { x: this.w, y: this.x, z: this.z }; }
	get wxw(): Vec3f { return { x: this.w, y: this.x, z: this.w }; }
	get wyx(): Vec3f { return { x: this.w, y: this.y, z: this.x }; }
	get wyy(): Vec3f { return { x: this.w, y: this.y, z: this.y }; }
	get wyz(): Vec3f { return { x: this.w, y: this.y, z: this.z }; }
	get wyw(): Vec3f { return { x: this.w, y: this.y, z: this.w }; }
	get wzx(): Vec3f { return { x: this.w, y: this.z, z: this.x }; }
	get wzy(): Vec3f { return { x: this.w, y: this.z, z: this.y }; }
	get wzz(): Vec3f { return { x: this.w, y: this.z, z: this.z }; }
	get wzw(): Vec3f { return { x: this.w, y: this.z, z: this.w }; }
	get wwx(): Vec3f { return { x: this.w, y: this.w, z: this.x }; }
	get wwy(): Vec3f { return { x: this.w, y: this.w, z: this.y }; }
	get wwz(): Vec3f { return { x: this.w, y: this.w, z: this.z }; }
	get www(): Vec3f { return { x: this.w, y: this.w, z: this.w }; }
	get xxxx(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get xxxy(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get xxxz(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.z }; }
	get xxxw(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.w }; }
	get xxyx(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get xxyy(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get xxyz(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.z }; }
	get xxyw(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.w }; }
	get xxzx(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.x }; }
	get xxzy(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.y }; }
	get xxzz(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.z }; }
	get xxzw(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.w }; }
	get xxwx(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.x }; }
	get xxwy(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.y }; }
	get xxwz(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.z }; }
	get xxww(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.w }; }
	get xyxx(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get xyxy(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get xyxz(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.z }; }
	get xyxw(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.w }; }
	get xyyx(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get xyyy(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get xyyz(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.z }; }
	get xyyw(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.w }; }
	get xyzx(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.x }; }
	get xyzy(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.y }; }
	get xyzz(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.z }; }
	get xyzw(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.w }; }
	get xywx(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.x }; }
	get xywy(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.y }; }
	get xywz(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.z }; }
	get xyww(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.w }; }
	get xzxx(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.x }; }
	get xzxy(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.y }; }
	get xzxz(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.z }; }
	get xzxw(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.w }; }
	get xzyx(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.x }; }
	get xzyy(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.y }; }
	get xzyz(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.z }; }
	get xzyw(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.w }; }
	get xzzx(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.x }; }
	get xzzy(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.y }; }
	get xzzz(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.z }; }
	get xzzw(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.w }; }
	get xzwx(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.x }; }
	get xzwy(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.y }; }
	get xzwz(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.z }; }
	get xzww(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.w }; }
	get xwxx(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.x }; }
	get xwxy(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.y }; }
	get xwxz(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.z }; }
	get xwxw(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.w }; }
	get xwyx(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.x }; }
	get xwyy(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.y }; }
	get xwyz(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.z }; }
	get xwyw(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.w }; }
	get xwzx(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.x }; }
	get xwzy(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.y }; }
	get xwzz(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.z }; }
	get xwzw(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.w }; }
	get xwwx(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.x }; }
	get xwwy(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.y }; }
	get xwwz(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.z }; }
	get xwww(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.w }; }
	get yxxx(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get yxxy(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get yxxz(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.z }; }
	get yxxw(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.w }; }
	get yxyx(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get yxyy(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get yxyz(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.z }; }
	get yxyw(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.w }; }
	get yxzx(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.x }; }
	get yxzy(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.y }; }
	get yxzz(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.z }; }
	get yxzw(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.w }; }
	get yxwx(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.x }; }
	get yxwy(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.y }; }
	get yxwz(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.z }; }
	get yxww(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.w }; }
	get yyxx(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get yyxy(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get yyxz(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.z }; }
	get yyxw(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.w }; }
	get yyyx(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get yyyy(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
	get yyyz(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.z }; }
	get yyyw(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.w }; }
	get yyzx(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.x }; }
	get yyzy(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.y }; }
	get yyzz(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.z }; }
	get yyzw(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.w }; }
	get yywx(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.x }; }
	get yywy(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.y }; }
	get yywz(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.z }; }
	get yyww(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.w }; }
	get yzxx(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.x }; }
	get yzxy(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.y }; }
	get yzxz(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.z }; }
	get yzxw(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.w }; }
	get yzyx(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.x }; }
	get yzyy(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.y }; }
	get yzyz(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.z }; }
	get yzyw(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.w }; }
	get yzzx(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.x }; }
	get yzzy(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.y }; }
	get yzzz(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.z }; }
	get yzzw(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.w }; }
	get yzwx(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.x }; }
	get yzwy(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.y }; }
	get yzwz(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.z }; }
	get yzww(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.w }; }
	get ywxx(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.x }; }
	get ywxy(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.y }; }
	get ywxz(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.z }; }
	get ywxw(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.w }; }
	get ywyx(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.x }; }
	get ywyy(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.y }; }
	get ywyz(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.z }; }
	get ywyw(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.w }; }
	get ywzx(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.x }; }
	get ywzy(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.y }; }
	get ywzz(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.z }; }
	get ywzw(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.w }; }
	get ywwx(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.x }; }
	get ywwy(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.y }; }
	get ywwz(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.z }; }
	get ywww(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.w }; }
	get zxxx(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.x }; }
	get zxxy(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.y }; }
	get zxxz(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.z }; }
	get zxxw(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.w }; }
	get zxyx(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.x }; }
	get zxyy(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.y }; }
	get zxyz(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.z }; }
	get zxyw(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.w }; }
	get zxzx(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.x }; }
	get zxzy(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.y }; }
	get zxzz(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.z }; }
	get zxzw(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.w }; }
	get zxwx(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.x }; }
	get zxwy(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.y }; }
	get zxwz(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.z }; }
	get zxww(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.w }; }
	get zyxx(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.x }; }
	get zyxy(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.y }; }
	get zyxz(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.z }; }
	get zyxw(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.w }; }
	get zyyx(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.x }; }
	get zyyy(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.y }; }
	get zyyz(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.z }; }
	get zyyw(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.w }; }
	get zyzx(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.x }; }
	get zyzy(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.y }; }
	get zyzz(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.z }; }
	get zyzw(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.w }; }
	get zywx(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.x }; }
	get zywy(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.y }; }
	get zywz(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.z }; }
	get zyww(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.w }; }
	get zzxx(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.x }; }
	get zzxy(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.y }; }
	get zzxz(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.z }; }
	get zzxw(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.w }; }
	get zzyx(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.x }; }
	get zzyy(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.y }; }
	get zzyz(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.z }; }
	get zzyw(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.w }; }
	get zzzx(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.x }; }
	get zzzy(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.y }; }
	get zzzz(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.z }; }
	get zzzw(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.w }; }
	get zzwx(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.x }; }
	get zzwy(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.y }; }
	get zzwz(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.z }; }
	get zzww(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.w }; }
	get zwxx(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.x }; }
	get zwxy(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.y }; }
	get zwxz(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.z }; }
	get zwxw(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.w }; }
	get zwyx(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.x }; }
	get zwyy(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.y }; }
	get zwyz(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.z }; }
	get zwyw(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.w }; }
	get zwzx(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.x }; }
	get zwzy(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.y }; }
	get zwzz(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.z }; }
	get zwzw(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.w }; }
	get zwwx(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.x }; }
	get zwwy(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.y }; }
	get zwwz(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.z }; }
	get zwww(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.w }; }
	get wxxx(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.x }; }
	get wxxy(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.y }; }
	get wxxz(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.z }; }
	get wxxw(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.w }; }
	get wxyx(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.x }; }
	get wxyy(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.y }; }
	get wxyz(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.z }; }
	get wxyw(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.w }; }
	get wxzx(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.x }; }
	get wxzy(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.y }; }
	get wxzz(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.z }; }
	get wxzw(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.w }; }
	get wxwx(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.x }; }
	get wxwy(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.y }; }
	get wxwz(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.z }; }
	get wxww(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.w }; }
	get wyxx(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.x }; }
	get wyxy(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.y }; }
	get wyxz(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.z }; }
	get wyxw(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.w }; }
	get wyyx(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.x }; }
	get wyyy(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.y }; }
	get wyyz(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.z }; }
	get wyyw(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.w }; }
	get wyzx(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.x }; }
	get wyzy(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.y }; }
	get wyzz(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.z }; }
	get wyzw(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.w }; }
	get wywx(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.x }; }
	get wywy(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.y }; }
	get wywz(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.z }; }
	get wyww(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.w }; }
	get wzxx(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.x }; }
	get wzxy(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.y }; }
	get wzxz(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.z }; }
	get wzxw(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.w }; }
	get wzyx(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.x }; }
	get wzyy(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.y }; }
	get wzyz(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.z }; }
	get wzyw(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.w }; }
	get wzzx(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.x }; }
	get wzzy(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.y }; }
	get wzzz(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.z }; }
	get wzzw(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.w }; }
	get wzwx(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.x }; }
	get wzwy(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.y }; }
	get wzwz(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.z }; }
	get wzww(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.w }; }
	get wwxx(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.x }; }
	get wwxy(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.y }; }
	get wwxz(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.z }; }
	get wwxw(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.w }; }
	get wwyx(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.x }; }
	get wwyy(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.y }; }
	get wwyz(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.z }; }
	get wwyw(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.w }; }
	get wwzx(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.x }; }
	get wwzy(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.y }; }
	get wwzz(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.z }; }
	get wwzw(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.w }; }
	get wwwx(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.x }; }
	get wwwy(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.y }; }
	get wwwz(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.z }; }
	get wwww(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.w }; }
	get r(): float32 { return this.x; }
	get g(): float32 { return this.y; }
	get b(): float32 { return this.z; }
	get a(): float32 { return this.w; }
	get rr(): Vec2f { return { x: this.x, y: this.x }; }
	get rg(): Vec2f { return { x: this.x, y: this.y }; }
	get rb(): Vec2f { return { x: this.x, y: this.z }; }
	get ra(): Vec2f { return { x: this.x, y: this.w }; }
	get gr(): Vec2f { return { x: this.y, y: this.x }; }
	get gg(): Vec2f { return { x: this.y, y: this.y }; }
	get gb(): Vec2f { return { x: this.y, y: this.z }; }
	get ga(): Vec2f { return { x: this.y, y: this.w }; }
	get br(): Vec2f { return { x: this.z, y: this.x }; }
	get bg(): Vec2f { return { x: this.z, y: this.y }; }
	get bb(): Vec2f { return { x: this.z, y: this.z }; }
	get ba(): Vec2f { return { x: this.z, y: this.w }; }
	get ar(): Vec2f { return { x: this.w, y: this.x }; }
	get ag(): Vec2f { return { x: this.w, y: this.y }; }
	get ab(): Vec2f { return { x: this.w, y: this.z }; }
	get aa(): Vec2f { return { x: this.w, y: this.w }; }
	get rrr(): Vec3f { return { x: this.x, y: this.x, z: this.x }; }
	get rrg(): Vec3f { return { x: this.x, y: this.x, z: this.y }; }
	get rrb(): Vec3f { return { x: this.x, y: this.x, z: this.z }; }
	get rra(): Vec3f { return { x: this.x, y: this.x, z: this.w }; }
	get rgr(): Vec3f { return { x: this.x, y: this.y, z: this.x }; }
	get rgg(): Vec3f { return { x: this.x, y: this.y, z: this.y }; }
	get rgb(): Vec3f { return { x: this.x, y: this.y, z: this.z }; }
	get rga(): Vec3f { return { x: this.x, y: this.y, z: this.w }; }
	get rbr(): Vec3f { return { x: this.x, y: this.z, z: this.x }; }
	get rbg(): Vec3f { return { x: this.x, y: this.z, z: this.y }; }
	get rbb(): Vec3f { return { x: this.x, y: this.z, z: this.z }; }
	get rba(): Vec3f { return { x: this.x, y: this.z, z: this.w }; }
	get rar(): Vec3f { return { x: this.x, y: this.w, z: this.x }; }
	get rag(): Vec3f { return { x: this.x, y: this.w, z: this.y }; }
	get rab(): Vec3f { return { x: this.x, y: this.w, z: this.z }; }
	get raa(): Vec3f { return { x: this.x, y: this.w, z: this.w }; }
	get grr(): Vec3f { return { x: this.y, y: this.x, z: this.x }; }
	get grg(): Vec3f { return { x: this.y, y: this.x, z: this.y }; }
	get grb(): Vec3f { return { x: this.y, y: this.x, z: this.z }; }
	get gra(): Vec3f { return { x: this.y, y: this.x, z: this.w }; }
	get ggr(): Vec3f { return { x: this.y, y: this.y, z: this.x }; }
	get ggg(): Vec3f { return { x: this.y, y: this.y, z: this.y }; }
	get ggb(): Vec3f { return { x: this.y, y: this.y, z: this.z }; }
	get gga(): Vec3f { return { x: this.y, y: this.y, z: this.w }; }
	get gbr(): Vec3f { return { x: this.y, y: this.z, z: this.x }; }
	get gbg(): Vec3f { return { x: this.y, y: this.z, z: this.y }; }
	get gbb(): Vec3f { return { x: this.y, y: this.z, z: this.z }; }
	get gba(): Vec3f { return { x: this.y, y: this.z, z: this.w }; }
	get gar(): Vec3f { return { x: this.y, y: this.w, z: this.x }; }
	get gag(): Vec3f { return { x: this.y, y: this.w, z: this.y }; }
	get gab(): Vec3f { return { x: this.y, y: this.w, z: this.z }; }
	get gaa(): Vec3f { return { x: this.y, y: this.w, z: this.w }; }
	get brr(): Vec3f { return { x: this.z, y: this.x, z: this.x }; }
	get brg(): Vec3f { return { x: this.z, y: this.x, z: this.y }; }
	get brb(): Vec3f { return { x: this.z, y: this.x, z: this.z }; }
	get bra(): Vec3f { return { x: this.z, y: this.x, z: this.w }; }
	get bgr(): Vec3f { return { x: this.z, y: this.y, z: this.x }; }
	get bgg(): Vec3f { return { x: this.z, y: this.y, z: this.y }; }
	get bgb(): Vec3f { return { x: this.z, y: this.y, z: this.z }; }
	get bga(): Vec3f { return { x: this.z, y: this.y, z: this.w }; }
	get bbr(): Vec3f { return { x: this.z, y: this.z, z: this.x }; }
	get bbg(): Vec3f { return { x: this.z, y: this.z, z: this.y }; }
	get bbb(): Vec3f { return { x: this.z, y: this.z, z: this.z }; }
	get bba(): Vec3f { return { x: this.z, y: this.z, z: this.w }; }
	get bar(): Vec3f { return { x: this.z, y: this.w, z: this.x }; }
	get bag(): Vec3f { return { x: this.z, y: this.w, z: this.y }; }
	get bab(): Vec3f { return { x: this.z, y: this.w, z: this.z }; }
	get baa(): Vec3f { return { x: this.z, y: this.w, z: this.w }; }
	get arr(): Vec3f { return { x: this.w, y: this.x, z: this.x }; }
	get arg(): Vec3f { return { x: this.w, y: this.x, z: this.y }; }
	get arb(): Vec3f { return { x: this.w, y: this.x, z: this.z }; }
	get ara(): Vec3f { return { x: this.w, y: this.x, z: this.w }; }
	get agr(): Vec3f { return { x: this.w, y: this.y, z: this.x }; }
	get agg(): Vec3f { return { x: this.w, y: this.y, z: this.y }; }
	get agb(): Vec3f { return { x: this.w, y: this.y, z: this.z }; }
	get aga(): Vec3f { return { x: this.w, y: this.y, z: this.w }; }
	get abr(): Vec3f { return { x: this.w, y: this.z, z: this.x }; }
	get abg(): Vec3f { return { x: this.w, y: this.z, z: this.y }; }
	get abb(): Vec3f { return { x: this.w, y: this.z, z: this.z }; }
	get aba(): Vec3f { return { x: this.w, y: this.z, z: this.w }; }
	get aar(): Vec3f { return { x: this.w, y: this.w, z: this.x }; }
	get aag(): Vec3f { return { x: this.w, y: this.w, z: this.y }; }
	get aab(): Vec3f { return { x: this.w, y: this.w, z: this.z }; }
	get aaa(): Vec3f { return { x: this.w, y: this.w, z: this.w }; }
	get rrrr(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.x }; }
	get rrrg(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.y }; }
	get rrrb(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.z }; }
	get rrra(): Vec4f { return { x: this.x, y: this.x, z: this.x, w: this.w }; }
	get rrgr(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.x }; }
	get rrgg(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.y }; }
	get rrgb(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.z }; }
	get rrga(): Vec4f { return { x: this.x, y: this.x, z: this.y, w: this.w }; }
	get rrbr(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.x }; }
	get rrbg(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.y }; }
	get rrbb(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.z }; }
	get rrba(): Vec4f { return { x: this.x, y: this.x, z: this.z, w: this.w }; }
	get rrar(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.x }; }
	get rrag(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.y }; }
	get rrab(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.z }; }
	get rraa(): Vec4f { return { x: this.x, y: this.x, z: this.w, w: this.w }; }
	get rgrr(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.x }; }
	get rgrg(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.y }; }
	get rgrb(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.z }; }
	get rgra(): Vec4f { return { x: this.x, y: this.y, z: this.x, w: this.w }; }
	get rggr(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.x }; }
	get rggg(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.y }; }
	get rggb(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.z }; }
	get rgga(): Vec4f { return { x: this.x, y: this.y, z: this.y, w: this.w }; }
	get rgbr(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.x }; }
	get rgbg(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.y }; }
	get rgbb(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.z }; }
	get rgba(): Vec4f { return { x: this.x, y: this.y, z: this.z, w: this.w }; }
	get rgar(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.x }; }
	get rgag(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.y }; }
	get rgab(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.z }; }
	get rgaa(): Vec4f { return { x: this.x, y: this.y, z: this.w, w: this.w }; }
	get rbrr(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.x }; }
	get rbrg(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.y }; }
	get rbrb(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.z }; }
	get rbra(): Vec4f { return { x: this.x, y: this.z, z: this.x, w: this.w }; }
	get rbgr(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.x }; }
	get rbgg(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.y }; }
	get rbgb(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.z }; }
	get rbga(): Vec4f { return { x: this.x, y: this.z, z: this.y, w: this.w }; }
	get rbbr(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.x }; }
	get rbbg(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.y }; }
	get rbbb(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.z }; }
	get rbba(): Vec4f { return { x: this.x, y: this.z, z: this.z, w: this.w }; }
	get rbar(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.x }; }
	get rbag(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.y }; }
	get rbab(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.z }; }
	get rbaa(): Vec4f { return { x: this.x, y: this.z, z: this.w, w: this.w }; }
	get rarr(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.x }; }
	get rarg(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.y }; }
	get rarb(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.z }; }
	get rara(): Vec4f { return { x: this.x, y: this.w, z: this.x, w: this.w }; }
	get ragr(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.x }; }
	get ragg(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.y }; }
	get ragb(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.z }; }
	get raga(): Vec4f { return { x: this.x, y: this.w, z: this.y, w: this.w }; }
	get rabr(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.x }; }
	get rabg(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.y }; }
	get rabb(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.z }; }
	get raba(): Vec4f { return { x: this.x, y: this.w, z: this.z, w: this.w }; }
	get raar(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.x }; }
	get raag(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.y }; }
	get raab(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.z }; }
	get raaa(): Vec4f { return { x: this.x, y: this.w, z: this.w, w: this.w }; }
	get grrr(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.x }; }
	get grrg(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.y }; }
	get grrb(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.z }; }
	get grra(): Vec4f { return { x: this.y, y: this.x, z: this.x, w: this.w }; }
	get grgr(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.x }; }
	get grgg(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.y }; }
	get grgb(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.z }; }
	get grga(): Vec4f { return { x: this.y, y: this.x, z: this.y, w: this.w }; }
	get grbr(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.x }; }
	get grbg(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.y }; }
	get grbb(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.z }; }
	get grba(): Vec4f { return { x: this.y, y: this.x, z: this.z, w: this.w }; }
	get grar(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.x }; }
	get grag(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.y }; }
	get grab(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.z }; }
	get graa(): Vec4f { return { x: this.y, y: this.x, z: this.w, w: this.w }; }
	get ggrr(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.x }; }
	get ggrg(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.y }; }
	get ggrb(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.z }; }
	get ggra(): Vec4f { return { x: this.y, y: this.y, z: this.x, w: this.w }; }
	get gggr(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.x }; }
	get gggg(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.y }; }
	get gggb(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.z }; }
	get ggga(): Vec4f { return { x: this.y, y: this.y, z: this.y, w: this.w }; }
	get ggbr(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.x }; }
	get ggbg(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.y }; }
	get ggbb(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.z }; }
	get ggba(): Vec4f { return { x: this.y, y: this.y, z: this.z, w: this.w }; }
	get ggar(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.x }; }
	get ggag(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.y }; }
	get ggab(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.z }; }
	get ggaa(): Vec4f { return { x: this.y, y: this.y, z: this.w, w: this.w }; }
	get gbrr(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.x }; }
	get gbrg(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.y }; }
	get gbrb(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.z }; }
	get gbra(): Vec4f { return { x: this.y, y: this.z, z: this.x, w: this.w }; }
	get gbgr(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.x }; }
	get gbgg(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.y }; }
	get gbgb(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.z }; }
	get gbga(): Vec4f { return { x: this.y, y: this.z, z: this.y, w: this.w }; }
	get gbbr(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.x }; }
	get gbbg(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.y }; }
	get gbbb(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.z }; }
	get gbba(): Vec4f { return { x: this.y, y: this.z, z: this.z, w: this.w }; }
	get gbar(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.x }; }
	get gbag(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.y }; }
	get gbab(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.z }; }
	get gbaa(): Vec4f { return { x: this.y, y: this.z, z: this.w, w: this.w }; }
	get garr(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.x }; }
	get garg(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.y }; }
	get garb(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.z }; }
	get gara(): Vec4f { return { x: this.y, y: this.w, z: this.x, w: this.w }; }
	get gagr(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.x }; }
	get gagg(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.y }; }
	get gagb(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.z }; }
	get gaga(): Vec4f { return { x: this.y, y: this.w, z: this.y, w: this.w }; }
	get gabr(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.x }; }
	get gabg(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.y }; }
	get gabb(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.z }; }
	get gaba(): Vec4f { return { x: this.y, y: this.w, z: this.z, w: this.w }; }
	get gaar(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.x }; }
	get gaag(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.y }; }
	get gaab(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.z }; }
	get gaaa(): Vec4f { return { x: this.y, y: this.w, z: this.w, w: this.w }; }
	get brrr(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.x }; }
	get brrg(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.y }; }
	get brrb(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.z }; }
	get brra(): Vec4f { return { x: this.z, y: this.x, z: this.x, w: this.w }; }
	get brgr(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.x }; }
	get brgg(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.y }; }
	get brgb(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.z }; }
	get brga(): Vec4f { return { x: this.z, y: this.x, z: this.y, w: this.w }; }
	get brbr(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.x }; }
	get brbg(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.y }; }
	get brbb(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.z }; }
	get brba(): Vec4f { return { x: this.z, y: this.x, z: this.z, w: this.w }; }
	get brar(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.x }; }
	get brag(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.y }; }
	get brab(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.z }; }
	get braa(): Vec4f { return { x: this.z, y: this.x, z: this.w, w: this.w }; }
	get bgrr(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.x }; }
	get bgrg(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.y }; }
	get bgrb(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.z }; }
	get bgra(): Vec4f { return { x: this.z, y: this.y, z: this.x, w: this.w }; }
	get bggr(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.x }; }
	get bggg(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.y }; }
	get bggb(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.z }; }
	get bgga(): Vec4f { return { x: this.z, y: this.y, z: this.y, w: this.w }; }
	get bgbr(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.x }; }
	get bgbg(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.y }; }
	get bgbb(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.z }; }
	get bgba(): Vec4f { return { x: this.z, y: this.y, z: this.z, w: this.w }; }
	get bgar(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.x }; }
	get bgag(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.y }; }
	get bgab(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.z }; }
	get bgaa(): Vec4f { return { x: this.z, y: this.y, z: this.w, w: this.w }; }
	get bbrr(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.x }; }
	get bbrg(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.y }; }
	get bbrb(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.z }; }
	get bbra(): Vec4f { return { x: this.z, y: this.z, z: this.x, w: this.w }; }
	get bbgr(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.x }; }
	get bbgg(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.y }; }
	get bbgb(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.z }; }
	get bbga(): Vec4f { return { x: this.z, y: this.z, z: this.y, w: this.w }; }
	get bbbr(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.x }; }
	get bbbg(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.y }; }
	get bbbb(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.z }; }
	get bbba(): Vec4f { return { x: this.z, y: this.z, z: this.z, w: this.w }; }
	get bbar(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.x }; }
	get bbag(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.y }; }
	get bbab(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.z }; }
	get bbaa(): Vec4f { return { x: this.z, y: this.z, z: this.w, w: this.w }; }
	get barr(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.x }; }
	get barg(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.y }; }
	get barb(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.z }; }
	get bara(): Vec4f { return { x: this.z, y: this.w, z: this.x, w: this.w }; }
	get bagr(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.x }; }
	get bagg(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.y }; }
	get bagb(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.z }; }
	get baga(): Vec4f { return { x: this.z, y: this.w, z: this.y, w: this.w }; }
	get babr(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.x }; }
	get babg(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.y }; }
	get babb(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.z }; }
	get baba(): Vec4f { return { x: this.z, y: this.w, z: this.z, w: this.w }; }
	get baar(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.x }; }
	get baag(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.y }; }
	get baab(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.z }; }
	get baaa(): Vec4f { return { x: this.z, y: this.w, z: this.w, w: this.w }; }
	get arrr(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.x }; }
	get arrg(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.y }; }
	get arrb(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.z }; }
	get arra(): Vec4f { return { x: this.w, y: this.x, z: this.x, w: this.w }; }
	get argr(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.x }; }
	get argg(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.y }; }
	get argb(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.z }; }
	get arga(): Vec4f { return { x: this.w, y: this.x, z: this.y, w: this.w }; }
	get arbr(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.x }; }
	get arbg(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.y }; }
	get arbb(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.z }; }
	get arba(): Vec4f { return { x: this.w, y: this.x, z: this.z, w: this.w }; }
	get arar(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.x }; }
	get arag(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.y }; }
	get arab(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.z }; }
	get araa(): Vec4f { return { x: this.w, y: this.x, z: this.w, w: this.w }; }
	get agrr(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.x }; }
	get agrg(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.y }; }
	get agrb(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.z }; }
	get agra(): Vec4f { return { x: this.w, y: this.y, z: this.x, w: this.w }; }
	get aggr(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.x }; }
	get aggg(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.y }; }
	get aggb(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.z }; }
	get agga(): Vec4f { return { x: this.w, y: this.y, z: this.y, w: this.w }; }
	get agbr(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.x }; }
	get agbg(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.y }; }
	get agbb(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.z }; }
	get agba(): Vec4f { return { x: this.w, y: this.y, z: this.z, w: this.w }; }
	get agar(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.x }; }
	get agag(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.y }; }
	get agab(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.z }; }
	get agaa(): Vec4f { return { x: this.w, y: this.y, z: this.w, w: this.w }; }
	get abrr(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.x }; }
	get abrg(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.y }; }
	get abrb(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.z }; }
	get abra(): Vec4f { return { x: this.w, y: this.z, z: this.x, w: this.w }; }
	get abgr(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.x }; }
	get abgg(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.y }; }
	get abgb(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.z }; }
	get abga(): Vec4f { return { x: this.w, y: this.z, z: this.y, w: this.w }; }
	get abbr(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.x }; }
	get abbg(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.y }; }
	get abbb(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.z }; }
	get abba(): Vec4f { return { x: this.w, y: this.z, z: this.z, w: this.w }; }
	get abar(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.x }; }
	get abag(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.y }; }
	get abab(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.z }; }
	get abaa(): Vec4f { return { x: this.w, y: this.z, z: this.w, w: this.w }; }
	get aarr(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.x }; }
	get aarg(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.y }; }
	get aarb(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.z }; }
	get aara(): Vec4f { return { x: this.w, y: this.w, z: this.x, w: this.w }; }
	get aagr(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.x }; }
	get aagg(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.y }; }
	get aagb(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.z }; }
	get aaga(): Vec4f { return { x: this.w, y: this.w, z: this.y, w: this.w }; }
	get aabr(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.x }; }
	get aabg(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.y }; }
	get aabb(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.z }; }
	get aaba(): Vec4f { return { x: this.w, y: this.w, z: this.z, w: this.w }; }
	get aaar(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.x }; }
	get aaag(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.y }; }
	get aaab(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.z }; }
	get aaaa(): Vec4f { return { x: this.w, y: this.w, z: this.w, w: this.w }; }
}

export struct Vec2i {
	x: int32;
	y: int32;
}

export struct Vec3i {
	x: int32;
	y: int32;
	z: int32;
	get xy(): Vec2i { return { x: this.x, y: this.y }; }
}

export struct Vec4i {
	x: int32;
	y: int32;
	z: int32;
	w: int32;
	get xy(): Vec2i { return { x: this.x, y: this.y }; }
	get xyz(): Vec3i { return { x: this.x, y: this.y, z: this.z }; }
}

export struct Vec2u {
	x: uint32;
	y: uint32;
}

export struct Vec3u {
	x: uint32;
	y: uint32;
	z: uint32;
	get xy(): Vec2u { return { x: this.x, y: this.y }; }
}

export struct Vec4u {
	x: uint32;
	y: uint32;
	z: uint32;
	w: uint32;
	get xy(): Vec2u { return { x: this.x, y: this.y }; }
	get xyz(): Vec3u { return { x: this.x, y: this.y, z: this.z }; }
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
export function vec2f(s: float32): Vec2f { return { x: s, y: s }; }
export function vec2f(v: Vec2i): Vec2f { return { x: v.x as float32, y: v.y as float32 }; }
export function vec2f(v: Vec2u): Vec2f { return { x: v.x as float32, y: v.y as float32 }; }
export function vec3f(x: float32, y: float32, z: float32): Vec3f { return { x, y, z }; }
export function vec3f(s: float32): Vec3f { return { x: s, y: s, z: s }; }
export function vec3f(v: Vec2f, z: float32): Vec3f { return { x: v.x, y: v.y, z }; }
export function vec3f(v: Vec3i): Vec3f {
	return vec3f(v.x as float32, v.y as float32, v.z as float32);
}
export function vec3f(v: Vec3u): Vec3f {
	return vec3f(v.x as float32, v.y as float32, v.z as float32);
}
export function vec4f(x: float32, y: float32, z: float32, w: float32): Vec4f {
	return { x, y, z, w };
}
export function vec4f(s: float32): Vec4f { return { x: s, y: s, z: s, w: s }; }
export function vec4f(v: Vec3f, w: float32): Vec4f { return { x: v.x, y: v.y, z: v.z, w }; }
export function vec4f(v: Vec2f, z: float32, w: float32): Vec4f { return { x: v.x, y: v.y, z, w }; }
export function vec4f(a: Vec2f, b: Vec2f): Vec4f { return { x: a.x, y: a.y, z: b.x, w: b.y }; }
export function vec4f(v: Vec4i): Vec4f {
	return vec4f(v.x as float32, v.y as float32, v.z as float32, v.w as float32);
}
export function vec4f(v: Vec4u): Vec4f {
	return vec4f(v.x as float32, v.y as float32, v.z as float32, v.w as float32);
}

// WGSL saturates a float out of the integer range, GLSL leaves the result undefined.
function int32Of(x: float32): int32 {
	if (!(x >= -2147483648.0 && x < 2147483648.0)) {
		unreachable("an int vector of a float: it is not finite, or outside the int32 range");
	}
	return x as int32;
}

// WGSL converts between i32 and u32 by their bits; MetaScript's `as` checks the range instead.
function int32Bits(u: uint32): int32 {
	const wide = u as int64;
	return (wide > (0x7FFFFFFF as int64) ? wide - (0x100000000 as int64) : wide) as int32;
}
function uint32Bits(i: int32): uint32 {
	const wide = i as int64;
	return (wide < (0 as int64) ? wide + (0x100000000 as int64) : wide) as uint32;
}

export function vec2i(x: int32, y: int32): Vec2i { return { x, y }; }
export function vec2i(v: Vec2f): Vec2i { return { x: int32Of(v.x), y: int32Of(v.y) }; }
export function vec2i(v: Vec2u): Vec2i { return { x: int32Bits(v.x), y: int32Bits(v.y) }; }
export function vec3i(x: int32, y: int32, z: int32): Vec3i { return { x, y, z }; }
export function vec3i(v: Vec3f): Vec3i { return vec3i(int32Of(v.x), int32Of(v.y), int32Of(v.z)); }
export function vec3i(v: Vec3u): Vec3i {
	return vec3i(int32Bits(v.x), int32Bits(v.y), int32Bits(v.z));
}
export function vec4i(x: int32, y: int32, z: int32, w: int32): Vec4i { return { x, y, z, w }; }
export function vec4i(v: Vec4f): Vec4i {
	return vec4i(int32Of(v.x), int32Of(v.y), int32Of(v.z), int32Of(v.w));
}
export function vec4i(v: Vec4u): Vec4i {
	return vec4i(int32Bits(v.x), int32Bits(v.y), int32Bits(v.z), int32Bits(v.w));
}
export function vec2u(x: uint32, y: uint32): Vec2u { return { x, y }; }
export function vec2u(v: Vec2i): Vec2u { return { x: uint32Bits(v.x), y: uint32Bits(v.y) }; }
export function vec3u(x: uint32, y: uint32, z: uint32): Vec3u { return { x, y, z }; }
export function vec3u(v: Vec3i): Vec3u {
	return vec3u(uint32Bits(v.x), uint32Bits(v.y), uint32Bits(v.z));
}
export function vec4u(x: uint32, y: uint32, z: uint32, w: uint32): Vec4u { return { x, y, z, w }; }
export function vec4u(v: Vec4i): Vec4u {
	return vec4u(uint32Bits(v.x), uint32Bits(v.y), uint32Bits(v.z), uint32Bits(v.w));
}

export function mat2x2f(c0: Vec2f, c1: Vec2f): Mat2x2f { return { columns: [c0, c1] }; }
export function mat2x2f(c0x: float32, c0y: float32, c1x: float32, c1y: float32): Mat2x2f {
	return mat2x2f(vec2f(c0x, c0y), vec2f(c1x, c1y));
}
export function mat3x3f(c0: Vec3f, c1: Vec3f, c2: Vec3f): Mat3x3f {
	return { columns: [c0, c1, c2] };
}
export function mat3x3f(
	c0x: float32, c0y: float32, c0z: float32,
	c1x: float32, c1y: float32, c1z: float32,
	c2x: float32, c2y: float32, c2z: float32,
): Mat3x3f {
	return mat3x3f(vec3f(c0x, c0y, c0z), vec3f(c1x, c1y, c1z), vec3f(c2x, c2y, c2z));
}
export function mat4x4f(c0: Vec4f, c1: Vec4f, c2: Vec4f, c3: Vec4f): Mat4x4f {
	return { columns: [c0, c1, c2, c3] };
}

// GLSL's mat3(m): WGSL has no constructor from a wider matrix, so the name is Void's.
export function upperLeft3x3(m: Mat4x4f): Mat3x3f {
	return mat3x3f(m.columns[0].xyz, m.columns[1].xyz, m.columns[2].xyz);
}

export function `+`(this a: Vec2f, b: Vec2f): Vec2f { return vec2f(a.x + b.x, a.y + b.y); }
export function `-`(this a: Vec2f, b: Vec2f): Vec2f { return vec2f(a.x - b.x, a.y - b.y); }
export function `*`(this a: Vec2f, b: Vec2f): Vec2f { return vec2f(a.x * b.x, a.y * b.y); }
export function `/`(this a: Vec2f, b: Vec2f): Vec2f { return vec2f(a.x / b.x, a.y / b.y); }
export function `%`(this a: Vec2f, b: Vec2f): Vec2f { return vec2f(a.x % b.x, a.y % b.y); }
export function `+`(this a: Vec2f, s: float32): Vec2f { return vec2f(a.x + s, a.y + s); }
export function `-`(this a: Vec2f, s: float32): Vec2f { return vec2f(a.x - s, a.y - s); }
export function `*`(this a: Vec2f, s: float32): Vec2f { return vec2f(a.x * s, a.y * s); }
export function `/`(this a: Vec2f, s: float32): Vec2f { return vec2f(a.x / s, a.y / s); }
export function `%`(this a: Vec2f, s: float32): Vec2f { return vec2f(a.x % s, a.y % s); }
export function `+`(this s: float32, a: Vec2f): Vec2f { return vec2f(s + a.x, s + a.y); }
export function `-`(this s: float32, a: Vec2f): Vec2f { return vec2f(s - a.x, s - a.y); }
export function `*`(this s: float32, a: Vec2f): Vec2f { return vec2f(s * a.x, s * a.y); }
export function `/`(this s: float32, a: Vec2f): Vec2f { return vec2f(s / a.x, s / a.y); }
export function `%`(this s: float32, a: Vec2f): Vec2f { return vec2f(s % a.x, s % a.y); }
export function `-`(this a: Vec2f): Vec2f { return vec2f(-a.x, -a.y); }
export function `+`(this a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(a.x + b.x, a.y + b.y, a.z + b.z);
}
export function `-`(this a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(a.x - b.x, a.y - b.y, a.z - b.z);
}
export function `*`(this a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(a.x * b.x, a.y * b.y, a.z * b.z);
}
export function `/`(this a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(a.x / b.x, a.y / b.y, a.z / b.z);
}
export function `%`(this a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(a.x % b.x, a.y % b.y, a.z % b.z);
}
export function `+`(this a: Vec3f, s: float32): Vec3f { return vec3f(a.x + s, a.y + s, a.z + s); }
export function `-`(this a: Vec3f, s: float32): Vec3f { return vec3f(a.x - s, a.y - s, a.z - s); }
export function `*`(this a: Vec3f, s: float32): Vec3f { return vec3f(a.x * s, a.y * s, a.z * s); }
export function `/`(this a: Vec3f, s: float32): Vec3f { return vec3f(a.x / s, a.y / s, a.z / s); }
export function `%`(this a: Vec3f, s: float32): Vec3f { return vec3f(a.x % s, a.y % s, a.z % s); }
export function `+`(this s: float32, a: Vec3f): Vec3f { return vec3f(s + a.x, s + a.y, s + a.z); }
export function `-`(this s: float32, a: Vec3f): Vec3f { return vec3f(s - a.x, s - a.y, s - a.z); }
export function `*`(this s: float32, a: Vec3f): Vec3f { return vec3f(s * a.x, s * a.y, s * a.z); }
export function `/`(this s: float32, a: Vec3f): Vec3f { return vec3f(s / a.x, s / a.y, s / a.z); }
export function `%`(this s: float32, a: Vec3f): Vec3f { return vec3f(s % a.x, s % a.y, s % a.z); }
export function `-`(this a: Vec3f): Vec3f { return vec3f(-a.x, -a.y, -a.z); }
export function `+`(this a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w);
}
export function `-`(this a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w);
}
export function `*`(this a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w);
}
export function `/`(this a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w);
}
export function `%`(this a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(a.x % b.x, a.y % b.y, a.z % b.z, a.w % b.w);
}
export function `+`(this a: Vec4f, s: float32): Vec4f {
	return vec4f(a.x + s, a.y + s, a.z + s, a.w + s);
}
export function `-`(this a: Vec4f, s: float32): Vec4f {
	return vec4f(a.x - s, a.y - s, a.z - s, a.w - s);
}
export function `*`(this a: Vec4f, s: float32): Vec4f {
	return vec4f(a.x * s, a.y * s, a.z * s, a.w * s);
}
export function `/`(this a: Vec4f, s: float32): Vec4f {
	return vec4f(a.x / s, a.y / s, a.z / s, a.w / s);
}
export function `%`(this a: Vec4f, s: float32): Vec4f {
	return vec4f(a.x % s, a.y % s, a.z % s, a.w % s);
}
export function `+`(this s: float32, a: Vec4f): Vec4f {
	return vec4f(s + a.x, s + a.y, s + a.z, s + a.w);
}
export function `-`(this s: float32, a: Vec4f): Vec4f {
	return vec4f(s - a.x, s - a.y, s - a.z, s - a.w);
}
export function `*`(this s: float32, a: Vec4f): Vec4f {
	return vec4f(s * a.x, s * a.y, s * a.z, s * a.w);
}
export function `/`(this s: float32, a: Vec4f): Vec4f {
	return vec4f(s / a.x, s / a.y, s / a.z, s / a.w);
}
export function `%`(this s: float32, a: Vec4f): Vec4f {
	return vec4f(s % a.x, s % a.y, s % a.z, s % a.w);
}
export function `-`(this a: Vec4f): Vec4f { return vec4f(-a.x, -a.y, -a.z, -a.w); }
export function `+`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x + b.x, a.y + b.y); }
export function `-`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x - b.x, a.y - b.y); }
export function `*`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x * b.x, a.y * b.y); }
export function `+`(this a: Vec2i, s: int32): Vec2i { return vec2i(a.x + s, a.y + s); }
export function `-`(this a: Vec2i, s: int32): Vec2i { return vec2i(a.x - s, a.y - s); }
export function `*`(this a: Vec2i, s: int32): Vec2i { return vec2i(a.x * s, a.y * s); }
export function `+`(this s: int32, a: Vec2i): Vec2i { return vec2i(s + a.x, s + a.y); }
export function `-`(this s: int32, a: Vec2i): Vec2i { return vec2i(s - a.x, s - a.y); }
export function `*`(this s: int32, a: Vec2i): Vec2i { return vec2i(s * a.x, s * a.y); }
export function `-`(this a: Vec2i): Vec2i { return vec2i(-a.x, -a.y); }

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
export function `*`(this a: Mat2x2f, b: Mat2x2f): Mat2x2f {
	return mat2x2f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat3x3f, b: Mat3x3f): Mat3x3f {
	const c = b.columns;
	return mat3x3f(a * c[0], a * c[1], a * c[2]);
}
export function `*`(this a: Mat4x4f, b: Mat4x4f): Mat4x4f {
	const c = b.columns;
	return mat4x4f(a * c[0], a * c[1], a * c[2], a * c[3]);
}

export function transpose(m: Mat2x2f): Mat2x2f {
	const c = m.columns;
	return mat2x2f(c[0].x, c[1].x, c[0].y, c[1].y);
}
export function transpose(m: Mat3x3f): Mat3x3f {
	const c = m.columns;
	return mat3x3f(
		vec3f(c[0].x, c[1].x, c[2].x),
		vec3f(c[0].y, c[1].y, c[2].y),
		vec3f(c[0].z, c[1].z, c[2].z),
	);
}
export function transpose(m: Mat4x4f): Mat4x4f {
	const c = m.columns;
	return mat4x4f(
		vec4f(c[0].x, c[1].x, c[2].x, c[3].x),
		vec4f(c[0].y, c[1].y, c[2].y, c[3].y),
		vec4f(c[0].z, c[1].z, c[2].z, c[3].z),
		vec4f(c[0].w, c[1].w, c[2].w, c[3].w),
	);
}

export function determinant(m: Mat2x2f): float32 {
	const c = m.columns;
	return c[0].x * c[1].y - c[1].x * c[0].y;
}
export function determinant(m: Mat3x3f): float32 {
	const c = m.columns;
	return dot(c[0], cross(c[1], c[2]));
}
export function determinant(m: Mat4x4f): float32 { return inverseParts(m).det; }

// WGSL has no matrix inverse, so the name is GLSL's. A singular matrix has none, and GLSL's
// result for one is undefined.
function invertible(det: float32): float32 {
	if (det == 0.0) { unreachable("inverse: the matrix is singular"); }
	return det;
}

export function inverse(m: Mat2x2f): Mat2x2f {
	const c = m.columns;
	const k = 1.0 / invertible(determinant(m));
	return mat2x2f(c[1].y * k, -c[0].y * k, -c[1].x * k, c[0].x * k);
}
export function inverse(m: Mat3x3f): Mat3x3f {
	const c = m.columns;
	const k = 1.0 / invertible(determinant(m));
	const rows = mat3x3f(cross(c[1], c[2]) * k, cross(c[2], c[0]) * k, cross(c[0], c[1]) * k);
	return transpose(rows);
}

// The 4x4 determinant and inverse from cross products of the columns' upper three rows, as
// Lengyel's Foundations of Game Engine Development, volume 1, computes them.
struct InverseParts {
	s: Vec3f;
	t: Vec3f;
	u: Vec3f;
	v: Vec3f;
	det: float32;
}

function inverseParts(m: Mat4x4f): InverseParts {
	const c = m.columns;
	const s = cross(c[0].xyz, c[1].xyz);
	const t = cross(c[2].xyz, c[3].xyz);
	const u = c[0].xyz * c[1].w - c[1].xyz * c[0].w;
	const v = c[2].xyz * c[3].w - c[3].xyz * c[2].w;
	return { s, t, u, v, det: dot(s, v) + dot(t, u) };
}

export function inverse(m: Mat4x4f): Mat4x4f {
	const c = m.columns;
	const parts = inverseParts(m);
	const k = 1.0 / invertible(parts.det);
	const s = parts.s * k;
	const t = parts.t * k;
	const u = parts.u * k;
	const v = parts.v * k;
	const a = c[0].xyz;
	const b = c[1].xyz;
	const d = c[3].xyz;
	return transpose(mat4x4f(
		vec4f(cross(b, v) + t * c[1].w, -dot(b, t)),
		vec4f(cross(v, a) - t * c[0].w, dot(a, t)),
		vec4f(cross(d, u) + s * c[3].w, -dot(d, s)),
		vec4f(cross(u, c[2].xyz) - s * c[2].w, dot(c[2].xyz, s)),
	));
}


export function abs(x: float32): float32 { return Math.abs(x) as float32; }
export function sign(x: float32): float32 { return Math.sign(x) as float32; }
export function floor(x: float32): float32 { return Math.floor(x) as float32; }
export function ceil(x: float32): float32 { return Math.ceil(x) as float32; }
export function trunc(x: float32): float32 { return Math.trunc(x) as float32; }
export function fract(x: float32): float32 { return x - floor(x); }

export function round(x: float32): float32 {
	const down = Math.floor(x);
	const rest = x - down;
	return (rest > 0.5 || rest == 0.5 && down % 2.0 != 0.0 ? down + 1.0 : down) as float32;
}

export function sqrt(x: float32): float32 {
	if (!(x >= 0.0)) { unreachable("sqrt: the GPU result is undefined below 0"); }
	return Math.sqrt(x) as float32;
}
export function inverseSqrt(x: float32): float32 {
	if (!(x > 0.0)) { unreachable("inverseSqrt: the GPU result is undefined at or below 0"); }
	return (1.0 / Math.sqrt(x)) as float32;
}
export function exp(x: float32): float32 { return Math.exp(x) as float32; }
export function exp2(x: float32): float32 { return Math.pow(2.0, x) as float32; }
export function log(x: float32): float32 {
	if (!(x > 0.0)) { unreachable("log: the GPU result is undefined at or below 0"); }
	return Math.log(x) as float32;
}
export function log2(x: float32): float32 {
	if (!(x > 0.0)) { unreachable("log2: the GPU result is undefined at or below 0"); }
	return Math.log2(x) as float32;
}

export function sin(x: float32): float32 { return Math.sin(x) as float32; }
export function cos(x: float32): float32 { return Math.cos(x) as float32; }
export function tan(x: float32): float32 { return Math.tan(x) as float32; }
export function asin(x: float32): float32 {
	if (!(Math.abs(x) <= 1.0)) { unreachable("asin: the GPU result is undefined past -1 or 1"); }
	return Math.asin(x) as float32;
}
export function acos(x: float32): float32 {
	if (!(Math.abs(x) <= 1.0)) { unreachable("acos: the GPU result is undefined past -1 or 1"); }
	return Math.acos(x) as float32;
}
export function atan(x: float32): float32 { return Math.atan(x) as float32; }
export function atan2(y: float32, x: float32): float32 {
	if (x == 0.0 && y == 0.0) { unreachable("atan2: the GPU result is undefined at (0, 0)"); }
	return Math.atan2(y, x) as float32;
}
export function sinh(x: float32): float32 { return Math.sinh(x) as float32; }
export function cosh(x: float32): float32 { return Math.cosh(x) as float32; }
export function tanh(x: float32): float32 { return Math.tanh(x) as float32; }
export function degrees(x: float32): float32 { return (x * 180.0 / Math.PI) as float32; }
export function radians(x: float32): float32 { return (x * Math.PI / 180.0) as float32; }

export function max(a: float32, b: float32): float32 { return a < b ? b : a; }
export function min(a: float32, b: float32): float32 { return b < a ? b : a; }
export function clamp(v: float32, low: float32, high: float32): float32 {
	if (low > high) { unreachable("clamp: the GPU result is undefined when low > high"); }
	return min(max(v, low), high);
}
export function saturate(x: float32): float32 { return clamp(x, 0.0, 1.0); }
export function mix(a: float32, b: float32, t: float32): float32 { return a * (1.0 - t) + b * t; }
export function step(edge: float32, x: float32): float32 { return edge <= x ? 1.0 : 0.0; }
export function smoothstep(low: float32, high: float32, x: float32): float32 {
	if (!(low < high)) { unreachable("smoothstep: the GPU result is undefined when low >= high"); }
	const t = clamp((x - low) / (high - low), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
export function fma(a: float32, b: float32, c: float32): float32 {
	return ((a as float64) * (b as float64) + (c as float64)) as float32;
}

export function pow(base: float32, exponent: float32): float32 {
	if (base < 0.0 || (base == 0.0 && exponent <= 0.0)) {
		unreachable("pow: the GPU result is undefined for a negative base, or 0 to a power <= 0");
	}
	return Math.pow(base, exponent) as float32;
}

export function abs(x: int32): int32 { return x < 0 && x != -2147483648 ? -x : x; }
export function sign(x: int32): int32 { return x > 0 ? 1 : x < 0 ? -1 : 0; }
export function max(a: int32, b: int32): int32 { return a < b ? b : a; }
export function min(a: int32, b: int32): int32 { return b < a ? b : a; }
export function clamp(v: int32, low: int32, high: int32): int32 {
	if (low > high) { unreachable("clamp: the GPU result is undefined when low > high"); }
	return min(max(v, low), high);
}
export function max(a: uint32, b: uint32): uint32 { return a < b ? b : a; }
export function min(a: uint32, b: uint32): uint32 { return b < a ? b : a; }
export function clamp(v: uint32, low: uint32, high: uint32): uint32 {
	if (low > high) { unreachable("clamp: the GPU result is undefined when low > high"); }
	return min(max(v, low), high);
}
export function clamp(v: Vec2i, low: Vec2i, high: Vec2i): Vec2i {
	return vec2i(clamp(v.x, low.x, high.x), clamp(v.y, low.y, high.y));
}

export function abs(v: Vec2f): Vec2f { return vec2f(abs(v.x), abs(v.y)); }
export function abs(v: Vec3f): Vec3f { return vec3f(abs(v.x), abs(v.y), abs(v.z)); }
export function abs(v: Vec4f): Vec4f { return vec4f(abs(v.x), abs(v.y), abs(v.z), abs(v.w)); }
export function sign(v: Vec2f): Vec2f { return vec2f(sign(v.x), sign(v.y)); }
export function sign(v: Vec3f): Vec3f { return vec3f(sign(v.x), sign(v.y), sign(v.z)); }
export function sign(v: Vec4f): Vec4f { return vec4f(sign(v.x), sign(v.y), sign(v.z), sign(v.w)); }
export function floor(v: Vec2f): Vec2f { return vec2f(floor(v.x), floor(v.y)); }
export function floor(v: Vec3f): Vec3f { return vec3f(floor(v.x), floor(v.y), floor(v.z)); }
export function floor(v: Vec4f): Vec4f {
	return vec4f(floor(v.x), floor(v.y), floor(v.z), floor(v.w));
}
export function ceil(v: Vec2f): Vec2f { return vec2f(ceil(v.x), ceil(v.y)); }
export function ceil(v: Vec3f): Vec3f { return vec3f(ceil(v.x), ceil(v.y), ceil(v.z)); }
export function ceil(v: Vec4f): Vec4f { return vec4f(ceil(v.x), ceil(v.y), ceil(v.z), ceil(v.w)); }
export function round(v: Vec2f): Vec2f { return vec2f(round(v.x), round(v.y)); }
export function round(v: Vec3f): Vec3f { return vec3f(round(v.x), round(v.y), round(v.z)); }
export function round(v: Vec4f): Vec4f {
	return vec4f(round(v.x), round(v.y), round(v.z), round(v.w));
}
export function trunc(v: Vec2f): Vec2f { return vec2f(trunc(v.x), trunc(v.y)); }
export function trunc(v: Vec3f): Vec3f { return vec3f(trunc(v.x), trunc(v.y), trunc(v.z)); }
export function trunc(v: Vec4f): Vec4f {
	return vec4f(trunc(v.x), trunc(v.y), trunc(v.z), trunc(v.w));
}
export function fract(v: Vec2f): Vec2f { return vec2f(fract(v.x), fract(v.y)); }
export function fract(v: Vec3f): Vec3f { return vec3f(fract(v.x), fract(v.y), fract(v.z)); }
export function fract(v: Vec4f): Vec4f {
	return vec4f(fract(v.x), fract(v.y), fract(v.z), fract(v.w));
}
export function sqrt(v: Vec2f): Vec2f { return vec2f(sqrt(v.x), sqrt(v.y)); }
export function sqrt(v: Vec3f): Vec3f { return vec3f(sqrt(v.x), sqrt(v.y), sqrt(v.z)); }
export function sqrt(v: Vec4f): Vec4f { return vec4f(sqrt(v.x), sqrt(v.y), sqrt(v.z), sqrt(v.w)); }
export function inverseSqrt(v: Vec2f): Vec2f { return vec2f(inverseSqrt(v.x), inverseSqrt(v.y)); }
export function inverseSqrt(v: Vec3f): Vec3f {
	return vec3f(inverseSqrt(v.x), inverseSqrt(v.y), inverseSqrt(v.z));
}
export function inverseSqrt(v: Vec4f): Vec4f {
	return vec4f(inverseSqrt(v.x), inverseSqrt(v.y), inverseSqrt(v.z), inverseSqrt(v.w));
}
export function exp(v: Vec2f): Vec2f { return vec2f(exp(v.x), exp(v.y)); }
export function exp(v: Vec3f): Vec3f { return vec3f(exp(v.x), exp(v.y), exp(v.z)); }
export function exp(v: Vec4f): Vec4f { return vec4f(exp(v.x), exp(v.y), exp(v.z), exp(v.w)); }
export function exp2(v: Vec2f): Vec2f { return vec2f(exp2(v.x), exp2(v.y)); }
export function exp2(v: Vec3f): Vec3f { return vec3f(exp2(v.x), exp2(v.y), exp2(v.z)); }
export function exp2(v: Vec4f): Vec4f { return vec4f(exp2(v.x), exp2(v.y), exp2(v.z), exp2(v.w)); }
export function log(v: Vec2f): Vec2f { return vec2f(log(v.x), log(v.y)); }
export function log(v: Vec3f): Vec3f { return vec3f(log(v.x), log(v.y), log(v.z)); }
export function log(v: Vec4f): Vec4f { return vec4f(log(v.x), log(v.y), log(v.z), log(v.w)); }
export function log2(v: Vec2f): Vec2f { return vec2f(log2(v.x), log2(v.y)); }
export function log2(v: Vec3f): Vec3f { return vec3f(log2(v.x), log2(v.y), log2(v.z)); }
export function log2(v: Vec4f): Vec4f { return vec4f(log2(v.x), log2(v.y), log2(v.z), log2(v.w)); }
export function sin(v: Vec2f): Vec2f { return vec2f(sin(v.x), sin(v.y)); }
export function sin(v: Vec3f): Vec3f { return vec3f(sin(v.x), sin(v.y), sin(v.z)); }
export function sin(v: Vec4f): Vec4f { return vec4f(sin(v.x), sin(v.y), sin(v.z), sin(v.w)); }
export function cos(v: Vec2f): Vec2f { return vec2f(cos(v.x), cos(v.y)); }
export function cos(v: Vec3f): Vec3f { return vec3f(cos(v.x), cos(v.y), cos(v.z)); }
export function cos(v: Vec4f): Vec4f { return vec4f(cos(v.x), cos(v.y), cos(v.z), cos(v.w)); }
export function tan(v: Vec2f): Vec2f { return vec2f(tan(v.x), tan(v.y)); }
export function tan(v: Vec3f): Vec3f { return vec3f(tan(v.x), tan(v.y), tan(v.z)); }
export function tan(v: Vec4f): Vec4f { return vec4f(tan(v.x), tan(v.y), tan(v.z), tan(v.w)); }
export function asin(v: Vec2f): Vec2f { return vec2f(asin(v.x), asin(v.y)); }
export function asin(v: Vec3f): Vec3f { return vec3f(asin(v.x), asin(v.y), asin(v.z)); }
export function asin(v: Vec4f): Vec4f { return vec4f(asin(v.x), asin(v.y), asin(v.z), asin(v.w)); }
export function acos(v: Vec2f): Vec2f { return vec2f(acos(v.x), acos(v.y)); }
export function acos(v: Vec3f): Vec3f { return vec3f(acos(v.x), acos(v.y), acos(v.z)); }
export function acos(v: Vec4f): Vec4f { return vec4f(acos(v.x), acos(v.y), acos(v.z), acos(v.w)); }
export function atan(v: Vec2f): Vec2f { return vec2f(atan(v.x), atan(v.y)); }
export function atan(v: Vec3f): Vec3f { return vec3f(atan(v.x), atan(v.y), atan(v.z)); }
export function atan(v: Vec4f): Vec4f { return vec4f(atan(v.x), atan(v.y), atan(v.z), atan(v.w)); }
export function sinh(v: Vec2f): Vec2f { return vec2f(sinh(v.x), sinh(v.y)); }
export function sinh(v: Vec3f): Vec3f { return vec3f(sinh(v.x), sinh(v.y), sinh(v.z)); }
export function sinh(v: Vec4f): Vec4f { return vec4f(sinh(v.x), sinh(v.y), sinh(v.z), sinh(v.w)); }
export function cosh(v: Vec2f): Vec2f { return vec2f(cosh(v.x), cosh(v.y)); }
export function cosh(v: Vec3f): Vec3f { return vec3f(cosh(v.x), cosh(v.y), cosh(v.z)); }
export function cosh(v: Vec4f): Vec4f { return vec4f(cosh(v.x), cosh(v.y), cosh(v.z), cosh(v.w)); }
export function tanh(v: Vec2f): Vec2f { return vec2f(tanh(v.x), tanh(v.y)); }
export function tanh(v: Vec3f): Vec3f { return vec3f(tanh(v.x), tanh(v.y), tanh(v.z)); }
export function tanh(v: Vec4f): Vec4f { return vec4f(tanh(v.x), tanh(v.y), tanh(v.z), tanh(v.w)); }
export function degrees(v: Vec2f): Vec2f { return vec2f(degrees(v.x), degrees(v.y)); }
export function degrees(v: Vec3f): Vec3f { return vec3f(degrees(v.x), degrees(v.y), degrees(v.z)); }
export function degrees(v: Vec4f): Vec4f {
	return vec4f(degrees(v.x), degrees(v.y), degrees(v.z), degrees(v.w));
}
export function radians(v: Vec2f): Vec2f { return vec2f(radians(v.x), radians(v.y)); }
export function radians(v: Vec3f): Vec3f { return vec3f(radians(v.x), radians(v.y), radians(v.z)); }
export function radians(v: Vec4f): Vec4f {
	return vec4f(radians(v.x), radians(v.y), radians(v.z), radians(v.w));
}
export function saturate(v: Vec2f): Vec2f { return vec2f(saturate(v.x), saturate(v.y)); }
export function saturate(v: Vec3f): Vec3f {
	return vec3f(saturate(v.x), saturate(v.y), saturate(v.z));
}
export function saturate(v: Vec4f): Vec4f {
	return vec4f(saturate(v.x), saturate(v.y), saturate(v.z), saturate(v.w));
}
export function atan2(y: Vec2f, x: Vec2f): Vec2f { return vec2f(atan2(y.x, x.x), atan2(y.y, x.y)); }
export function atan2(y: Vec3f, x: Vec3f): Vec3f {
	return vec3f(atan2(y.x, x.x), atan2(y.y, x.y), atan2(y.z, x.z));
}
export function atan2(y: Vec4f, x: Vec4f): Vec4f {
	return vec4f(atan2(y.x, x.x), atan2(y.y, x.y), atan2(y.z, x.z), atan2(y.w, x.w));
}
export function pow(base: Vec2f, exponent: Vec2f): Vec2f {
	return vec2f(pow(base.x, exponent.x), pow(base.y, exponent.y));
}
export function pow(base: Vec3f, exponent: Vec3f): Vec3f {
	return vec3f(pow(base.x, exponent.x), pow(base.y, exponent.y), pow(base.z, exponent.z));
}
export function pow(base: Vec4f, exponent: Vec4f): Vec4f {
	return vec4f(
		pow(base.x, exponent.x),
		pow(base.y, exponent.y),
		pow(base.z, exponent.z),
		pow(base.w, exponent.w),
	);
}
export function max(a: Vec2f, b: Vec2f): Vec2f { return vec2f(max(a.x, b.x), max(a.y, b.y)); }
export function max(a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z));
}
export function max(a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z), max(a.w, b.w));
}
export function min(a: Vec2f, b: Vec2f): Vec2f { return vec2f(min(a.x, b.x), min(a.y, b.y)); }
export function min(a: Vec3f, b: Vec3f): Vec3f {
	return vec3f(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z));
}
export function min(a: Vec4f, b: Vec4f): Vec4f {
	return vec4f(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z), min(a.w, b.w));
}
export function clamp(v: Vec2f, low: Vec2f, high: Vec2f): Vec2f {
	return vec2f(clamp(v.x, low.x, high.x), clamp(v.y, low.y, high.y));
}
export function clamp(v: Vec3f, low: Vec3f, high: Vec3f): Vec3f {
	return vec3f(clamp(v.x, low.x, high.x), clamp(v.y, low.y, high.y), clamp(v.z, low.z, high.z));
}
export function clamp(v: Vec4f, low: Vec4f, high: Vec4f): Vec4f {
	return vec4f(
		clamp(v.x, low.x, high.x),
		clamp(v.y, low.y, high.y),
		clamp(v.z, low.z, high.z),
		clamp(v.w, low.w, high.w),
	);
}
export function mix(a: Vec2f, b: Vec2f, t: Vec2f): Vec2f {
	return vec2f(mix(a.x, b.x, t.x), mix(a.y, b.y, t.y));
}
export function mix(a: Vec3f, b: Vec3f, t: Vec3f): Vec3f {
	return vec3f(mix(a.x, b.x, t.x), mix(a.y, b.y, t.y), mix(a.z, b.z, t.z));
}
export function mix(a: Vec4f, b: Vec4f, t: Vec4f): Vec4f {
	return vec4f(mix(a.x, b.x, t.x), mix(a.y, b.y, t.y), mix(a.z, b.z, t.z), mix(a.w, b.w, t.w));
}
export function mix(a: Vec2f, b: Vec2f, t: float32): Vec2f {
	return vec2f(mix(a.x, b.x, t), mix(a.y, b.y, t));
}
export function mix(a: Vec3f, b: Vec3f, t: float32): Vec3f {
	return vec3f(mix(a.x, b.x, t), mix(a.y, b.y, t), mix(a.z, b.z, t));
}
export function mix(a: Vec4f, b: Vec4f, t: float32): Vec4f {
	return vec4f(mix(a.x, b.x, t), mix(a.y, b.y, t), mix(a.z, b.z, t), mix(a.w, b.w, t));
}
export function step(edge: Vec2f, x: Vec2f): Vec2f {
	return vec2f(step(edge.x, x.x), step(edge.y, x.y));
}
export function step(edge: Vec3f, x: Vec3f): Vec3f {
	return vec3f(step(edge.x, x.x), step(edge.y, x.y), step(edge.z, x.z));
}
export function step(edge: Vec4f, x: Vec4f): Vec4f {
	return vec4f(step(edge.x, x.x), step(edge.y, x.y), step(edge.z, x.z), step(edge.w, x.w));
}
export function smoothstep(low: Vec2f, high: Vec2f, x: Vec2f): Vec2f {
	return vec2f(smoothstep(low.x, high.x, x.x), smoothstep(low.y, high.y, x.y));
}
export function smoothstep(low: Vec3f, high: Vec3f, x: Vec3f): Vec3f {
	return vec3f(
		smoothstep(low.x, high.x, x.x),
		smoothstep(low.y, high.y, x.y),
		smoothstep(low.z, high.z, x.z),
	);
}
export function smoothstep(low: Vec4f, high: Vec4f, x: Vec4f): Vec4f {
	return vec4f(
		smoothstep(low.x, high.x, x.x),
		smoothstep(low.y, high.y, x.y),
		smoothstep(low.z, high.z, x.z),
		smoothstep(low.w, high.w, x.w),
	);
}
export function fma(a: Vec2f, b: Vec2f, c: Vec2f): Vec2f {
	return vec2f(fma(a.x, b.x, c.x), fma(a.y, b.y, c.y));
}
export function fma(a: Vec3f, b: Vec3f, c: Vec3f): Vec3f {
	return vec3f(fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z));
}
export function fma(a: Vec4f, b: Vec4f, c: Vec4f): Vec4f {
	return vec4f(fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z), fma(a.w, b.w, c.w));
}

export function dot(a: Vec2f, b: Vec2f): float32 { return a.x * b.x + a.y * b.y; }
export function dot(a: Vec3f, b: Vec3f): float32 { return a.x * b.x + a.y * b.y + a.z * b.z; }
export function dot(a: Vec4f, b: Vec4f): float32 {
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}
export function cross(a: Vec3f, b: Vec3f): Vec3f {
	return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}
export function length(v: Vec2f): float32 { return Math.sqrt(dot(v, v)) as float32; }
export function length(v: Vec3f): float32 { return Math.sqrt(dot(v, v)) as float32; }
export function length(v: Vec4f): float32 { return Math.sqrt(dot(v, v)) as float32; }
export function distance(a: Vec2f, b: Vec2f): float32 { return length(a - b); }
export function distance(a: Vec3f, b: Vec3f): float32 { return length(a - b); }
export function distance(a: Vec4f, b: Vec4f): float32 { return length(a - b); }

function directionLength(size: float32): float32 {
	if (size == 0.0) { unreachable("normalize: the GPU result is undefined for a zero vector"); }
	return size;
}
export function normalize(v: Vec2f): Vec2f { return v / directionLength(length(v)); }
export function normalize(v: Vec3f): Vec3f { return v / directionLength(length(v)); }
export function normalize(v: Vec4f): Vec4f { return v / directionLength(length(v)); }

export function reflect(e1: Vec2f, e2: Vec2f): Vec2f { return e1 - 2.0 * dot(e2, e1) * e2; }
export function reflect(e1: Vec3f, e2: Vec3f): Vec3f { return e1 - 2.0 * dot(e2, e1) * e2; }
export function reflect(e1: Vec4f, e2: Vec4f): Vec4f { return e1 - 2.0 * dot(e2, e1) * e2; }

function refractK(cosine: float32, eta: float32): float32 {
	return 1.0 - eta * eta * (1.0 - cosine * cosine);
}
export function refract(e1: Vec2f, e2: Vec2f, eta: float32): Vec2f {
	const k = refractK(dot(e2, e1), eta);
	return k < 0.0 ? vec2f(0.0) : eta * e1 - (eta * dot(e2, e1) + sqrt(k)) * e2;
}
export function refract(e1: Vec3f, e2: Vec3f, eta: float32): Vec3f {
	const k = refractK(dot(e2, e1), eta);
	return k < 0.0 ? vec3f(0.0) : eta * e1 - (eta * dot(e2, e1) + sqrt(k)) * e2;
}
export function refract(e1: Vec4f, e2: Vec4f, eta: float32): Vec4f {
	const k = refractK(dot(e2, e1), eta);
	return k < 0.0 ? vec4f(0.0) : eta * e1 - (eta * dot(e2, e1) + sqrt(k)) * e2;
}

export function faceForward(e1: Vec2f, e2: Vec2f, e3: Vec2f): Vec2f {
	return dot(e2, e3) < 0.0 ? e1 : -e1;
}
export function faceForward(e1: Vec3f, e2: Vec3f, e3: Vec3f): Vec3f {
	return dot(e2, e3) < 0.0 ? e1 : -e1;
}
export function faceForward(e1: Vec4f, e2: Vec4f, e3: Vec4f): Vec4f {
	return dot(e2, e3) < 0.0 ? e1 : -e1;
}

// WGSL's derivatives, taken across a fragment quad. Like TypeGPU's, they have no CPU meaning.
export function dpdx(v: float32): float32 { unreachable("dpdx: only a GPU fragment has one"); }
export function dpdx(v: Vec2f): Vec2f { unreachable("dpdx: only a GPU fragment has one"); }
export function dpdx(v: Vec3f): Vec3f { unreachable("dpdx: only a GPU fragment has one"); }
export function dpdx(v: Vec4f): Vec4f { unreachable("dpdx: only a GPU fragment has one"); }
export function dpdy(v: float32): float32 { unreachable("dpdy: only a GPU fragment has one"); }
export function dpdy(v: Vec2f): Vec2f { unreachable("dpdy: only a GPU fragment has one"); }
export function dpdy(v: Vec3f): Vec3f { unreachable("dpdy: only a GPU fragment has one"); }
export function dpdy(v: Vec4f): Vec4f { unreachable("dpdy: only a GPU fragment has one"); }
export function fwidth(v: float32): float32 { unreachable("fwidth: only a GPU fragment has one"); }
export function fwidth(v: Vec2f): Vec2f { unreachable("fwidth: only a GPU fragment has one"); }
export function fwidth(v: Vec3f): Vec3f { unreachable("fwidth: only a GPU fragment has one"); }
export function fwidth(v: Vec4f): Vec4f { unreachable("fwidth: only a GPU fragment has one"); }

// WGSL's operand order: the value when false comes first.
export function select(f: float32, t: float32, cond: boolean): float32 { return cond ? t : f; }
export function select(f: Vec3f, t: Vec3f, cond: boolean): Vec3f { return cond ? t : f; }
export function select(f: Vec3f, t: Vec3f, cond: Vec3b): Vec3f {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y, z: cond.z ? t.z : f.z };
}

export struct Vec3b {
	x: boolean;
	y: boolean;
	z: boolean;
}

export function le(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z };
}

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
	unreachable("discard: a fragment is discarded only on the GPU");
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
		unreachable("textureStore: the texel is outside the texture");
	}
	const first = (at.y * texture.width + at.x) * 4;
	texture.texels[first] = value.x;
	texture.texels[first + 1] = value.y;
	texture.texels[first + 2] = value.z;
	texture.texels[first + 3] = value.w;
}

// WGSL's textureDimensions and textureLoad take no sampler. These do: sokol-shdc cannot fetch
// without one (src/shader/CLAUDE.md, "shdc's own limits"). The size is signed, as the texel
// coordinate it bounds is (docs/VOCABULARY.md, "A name brings its meaning").
export function textureDimensions(texture: Texture2d, sampler: Sampler, level: int32): Vec2i {
	if (level != 0) { unreachable("textureDimensions: the CPU texture has no mip levels"); }
	return { x: texture.width, y: texture.height };
}

export function textureLoad(texture: Texture2d, sampler: Sampler, at: Vec2i, level: int32): Vec4f {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	if (at.x < 0 || at.y < 0 || at.x >= texture.width || at.y >= texture.height) {
		unreachable("textureLoad: the texel is outside the texture");
	}
	return texelAt(texture, at.x, at.y);
}

// WGSL's texture_2d<u32>: four uint32 a texel, fetched, never filtered.
export struct Texture2dU32 {
	width: int32;
	height: int32;
	texels: uint32[];
}

export function textureLoad(
	texture: Texture2dU32,
	sampler: Sampler,
	at: Vec2i,
	level: int32,
): Vec4u {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	if (at.x < 0 || at.y < 0 || at.x >= texture.width || at.y >= texture.height) {
		unreachable("textureLoad: the texel is outside the texture");
	}
	const first = (at.y * texture.width + at.x) * 4;
	const t = texture.texels;
	return { x: t[first], y: t[first + 1], z: t[first + 2], w: t[first + 3] };
}

// WGSL's texture_2d_array<f32>: layers of one size, one picked by its index.
export struct Texture2dArray {
	width: int32;
	height: int32;
	layers: int32;
	texels: float32[];
}

function layerOf(texture: Texture2dArray, layer: int32): Texture2d {
	if (layer < 0 || layer >= texture.layers) { unreachable("the layer is outside the texture"); }
	const size = texture.width * texture.height * 4;
	let texels: float32[] = [];
	for (let i = 0; i < size; i++) { texels.push(texture.texels[layer * size + i]); }
	return { width: texture.width, height: texture.height, texels };
}

export function textureLoad(
	texture: Texture2dArray,
	sampler: Sampler,
	at: Vec2i,
	layer: int32,
	level: int32,
): Vec4f {
	return textureLoad(layerOf(texture, layer), sampler, at, level);
}

export function textureSample(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
): Vec4f {
	return textureSample(layerOf(texture, layer), sampler, uv);
}

// WGSL's textureSampleLevel, textureSampleBias and textureSampleGrad choose the mip level: given,
// biased, or from given derivatives. The Vulkan specification's "Level-of-Detail Operation" clamps
// that level to the image's levels, and a CPU texture has one, so each samples as textureSample.
export function textureSampleLevel(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	level: float32,
): Vec4f {
	return textureSample(texture, sampler, uv);
}

// WGSL's texture_cube<f32>: six square faces in the order +X, -X, +Y, -Y, +Z, -Z.
export struct TextureCube {
	size: int32;
	texels: float32[];
}

// The face a direction reads and where on it, by the OpenGL specification's cube map table
// ("Cube Map Texture Selection"): the major axis picks the face, a tie going to x, then y.
function cubeFaceOf(texture: TextureCube, dir: Vec3f): Texture2d {
	const ax = abs(dir.x);
	const ay = abs(dir.y);
	const az = abs(dir.z);
	const face = ax >= ay && ax >= az ? (dir.x >= 0.0 ? 0 : 1) :
		ay >= az ? (dir.y >= 0.0 ? 2 : 3) : (dir.z >= 0.0 ? 4 : 5);
	const size = texture.size * texture.size * 4;
	let texels: float32[] = [];
	for (let i = 0; i < size; i++) { texels.push(texture.texels[face * size + i]); }
	return { width: texture.size, height: texture.size, texels };
}

function cubeFaceUv(dir: Vec3f): Vec2f {
	const ax = abs(dir.x);
	const ay = abs(dir.y);
	const az = abs(dir.z);
	let sc: float32 = 0.0;
	let tc: float32 = 0.0;
	let ma: float32 = 0.0;
	if (ax >= ay && ax >= az) {
		sc = dir.x >= 0.0 ? -dir.z : dir.z;
		tc = -dir.y;
		ma = ax;
	} else if (ay >= az) {
		sc = dir.x;
		tc = dir.y >= 0.0 ? dir.z : -dir.z;
		ma = ay;
	} else {
		sc = dir.z >= 0.0 ? dir.x : -dir.x;
		tc = -dir.y;
		ma = az;
	}
	if (!(ma > 0.0)) { unreachable("textureSample: a cube is sampled along a zero direction"); }
	return { x: (sc / ma + 1.0) * 0.5, y: (tc / ma + 1.0) * 0.5 };
}

export function textureSample(texture: TextureCube, sampler: Sampler, dir: Vec3f): Vec4f {
	const clamped: Sampler = { nearest: sampler.nearest, wrap: Wrap.Clamp };
	return textureSample(cubeFaceOf(texture, dir), clamped, cubeFaceUv(dir));
}

export function textureSampleLevel(
	texture: TextureCube,
	sampler: Sampler,
	dir: Vec3f,
	level: float32,
): Vec4f {
	return textureSample(texture, sampler, dir);
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
		unreachable("textureSample: the coordinate is not finite, or past any texel index");
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
