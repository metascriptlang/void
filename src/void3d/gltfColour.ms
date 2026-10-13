import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
	GltfAccessorValues,
	GltfAccessorError,
} from "./gltfAccessor";

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
	if (source.role != GltfAccessorRole.Attribute ||
		(source.componentType != 5126 && source.componentType != 5121 &&
			source.componentType != 5123) || source.normalized != (source.componentType != 5126)) {
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
		if (decoded.error == GltfAccessorError.Bounds) { return Result.err(GltfColourError.Bounds); }
		if (decoded.error == GltfAccessorError.NonFinite) { return Result.err(GltfColourError.NonFinite); }
		return Result.err(GltfColourError.Accessor);
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
