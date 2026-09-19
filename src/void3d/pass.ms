// Render state of a material pass: port of the fixed-function half of h3d.mat.Pass
// (culling, depth, blend, colorMask). Shader lists, stencil, depth clamp and wireframe are
// not ported: a Material names one sokol-shdc program instead (docs/VOID3D.md).
//
// The state is a plain value; `bits()` packs it into the uint32 that the pipeline cache keys
// on, the way Heaps' BitsBuilder packs Pass.bits, and `RenderState.fromBits` reads it back.

// h3d.mat.Data.Face; Both is not ported (sokol has no cull-all mode).
export enum Face {
	None,
	Back,
	Front,
}

// h3d.mat.Data.Compare
export enum Compare {
	Always,
	Never,
	Equal,
	NotEqual,
	Greater,
	GreaterEqual,
	Less,
	LessEqual,
}

// h3d.mat.Data.Blend, without the constant-color factors (WebGL only in Heaps).
export enum Blend {
	One,
	Zero,
	SourceAlpha,
	SourceColor,
	DestinationAlpha,
	DestinationColor,
	OneMinusSourceAlpha,
	OneMinusSourceColor,
	OneMinusDestinationAlpha,
	OneMinusDestinationColor,
}

// h3d.mat.Data.Operation
export enum Operation {
	Add,
	Subtract,
	ReverseSubtract,
	Min,
	Max,
}

// h3d.mat.BlendMode
export enum BlendMode {
	None,
	Alpha,
	Add,
	AlphaAdd,
	SoftAdd,
	Multiply,
	AlphaMultiply,
	Erase,
	Screen,
	Subtract,
	Max,
	Min,
}

export struct RenderState {
	culling: Face;
	depthWrite: boolean;
	depthTest: Compare;
	blendSource: Blend;
	blendDestination: Blend;
	blendAlphaSource: Blend;
	blendAlphaDestination: Blend;
	blendOperation: Operation;
	blendAlphaOperation: Operation;
	colorMask: int32;
}

export const COLOR_MASK_ALL: int32 = 15;

// Bit layout of `bits()`, low to high (field widths fit every enum above).
const CULLING_SHIFT: int32 = 0;
const DEPTH_WRITE_SHIFT: int32 = 2;
const DEPTH_TEST_SHIFT: int32 = 3;
const BLEND_SOURCE_SHIFT: int32 = 6;
const BLEND_DESTINATION_SHIFT: int32 = 10;
const BLEND_ALPHA_SOURCE_SHIFT: int32 = 14;
const BLEND_ALPHA_DESTINATION_SHIFT: int32 = 18;
const BLEND_OPERATION_SHIFT: int32 = 22;
const BLEND_ALPHA_OPERATION_SHIFT: int32 = 25;
const COLOR_MASK_SHIFT: int32 = 28;

// new h3d.mat.Pass(): back faces culled, depth written and tested with Less, no blending.
export function defaults(this typeof RenderState): RenderState {
	return {
		culling: Face.Back,
		depthWrite: true,
		depthTest: Compare.Less,
		blendSource: Blend.One,
		blendDestination: Blend.Zero,
		blendAlphaSource: Blend.One,
		blendAlphaDestination: Blend.Zero,
		blendOperation: Operation.Add,
		blendAlphaOperation: Operation.Add,
		colorMask: COLOR_MASK_ALL,
	};
}

// Pass.depth(write, test)
export function withDepth(this state: RenderState, write: boolean, test: Compare): RenderState {
	return { ...state, depthWrite: write, depthTest: test };
}

export function withCulling(this state: RenderState, culling: Face): RenderState {
	return { ...state, culling: culling };
}

// Pass.blend(src, dst): the same factors for color and alpha.
export function withBlend(this state: RenderState, source: Blend, destination: Blend): RenderState {
	return {
		...state,
		blendSource: source,
		blendDestination: destination,
		blendAlphaSource: source,
		blendAlphaDestination: destination,
	};
}

// Pass.setColorMask(r, g, b, a)
export function withColorMask(
	this state: RenderState,
	red: boolean,
	green: boolean,
	blue: boolean,
	alpha: boolean,
): RenderState {
	const mask: int32 = (red ? 1 : 0) + (green ? 2 : 0) + (blue ? 4 : 0) + (alpha ? 8 : 0);
	return { ...state, colorMask: mask };
}

// The same operation for color and alpha.
export function withOperation(this state: RenderState, operation: Operation): RenderState {
	return { ...state, blendOperation: operation, blendAlphaOperation: operation };
}

// setBlendMode's `blendAlphaSrc = One`: the source alpha is written unscaled.
function withAlphaSourceOne(this state: RenderState): RenderState {
	return { ...state, blendAlphaSource: Blend.One };
}

// Pass.setBlendMode
export function withBlendMode(this state: RenderState, mode: BlendMode): RenderState {
	const added: RenderState = state.withOperation(Operation.Add);
	return match (mode) {
		BlendMode.None => added.withBlend(Blend.One, Blend.Zero),
		BlendMode.Alpha => added
			.withBlend(Blend.SourceAlpha, Blend.OneMinusSourceAlpha)
			.withAlphaSourceOne(),
		BlendMode.Add => added.withBlend(Blend.SourceAlpha, Blend.One).withAlphaSourceOne(),
		BlendMode.AlphaAdd => added.withBlend(Blend.One, Blend.OneMinusSourceAlpha),
		BlendMode.SoftAdd => added
			.withBlend(Blend.OneMinusDestinationColor, Blend.One)
			.withAlphaSourceOne(),
		BlendMode.Multiply => added
			.withBlend(Blend.DestinationColor, Blend.Zero)
			.withAlphaSourceOne(),
		BlendMode.AlphaMultiply => added
			.withBlend(Blend.DestinationColor, Blend.OneMinusSourceAlpha),
		BlendMode.Erase => added.withBlend(Blend.Zero, Blend.OneMinusSourceColor),
		BlendMode.Screen => added.withBlend(Blend.One, Blend.OneMinusSourceColor),
		BlendMode.Subtract => added
			.withBlend(Blend.SourceAlpha, Blend.One)
			.withOperation(Operation.ReverseSubtract),
		BlendMode.Max => added.withBlend(Blend.One, Blend.One).withOperation(Operation.Max),
		BlendMode.Min => added.withBlend(Blend.One, Blend.One).withOperation(Operation.Min),
	};
}

function field(value: int32, shift: int32): uint32 {
	return (value as uint32) << (shift as uint32);
}

function extract(bits: uint32, shift: int32, width: int32): int32 {
	const mask: uint32 = ((1 as uint32) << (width as uint32)) - 1;
	return ((bits >> (shift as uint32)) & mask) as int32;
}

export function bits(this state: RenderState): uint32 {
	return field(state.culling as int32, CULLING_SHIFT) |
		field(state.depthWrite ? 1 : 0, DEPTH_WRITE_SHIFT) |
		field(state.depthTest as int32, DEPTH_TEST_SHIFT) |
		field(state.blendSource as int32, BLEND_SOURCE_SHIFT) |
		field(state.blendDestination as int32, BLEND_DESTINATION_SHIFT) |
		field(state.blendAlphaSource as int32, BLEND_ALPHA_SOURCE_SHIFT) |
		field(state.blendAlphaDestination as int32, BLEND_ALPHA_DESTINATION_SHIFT) |
		field(state.blendOperation as int32, BLEND_OPERATION_SHIFT) |
		field(state.blendAlphaOperation as int32, BLEND_ALPHA_OPERATION_SHIFT) |
		field(state.colorMask, COLOR_MASK_SHIFT);
}

// One line for logs and cache diagnostics, in the spirit of Heaps' CachedPipeline.getFields.
// Allocates: keep it out of the frame loop.
export function toString(this state: RenderState): string {
	return `culling=${state.culling.toString()} depthWrite=${state.depthWrite}` +
		` depthTest=${state.depthTest.toString()}` +
		` blend=${state.blendSource.toString()},${state.blendDestination.toString()}` +
		` alphaBlend=${state.blendAlphaSource.toString()}` +
		`,${state.blendAlphaDestination.toString()}` +
		` operation=${state.blendOperation.toString()},${state.blendAlphaOperation.toString()}` +
		` colorMask=${state.colorMask}`;
}

// Pass.loadBits
export function fromBits(this typeof RenderState, bits: uint32): RenderState {
	return {
		culling: extract(bits, CULLING_SHIFT, 2) as Face,
		depthWrite: extract(bits, DEPTH_WRITE_SHIFT, 1) != 0,
		depthTest: extract(bits, DEPTH_TEST_SHIFT, 3) as Compare,
		blendSource: extract(bits, BLEND_SOURCE_SHIFT, 4) as Blend,
		blendDestination: extract(bits, BLEND_DESTINATION_SHIFT, 4) as Blend,
		blendAlphaSource: extract(bits, BLEND_ALPHA_SOURCE_SHIFT, 4) as Blend,
		blendAlphaDestination: extract(bits, BLEND_ALPHA_DESTINATION_SHIFT, 4) as Blend,
		blendOperation: extract(bits, BLEND_OPERATION_SHIFT, 3) as Operation,
		blendAlphaOperation: extract(bits, BLEND_ALPHA_OPERATION_SHIFT, 3) as Operation,
		colorMask: extract(bits, COLOR_MASK_SHIFT, 4),
	};
}
