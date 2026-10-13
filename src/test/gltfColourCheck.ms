import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
} from "../void3d/gltfAccessor";
import { GltfColour, GltfColourError } from "../void3d/gltfColour";

function colourFixture(component: int32, shape: GltfAccessorShape): GltfAccessorSource {
	return {
		bufferView: 0, byteOffset: null, count: 2, componentType: component,
		shape: shape, normalized: component != 5126,
		role: GltfAccessorRole.Attribute, sparse: null,
	};
}

test "gltfColour VEC4 unorm8 keeps distinct alpha and owned linear RGB" {
	let buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [255, 128, 0, 64, 90, 91, 92, 93, 0, 64, 255, 192], byteLength: 12,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 12, byteStride: 8, target: 34962,
	}];
	const source = colourFixture(5121, GltfAccessorShape.Vec4);
	const made = GltfColour.fromAccessor(source, buffers, views, 2);
	assert made.ok;
	if (!made.ok) { return; }
	const data = made.value;
	assert data.values.length == 2;
	assert data.values[0].red == 1.0 && data.values[0].blue == 0.0;
	assert Math.abs(data.values[0].green - 0.5019607843) < 0.000001;
	assert Math.abs(data.values[0].alpha - 0.2509803922) < 0.000001;
	assert Math.abs(data.values[1].alpha - 0.7529411765) < 0.000001;
	const alphaProduct: float32 = data.values[0].alpha * 0.5;
	assert Math.abs(alphaProduct - 0.1254901961) < 0.000001;
	buffers[0].bytes[3] = 0;
	assert Math.abs(data.values[0].alpha - 0.2509803922) < 0.000001;
}

test "gltfColour unorm16 VEC3 supplies alpha one without gamma or factor baking" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 0, 0, 128, 255, 255, 88, 88, 0, 64, 0, 32, 1, 0],
		byteLength: 14,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 14, byteStride: 8, target: null,
	}];
	const source = colourFixture(5123, GltfAccessorShape.Vec3);
	const made = GltfColour.fromAccessor(source, buffers, views, 2);
	assert made.ok;
	if (!made.ok) { return; }
	const data = made.value;
	assert data.values[0].red == 0.0 && data.values[0].blue == 1.0;
	assert Math.abs(data.values[0].green - 0.5000076295) < 0.000001;
	assert Math.abs(data.values[1].red - 0.2500038148) < 0.000001;
	assert Math.abs(data.values[1].green - 0.1250019074) < 0.000001;
	assert Math.abs(data.values[1].blue - 0.0000152590) < 0.00000001;
	assert data.values[0].alpha == 1.0 && data.values[1].alpha == 1.0;
	const linearProduct: float32 = data.values[0].green * 0.5;
	assert Math.abs(linearProduct - 0.2500038148) < 0.000001;
}

test "gltfColour VEC4 unorm16 preserves small source alpha" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [255, 255, 0, 128, 0, 64, 1, 0], byteLength: 8,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 8, byteStride: 8, target: null,
	}];
	const base = colourFixture(5123, GltfAccessorShape.Vec4);
	const source: GltfAccessorSource = { ...base, count: 1 };
	const made = GltfColour.fromAccessor(source, buffers, views, 1);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.values[0].red == 1.0;
	assert Math.abs(made.value.values[0].alpha - 0.0000152590) < 0.00000001;
}

test "gltfColour float VEC4 preserves source alpha and sparse VEC3 defaults alpha" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 0, 128, 62, 0, 0, 0, 63, 0, 0, 128, 63, 0, 0, 0, 62,
			0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 63, 0, 0, 64, 63],
		byteLength: 32,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 32, byteStride: null, target: null,
	}];
	const source = colourFixture(5126, GltfAccessorShape.Vec4);
	const made = GltfColour.fromAccessor(source, buffers, views, 2);
	assert made.ok;
	if (made.ok) {
		assert made.value.values[0].red == 0.25;
		assert made.value.values[0].alpha == 0.125 && made.value.values[1].alpha == 0.75;
	}
	const sparseBuffers: Vec<GltfAccessorBuffer> = [
		{ bytes: [1], byteLength: 1 },
		{ bytes: [64, 128, 255], byteLength: 3 },
	];
	const sparseViews: Vec<GltfAccessorView> = [
		{ ...views[0], byteLength: 1 },
		{ ...views[0], buffer: 1, byteLength: 3 },
	];
	const sparseSource: GltfAccessorSource = {
		...colourFixture(5121, GltfAccessorShape.Vec3), bufferView: null,
		sparse: {
			count: 1, indicesView: 0, indicesByteOffset: 0, indicesComponentType: 5121,
			valuesView: 1, valuesByteOffset: 0,
		},
	};
	const sparse = GltfColour.fromAccessor(sparseSource, sparseBuffers, sparseViews, 2);
	assert sparse.ok;
	if (sparse.ok) {
		assert sparse.value.values[0].red == 0.0 && sparse.value.values[0].alpha == 1.0;
		assert Math.abs(sparse.value.values[1].green - 0.5019607843) < 0.000001;
		assert sparse.value.values[1].blue == 1.0 && sparse.value.values[1].alpha == 1.0;
	}
}

test "gltfColour refuses count encoding shape and out of range float components" {
	const buffers: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 128, 63, 0, 0, 0, 63], byteLength: 16,
	}];
	const views: Vec<GltfAccessorView> = [{
		buffer: 0, byteOffset: 0, byteLength: 16, byteStride: null, target: null,
	}];
	const source: GltfAccessorSource = {
		...colourFixture(5126, GltfAccessorShape.Vec4), count: 1,
	};
	const bad = GltfColour.fromAccessor(source, buffers, views, 1);
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == GltfColourError.Range; }
	const mismatch = GltfColour.fromAccessor(source, buffers, views, 2);
	assert !mismatch.ok;
	if (!mismatch.ok) { assert mismatch.error == GltfColourError.Count; }
	const integer: GltfAccessorSource = { ...source, componentType: 5121 };
	assert !GltfColour.fromAccessor(integer, buffers, views, 1).ok;
	const signed: GltfAccessorSource = { ...source, componentType: 5120, normalized: true };
	assert !GltfColour.fromAccessor(signed, buffers, views, 1).ok;
	const matrix: GltfAccessorSource = { ...source, shape: GltfAccessorShape.Mat2 };
	assert !GltfColour.fromAccessor(matrix, buffers, views, 1).ok;
	const normalized: GltfAccessorSource = { ...source, normalized: true };
	assert !GltfColour.fromAccessor(normalized, buffers, views, 1).ok;
	const badAlpha: Vec<GltfAccessorBuffer> = [{
		bytes: [0, 0, 128, 63, 0, 0, 0, 63, 0, 0, 128, 62, 0, 0, 0, 64], byteLength: 16,
	}];
	assert !GltfColour.fromAccessor(source, badAlpha, views, 1).ok;
}
