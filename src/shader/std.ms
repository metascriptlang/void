import { Compare, Wrap } from "../gpu/state";

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

export struct Mat2x3f {
	columns: Vec3f[2];
}

export struct Mat2x4f {
	columns: Vec4f[2];
}

export struct Mat3x2f {
	columns: Vec2f[3];
}

export struct Mat3x4f {
	columns: Vec4f[3];
}

export struct Mat4x2f {
	columns: Vec2f[4];
}

export struct Mat4x3f {
	columns: Vec3f[4];
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
export function mat2x3f(c0: Vec3f, c1: Vec3f): Mat2x3f {
	return { columns: [c0, c1] };
}
export function mat2x4f(c0: Vec4f, c1: Vec4f): Mat2x4f {
	return { columns: [c0, c1] };
}
export function mat3x2f(c0: Vec2f, c1: Vec2f, c2: Vec2f): Mat3x2f {
	return { columns: [c0, c1, c2] };
}
export function mat3x4f(c0: Vec4f, c1: Vec4f, c2: Vec4f): Mat3x4f {
	return { columns: [c0, c1, c2] };
}
export function mat4x2f(c0: Vec2f, c1: Vec2f, c2: Vec2f, c3: Vec2f): Mat4x2f {
	return { columns: [c0, c1, c2, c3] };
}
export function mat4x3f(c0: Vec3f, c1: Vec3f, c2: Vec3f, c3: Vec3f): Mat4x3f {
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
export function `&`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x & b.x, a.y & b.y); }
export function `|`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x | b.x, a.y | b.y); }
export function `^`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x ^ b.x, a.y ^ b.y); }
export function `<<`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x << b.x, a.y << b.y); }
export function `>>`(this a: Vec2i, b: Vec2i): Vec2i { return vec2i(a.x >> b.x, a.y >> b.y); }
export function `&`(this a: Vec3i, b: Vec3i): Vec3i {
	return vec3i(a.x & b.x, a.y & b.y, a.z & b.z);
}
export function `|`(this a: Vec3i, b: Vec3i): Vec3i {
	return vec3i(a.x | b.x, a.y | b.y, a.z | b.z);
}
export function `^`(this a: Vec3i, b: Vec3i): Vec3i {
	return vec3i(a.x ^ b.x, a.y ^ b.y, a.z ^ b.z);
}
export function `<<`(this a: Vec3i, b: Vec3i): Vec3i {
	return vec3i(a.x << b.x, a.y << b.y, a.z << b.z);
}
export function `>>`(this a: Vec3i, b: Vec3i): Vec3i {
	return vec3i(a.x >> b.x, a.y >> b.y, a.z >> b.z);
}
export function `&`(this a: Vec4i, b: Vec4i): Vec4i {
	return vec4i(a.x & b.x, a.y & b.y, a.z & b.z, a.w & b.w);
}
export function `|`(this a: Vec4i, b: Vec4i): Vec4i {
	return vec4i(a.x | b.x, a.y | b.y, a.z | b.z, a.w | b.w);
}
export function `^`(this a: Vec4i, b: Vec4i): Vec4i {
	return vec4i(a.x ^ b.x, a.y ^ b.y, a.z ^ b.z, a.w ^ b.w);
}
export function `<<`(this a: Vec4i, b: Vec4i): Vec4i {
	return vec4i(a.x << b.x, a.y << b.y, a.z << b.z, a.w << b.w);
}
export function `>>`(this a: Vec4i, b: Vec4i): Vec4i {
	return vec4i(a.x >> b.x, a.y >> b.y, a.z >> b.z, a.w >> b.w);
}
export function `&`(this a: Vec2u, b: Vec2u): Vec2u { return vec2u(a.x & b.x, a.y & b.y); }
export function `|`(this a: Vec2u, b: Vec2u): Vec2u { return vec2u(a.x | b.x, a.y | b.y); }
export function `^`(this a: Vec2u, b: Vec2u): Vec2u { return vec2u(a.x ^ b.x, a.y ^ b.y); }
export function `<<`(this a: Vec2u, b: Vec2u): Vec2u { return vec2u(a.x << b.x, a.y << b.y); }
export function `>>`(this a: Vec2u, b: Vec2u): Vec2u { return vec2u(a.x >> b.x, a.y >> b.y); }
export function `&`(this a: Vec3u, b: Vec3u): Vec3u {
	return vec3u(a.x & b.x, a.y & b.y, a.z & b.z);
}
export function `|`(this a: Vec3u, b: Vec3u): Vec3u {
	return vec3u(a.x | b.x, a.y | b.y, a.z | b.z);
}
export function `^`(this a: Vec3u, b: Vec3u): Vec3u {
	return vec3u(a.x ^ b.x, a.y ^ b.y, a.z ^ b.z);
}
export function `<<`(this a: Vec3u, b: Vec3u): Vec3u {
	return vec3u(a.x << b.x, a.y << b.y, a.z << b.z);
}
export function `>>`(this a: Vec3u, b: Vec3u): Vec3u {
	return vec3u(a.x >> b.x, a.y >> b.y, a.z >> b.z);
}
export function `&`(this a: Vec4u, b: Vec4u): Vec4u {
	return vec4u(a.x & b.x, a.y & b.y, a.z & b.z, a.w & b.w);
}
export function `|`(this a: Vec4u, b: Vec4u): Vec4u {
	return vec4u(a.x | b.x, a.y | b.y, a.z | b.z, a.w | b.w);
}
export function `^`(this a: Vec4u, b: Vec4u): Vec4u {
	return vec4u(a.x ^ b.x, a.y ^ b.y, a.z ^ b.z, a.w ^ b.w);
}
export function `<<`(this a: Vec4u, b: Vec4u): Vec4u {
	return vec4u(a.x << b.x, a.y << b.y, a.z << b.z, a.w << b.w);
}
export function `>>`(this a: Vec4u, b: Vec4u): Vec4u {
	return vec4u(a.x >> b.x, a.y >> b.y, a.z >> b.z, a.w >> b.w);
}

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
export function `*`(this m: Mat2x3f, v: Vec2f): Vec3f {
	return m.columns[0] * v.x + m.columns[1] * v.y;
}
export function `*`(this m: Mat2x4f, v: Vec2f): Vec4f {
	return m.columns[0] * v.x + m.columns[1] * v.y;
}
export function `*`(this m: Mat3x2f, v: Vec3f): Vec2f {
	return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z;
}
export function `*`(this m: Mat3x4f, v: Vec3f): Vec4f {
	return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z;
}
export function `*`(this m: Mat4x2f, v: Vec4f): Vec2f {
	return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z + m.columns[3] * v.w;
}
export function `*`(this m: Mat4x3f, v: Vec4f): Vec3f {
	return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z + m.columns[3] * v.w;
}
export function `*`(this v: Vec2f, m: Mat2x2f): Vec2f {
	return vec2f(dot(v, m.columns[0]), dot(v, m.columns[1]));
}
export function `*`(this v: Vec3f, m: Mat2x3f): Vec2f {
	return vec2f(dot(v, m.columns[0]), dot(v, m.columns[1]));
}
export function `*`(this v: Vec4f, m: Mat2x4f): Vec2f {
	return vec2f(dot(v, m.columns[0]), dot(v, m.columns[1]));
}
export function `*`(this v: Vec2f, m: Mat3x2f): Vec3f {
	return vec3f(dot(v, m.columns[0]), dot(v, m.columns[1]), dot(v, m.columns[2]));
}
export function `*`(this v: Vec3f, m: Mat3x3f): Vec3f {
	return vec3f(dot(v, m.columns[0]), dot(v, m.columns[1]), dot(v, m.columns[2]));
}
export function `*`(this v: Vec4f, m: Mat3x4f): Vec3f {
	return vec3f(dot(v, m.columns[0]), dot(v, m.columns[1]), dot(v, m.columns[2]));
}
export function `*`(this v: Vec2f, m: Mat4x2f): Vec4f {
	const c = m.columns;
	return vec4f(dot(v, c[0]), dot(v, c[1]), dot(v, c[2]), dot(v, c[3]));
}
export function `*`(this v: Vec3f, m: Mat4x3f): Vec4f {
	const c = m.columns;
	return vec4f(dot(v, c[0]), dot(v, c[1]), dot(v, c[2]), dot(v, c[3]));
}
export function `*`(this v: Vec4f, m: Mat4x4f): Vec4f {
	const c = m.columns;
	return vec4f(dot(v, c[0]), dot(v, c[1]), dot(v, c[2]), dot(v, c[3]));
}
export function `*`(this a: Mat4x4f, b: Mat4x4f): Mat4x4f {
	const c = b.columns;
	return mat4x4f(a * c[0], a * c[1], a * c[2], a * c[3]);
}
export function `*`(this a: Mat2x2f, b: Mat3x2f): Mat3x2f {
	return mat3x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat2x2f, b: Mat4x2f): Mat4x2f {
	return mat4x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat2x3f, b: Mat2x2f): Mat2x3f {
	return mat2x3f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat2x3f, b: Mat3x2f): Mat3x3f {
	return mat3x3f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat2x3f, b: Mat4x2f): Mat4x3f {
	return mat4x3f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat2x4f, b: Mat2x2f): Mat2x4f {
	return mat2x4f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat2x4f, b: Mat3x2f): Mat3x4f {
	return mat3x4f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat2x4f, b: Mat4x2f): Mat4x4f {
	return mat4x4f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat3x2f, b: Mat2x3f): Mat2x2f {
	return mat2x2f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat3x2f, b: Mat3x3f): Mat3x2f {
	return mat3x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat3x2f, b: Mat4x3f): Mat4x2f {
	return mat4x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat3x3f, b: Mat2x3f): Mat2x3f {
	return mat2x3f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat3x3f, b: Mat4x3f): Mat4x3f {
	return mat4x3f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat3x4f, b: Mat2x3f): Mat2x4f {
	return mat2x4f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat3x4f, b: Mat3x3f): Mat3x4f {
	return mat3x4f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat3x4f, b: Mat4x3f): Mat4x4f {
	return mat4x4f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat4x2f, b: Mat2x4f): Mat2x2f {
	return mat2x2f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat4x2f, b: Mat3x4f): Mat3x2f {
	return mat3x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat4x2f, b: Mat4x4f): Mat4x2f {
	return mat4x2f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat4x3f, b: Mat2x4f): Mat2x3f {
	return mat2x3f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat4x3f, b: Mat3x4f): Mat3x3f {
	return mat3x3f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
}
export function `*`(this a: Mat4x3f, b: Mat4x4f): Mat4x3f {
	return mat4x3f(a * b.columns[0], a * b.columns[1], a * b.columns[2], a * b.columns[3]);
}
export function `*`(this a: Mat4x4f, b: Mat2x4f): Mat2x4f {
	return mat2x4f(a * b.columns[0], a * b.columns[1]);
}
export function `*`(this a: Mat4x4f, b: Mat3x4f): Mat3x4f {
	return mat3x4f(a * b.columns[0], a * b.columns[1], a * b.columns[2]);
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
export function transpose(m: Mat2x3f): Mat3x2f {
	const c = m.columns;
	return mat3x2f(
		vec2f(c[0].x, c[1].x),
		vec2f(c[0].y, c[1].y),
		vec2f(c[0].z, c[1].z),
	);
}
export function transpose(m: Mat2x4f): Mat4x2f {
	const c = m.columns;
	return mat4x2f(
		vec2f(c[0].x, c[1].x),
		vec2f(c[0].y, c[1].y),
		vec2f(c[0].z, c[1].z),
		vec2f(c[0].w, c[1].w),
	);
}
export function transpose(m: Mat3x2f): Mat2x3f {
	const c = m.columns;
	return mat2x3f(
		vec3f(c[0].x, c[1].x, c[2].x),
		vec3f(c[0].y, c[1].y, c[2].y),
	);
}
export function transpose(m: Mat3x4f): Mat4x3f {
	const c = m.columns;
	return mat4x3f(
		vec3f(c[0].x, c[1].x, c[2].x),
		vec3f(c[0].y, c[1].y, c[2].y),
		vec3f(c[0].z, c[1].z, c[2].z),
		vec3f(c[0].w, c[1].w, c[2].w),
	);
}
export function transpose(m: Mat4x2f): Mat2x4f {
	const c = m.columns;
	return mat2x4f(
		vec4f(c[0].x, c[1].x, c[2].x, c[3].x),
		vec4f(c[0].y, c[1].y, c[2].y, c[3].y),
	);
}
export function transpose(m: Mat4x3f): Mat3x4f {
	const c = m.columns;
	return mat3x4f(
		vec4f(c[0].x, c[1].x, c[2].x, c[3].x),
		vec4f(c[0].y, c[1].y, c[2].y, c[3].y),
		vec4f(c[0].z, c[1].z, c[2].z, c[3].z),
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
export function asinh(x: float32): float32 { return Math.asinh(x) as float32; }
export function acosh(x: float32): float32 {
	if (!(x >= 1.0)) { unreachable("acosh: the GPU result is undefined below 1"); }
	return Math.acosh(x) as float32;
}
export function atanh(x: float32): float32 {
	if (!(Math.abs(x) < 1.0)) { unreachable("atanh: the GPU result is undefined at or past -1 and 1"); }
	return Math.atanh(x) as float32;
}
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
export function asinh(v: Vec2f): Vec2f { return vec2f(asinh(v.x), asinh(v.y)); }
export function asinh(v: Vec3f): Vec3f { return vec3f(asinh(v.x), asinh(v.y), asinh(v.z)); }
export function asinh(v: Vec4f): Vec4f { return vec4f(asinh(v.x), asinh(v.y), asinh(v.z), asinh(v.w)); }
export function acosh(v: Vec2f): Vec2f { return vec2f(acosh(v.x), acosh(v.y)); }
export function acosh(v: Vec3f): Vec3f { return vec3f(acosh(v.x), acosh(v.y), acosh(v.z)); }
export function acosh(v: Vec4f): Vec4f { return vec4f(acosh(v.x), acosh(v.y), acosh(v.z), acosh(v.w)); }
export function atanh(v: Vec2f): Vec2f { return vec2f(atanh(v.x), atanh(v.y)); }
export function atanh(v: Vec3f): Vec3f { return vec3f(atanh(v.x), atanh(v.y), atanh(v.z)); }
export function atanh(v: Vec4f): Vec4f { return vec4f(atanh(v.x), atanh(v.y), atanh(v.z), atanh(v.w)); }

// WGSL's ldexp: e1 * 2^e2. The specification leaves an e2 past 128 undefined.
export function ldexp(x: float32, e: int32): float32 {
	if (e > 128) { unreachable("ldexp: the exponent is past 128, which WGSL leaves undefined"); }
	return (x * Math.pow(2.0, e as float64)) as float32;
}
export function ldexp(x: Vec2f, e: Vec2i): Vec2f { return vec2f(ldexp(x.x, e.x), ldexp(x.y, e.y)); }
export function ldexp(x: Vec3f, e: Vec3i): Vec3f { return vec3f(ldexp(x.x, e.x), ldexp(x.y, e.y), ldexp(x.z, e.z)); }
export function ldexp(x: Vec4f, e: Vec4i): Vec4f { return vec4f(ldexp(x.x, e.x), ldexp(x.y, e.y), ldexp(x.z, e.z), ldexp(x.w, e.w)); }

// WGSL's modf and frexp answer a struct whose fields the specification names: a fraction and the
// whole part or the exponent. Each width of each is a ./std struct, as the atomic exchange results
// are; the IR marks the type as one a printer declares. An infinity or NaN has no result the
// targets agree on, so the oracle refuses it.
export struct ModfResultF32 {
	fract: float32;
	whole: float32;
}

export struct ModfResultVec2f {
	fract: Vec2f;
	whole: Vec2f;
}

export struct ModfResultVec3f {
	fract: Vec3f;
	whole: Vec3f;
}

export struct ModfResultVec4f {
	fract: Vec4f;
	whole: Vec4f;
}

export struct FrexpResultF32 {
	fract: float32;
	exp: int32;
}

export struct FrexpResultVec2f {
	fract: Vec2f;
	exp: Vec2i;
}

export struct FrexpResultVec3f {
	fract: Vec3f;
	exp: Vec3i;
}

export struct FrexpResultVec4f {
	fract: Vec4f;
	exp: Vec4i;
}

function finite(x: float32): float32 {
	if (!(Math.abs(x) <= 3.4028234663852886e38)) {
		unreachable("modf and frexp: an infinity or NaN has no result the targets agree on");
	}
	return x;
}

export function modf(x: float32): ModfResultF32 {
	const whole = Math.trunc(finite(x)) as float32;
	return { fract: x - whole, whole };
}
export function modf(v: Vec2f): ModfResultVec2f {
	const x = modf(v.x);
	const y = modf(v.y);
	return { fract: vec2f(x.fract, y.fract), whole: vec2f(x.whole, y.whole) };
}
export function modf(v: Vec3f): ModfResultVec3f {
	const x = modf(v.x);
	const y = modf(v.y);
	const z = modf(v.z);
	return { fract: vec3f(x.fract, y.fract, z.fract), whole: vec3f(x.whole, y.whole, z.whole) };
}
export function modf(v: Vec4f): ModfResultVec4f {
	const x = modf(v.x);
	const y = modf(v.y);
	const z = modf(v.z);
	const w = modf(v.w);
	return {
		fract: vec4f(x.fract, y.fract, z.fract, w.fract),
		whole: vec4f(x.whole, y.whole, z.whole, w.whole),
	};
}

// C's frexp: x = fract * 2^exp with |fract| in [0.5, 1), and a zero keeps its sign and exponent 0.
export function frexp(x: float32): FrexpResultF32 {
	if (finite(x) == 0.0) { return { fract: x, exp: 0 }; }
	const e = binaryExponent(Math.abs(x) as float64) + 1.0;
	return { fract: ((x as float64) / Math.pow(2.0, e)) as float32, exp: e as int32 };
}
export function frexp(v: Vec2f): FrexpResultVec2f {
	const x = frexp(v.x);
	const y = frexp(v.y);
	return { fract: vec2f(x.fract, y.fract), exp: vec2i(x.exp, y.exp) };
}
export function frexp(v: Vec3f): FrexpResultVec3f {
	const x = frexp(v.x);
	const y = frexp(v.y);
	const z = frexp(v.z);
	return { fract: vec3f(x.fract, y.fract, z.fract), exp: vec3i(x.exp, y.exp, z.exp) };
}
export function frexp(v: Vec4f): FrexpResultVec4f {
	const x = frexp(v.x);
	const y = frexp(v.y);
	const z = frexp(v.z);
	const w = frexp(v.w);
	return {
		fract: vec4f(x.fract, y.fract, z.fract, w.fract),
		exp: vec4i(x.exp, y.exp, z.exp, w.exp),
	};
}
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

// The coarse and fine derivatives: a fragment quad's too, so they have no CPU meaning either.
export function dpdxCoarse(v: float32): float32 { unreachable("dpdxCoarse: only a GPU fragment has one"); }
export function dpdxCoarse(v: Vec2f): Vec2f { unreachable("dpdxCoarse: only a GPU fragment has one"); }
export function dpdxCoarse(v: Vec3f): Vec3f { unreachable("dpdxCoarse: only a GPU fragment has one"); }
export function dpdxCoarse(v: Vec4f): Vec4f { unreachable("dpdxCoarse: only a GPU fragment has one"); }
export function dpdxFine(v: float32): float32 { unreachable("dpdxFine: only a GPU fragment has one"); }
export function dpdxFine(v: Vec2f): Vec2f { unreachable("dpdxFine: only a GPU fragment has one"); }
export function dpdxFine(v: Vec3f): Vec3f { unreachable("dpdxFine: only a GPU fragment has one"); }
export function dpdxFine(v: Vec4f): Vec4f { unreachable("dpdxFine: only a GPU fragment has one"); }
export function dpdyCoarse(v: float32): float32 { unreachable("dpdyCoarse: only a GPU fragment has one"); }
export function dpdyCoarse(v: Vec2f): Vec2f { unreachable("dpdyCoarse: only a GPU fragment has one"); }
export function dpdyCoarse(v: Vec3f): Vec3f { unreachable("dpdyCoarse: only a GPU fragment has one"); }
export function dpdyCoarse(v: Vec4f): Vec4f { unreachable("dpdyCoarse: only a GPU fragment has one"); }
export function dpdyFine(v: float32): float32 { unreachable("dpdyFine: only a GPU fragment has one"); }
export function dpdyFine(v: Vec2f): Vec2f { unreachable("dpdyFine: only a GPU fragment has one"); }
export function dpdyFine(v: Vec3f): Vec3f { unreachable("dpdyFine: only a GPU fragment has one"); }
export function dpdyFine(v: Vec4f): Vec4f { unreachable("dpdyFine: only a GPU fragment has one"); }
export function fwidthCoarse(v: float32): float32 { unreachable("fwidthCoarse: only a GPU fragment has one"); }
export function fwidthCoarse(v: Vec2f): Vec2f { unreachable("fwidthCoarse: only a GPU fragment has one"); }
export function fwidthCoarse(v: Vec3f): Vec3f { unreachable("fwidthCoarse: only a GPU fragment has one"); }
export function fwidthCoarse(v: Vec4f): Vec4f { unreachable("fwidthCoarse: only a GPU fragment has one"); }
export function fwidthFine(v: float32): float32 { unreachable("fwidthFine: only a GPU fragment has one"); }
export function fwidthFine(v: Vec2f): Vec2f { unreachable("fwidthFine: only a GPU fragment has one"); }
export function fwidthFine(v: Vec3f): Vec3f { unreachable("fwidthFine: only a GPU fragment has one"); }
export function fwidthFine(v: Vec4f): Vec4f { unreachable("fwidthFine: only a GPU fragment has one"); }

// WGSL's boolean vectors, and the componentwise tests and selects that make and take them.
export struct Vec2b {
	x: boolean;
	y: boolean;
}

export struct Vec3b {
	x: boolean;
	y: boolean;
	z: boolean;
}

export struct Vec4b {
	x: boolean;
	y: boolean;
	z: boolean;
	w: boolean;
}

export function vec2b(x: boolean, y: boolean): Vec2b { return { x, y }; }
export function vec3b(x: boolean, y: boolean, z: boolean): Vec3b { return { x, y, z }; }
export function vec4b(x: boolean, y: boolean, z: boolean, w: boolean): Vec4b {
	return { x, y, z, w };
}

export function eq(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x == b.x, y: a.y == b.y }; }
export function eq(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z };
}
export function eq(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z, w: a.w == b.w };
}
export function eq(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x == b.x, y: a.y == b.y }; }
export function eq(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z };
}
export function eq(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z, w: a.w == b.w };
}
export function eq(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x == b.x, y: a.y == b.y }; }
export function eq(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z };
}
export function eq(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x == b.x, y: a.y == b.y, z: a.z == b.z, w: a.w == b.w };
}

export function ne(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x != b.x, y: a.y != b.y }; }
export function ne(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z };
}
export function ne(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z, w: a.w != b.w };
}
export function ne(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x != b.x, y: a.y != b.y }; }
export function ne(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z };
}
export function ne(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z, w: a.w != b.w };
}
export function ne(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x != b.x, y: a.y != b.y }; }
export function ne(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z };
}
export function ne(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z, w: a.w != b.w };
}

export function lt(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x < b.x, y: a.y < b.y }; }
export function lt(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z };
}
export function lt(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z, w: a.w < b.w };
}
export function lt(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x < b.x, y: a.y < b.y }; }
export function lt(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z };
}
export function lt(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z, w: a.w < b.w };
}
export function lt(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x < b.x, y: a.y < b.y }; }
export function lt(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z };
}
export function lt(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x < b.x, y: a.y < b.y, z: a.z < b.z, w: a.w < b.w };
}

export function le(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x <= b.x, y: a.y <= b.y }; }
export function le(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z };
}
export function le(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z, w: a.w <= b.w };
}
export function le(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x <= b.x, y: a.y <= b.y }; }
export function le(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z };
}
export function le(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z, w: a.w <= b.w };
}
export function le(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x <= b.x, y: a.y <= b.y }; }
export function le(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z };
}
export function le(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x <= b.x, y: a.y <= b.y, z: a.z <= b.z, w: a.w <= b.w };
}

export function gt(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x > b.x, y: a.y > b.y }; }
export function gt(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z };
}
export function gt(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z, w: a.w > b.w };
}
export function gt(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x > b.x, y: a.y > b.y }; }
export function gt(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z };
}
export function gt(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z, w: a.w > b.w };
}
export function gt(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x > b.x, y: a.y > b.y }; }
export function gt(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z };
}
export function gt(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x > b.x, y: a.y > b.y, z: a.z > b.z, w: a.w > b.w };
}

export function ge(a: Vec2f, b: Vec2f): Vec2b { return { x: a.x >= b.x, y: a.y >= b.y }; }
export function ge(a: Vec3f, b: Vec3f): Vec3b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z };
}
export function ge(a: Vec4f, b: Vec4f): Vec4b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z, w: a.w >= b.w };
}
export function ge(a: Vec2i, b: Vec2i): Vec2b { return { x: a.x >= b.x, y: a.y >= b.y }; }
export function ge(a: Vec3i, b: Vec3i): Vec3b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z };
}
export function ge(a: Vec4i, b: Vec4i): Vec4b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z, w: a.w >= b.w };
}
export function ge(a: Vec2u, b: Vec2u): Vec2b { return { x: a.x >= b.x, y: a.y >= b.y }; }
export function ge(a: Vec3u, b: Vec3u): Vec3b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z };
}
export function ge(a: Vec4u, b: Vec4u): Vec4b {
	return { x: a.x >= b.x, y: a.y >= b.y, z: a.z >= b.z, w: a.w >= b.w };
}

export function any(v: Vec2b): boolean { return v.x || v.y; }
export function any(v: Vec3b): boolean { return v.x || v.y || v.z; }
export function any(v: Vec4b): boolean { return v.x || v.y || v.z || v.w; }
export function all(v: Vec2b): boolean { return v.x && v.y; }
export function all(v: Vec3b): boolean { return v.x && v.y && v.z; }
export function all(v: Vec4b): boolean { return v.x && v.y && v.z && v.w; }
export function not(v: boolean): boolean { return !v; }
export function not(v: Vec2b): Vec2b { return { x: !v.x, y: !v.y }; }
export function not(v: Vec3b): Vec3b { return { x: !v.x, y: !v.y, z: !v.z }; }
export function not(v: Vec4b): Vec4b { return { x: !v.x, y: !v.y, z: !v.z, w: !v.w }; }

// WGSL's operand order: the value when false comes first.
export function select(f: float32, t: float32, cond: boolean): float32 { return cond ? t : f; }
export function select(f: int32, t: int32, cond: boolean): int32 { return cond ? t : f; }
export function select(f: uint32, t: uint32, cond: boolean): uint32 { return cond ? t : f; }
export function select(f: boolean, t: boolean, cond: boolean): boolean { return cond ? t : f; }
export function select(f: Vec2f, t: Vec2f, cond: boolean): Vec2f { return cond ? t : f; }
export function select(f: Vec2f, t: Vec2f, cond: Vec2b): Vec2f {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y };
}
export function select(f: Vec3f, t: Vec3f, cond: boolean): Vec3f { return cond ? t : f; }
export function select(f: Vec3f, t: Vec3f, cond: Vec3b): Vec3f {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y, z: cond.z ? t.z : f.z };
}
export function select(f: Vec4f, t: Vec4f, cond: boolean): Vec4f { return cond ? t : f; }
export function select(f: Vec4f, t: Vec4f, cond: Vec4b): Vec4f {
	return {
		x: cond.x ? t.x : f.x,
		y: cond.y ? t.y : f.y,
		z: cond.z ? t.z : f.z,
		w: cond.w ? t.w : f.w,
	};
}
export function select(f: Vec2i, t: Vec2i, cond: boolean): Vec2i { return cond ? t : f; }
export function select(f: Vec2i, t: Vec2i, cond: Vec2b): Vec2i {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y };
}
export function select(f: Vec3i, t: Vec3i, cond: boolean): Vec3i { return cond ? t : f; }
export function select(f: Vec3i, t: Vec3i, cond: Vec3b): Vec3i {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y, z: cond.z ? t.z : f.z };
}
export function select(f: Vec4i, t: Vec4i, cond: boolean): Vec4i { return cond ? t : f; }
export function select(f: Vec4i, t: Vec4i, cond: Vec4b): Vec4i {
	return {
		x: cond.x ? t.x : f.x,
		y: cond.y ? t.y : f.y,
		z: cond.z ? t.z : f.z,
		w: cond.w ? t.w : f.w,
	};
}
export function select(f: Vec2u, t: Vec2u, cond: boolean): Vec2u { return cond ? t : f; }
export function select(f: Vec2u, t: Vec2u, cond: Vec2b): Vec2u {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y };
}
export function select(f: Vec3u, t: Vec3u, cond: boolean): Vec3u { return cond ? t : f; }
export function select(f: Vec3u, t: Vec3u, cond: Vec3b): Vec3u {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y, z: cond.z ? t.z : f.z };
}
export function select(f: Vec4u, t: Vec4u, cond: boolean): Vec4u { return cond ? t : f; }
export function select(f: Vec4u, t: Vec4u, cond: Vec4b): Vec4u {
	return {
		x: cond.x ? t.x : f.x,
		y: cond.y ? t.y : f.y,
		z: cond.z ? t.z : f.z,
		w: cond.w ? t.w : f.w,
	};
}
export function select(f: Vec2b, t: Vec2b, cond: boolean): Vec2b { return cond ? t : f; }
export function select(f: Vec2b, t: Vec2b, cond: Vec2b): Vec2b {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y };
}
export function select(f: Vec3b, t: Vec3b, cond: boolean): Vec3b { return cond ? t : f; }
export function select(f: Vec3b, t: Vec3b, cond: Vec3b): Vec3b {
	return { x: cond.x ? t.x : f.x, y: cond.y ? t.y : f.y, z: cond.z ? t.z : f.z };
}
export function select(f: Vec4b, t: Vec4b, cond: boolean): Vec4b { return cond ? t : f; }
export function select(f: Vec4b, t: Vec4b, cond: Vec4b): Vec4b {
	return {
		x: cond.x ? t.x : f.x,
		y: cond.y ? t.y : f.y,
		z: cond.z ? t.z : f.z,
		w: cond.w ? t.w : f.w,
	};
}
export function builtin(): void {}
export function location(): void {}
export function binding(): void {}
export function sampleType(): void {}
export function samplerType(): void {}
export function feature(): void {}
export function interpolate(): void {}
export function access(): void {}
export function format(): void {}

export function workgroupBarrier(): void {}
export function storageBarrier(): void {}
export function textureBarrier(): void {}

// WGSL's workgroupUniformLoad(&v): a barrier, a read of workgroup memory that every invocation
// of the group sees alike, and a barrier. The CPU runs one invocation at a time, so it is the read.
export function workgroupUniformLoad(ref v: float32): float32 { return v; }
export function workgroupUniformLoad(ref v: int32): int32 { return v; }
export function workgroupUniformLoad(ref v: uint32): uint32 { return v; }
export function workgroupUniformLoad(ref v: boolean): boolean { return v; }

// WGSL's atomic<i32> and atomic<u32>, in a storage buffer element or workgroup memory. An
// operation takes it by ref, as WGSL takes &a; the CPU runs one invocation at a time, so each
// is a plain read-modify-write that returns the old value.
export struct AtomicI32 {
	value: int32;
}

export struct AtomicU32 {
	value: uint32;
}

export struct AtomicExchangeI32 {
	oldValue: int32;
	exchanged: boolean;
}

export struct AtomicExchangeU32 {
	oldValue: uint32;
	exchanged: boolean;
}

export function atomicLoad(ref a: AtomicI32): int32 { return a.value; }
export function atomicLoad(ref a: AtomicU32): uint32 { return a.value; }
export function atomicStore(ref a: AtomicI32, v: int32): void { a.value = v; }
export function atomicStore(ref a: AtomicU32, v: uint32): void { a.value = v; }

export function atomicAdd(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = old + v;
	return old;
}

export function atomicAdd(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = old + v;
	return old;
}

export function atomicSub(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = old - v;
	return old;
}

export function atomicSub(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = old - v;
	return old;
}

export function atomicMax(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = v > old ? v : old;
	return old;
}

export function atomicMax(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = v > old ? v : old;
	return old;
}

export function atomicMin(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = v < old ? v : old;
	return old;
}

export function atomicMin(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = v < old ? v : old;
	return old;
}

export function atomicAnd(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = old & v;
	return old;
}

export function atomicAnd(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = old & v;
	return old;
}

export function atomicOr(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = old | v;
	return old;
}

export function atomicOr(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = old | v;
	return old;
}

export function atomicXor(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = old ^ v;
	return old;
}

export function atomicXor(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = old ^ v;
	return old;
}

export function atomicExchange(ref a: AtomicI32, v: int32): int32 {
	const old = a.value;
	a.value = v;
	return old;
}

export function atomicExchange(ref a: AtomicU32, v: uint32): uint32 {
	const old = a.value;
	a.value = v;
	return old;
}

// A weak exchange may fail on the GPU though the values match; the CPU's never does.
export function atomicCompareExchangeWeak(
	ref a: AtomicI32,
	compare: int32,
	v: int32,
): AtomicExchangeI32 {
	const old = a.value;
	if (old == compare) { a.value = v; }
	return { oldValue: old, exchanged: old == compare };
}

export function atomicCompareExchangeWeak(
	ref a: AtomicU32,
	compare: uint32,
	v: uint32,
): AtomicExchangeU32 {
	const old = a.value;
	if (old == compare) { a.value = v; }
	return { oldValue: old, exchanged: old == compare };
}

export function discard(): never {
	unreachable("discard: a fragment is discarded only on the GPU");
}

export struct Texture2d {
	width: int32;
	height: int32;
	texels: float32[];
}

// The sampler a void3d texture is drawn with (src/gpu/doorGpu.ms doorMakeSampler): one filter for
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
	const first = texelFirst("textureStore", texture.width, texture.height, 1, at.x, at.y, 0);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2d, at: Vec2i): Vec4f {
	const first = texelFirst("textureLoad", texture.width, texture.height, 1, at.x, at.y, 0);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_storage_2d_array: textureStore and textureLoad name the layer as an operand of
// its own, after the texel coordinate. Its texels run layer by layer, four floats a texel.
export struct StorageTexture2dArray {
	width: int32;
	height: int32;
	layers: int32;
	texels: float32[];
}

export function textureDimensions(texture: StorageTexture2dArray): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(
	texture: StorageTexture2dArray,
	at: Vec2i,
	layer: int32,
	value: Vec4f,
): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2dArray, at: Vec2i, layer: int32): Vec4f {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_storage_3d: its texels run slice by slice, four floats a texel.
export struct StorageTexture3d {
	width: int32;
	height: int32;
	depth: int32;
	texels: float32[];
}

export function textureDimensions(texture: StorageTexture3d): Vec3i {
	return { x: texture.width, y: texture.height, z: texture.depth };
}

export function textureStore(texture: StorageTexture3d, at: Vec3i, value: Vec4f): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture3d, at: Vec3i): Vec4f {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_storage_1d: one row of texels addressed by a scalar, four floats a texel.
export struct StorageTexture1d {
	width: int32;
	texels: float32[];
}

export function textureDimensions(texture: StorageTexture1d): int32 {
	return texture.width;
}

export function textureStore(texture: StorageTexture1d, at: int32, value: Vec4f): void {
	const first = texelFirst("textureStore", texture.width, 1, 1, at, 0, 0);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture1d, at: int32): Vec4f {
	const first = texelFirst("textureLoad", texture.width, 1, 1, at, 0, 0);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_storage_2d of a uint format (r32uint, rgba16uint, ...): its texel is a
// vec4<u32>, so the texels are four uint32 each and textureLoad and textureStore take a Vec4u.
export struct StorageTexture2dU32 {
	width: int32;
	height: int32;
	texels: uint32[];
}

export function textureDimensions(texture: StorageTexture2dU32): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(texture: StorageTexture2dU32, at: Vec2i, value: Vec4u): void {
	const first = texelFirst("textureStore", texture.width, texture.height, 1, at.x, at.y, 0);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2dU32, at: Vec2i): Vec4u {
	const first = texelFirst("textureLoad", texture.width, texture.height, 1, at.x, at.y, 0);
	return loadTexel(texture.texels, first);
}

export struct StorageTexture2dArrayU32 {
	width: int32;
	height: int32;
	layers: int32;
	texels: uint32[];
}

export function textureDimensions(texture: StorageTexture2dArrayU32): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(
	texture: StorageTexture2dArrayU32,
	at: Vec2i,
	layer: int32,
	value: Vec4u,
): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2dArrayU32, at: Vec2i, layer: int32): Vec4u {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	return loadTexel(texture.texels, first);
}

export struct StorageTexture3dU32 {
	width: int32;
	height: int32;
	depth: int32;
	texels: uint32[];
}

export function textureDimensions(texture: StorageTexture3dU32): Vec3i {
	return { x: texture.width, y: texture.height, z: texture.depth };
}

export function textureStore(texture: StorageTexture3dU32, at: Vec3i, value: Vec4u): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture3dU32, at: Vec3i): Vec4u {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_storage_2d of a sint format (r32sint, rgba16sint, ...): its texel is a
// vec4<i32>, so the texels are four int32 each and textureLoad and textureStore take a Vec4i.
export struct StorageTexture2dI32 {
	width: int32;
	height: int32;
	texels: int32[];
}

export function textureDimensions(texture: StorageTexture2dI32): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(texture: StorageTexture2dI32, at: Vec2i, value: Vec4i): void {
	const first = texelFirst("textureStore", texture.width, texture.height, 1, at.x, at.y, 0);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2dI32, at: Vec2i): Vec4i {
	const first = texelFirst("textureLoad", texture.width, texture.height, 1, at.x, at.y, 0);
	return loadTexel(texture.texels, first);
}

export struct StorageTexture2dArrayI32 {
	width: int32;
	height: int32;
	layers: int32;
	texels: int32[];
}

export function textureDimensions(texture: StorageTexture2dArrayI32): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureStore(
	texture: StorageTexture2dArrayI32,
	at: Vec2i,
	layer: int32,
	value: Vec4i,
): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture2dArrayI32, at: Vec2i, layer: int32): Vec4i {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	return loadTexel(texture.texels, first);
}

export struct StorageTexture3dI32 {
	width: int32;
	height: int32;
	depth: int32;
	texels: int32[];
}

export function textureDimensions(texture: StorageTexture3dI32): Vec3i {
	return { x: texture.width, y: texture.height, z: texture.depth };
}

export function textureStore(texture: StorageTexture3dI32, at: Vec3i, value: Vec4i): void {
	const first = texelFirst("textureStore", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	storeTexel(texture.texels, first, value);
}

export function textureLoad(texture: StorageTexture3dI32, at: Vec3i): Vec4i {
	const first = texelFirst("textureLoad", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	return loadTexel(texture.texels, first);
}

function insideTexture(width: int32, height: int32, at: Vec2i): boolean {
	return at.x >= 0 && at.y >= 0 && at.x < width && at.y < height;
}

function checkedLayer(op: string, layer: int32, layers: int32): void {
	if (layer < 0 || layer >= layers) {
		throw new Error(op + ": the layer is outside the texture");
	}
}

// The index of a texel's first component in texels that run slice by slice, four to a texel.
function texelFirst(
	op: string,
	width: int32,
	height: int32,
	depth: int32,
	x: int32,
	y: int32,
	z: int32,
): int32 {
	if (x < 0 || y < 0 || z < 0 || x >= width || y >= height || z >= depth) {
		throw new Error(op + ": the texel is outside the texture");
	}
	return ((z * height + y) * width + x) * 4;
}

function storeTexel(texels: float32[], first: int32, value: Vec4f): void {
	texels[first] = value.x;
	texels[first + 1] = value.y;
	texels[first + 2] = value.z;
	texels[first + 3] = value.w;
}

function loadTexel(texels: float32[], first: int32): Vec4f {
	return { x: texels[first], y: texels[first + 1], z: texels[first + 2], w: texels[first + 3] };
}

function storeTexel(texels: uint32[], first: int32, value: Vec4u): void {
	texels[first] = value.x;
	texels[first + 1] = value.y;
	texels[first + 2] = value.z;
	texels[first + 3] = value.w;
}

function loadTexel(texels: uint32[], first: int32): Vec4u {
	return { x: texels[first], y: texels[first + 1], z: texels[first + 2], w: texels[first + 3] };
}

function storeTexel(texels: int32[], first: int32, value: Vec4i): void {
	texels[first] = value.x;
	texels[first + 1] = value.y;
	texels[first + 2] = value.z;
	texels[first + 3] = value.w;
}

function loadTexel(texels: int32[], first: int32): Vec4i {
	return { x: texels[first], y: texels[first + 1], z: texels[first + 2], w: texels[first + 3] };
}

// The size is signed, as the texel coordinate it bounds is (docs/VOCABULARY.md, "A name brings
// its meaning").
export function textureDimensions(texture: Texture2d, level: int32): Vec2i {
	if (level != 0) { unreachable("textureDimensions: the CPU texture has no mip levels"); }
	return { x: texture.width, y: texture.height };
}

export function textureLoad(texture: Texture2d, at: Vec2i, level: int32): Vec4f {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	if (!insideTexture(texture.width, texture.height, at)) {
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

export function textureLoad(texture: Texture2dU32, at: Vec2i, level: int32): Vec4u {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	const first = texelFirst("textureLoad", texture.width, texture.height, 1, at.x, at.y, 0);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_2d_array<u32>: layers of one size, four uint32s a texel, fetched, never filtered.
export struct Texture2dArrayU32 {
	width: int32;
	height: int32;
	layers: int32;
	texels: uint32[];
}

export function textureLoad(
	texture: Texture2dArrayU32,
	at: Vec2i,
	layer: int32,
	level: int32,
): Vec4u {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	checkedLayer("textureLoad", layer, texture.layers);
	const first = texelFirst(
		"textureLoad", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_3d<u32>: slices of one size, four uint32s a texel, fetched, never filtered.
export struct Texture3dU32 {
	width: int32;
	height: int32;
	depth: int32;
	texels: uint32[];
}

export function textureLoad(texture: Texture3dU32, at: Vec3i, level: int32): Vec4u {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	const first = texelFirst(
		"textureLoad", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_2d_array<f32>: layers of one size, one picked by its index.
export struct Texture2dArray {
	width: int32;
	height: int32;
	layers: int32;
	texels: float32[];
}

function sliceTexels(texels: float32[], first: int32, count: int32): float32[] {
	let slice: float32[] = [];
	for (let i = 0; i < count; i++) { slice.push(texels[first + i]); }
	return slice;
}

function layerOf(op: string, texture: Texture2dArray, layer: int32): Texture2d {
	checkedLayer(op, layer, texture.layers);
	const size = texture.width * texture.height * 4;
	return {
		width: texture.width,
		height: texture.height,
		texels: sliceTexels(texture.texels, layer * size, size),
	};
}

export function textureLoad(
	texture: Texture2dArray,
	at: Vec2i,
	layer: int32,
	level: int32,
): Vec4f {
	return textureLoad(layerOf("textureLoad", texture, layer), at, level);
}

export function textureSample(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
): Vec4f {
	return textureSample(layerOf("textureSample", texture, layer), sampler, uv);
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

export function textureSampleBias(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	bias: float32,
): Vec4f {
	return textureSample(texture, sampler, uv);
}

export function textureSampleGrad(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	ddx: Vec2f,
	ddy: Vec2f,
): Vec4f {
	return textureSample(texture, sampler, uv);
}

export function textureSampleLevel(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	level: float32,
): Vec4f {
	return textureSample(layerOf("textureSampleLevel", texture, layer), sampler, uv);
}

export function textureSampleBias(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	bias: float32,
): Vec4f {
	return textureSample(layerOf("textureSampleBias", texture, layer), sampler, uv);
}

export function textureSampleGrad(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	ddx: Vec2f,
	ddy: Vec2f,
): Vec4f {
	return textureSample(layerOf("textureSampleGrad", texture, layer), sampler, uv);
}

// WGSL's texture_cube<f32>: six square faces in the order +X, -X, +Y, -Y, +Z, -Z.
export struct TextureCube {
	size: int32;
	texels: float32[];
}

// The face a direction reads and where on it, by the OpenGL specification's cube map table
// ("Cube Map Texture Selection"): the major axis picks the face, a tie going to x, then y.
function cubeFaceIndex(dir: Vec3f): int32 {
	const ax = abs(dir.x);
	const ay = abs(dir.y);
	const az = abs(dir.z);
	return ax >= ay && ax >= az ? (dir.x >= 0.0 ? 0 : 1) :
		ay >= az ? (dir.y >= 0.0 ? 2 : 3) : (dir.z >= 0.0 ? 4 : 5);
}

function cubeFaceOf(texture: TextureCube, dir: Vec3f): Texture2d {
	const face = cubeFaceIndex(dir);
	const size = texture.size * texture.size * 4;
	return {
		width: texture.size,
		height: texture.size,
		texels: sliceTexels(texture.texels, face * size, size),
	};
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
	const texels = texture.texels;
	return { x: texels[first], y: texels[first + 1], z: texels[first + 2], w: texels[first + 3] };
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

// WGSL's texture offset is a constant in [-8, 7] added to the texel indices before they wrap
// (the Vulkan specification's "Texel Offset" and "Wrapping Operation").
function checkedOffset(offset: Vec2i): Vec2i {
	if (offset.x < -8 || offset.x > 7 || offset.y < -8 || offset.y > 7) {
		unreachable("a texture offset is a constant in [-8, 7]");
	}
	return offset;
}

function sampleAt(texture: Texture2d, sampler: Sampler, uv: Vec2f, offset: Vec2i): Vec4f {
	const width = texture.width;
	const height = texture.height;
	const wrap = sampler.wrap;
	if (sampler.nearest) {
		const x = wrapped(texelIndex(uv.x * (width as float32)) + offset.x, width, wrap);
		return texelAt(texture, x,
			wrapped(texelIndex(uv.y * (height as float32)) + offset.y, height, wrap));
	}
	const u: float32 = uv.x * (width as float32) - 0.5;
	const v: float32 = uv.y * (height as float32) - 0.5;
	const column = texelIndex(u);
	const row = texelIndex(v);
	const x0 = wrapped(column + offset.x, width, wrap);
	const x1 = wrapped(column + 1 + offset.x, width, wrap);
	const y0 = wrapped(row + offset.y, height, wrap);
	const y1 = wrapped(row + 1 + offset.y, height, wrap);
	const fractionU: float32 = u - (column as float32);
	const fractionV: float32 = v - (row as float32);
	const top = lerp(texelAt(texture, x0, y0), texelAt(texture, x1, y0), fractionU);
	const bottom = lerp(texelAt(texture, x0, y1), texelAt(texture, x1, y1), fractionU);
	return lerp(top, bottom, fractionV);
}

// WGSL's textureSample on a texture of one mip level, as void3d's are.
export function textureSample(texture: Texture2d, sampler: Sampler, uv: Vec2f): Vec4f {
	return sampleAt(texture, sampler, uv, { x: 0, y: 0 });
}

export function textureSample(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	offset: Vec2i,
): Vec4f {
	return sampleAt(texture, sampler, uv, checkedOffset(offset));
}

// WGSL's texture_2d<i32>: four int32 a texel, fetched, never filtered.
export struct Texture2dI32 {
	width: int32;
	height: int32;
	texels: int32[];
}

export function textureLoad(texture: Texture2dI32, at: Vec2i, level: int32): Vec4i {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	const first = texelFirst("textureLoad", texture.width, texture.height, 1, at.x, at.y, 0);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_2d_array<i32>: layers of one size, four int32s a texel, fetched, never filtered.
export struct Texture2dArrayI32 {
	width: int32;
	height: int32;
	layers: int32;
	texels: int32[];
}

export function textureLoad(
	texture: Texture2dArrayI32,
	at: Vec2i,
	layer: int32,
	level: int32,
): Vec4i {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	checkedLayer("textureLoad", layer, texture.layers);
	const first = texelFirst(
		"textureLoad", texture.width, texture.height, texture.layers, at.x, at.y, layer);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_3d<i32>: slices of one size, four int32s a texel, fetched, never filtered.
export struct Texture3dI32 {
	width: int32;
	height: int32;
	depth: int32;
	texels: int32[];
}

export function textureLoad(texture: Texture3dI32, at: Vec3i, level: int32): Vec4i {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	const first = texelFirst(
		"textureLoad", texture.width, texture.height, texture.depth, at.x, at.y, at.z);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_multisampled_2d<f32>: `samples` images of one size, four floats a texel, the
// sample of a texel at `((sample * height + y) * width + x) * 4`. It is fetched, never filtered.
export struct TextureMultisampled2d {
	width: int32;
	height: int32;
	samples: int32;
	texels: float32[];
}

export function textureDimensions(texture: TextureMultisampled2d): Vec2i {
	return { x: texture.width, y: texture.height };
}

export function textureNumSamples(texture: TextureMultisampled2d): int32 {
	return texture.samples;
}

export function textureLoad(
	texture: TextureMultisampled2d,
	at: Vec2i,
	sampleIndex: int32,
): Vec4f {
	if (sampleIndex < 0 || sampleIndex >= texture.samples) {
		unreachable("textureLoad: the sample is outside the texture");
	}
	const first = texelFirst(
		"textureLoad", texture.width, texture.height, texture.samples, at.x, at.y, sampleIndex);
	return loadTexel(texture.texels, first);
}

// WGSL's texture_1d<f32>: one row of texels addressed by a scalar, four floats a texel. WGSL gives
// it textureSample and textureSampleLevel only, never a bias, derivatives or an offset, and it has
// one mip level, so a sample is the 2D sample of a one-texel-high texture at the middle of its row.
export struct Texture1d {
	width: int32;
	texels: float32[];
}

function rowOf(texture: Texture1d): Texture2d {
	return { width: texture.width, height: 1, texels: texture.texels };
}

export function textureDimensions(texture: Texture1d, level: int32): int32 {
	if (level != 0) { unreachable("textureDimensions: the CPU texture has no mip levels"); }
	return texture.width;
}

export function textureLoad(texture: Texture1d, at: int32, level: int32): Vec4f {
	return textureLoad(rowOf(texture), { x: at, y: 0 }, level);
}

export function textureSample(texture: Texture1d, sampler: Sampler, u: float32): Vec4f {
	return textureSample(rowOf(texture), sampler, { x: u, y: 0.5 });
}

export function textureSampleLevel(
	texture: Texture1d,
	sampler: Sampler,
	u: float32,
	level: float32,
): Vec4f {
	return textureSample(texture, sampler, u);
}

// WGSL's texture_3d<f32>: slices of one size, four floats a texel.
export struct Texture3d {
	width: int32;
	height: int32;
	depth: int32;
	texels: float32[];
}

function sliceOf(texture: Texture3d, z: int32): Texture2d {
	const size = texture.width * texture.height * 4;
	return {
		width: texture.width,
		height: texture.height,
		texels: sliceTexels(texture.texels, z * size, size),
	};
}

export function textureDimensions(texture: Texture3d, level: int32): Vec3i {
	if (level != 0) { unreachable("textureDimensions: the CPU texture has no mip levels"); }
	return { x: texture.width, y: texture.height, z: texture.depth };
}

export function textureLoad(texture: Texture3d, at: Vec3i, level: int32): Vec4f {
	if (level != 0) { unreachable("textureLoad: the CPU texture has no mip levels"); }
	if (at.z < 0 || at.z >= texture.depth ||
		!insideTexture(texture.width, texture.height, { x: at.x, y: at.y })) {
		unreachable("textureLoad: the texel is outside the texture");
	}
	return texelAt(sliceOf(texture, at.z), at.x, at.y);
}

// Trilinear on a texture of one level: each of the two slices around the coordinate is sampled
// as textureSample, then the results mix by the coordinate's fraction between them.
function sample3d(texture: Texture3d, sampler: Sampler, uv: Vec3f, offset: Vec3i): Vec4f {
	const depth = texture.depth;
	const flat: Vec2f = { x: uv.x, y: uv.y };
	const plane: Vec2i = checkedOffset({ x: offset.x, y: offset.y });
	if (offset.z < -8 || offset.z > 7) { unreachable("a texture offset is a constant in [-8, 7]"); }
	if (sampler.nearest) {
		const z = wrapped(texelIndex(uv.z * (depth as float32)) + offset.z, depth, sampler.wrap);
		return sampleAt(sliceOf(texture, z), sampler, flat, plane);
	}
	const w: float32 = uv.z * (depth as float32) - 0.5;
	const slice = texelIndex(w);
	const z0 = wrapped(slice + offset.z, depth, sampler.wrap);
	const z1 = wrapped(slice + 1 + offset.z, depth, sampler.wrap);
	return lerp(sampleAt(sliceOf(texture, z0), sampler, flat, plane),
		sampleAt(sliceOf(texture, z1), sampler, flat, plane), w - (slice as float32));
}

export function textureSample(texture: Texture3d, sampler: Sampler, uv: Vec3f): Vec4f {
	return sample3d(texture, sampler, uv, { x: 0, y: 0, z: 0 });
}

export function textureSample(
	texture: Texture3d,
	sampler: Sampler,
	uv: Vec3f,
	offset: Vec3i,
): Vec4f {
	return sample3d(texture, sampler, uv, offset);
}

export function textureSampleLevel(
	texture: Texture3d,
	sampler: Sampler,
	uv: Vec3f,
	level: float32,
): Vec4f {
	return textureSample(texture, sampler, uv);
}

// WGSL's sampler_comparison: Sampler's filter and wrap, and the function a depth texel is
// compared with, as the Vulkan specification's "Depth Compare Operation" (reference OP texel).
export struct SamplerComparison {
	nearest: boolean;
	wrap: Wrap;
	compare: Compare;
}

// WGSL's texture_depth_2d, texture_depth_2d_array and texture_depth_cube: one float32 a texel.
export struct TextureDepth2d {
	width: int32;
	height: int32;
	texels: float32[];
}

export struct TextureDepth2dArray {
	width: int32;
	height: int32;
	layers: int32;
	texels: float32[];
}

export struct TextureDepthCube {
	size: int32;
	texels: float32[];
}

function depthPasses(compare: Compare, reference: float32, depth: float32): float32 {
	const passes = match (compare) {
		Compare.Always => true,
		Compare.Never => false,
		Compare.Equal => reference == depth,
		Compare.NotEqual => reference != depth,
		Compare.Greater => reference > depth,
		Compare.GreaterEqual => reference >= depth,
		Compare.Less => reference < depth,
		Compare.LessEqual => reference <= depth,
	};
	return passes ? 1.0 : 0.0;
}

// The comparison runs per texel before the filter mixes the results (PCF), so the compared
// texels become a color texture whose x is the result, and textureSample does the rest.
function comparedTexels(
	sampler: SamplerComparison,
	reference: float32,
	texels: float32[],
	first: int32,
	size: Vec2i,
): Texture2d {
	let compared: float32[] = [];
	for (let i = 0; i < size.x * size.y; i++) {
		compared.push(depthPasses(sampler.compare, reference, texels[first + i]));
		compared.push(0.0);
		compared.push(0.0);
		compared.push(0.0);
	}
	return { width: size.x, height: size.y, texels: compared };
}

function plainSampler(sampler: SamplerComparison): Sampler {
	return { nearest: sampler.nearest, wrap: sampler.wrap };
}

export function textureSampleCompare(
	texture: TextureDepth2d,
	sampler: SamplerComparison,
	uv: Vec2f,
	reference: float32,
): float32 {
	const size: Vec2i = { x: texture.width, y: texture.height };
	const compared = comparedTexels(sampler, reference, texture.texels, 0, size);
	return textureSample(compared, plainSampler(sampler), uv).x;
}

export function textureSampleCompare(
	texture: TextureDepth2dArray,
	sampler: SamplerComparison,
	uv: Vec2f,
	layer: int32,
	reference: float32,
): float32 {
	checkedLayer("textureSampleCompare", layer, texture.layers);
	const size: Vec2i = { x: texture.width, y: texture.height };
	const compared = comparedTexels(sampler, reference, texture.texels,
		layer * texture.width * texture.height, size);
	return textureSample(compared, plainSampler(sampler), uv).x;
}

export function textureSampleCompare(
	texture: TextureDepthCube,
	sampler: SamplerComparison,
	dir: Vec3f,
	reference: float32,
): float32 {
	const size: Vec2i = { x: texture.size, y: texture.size };
	const compared = comparedTexels(sampler, reference, texture.texels,
		cubeFaceIndex(dir) * texture.size * texture.size, size);
	const clamped: Sampler = { nearest: sampler.nearest, wrap: Wrap.Clamp };
	return textureSample(compared, clamped, cubeFaceUv(dir)).x;
}

// A CPU depth texture has one level, so the level form compares as textureSampleCompare does.
export function textureSampleCompareLevel(
	texture: TextureDepth2d,
	sampler: SamplerComparison,
	uv: Vec2f,
	reference: float32,
): float32 {
	return textureSampleCompare(texture, sampler, uv, reference);
}

export function textureSampleCompareLevel(
	texture: TextureDepth2dArray,
	sampler: SamplerComparison,
	uv: Vec2f,
	layer: int32,
	reference: float32,
): float32 {
	return textureSampleCompare(texture, sampler, uv, layer, reference);
}

export function textureSampleCompareLevel(
	texture: TextureDepthCube,
	sampler: SamplerComparison,
	dir: Vec3f,
	reference: float32,
): float32 {
	return textureSampleCompare(texture, sampler, dir, reference);
}

// WGSL's textureSampleLevel on a depth texture takes an integer level and answers the depth
// itself, no comparison. A CPU depth texture has one level and a level past the last clamps to
// it (the Vulkan specification's "Level-of-Detail Operation"), so each samples the texels as
// textureSample does, read as the x of a color texture.
function depthColor(texels: float32[], first: int32, size: Vec2i): Texture2d {
	let colors: float32[] = [];
	for (let i = 0; i < size.x * size.y; i++) {
		colors.push(texels[first + i]);
		colors.push(0.0);
		colors.push(0.0);
		colors.push(0.0);
	}
	return { width: size.x, height: size.y, texels: colors };
}

export function textureSampleLevel(
	texture: TextureDepth2d,
	sampler: Sampler,
	uv: Vec2f,
	level: int32,
): float32 {
	const size: Vec2i = { x: texture.width, y: texture.height };
	return textureSample(depthColor(texture.texels, 0, size), sampler, uv).x;
}

export function textureSampleLevel(
	texture: TextureDepth2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	level: int32,
): float32 {
	checkedLayer("textureSampleLevel", layer, texture.layers);
	const size: Vec2i = { x: texture.width, y: texture.height };
	const colors = depthColor(texture.texels, layer * texture.width * texture.height, size);
	return textureSample(colors, sampler, uv).x;
}

export function textureSampleLevel(
	texture: TextureDepthCube,
	sampler: Sampler,
	dir: Vec3f,
	level: int32,
): float32 {
	const size: Vec2i = { x: texture.size, y: texture.size };
	const colors = depthColor(texture.texels, cubeFaceIndex(dir) * texture.size * texture.size, size);
	const clamped: Sampler = { nearest: sampler.nearest, wrap: Wrap.Clamp };
	return textureSample(colors, clamped, cubeFaceUv(dir)).x;
}

// WGSL's constant texel offset on every sampling builtin that takes one: the last argument,
// a vec2<i32> (vec3<i32> for a 3d texture) in [-8, 7], shifts the texels read, not the
// coordinate, so the filter and the wrap act on the shifted indices. A cube has no offset.
export function textureSample(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	offset: Vec2i,
): Vec4f {
	return sampleAt(layerOf("textureSample", texture, layer), sampler, uv, checkedOffset(offset));
}

export function textureSampleLevel(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	level: float32,
	offset: Vec2i,
): Vec4f {
	return sampleAt(texture, sampler, uv, checkedOffset(offset));
}

export function textureSampleLevel(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	level: float32,
	offset: Vec2i,
): Vec4f {
	return sampleAt(layerOf("textureSampleLevel", texture, layer), sampler, uv, checkedOffset(offset));
}

export function textureSampleLevel(
	texture: Texture3d,
	sampler: Sampler,
	uv: Vec3f,
	level: float32,
	offset: Vec3i,
): Vec4f {
	return sample3d(texture, sampler, uv, offset);
}

export function textureSampleBias(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	bias: float32,
	offset: Vec2i,
): Vec4f {
	return sampleAt(texture, sampler, uv, checkedOffset(offset));
}

export function textureSampleBias(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	bias: float32,
	offset: Vec2i,
): Vec4f {
	return sampleAt(layerOf("textureSampleBias", texture, layer), sampler, uv, checkedOffset(offset));
}

export function textureSampleGrad(
	texture: Texture2d,
	sampler: Sampler,
	uv: Vec2f,
	ddx: Vec2f,
	ddy: Vec2f,
	offset: Vec2i,
): Vec4f {
	return sampleAt(texture, sampler, uv, checkedOffset(offset));
}

export function textureSampleGrad(
	texture: Texture2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	ddx: Vec2f,
	ddy: Vec2f,
	offset: Vec2i,
): Vec4f {
	return sampleAt(layerOf("textureSampleGrad", texture, layer), sampler, uv, checkedOffset(offset));
}

export function textureSampleLevel(
	texture: TextureDepth2d,
	sampler: Sampler,
	uv: Vec2f,
	level: int32,
	offset: Vec2i,
): float32 {
	const size: Vec2i = { x: texture.width, y: texture.height };
	return sampleAt(depthColor(texture.texels, 0, size), sampler, uv, checkedOffset(offset)).x;
}

export function textureSampleLevel(
	texture: TextureDepth2dArray,
	sampler: Sampler,
	uv: Vec2f,
	layer: int32,
	level: int32,
	offset: Vec2i,
): float32 {
	checkedLayer("textureSampleLevel", layer, texture.layers);
	const size: Vec2i = { x: texture.width, y: texture.height };
	const colors = depthColor(texture.texels, layer * texture.width * texture.height, size);
	return sampleAt(colors, sampler, uv, checkedOffset(offset)).x;
}

export function textureSampleCompare(
	texture: TextureDepth2d,
	sampler: SamplerComparison,
	uv: Vec2f,
	reference: float32,
	offset: Vec2i,
): float32 {
	const size: Vec2i = { x: texture.width, y: texture.height };
	const compared = comparedTexels(sampler, reference, texture.texels, 0, size);
	return sampleAt(compared, plainSampler(sampler), uv, checkedOffset(offset)).x;
}

export function textureSampleCompare(
	texture: TextureDepth2dArray,
	sampler: SamplerComparison,
	uv: Vec2f,
	layer: int32,
	reference: float32,
	offset: Vec2i,
): float32 {
	checkedLayer("textureSampleCompare", layer, texture.layers);
	const size: Vec2i = { x: texture.width, y: texture.height };
	const compared = comparedTexels(sampler, reference, texture.texels,
		layer * texture.width * texture.height, size);
	return sampleAt(compared, plainSampler(sampler), uv, checkedOffset(offset)).x;
}

export function textureSampleCompareLevel(
	texture: TextureDepth2d,
	sampler: SamplerComparison,
	uv: Vec2f,
	reference: float32,
	offset: Vec2i,
): float32 {
	return textureSampleCompare(texture, sampler, uv, reference, offset);
}

export function textureSampleCompareLevel(
	texture: TextureDepth2dArray,
	sampler: SamplerComparison,
	uv: Vec2f,
	layer: int32,
	reference: float32,
	offset: Vec2i,
): float32 {
	return textureSampleCompare(texture, sampler, uv, layer, reference, offset);
}

// WGSL's integer bit builtins on one invocation. The core runs on uint32 bits; int32 goes
// through int32Bits and uint32Bits, as WGSL's i32 and u32 share their bits.
export function countOneBits(x: uint32): uint32 {
	let rest = x;
	let n: uint32 = 0;
	while (rest != 0) {
		n += rest & 1;
		rest = rest >> 1;
	}
	return n;
}

export function reverseBits(x: uint32): uint32 {
	let rest = x;
	let r: uint32 = 0;
	for (let i = 0; i < 32; i++) {
		r = (r << 1) | (rest & 1);
		rest = rest >> 1;
	}
	return r;
}

function highestBit(x: uint32): int32 {
	let rest = x;
	let at = -1;
	while (rest != 0) {
		at += 1;
		rest = rest >> 1;
	}
	return at;
}

function lowestBit(x: uint32): int32 {
	if (x == 0) { return -1; }
	let rest = x;
	let at = 0;
	while ((rest & 1) == 0) {
		at += 1;
		rest = rest >> 1;
	}
	return at;
}

// WGSL: the highest 0 bit of a negative i32, and -1 (all ones as u32) when no bit qualifies.
export function firstLeadingBit(x: uint32): uint32 {
	const at = highestBit(x);
	return at < 0 ? 0xFFFFFFFF : at as uint32;
}

export function firstLeadingBit(x: int32): int32 {
	return highestBit((x < 0 ? -(x + 1) : x) as uint32);
}

export function firstTrailingBit(x: uint32): uint32 {
	const at = lowestBit(x);
	return at < 0 ? 0xFFFFFFFF : at as uint32;
}

export function firstTrailingBit(x: int32): int32 { return lowestBit(uint32Bits(x)); }

// The WGSL specification's extractBits and insertBits: offset and count clamp to the 32 bits.
export function extractBits(e: uint32, offset: uint32, count: uint32): uint32 {
	const o = min(offset, 32);
	const c = min(count, 32 - o);
	if (c == 0) { return 0; }
	return (e << (32 - c - o)) >> (32 - c);
}

export function extractBits(e: int32, offset: uint32, count: uint32): int32 {
	const o = min(offset, 32);
	const c = min(count, 32 - o);
	if (c == 0) { return 0; }
	const bits = extractBits(uint32Bits(e), o, c);
	const negative = ((bits >> (c - 1)) & 1) == 1;
	return int32Bits(negative && c < 32 ? bits | (0xFFFFFFFF << c) : bits);
}

export function insertBits(e: uint32, newBits: uint32, offset: uint32, count: uint32): uint32 {
	const o = min(offset, 32);
	const c = min(count, 32 - o);
	if (c == 0) { return e; }
	const mask = (0xFFFFFFFF >> (32 - c)) << o;
	return (e & ~mask) | ((newBits << o) & mask);
}

export function insertBits(e: int32, newBits: int32, offset: uint32, count: uint32): int32 {
	return int32Bits(insertBits(uint32Bits(e), uint32Bits(newBits), offset, count));
}

export function countOneBits(x: int32): int32 { return int32Bits(countOneBits(uint32Bits(x))); }
export function reverseBits(x: int32): int32 { return int32Bits(reverseBits(uint32Bits(x))); }

export function countOneBits(v: Vec2u): Vec2u {
	return vec2u(countOneBits(v.x), countOneBits(v.y));
}
export function reverseBits(v: Vec2u): Vec2u {
	return vec2u(reverseBits(v.x), reverseBits(v.y));
}
export function firstLeadingBit(v: Vec2u): Vec2u {
	return vec2u(firstLeadingBit(v.x), firstLeadingBit(v.y));
}
export function firstTrailingBit(v: Vec2u): Vec2u {
	return vec2u(firstTrailingBit(v.x), firstTrailingBit(v.y));
}
export function extractBits(e: Vec2u, offset: uint32, count: uint32): Vec2u {
	return vec2u(extractBits(e.x, offset, count), extractBits(e.y, offset, count));
}
export function insertBits(e: Vec2u, newBits: Vec2u, offset: uint32, count: uint32): Vec2u {
	return vec2u(insertBits(e.x, newBits.x, offset, count), insertBits(e.y, newBits.y, offset, count));
}
export function countOneBits(v: Vec3u): Vec3u {
	return vec3u(countOneBits(v.x), countOneBits(v.y), countOneBits(v.z));
}
export function reverseBits(v: Vec3u): Vec3u {
	return vec3u(reverseBits(v.x), reverseBits(v.y), reverseBits(v.z));
}
export function firstLeadingBit(v: Vec3u): Vec3u {
	return vec3u(firstLeadingBit(v.x), firstLeadingBit(v.y), firstLeadingBit(v.z));
}
export function firstTrailingBit(v: Vec3u): Vec3u {
	return vec3u(firstTrailingBit(v.x), firstTrailingBit(v.y), firstTrailingBit(v.z));
}
export function extractBits(e: Vec3u, offset: uint32, count: uint32): Vec3u {
	return vec3u(
		extractBits(e.x, offset, count),
		extractBits(e.y, offset, count),
		extractBits(e.z, offset, count)
	);
}
export function insertBits(e: Vec3u, newBits: Vec3u, offset: uint32, count: uint32): Vec3u {
	return vec3u(
		insertBits(e.x, newBits.x, offset, count),
		insertBits(e.y, newBits.y, offset, count),
		insertBits(e.z, newBits.z, offset, count)
	);
}
export function countOneBits(v: Vec4u): Vec4u {
	return vec4u(countOneBits(v.x), countOneBits(v.y), countOneBits(v.z), countOneBits(v.w));
}
export function reverseBits(v: Vec4u): Vec4u {
	return vec4u(reverseBits(v.x), reverseBits(v.y), reverseBits(v.z), reverseBits(v.w));
}
export function firstLeadingBit(v: Vec4u): Vec4u {
	return vec4u(
		firstLeadingBit(v.x),
		firstLeadingBit(v.y),
		firstLeadingBit(v.z),
		firstLeadingBit(v.w)
	);
}
export function firstTrailingBit(v: Vec4u): Vec4u {
	return vec4u(
		firstTrailingBit(v.x),
		firstTrailingBit(v.y),
		firstTrailingBit(v.z),
		firstTrailingBit(v.w)
	);
}
export function extractBits(e: Vec4u, offset: uint32, count: uint32): Vec4u {
	return vec4u(
		extractBits(e.x, offset, count),
		extractBits(e.y, offset, count),
		extractBits(e.z, offset, count),
		extractBits(e.w, offset, count)
	);
}
export function insertBits(e: Vec4u, newBits: Vec4u, offset: uint32, count: uint32): Vec4u {
	return vec4u(
		insertBits(e.x, newBits.x, offset, count),
		insertBits(e.y, newBits.y, offset, count),
		insertBits(e.z, newBits.z, offset, count),
		insertBits(e.w, newBits.w, offset, count)
	);
}
export function countOneBits(v: Vec2i): Vec2i {
	return vec2i(countOneBits(v.x), countOneBits(v.y));
}
export function reverseBits(v: Vec2i): Vec2i {
	return vec2i(reverseBits(v.x), reverseBits(v.y));
}
export function firstLeadingBit(v: Vec2i): Vec2i {
	return vec2i(firstLeadingBit(v.x), firstLeadingBit(v.y));
}
export function firstTrailingBit(v: Vec2i): Vec2i {
	return vec2i(firstTrailingBit(v.x), firstTrailingBit(v.y));
}
export function extractBits(e: Vec2i, offset: uint32, count: uint32): Vec2i {
	return vec2i(extractBits(e.x, offset, count), extractBits(e.y, offset, count));
}
export function insertBits(e: Vec2i, newBits: Vec2i, offset: uint32, count: uint32): Vec2i {
	return vec2i(insertBits(e.x, newBits.x, offset, count), insertBits(e.y, newBits.y, offset, count));
}
export function countOneBits(v: Vec3i): Vec3i {
	return vec3i(countOneBits(v.x), countOneBits(v.y), countOneBits(v.z));
}
export function reverseBits(v: Vec3i): Vec3i {
	return vec3i(reverseBits(v.x), reverseBits(v.y), reverseBits(v.z));
}
export function firstLeadingBit(v: Vec3i): Vec3i {
	return vec3i(firstLeadingBit(v.x), firstLeadingBit(v.y), firstLeadingBit(v.z));
}
export function firstTrailingBit(v: Vec3i): Vec3i {
	return vec3i(firstTrailingBit(v.x), firstTrailingBit(v.y), firstTrailingBit(v.z));
}
export function extractBits(e: Vec3i, offset: uint32, count: uint32): Vec3i {
	return vec3i(
		extractBits(e.x, offset, count),
		extractBits(e.y, offset, count),
		extractBits(e.z, offset, count)
	);
}
export function insertBits(e: Vec3i, newBits: Vec3i, offset: uint32, count: uint32): Vec3i {
	return vec3i(
		insertBits(e.x, newBits.x, offset, count),
		insertBits(e.y, newBits.y, offset, count),
		insertBits(e.z, newBits.z, offset, count)
	);
}
export function countOneBits(v: Vec4i): Vec4i {
	return vec4i(countOneBits(v.x), countOneBits(v.y), countOneBits(v.z), countOneBits(v.w));
}
export function reverseBits(v: Vec4i): Vec4i {
	return vec4i(reverseBits(v.x), reverseBits(v.y), reverseBits(v.z), reverseBits(v.w));
}
export function firstLeadingBit(v: Vec4i): Vec4i {
	return vec4i(
		firstLeadingBit(v.x),
		firstLeadingBit(v.y),
		firstLeadingBit(v.z),
		firstLeadingBit(v.w)
	);
}
export function firstTrailingBit(v: Vec4i): Vec4i {
	return vec4i(
		firstTrailingBit(v.x),
		firstTrailingBit(v.y),
		firstTrailingBit(v.z),
		firstTrailingBit(v.w)
	);
}
export function extractBits(e: Vec4i, offset: uint32, count: uint32): Vec4i {
	return vec4i(
		extractBits(e.x, offset, count),
		extractBits(e.y, offset, count),
		extractBits(e.z, offset, count),
		extractBits(e.w, offset, count)
	);
}
export function insertBits(e: Vec4i, newBits: Vec4i, offset: uint32, count: uint32): Vec4i {
	return vec4i(
		insertBits(e.x, newBits.x, offset, count),
		insertBits(e.y, newBits.y, offset, count),
		insertBits(e.z, newBits.z, offset, count),
		insertBits(e.w, newBits.w, offset, count)
	);
}

// WGSL's countLeadingZeros and countTrailingZeros: the full 32 for a zero, where firstLeadingBit and
// firstTrailingBit answer -1.
export function countLeadingZeros(x: uint32): uint32 { return (31 - highestBit(x)) as uint32; }
export function countLeadingZeros(x: int32): int32 {
	return int32Bits(countLeadingZeros(uint32Bits(x)));
}
export function countTrailingZeros(x: uint32): uint32 { return x == 0 ? 32 : lowestBit(x) as uint32; }
export function countTrailingZeros(x: int32): int32 {
	return int32Bits(countTrailingZeros(uint32Bits(x)));
}
export function countLeadingZeros(v: Vec2u): Vec2u { return vec2u(countLeadingZeros(v.x), countLeadingZeros(v.y)); }
export function countLeadingZeros(v: Vec3u): Vec3u { return vec3u(countLeadingZeros(v.x), countLeadingZeros(v.y), countLeadingZeros(v.z)); }
export function countLeadingZeros(v: Vec4u): Vec4u { return vec4u(countLeadingZeros(v.x), countLeadingZeros(v.y), countLeadingZeros(v.z), countLeadingZeros(v.w)); }
export function countLeadingZeros(v: Vec2i): Vec2i { return vec2i(countLeadingZeros(v.x), countLeadingZeros(v.y)); }
export function countLeadingZeros(v: Vec3i): Vec3i { return vec3i(countLeadingZeros(v.x), countLeadingZeros(v.y), countLeadingZeros(v.z)); }
export function countLeadingZeros(v: Vec4i): Vec4i { return vec4i(countLeadingZeros(v.x), countLeadingZeros(v.y), countLeadingZeros(v.z), countLeadingZeros(v.w)); }
export function countTrailingZeros(v: Vec2u): Vec2u { return vec2u(countTrailingZeros(v.x), countTrailingZeros(v.y)); }
export function countTrailingZeros(v: Vec3u): Vec3u { return vec3u(countTrailingZeros(v.x), countTrailingZeros(v.y), countTrailingZeros(v.z)); }
export function countTrailingZeros(v: Vec4u): Vec4u { return vec4u(countTrailingZeros(v.x), countTrailingZeros(v.y), countTrailingZeros(v.z), countTrailingZeros(v.w)); }
export function countTrailingZeros(v: Vec2i): Vec2i { return vec2i(countTrailingZeros(v.x), countTrailingZeros(v.y)); }
export function countTrailingZeros(v: Vec3i): Vec3i { return vec3i(countTrailingZeros(v.x), countTrailingZeros(v.y), countTrailingZeros(v.z)); }
export function countTrailingZeros(v: Vec4i): Vec4i { return vec4i(countTrailingZeros(v.x), countTrailingZeros(v.y), countTrailingZeros(v.z), countTrailingZeros(v.w)); }

// floor(log2(a)) of a positive finite a, corrected for log2's rounding at a power of two.
function binaryExponent(a: float64): float64 {
	let e = Math.floor(Math.log2(a));
	if (Math.pow(2.0, e) > a) { e -= 1.0; }
	if (Math.pow(2.0, e + 1.0) <= a) { e += 1.0; }
	return e;
}

// IEEE binary32 by arithmetic, as halfBits is binary16. WGSL leaves the bits of an infinity or NaN
// indeterminate, so the oracle refuses both ways.
function floatToBits(x: float32): uint32 {
	if (!(Math.abs(x) <= 3.4028234663852886e38)) {
		unreachable("bitcast: an infinity or NaN has no defined bits in WGSL");
	}
	const sign: uint32 = x < 0.0 || (x == 0.0 && 1.0 / x < 0.0) ? 0x80000000 : 0;
	const a = Math.abs(x) as float64;
	if (a < 1.1754943508222875e-38) { return sign | ((a * Math.pow(2.0, 149.0)) as uint32); }
	const e = binaryExponent(a);
	const fraction = (a / Math.pow(2.0, e) - 1.0) * 8388608.0;
	return sign | (((e + 127.0) as uint32) << 23) | (fraction as uint32);
}

function bitsToFloat(bits: uint32): float32 {
	const exponent = (bits >> 23) & 255;
	if (exponent == 255) { unreachable("bitcast: bits of an infinity or NaN are indeterminate in WGSL"); }
	const fraction = (bits & 0x7FFFFF) as float64;
	const magnitude = exponent == 0 ? fraction * Math.pow(2.0, -149.0) :
		(1.0 + fraction / 8388608.0) * Math.pow(2.0, (exponent as float64) - 127.0);
	return (bits & 0x80000000) != 0 ? -magnitude as float32 : magnitude as float32;
}

// WGSL's bitcast<T>(e) by source and target scalar, in TypeGPU's names.
export function bitcastF32toU32(x: float32): uint32 { return floatToBits(x); }
export function bitcastF32toI32(x: float32): int32 { return int32Bits(floatToBits(x)); }
export function bitcastI32toF32(x: int32): float32 { return bitsToFloat(uint32Bits(x)); }
export function bitcastI32toU32(x: int32): uint32 { return uint32Bits(x); }
export function bitcastU32toF32(x: uint32): float32 { return bitsToFloat(x); }
export function bitcastU32toI32(x: uint32): int32 { return int32Bits(x); }
export function bitcastF32toU32(v: Vec2f): Vec2u { return vec2u(bitcastF32toU32(v.x), bitcastF32toU32(v.y)); }
export function bitcastF32toU32(v: Vec3f): Vec3u { return vec3u(bitcastF32toU32(v.x), bitcastF32toU32(v.y), bitcastF32toU32(v.z)); }
export function bitcastF32toU32(v: Vec4f): Vec4u { return vec4u(bitcastF32toU32(v.x), bitcastF32toU32(v.y), bitcastF32toU32(v.z), bitcastF32toU32(v.w)); }
export function bitcastF32toI32(v: Vec2f): Vec2i { return vec2i(bitcastF32toI32(v.x), bitcastF32toI32(v.y)); }
export function bitcastF32toI32(v: Vec3f): Vec3i { return vec3i(bitcastF32toI32(v.x), bitcastF32toI32(v.y), bitcastF32toI32(v.z)); }
export function bitcastF32toI32(v: Vec4f): Vec4i { return vec4i(bitcastF32toI32(v.x), bitcastF32toI32(v.y), bitcastF32toI32(v.z), bitcastF32toI32(v.w)); }
export function bitcastI32toF32(v: Vec2i): Vec2f { return vec2f(bitcastI32toF32(v.x), bitcastI32toF32(v.y)); }
export function bitcastI32toF32(v: Vec3i): Vec3f { return vec3f(bitcastI32toF32(v.x), bitcastI32toF32(v.y), bitcastI32toF32(v.z)); }
export function bitcastI32toF32(v: Vec4i): Vec4f { return vec4f(bitcastI32toF32(v.x), bitcastI32toF32(v.y), bitcastI32toF32(v.z), bitcastI32toF32(v.w)); }
export function bitcastI32toU32(v: Vec2i): Vec2u { return vec2u(bitcastI32toU32(v.x), bitcastI32toU32(v.y)); }
export function bitcastI32toU32(v: Vec3i): Vec3u { return vec3u(bitcastI32toU32(v.x), bitcastI32toU32(v.y), bitcastI32toU32(v.z)); }
export function bitcastI32toU32(v: Vec4i): Vec4u { return vec4u(bitcastI32toU32(v.x), bitcastI32toU32(v.y), bitcastI32toU32(v.z), bitcastI32toU32(v.w)); }
export function bitcastU32toF32(v: Vec2u): Vec2f { return vec2f(bitcastU32toF32(v.x), bitcastU32toF32(v.y)); }
export function bitcastU32toF32(v: Vec3u): Vec3f { return vec3f(bitcastU32toF32(v.x), bitcastU32toF32(v.y), bitcastU32toF32(v.z)); }
export function bitcastU32toF32(v: Vec4u): Vec4f { return vec4f(bitcastU32toF32(v.x), bitcastU32toF32(v.y), bitcastU32toF32(v.z), bitcastU32toF32(v.w)); }
export function bitcastU32toI32(v: Vec2u): Vec2i { return vec2i(bitcastU32toI32(v.x), bitcastU32toI32(v.y)); }
export function bitcastU32toI32(v: Vec3u): Vec3i { return vec3i(bitcastU32toI32(v.x), bitcastU32toI32(v.y), bitcastU32toI32(v.z)); }
export function bitcastU32toI32(v: Vec4u): Vec4i { return vec4i(bitcastU32toI32(v.x), bitcastU32toI32(v.y), bitcastU32toI32(v.z), bitcastU32toI32(v.w)); }

// WGSL's data packing: component 0 in the low bits, a normalized value ⌊0.5 + scale * clamp⌋ as the
// specification defines it. A NaN has no defined packing, so the oracle refuses it.
function packedUnorm(x: float32, scale: float32): uint32 {
	if (x != x) { unreachable("a pack of NaN is indeterminate"); }
	return Math.floor(0.5 + scale * Math.min(1.0, Math.max(0.0, x))) as uint32;
}

function packedSnorm(x: float32, scale: float32, mask: uint32): uint32 {
	if (x != x) { unreachable("a pack of NaN is indeterminate"); }
	const n = Math.floor(0.5 + scale * Math.min(1.0, Math.max(-1.0, x)));
	return uint32Bits(n as int32) & mask;
}

export function pack4x8unorm(e: Vec4f): uint32 {
	return packedUnorm(e.x, 255.0) | (packedUnorm(e.y, 255.0) << 8) |
		(packedUnorm(e.z, 255.0) << 16) | (packedUnorm(e.w, 255.0) << 24);
}

export function pack4x8snorm(e: Vec4f): uint32 {
	return packedSnorm(e.x, 127.0, 0xFF) | (packedSnorm(e.y, 127.0, 0xFF) << 8) |
		(packedSnorm(e.z, 127.0, 0xFF) << 16) | (packedSnorm(e.w, 127.0, 0xFF) << 24);
}

export function pack2x16unorm(e: Vec2f): uint32 {
	return packedUnorm(e.x, 65535.0) | (packedUnorm(e.y, 65535.0) << 16);
}

export function pack2x16snorm(e: Vec2f): uint32 {
	return packedSnorm(e.x, 32767.0, 0xFFFF) | (packedSnorm(e.y, 32767.0, 0xFFFF) << 16);
}

function signedField(bits: uint32, width: uint32): int32 {
	const field = bits & ((1 << width) - 1);
	return int32Bits(field >= (1 << (width - 1)) ? field | (0xFFFFFFFF << width) : field);
}

function unorm(bits: uint32, width: uint32, shift: uint32): float32 {
	const top = (1 << width) - 1;
	return ((bits >> shift) & top) as float32 / (top as float32);
}

function snorm(bits: uint32, width: uint32, shift: uint32): float32 {
	const top = (1 << (width - 1)) - 1;
	return Math.max(signedField(bits >> shift, width) as float32 / (top as float32), -1.0) as float32;
}

export function unpack4x8unorm(e: uint32): Vec4f {
	return vec4f(unorm(e, 8, 0), unorm(e, 8, 8), unorm(e, 8, 16), unorm(e, 8, 24));
}

export function unpack4x8snorm(e: uint32): Vec4f {
	return vec4f(snorm(e, 8, 0), snorm(e, 8, 8), snorm(e, 8, 16), snorm(e, 8, 24));
}

export function unpack2x16unorm(e: uint32): Vec2f { return vec2f(unorm(e, 16, 0), unorm(e, 16, 16)); }

export function unpack2x16snorm(e: uint32): Vec2f { return vec2f(snorm(e, 16, 0), snorm(e, 16, 16)); }

function nearestEven(x: float64): float64 {
	const down = Math.floor(x);
	const rest = x - down;
	return rest > 0.5 || (rest == 0.5 && down % 2.0 == 1.0) ? down + 1.0 : down;
}

// IEEE binary16 by arithmetic, rounding to nearest even. A component the format cannot hold
// (|x| >= 65520, NaN) has no defined pack in WGSL, so the oracle refuses it.
function halfBits(x: float32): uint32 {
	if (!(Math.abs(x) < 65520.0)) { unreachable("pack2x16float: a component outside f16's range"); }
	const sign: uint32 = x < 0.0 || (x == 0.0 && 1.0 / x < 0.0) ? 0x8000 : 0;
	const a = Math.abs(x) as float64;
	if (a < 0.00006103515625) { return sign | (nearestEven(a * 16777216.0) as uint32); }
	let e = binaryExponent(a);
	let fraction = nearestEven((a / Math.pow(2.0, e) - 1.0) * 1024.0);
	if (fraction == 1024.0) {
		e += 1.0;
		fraction = 0.0;
	}
	return sign | (((e + 15.0) as uint32) << 10) | (fraction as uint32);
}

function halfValue(bits: uint32): float32 {
	const exponent = (bits >> 10) & 31;
	if (exponent == 31) { unreachable("unpack2x16float: an infinity or NaN component"); }
	const fraction = (bits & 1023) as float64;
	const magnitude = exponent == 0 ? fraction / 16777216.0 :
		(1.0 + fraction / 1024.0) * Math.pow(2.0, (exponent as float64) - 15.0);
	return (bits & 0x8000) != 0 ? -magnitude as float32 : magnitude as float32;
}

export function pack2x16float(e: Vec2f): uint32 { return halfBits(e.x) | (halfBits(e.y) << 16); }

export function unpack2x16float(e: uint32): Vec2f {
	return vec2f(halfValue(e & 0xFFFF), halfValue(e >> 16));
}
