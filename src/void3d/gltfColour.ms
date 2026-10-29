import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
	GltfAccessorValues,
	GltfAccessorError,
} from "./gltfAccessor";

const COMPONENT_FLOAT: int32 = 5126;
const COMPONENT_UNSIGNED_BYTE: int32 = 5121;
const COMPONENT_UNSIGNED_SHORT: int32 = 5123;

export enum GltfColourError {
	Encoding,
	Shape,
	Count,
	Accessor,
	Range,
	Bounds,
	NonFinite,
}

export struct GltfLinearRgba {
	red: float32;
	green: float32;
	blue: float32;
	alpha: float32;
}

export struct GltfColour {
	values: Vec<GltfLinearRgba>;
}

export function fromAccessor(
	this typeof GltfColour,
	source: GltfAccessorSource,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
	vertexCount: int32,
): Result<GltfColour, GltfColourError> {
	const floats: boolean = source.componentType == COMPONENT_FLOAT;
	const integers: boolean = source.componentType == COMPONENT_UNSIGNED_BYTE ||
		source.componentType == COMPONENT_UNSIGNED_SHORT;
	if (source.role != GltfAccessorRole.Attribute || (!floats && !integers) ||
		source.normalized != !floats) {
		return Result.err(GltfColourError.Encoding);
	}
	if (source.shape != GltfAccessorShape.Vec3 && source.shape != GltfAccessorShape.Vec4) {
		return Result.err(GltfColourError.Shape);
	}
	if (vertexCount < 1 || source.count != vertexCount) {
		return Result.err(GltfColourError.Count);
	}
	const decoded = GltfAccessorValues.decode(source, buffers, views);
	if (!decoded.ok) {
		return Result.err(match (decoded.error) {
			GltfAccessorError.Bounds => GltfColourError.Bounds,
			GltfAccessorError.NonFinite => GltfColourError.NonFinite,
			_ => GltfColourError.Accessor,
		});
	}
	const data = decoded.value;
	for (const value of data.values) {
		if (!Number.isFinite(value) || value < 0.0 || value > 1.0) {
			return Result.err(GltfColourError.Range);
		}
	}
	const components: int32 = source.shape == GltfAccessorShape.Vec3 ? 3 : 4;
	let values: Vec<GltfLinearRgba> = [];
	for (let i = 0; i < data.count; i++) {
		const start = i * components;
		values.push({
			red: data.values[start] as float32,
			green: data.values[start + 1] as float32,
			blue: data.values[start + 2] as float32,
			alpha: components == 4 ? data.values[start + 3] as float32 : 1.0,
		});
	}
	return Result.ok({ values: move values });
}
