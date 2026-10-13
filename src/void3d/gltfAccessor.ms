import { float32At } from "./gltfDecode";

export enum GltfAccessorShape {
	Scalar,
	Vec2,
	Vec3,
	Vec4,
	Mat2,
	Mat3,
	Mat4,
}

export enum GltfAccessorRole {
	Attribute,
	Indices,
	Other,
}

export enum GltfAccessorError {
	Encoding,
	Shape,
	Count,
	Bounds,
	Alignment,
	Stride,
	Target,
	SparseOrder,
	Index,
	NonFinite,
}

export struct GltfAccessorBuffer {
	bytes: Vec<uint8>;
	byteLength: int32;
}

export struct GltfAccessorView {
	buffer: int32;
	byteOffset: int32;
	byteLength: int32;
	byteStride: int32 | null;
	target: int32 | null;
}

export struct GltfSparseSource {
	count: int32;
	indicesView: int32;
	indicesByteOffset: int32;
	indicesComponentType: int32;
	valuesView: int32;
	valuesByteOffset: int32;
}

export struct GltfAccessorSource {
	bufferView: int32 | null;
	byteOffset: int32 | null;
	componentType: int32;
	shape: GltfAccessorShape;
	normalized: boolean;
	count: int32;
	role: GltfAccessorRole;
	sparse: GltfSparseSource | null;
}

export struct GltfAccessorRange {
	buffer: int32;
	byteOffset: int32;
	stride: int32;
}

export struct GltfAccessorLayout {
	componentType: int32;
	shape: GltfAccessorShape;
	normalized: boolean;
	role: GltfAccessorRole;
	count: int32;
	componentCount: int32;
	componentBytes: int32;
	columnBytes: int32;
	elementBytes: int32;
	stride: int32;
	dense: GltfAccessorRange | null;
	sparseCount: int32;
	sparseIndices: GltfAccessorRange | null;
	sparseIndexComponentType: int32;
	sparseValues: GltfAccessorRange | null;
}

export struct GltfAccessorValues {
	componentType: int32;
	shape: GltfAccessorShape;
	normalized: boolean;
	count: int32;
	values: Vec<float64>;
}

export struct GltfAccessorIndices {
	componentType: int32;
	values: Vec<uint32>;
}

function componentSize(component: int32): int32 {
	return match (component) {
		5120 | 5121 => 1,
		5122 | 5123 => 2,
		5125 | 5126 => 4,
		_ => 0,
	};
}

function componentsOf(shape: GltfAccessorShape): int32 {
	return match (shape) {
		GltfAccessorShape.Scalar => 1,
		GltfAccessorShape.Vec2 => 2,
		GltfAccessorShape.Vec3 => 3,
		GltfAccessorShape.Vec4 | GltfAccessorShape.Mat2 => 4,
		GltfAccessorShape.Mat3 => 9,
		GltfAccessorShape.Mat4 => 16,
		_ => 0,
	};
}

function matrixRows(shape: GltfAccessorShape): int32 {
	return match (shape) {
		GltfAccessorShape.Mat2 => 2,
		GltfAccessorShape.Mat3 => 3,
		GltfAccessorShape.Mat4 => 4,
		_ => 0,
	};
}

function isUnsigned(component: int32): boolean {
	return component == 5121 || component == 5123 || component == 5125;
}

function checkedRange(
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
	viewIndex: int32,
	offset: int32,
	count: int32,
	componentBytes: int32,
	elementBytes: int32,
	role: GltfAccessorRole,
): Result<GltfAccessorRange, GltfAccessorError> {
	if (viewIndex < 0 || viewIndex >= views.length) {
		return Result.err(GltfAccessorError.Bounds);
	}
	const view = views[viewIndex];
	if (view.buffer < 0 || view.buffer >= buffers.length) {
		return Result.err(GltfAccessorError.Bounds);
	}
	const bufferLength = buffers[view.buffer].byteLength;
	if (bufferLength < 1 || bufferLength > buffers[view.buffer].bytes.length ||
		view.byteOffset < 0 || view.byteLength < 1 || view.byteOffset > bufferLength ||
		view.byteLength > bufferLength - view.byteOffset || offset < 0) {
		return Result.err(GltfAccessorError.Bounds);
	}
	if (view.byteOffset % componentBytes != 0 || offset % componentBytes != 0) {
		return Result.err(GltfAccessorError.Alignment);
	}
	const target = view.target;
	if (target !== null && !((role == GltfAccessorRole.Attribute && target == 34962) ||
		(role == GltfAccessorRole.Indices && target == 34963))) {
		return Result.err(GltfAccessorError.Target);
	}
	let stride: int32 = elementBytes;
	const declaredStride = view.byteStride;
	if (declaredStride !== null) {
		if (role != GltfAccessorRole.Attribute || declaredStride < 4 ||
			declaredStride > 252 || declaredStride % 4 != 0 ||
			declaredStride < elementBytes || declaredStride > view.byteLength) {
			return Result.err(GltfAccessorError.Stride);
		}
		stride = declaredStride;
	}
	if (role == GltfAccessorRole.Attribute &&
		(offset % 4 != 0 || (componentBytes % 4 != 0 && declaredStride === null))) {
		return Result.err(GltfAccessorError.Alignment);
	}
	if (offset > view.byteLength || elementBytes > view.byteLength - offset ||
		count - 1 > (view.byteLength - offset - elementBytes) / stride) {
		return Result.err(GltfAccessorError.Bounds);
	}
	return Result.ok({ buffer: view.buffer, byteOffset: view.byteOffset + offset, stride: stride });
}

function unsignedAt(bytes: Readonly<Span<uint8>>, offset: int32, size: int32): uint32 {
	let value: uint32 = bytes[offset] as uint32;
	for (let i = 1; i < size; i++) {
		value |= (bytes[offset + i] as uint32) << ((i * 8) as uint32);
	}
	return value;
}

export function fromSource(
	this typeof GltfAccessorLayout,
	source: GltfAccessorSource,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
): Result<GltfAccessorLayout, GltfAccessorError> {
	const size = componentSize(source.componentType);
	if (size == 0 || (source.normalized &&
		(source.componentType == 5125 || source.componentType == 5126))) {
		return Result.err(GltfAccessorError.Encoding);
	}
	const components = componentsOf(source.shape);
	if (components == 0) { return Result.err(GltfAccessorError.Shape); }
	if (source.count < 1 || source.count > 0x7fffffff / components) {
		return Result.err(GltfAccessorError.Count);
	}
	if (source.role != GltfAccessorRole.Attribute && source.role != GltfAccessorRole.Indices &&
		source.role != GltfAccessorRole.Other) {
		return Result.err(GltfAccessorError.Encoding);
	}
	if (source.role == GltfAccessorRole.Indices && (source.shape != GltfAccessorShape.Scalar ||
		!isUnsigned(source.componentType) || source.normalized)) {
		return Result.err(GltfAccessorError.Encoding);
	}
	const rows = matrixRows(source.shape);
	const columnBytes: int32 = rows == 0 ? 0 : ((rows * size + 3) / 4) * 4;
	const elementBytes: int32 = rows == 0 ? components * size : rows * columnBytes;
	let layout: GltfAccessorLayout = {
		componentType: source.componentType, shape: source.shape, normalized: source.normalized,
		role: source.role, count: source.count, componentCount: components, componentBytes: size,
		columnBytes: columnBytes, elementBytes: elementBytes, stride: elementBytes,
		dense: null, sparseCount: 0, sparseIndices: null,
		sparseIndexComponentType: 0, sparseValues: null,
	};
	const denseView = source.bufferView;
	const byteOffset = source.byteOffset;
	if (denseView === null) {
		if (byteOffset !== null) { return Result.err(GltfAccessorError.Bounds); }
	} else {
		const range = try checkedRange(
			buffers, views, denseView, byteOffset === null ? 0 : byteOffset,
			source.count, size, elementBytes, source.role,
		);
		layout.dense = range;
		layout.stride = range.stride;
	}
	const sparse = source.sparse;
	if (sparse !== null) {
		if (sparse.count < 1 || sparse.count > source.count) {
			return Result.err(GltfAccessorError.Count);
		}
		if (!isUnsigned(sparse.indicesComponentType)) {
			return Result.err(GltfAccessorError.Encoding);
		}
		const indexSize = componentSize(sparse.indicesComponentType);
		const indices = try checkedRange(
			buffers, views, sparse.indicesView, sparse.indicesByteOffset,
			sparse.count, indexSize, indexSize, GltfAccessorRole.Other,
		);
		const values = try checkedRange(
			buffers, views, sparse.valuesView, sparse.valuesByteOffset,
			sparse.count, size, elementBytes, GltfAccessorRole.Other,
		);
		let previous: uint32 = 0;
		for (let i = 0; i < sparse.count; i++) {
			const index = unsignedAt(
				buffers[indices.buffer].bytes, indices.byteOffset + i * indexSize, indexSize,
			);
			if (index >= source.count as uint32 || (i > 0 && index <= previous)) {
				return Result.err(GltfAccessorError.SparseOrder);
			}
			previous = index;
		}
		layout.sparseCount = sparse.count;
		layout.sparseIndices = indices;
		layout.sparseIndexComponentType = sparse.indicesComponentType;
		layout.sparseValues = values;
	}
	return Result.ok(layout);
}

function componentAt(
	bytes: Readonly<Span<uint8>>,
	offset: int32,
	component: int32,
	normalized: boolean,
): Result<float64, GltfAccessorError> {
	if (component == 5126) {
		const value: float64 = float32At(bytes, offset) as float64;
		if (!Number.isFinite(value)) { return Result.err(GltfAccessorError.NonFinite); }
		return Result.ok(value);
	}
	const raw = unsignedAt(bytes, offset, componentSize(component));
	let value: float64 = raw as float64;
	if (component == 5120 || component == 5122) {
		const midpoint: float64 = component == 5120 ? 128.0 : 32768.0;
		if (value >= midpoint) { value -= midpoint * 2.0; }
		if (normalized) { value = Math.max(value, 1.0 - midpoint) / (midpoint - 1.0); }
	} else if (normalized) {
		value /= component == 5121 ? 255.0 : 65535.0;
	}
	return Result.ok(value);
}

function readElement(
	values: Span<float64>,
	layout: GltfAccessorLayout,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	range: GltfAccessorRange,
	index: int32,
	destination: int32,
): Result<void, GltfAccessorError> {
	const rows = matrixRows(layout.shape);
	const start = range.byteOffset + index * range.stride;
	for (let component = 0; component < layout.componentCount; component++) {
		const offset: int32 = rows == 0 ? component * layout.componentBytes :
			(component / rows) * layout.columnBytes + (component % rows) * layout.componentBytes;
		const value = try componentAt(
			buffers[range.buffer].bytes, start + offset, layout.componentType, layout.normalized,
		);
		values[destination * layout.componentCount + component] = value;
	}
	return Result.ok(null);
}

export function decode(
	this typeof GltfAccessorValues,
	source: GltfAccessorSource,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
): Result<GltfAccessorValues, GltfAccessorError> {
	const layout = try GltfAccessorLayout.fromSource(source, buffers, views);
	let values: Vec<float64> = new Array(layout.count * layout.componentCount);
	const dense = layout.dense;
	if (dense !== null) {
		for (let i = 0; i < layout.count; i++) {
			const read = try readElement(values, layout, buffers, dense, i, i);
		}
	} else {
		for (let i = 0; i < values.length; i++) { values[i] = 0.0; }
	}
	const indices = layout.sparseIndices;
	const replacements = layout.sparseValues;
	if (indices !== null && replacements !== null) {
		const indexSize = componentSize(layout.sparseIndexComponentType);
		for (let i = 0; i < layout.sparseCount; i++) {
			const index = unsignedAt(
				buffers[indices.buffer].bytes, indices.byteOffset + i * indexSize, indexSize,
			) as int32;
			const read = try readElement(values, layout, buffers, replacements, i, index);
		}
	}
	return Result.ok({
		componentType: layout.componentType, shape: layout.shape, normalized: layout.normalized,
		count: layout.count, values: move values,
	});
}

export function fromAccessor(
	this typeof GltfAccessorIndices,
	source: GltfAccessorSource,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
	vertexCount: uint32,
): Result<GltfAccessorIndices, GltfAccessorError> {
	if (source.role != GltfAccessorRole.Indices || vertexCount == 0) {
		return Result.err(GltfAccessorError.Encoding);
	}
	const decoded = try GltfAccessorValues.decode(source, buffers, views);
	const maximum: float64 = match (source.componentType) {
		5121 => 255.0,
		5123 => 65535.0,
		_ => 4294967295.0,
	};
	let values: Vec<uint32> = [];
	for (const value of decoded.values) {
		if (value == maximum || value >= vertexCount as float64) {
			return Result.err(GltfAccessorError.Index);
		}
		values.push(value as uint32);
	}
	return Result.ok({ componentType: decoded.componentType, values: move values });
}
