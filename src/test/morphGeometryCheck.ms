import {
	MorphData,
	MorphGeometry,
	MorphGeometryError,
	MorphPrimitiveInput,
	MorphTarget,
	publishMorphGeometry,
} from "../void3d/morphGeometry";
import { MeshData, addVertex, addTriangle } from "../void3d/meshData";
import { vec3 } from "../math/math3d";

function plainTriangle(x: float32): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(x, 0, 0), vec3(x + 1, 0, 0), vec3(x, 1, 0)]) {
		const added = addVertex(mesh, point, vec3(0, 0, 1), {
			red: 0.25, green: 0.5, blue: 0.75, alpha: 1,
		});
		if (!added.ok) { unreachable; }
	}
	const indexed = addTriangle(mesh, 0, 1, 2);
	if (!indexed.ok) { unreachable; }
	return move mesh;
}

function remappedTangentPrimitive(): MorphPrimitiveInput {
	let mesh = MeshData.withUvs();
	mesh.hasTangents = true;
	for (const x of [0.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32]) {
		const attributes: Vec<float32> = [
			x, 0, 0, 0, 1, 0, 0.25, 0.75, 0.25, 0.5, 0.75, 1, 1, 0, 0, -1,
		];
		for (const value of attributes) { mesh.vertices.push(value); }
	}
	mesh.indices = [0, 1, 2, 0, 2, 3];
	return {
		base: move mesh,
		sourceVertexCount: 3,
		sourceVertices: [0, 1, 2, 1],
		targets: [
			{
				positions: [2, 0, 0, 0, 4, 0, 0, 0, 6],
				normals: [1, 2, 0, 0, 1, 2, 2, 0, 1],
				tangents: [],
			},
			{
				positions: [-1, 2, 0, 2, 0, 1, 0, -2, 1],
				normals: [],
				tangents: [0, 1, 2, 2, 0, 1, 1, 2, 0],
			},
		],
	};
}

function mixedPrimitives(): Vec<MorphPrimitiveInput> {
	return [
		remappedTangentPrimitive(),
		{
			base: plainTriangle(10),
			sourceVertexCount: 3,
			sourceVertices: [0, 1, 2],
			targets: [
				{ positions: [], normals: [0, 0, 2, 0, 0, 2, 0, 0, 2], tangents: [] },
				{ positions: [0, 1, 0, 0, 1, 0, 0, 1, 0], normals: [], tangents: [] },
			],
		},
		{ base: plainTriangle(20), sourceVertexCount: 3, sourceVertices: [0, 1, 2], targets: [] },
	];
}

function sameMeshes(
	left: Readonly<Span<MeshData>>,
	right: Readonly<Span<MeshData>>,
): boolean {
	if (left.length != right.length) { return false; }
	for (let primitive = 0; primitive < left.length; primitive++) {
		if (left[primitive].bounds != right[primitive].bounds ||
			left[primitive].vertices.length != right[primitive].vertices.length ||
			left[primitive].indices.length != right[primitive].indices.length) { return false; }
		for (let at = 0; at < left[primitive].vertices.length; at++) {
			if (left[primitive].vertices[at] != right[primitive].vertices[at]) { return false; }
		}
		for (let at = 0; at < left[primitive].indices.length; at++) {
			if (left[primitive].indices[at] != right[primitive].indices[at]) { return false; }
		}
	}
	return true;
}

test "morphGeometry adds unequal xyz deltas with signed unnormalized mesh-wide weights" {
	const data = MorphData.create(mixedPrimitives(), 2);
	assert data.ok;
	if (!data.ok) { return; }
	const bound = MorphGeometry.bind(data.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	let geometry = move bound.value;
	const published = publishMorphGeometry(geometry, [0.5, -2]);
	assert published.ok;
	assert geometry.ready && geometry.revision == 1;
	assert geometry.weights[0] == 0.5 && geometry.weights[1] == -2;
	const first = geometry.meshes[0];
	assert first.vertices[0] == 3 && first.vertices[1] == -4 && first.vertices[2] == 0;
	assert first.vertices[3] == 0.5 && first.vertices[4] == 2 && first.vertices[5] == 0;
	assert first.vertices[12] == 1 && first.vertices[13] == -2 && first.vertices[14] == -4;
	assert first.vertices[15] == -1;
	assert first.vertices[16] == -3 && first.vertices[17] == 2 && first.vertices[18] == -2;
	assert first.vertices[32] == 1 && first.vertices[33] == 4 && first.vertices[34] == 1;
	assert first.vertices[48] == -3 && first.vertices[49] == 2 && first.vertices[50] == -2;
	assert first.vertices[6] == 0.25 && first.vertices[7] == 0.75;
	assert first.vertices[8] == 0.25 && first.vertices[11] == 1;
	assert first.indices[5] == 3;
	assert first.bounds.min == vec3(-3, -4, -2) && first.bounds.max == vec3(3, 4, 1);
	assert geometry.meshes[1].vertices[1] == -2 && geometry.meshes[1].vertices[5] == 2;
	assert geometry.meshes[1].bounds.min == vec3(10, -2, 0);
	assert geometry.meshes[1].bounds.max == vec3(11, -1, 0);
	assert geometry.meshes[2].vertices[0] == 20 && geometry.meshes[2].vertices[1] == 0;
	assert geometry.meshes[2].bounds.max == vec3(21, 1, 0);
	assert publishMorphGeometry(geometry, [0, 0]).ok;
	assert geometry.revision == 2 && geometry.meshes[0].vertices[0] == 0;
	assert geometry.meshes[0].vertices[4] == 1 && geometry.meshes[0].vertices[13] == 0;
}

test "morphGeometry shares immutable offsets but two instances own weights and staging" {
	let inputs = mixedPrimitives();
	const data = MorphData.create(inputs, 2);
	assert data.ok;
	if (!data.ok) { return; }
	inputs[0].base.vertices[0] = 99;
	inputs[0].targets[0].positions[0] = 99;
	inputs[0].sourceVertices[3] = 2;
	const boundFirst = MorphGeometry.bind(data.value);
	const boundSecond = MorphGeometry.bind(data.value);
	assert boundFirst.ok && boundSecond.ok;
	if (!boundFirst.ok || !boundSecond.ok) { return; }
	let first = move boundFirst.value;
	let second = move boundSecond.value;
	let weights: Vec<float32> = [0.5, -2];
	assert publishMorphGeometry(first, weights).ok;
	weights[0] = -1;
	weights[1] = 0.25;
	assert publishMorphGeometry(second, weights).ok;
	assert first.weights[0] == 0.5 && first.weights[1] == -2;
	assert first.meshes[0].vertices[0] == 3 && first.meshes[0].vertices[48] == -3;
	assert second.meshes[0].vertices[0] == -2.25;
	assert second.meshes[0].vertices[16] == 1.5 && second.meshes[0].vertices[17] == -4;
	assert second.meshes[0].vertices[34] == -5.75;
	assert second.meshes[0].bounds.min == vec3(-2.25, -4, -5.75);
	assert second.meshes[0].bounds.max == vec3(1.5, 0.5, 0.25);
	assert second.meshes[1].vertices[1] == 0.25 && second.meshes[1].vertices[5] == -1;
	first.pending[0].vertices[0] = 123;
	assert second.pending[0].vertices[0] == 0;
	assert publishMorphGeometry(second, [0, 1]).ok;
	assert first.revision == 1 && second.revision == 2;
	assert first.meshes[0].bounds.min == vec3(-3, -4, -2);
	assert second.meshes[0].vertices[0] == -1;
}

test "morphGeometry accepts three targets without normalizing or normalizing normals" {
	const target: MorphTarget = {
		positions: [], normals: [0, 2, 0, 0, 2, 0, 0, 2, 0], tangents: [],
	};
	const data = MorphData.create([{
		base: plainTriangle(0), sourceVertexCount: 3, sourceVertices: [2, 0, 1],
		targets: [target, target, target],
	}], 3);
	assert data.ok;
	if (!data.ok) { return; }
	const bound = MorphGeometry.bind(data.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	let geometry = move bound.value;
	assert publishMorphGeometry(geometry, [2, -0.5, 0.25]).ok;
	assert geometry.meshes[0].vertices[4] == 3.5 && geometry.meshes[0].vertices[5] == 1;
	assert geometry.meshes[0].bounds.max == vec3(1, 1, 0);
}

test "morphGeometry late overflow preserves every primitive weights bounds and revision" {
	let inputs = mixedPrimitives();
	inputs[2].targets = [
		{ positions: [0, 0, 0, 0, 0, 0, 3.0e38, 0, 0], normals: [], tangents: [] },
		{ positions: [0, 0, 0, 0, 0, 0, 0, 0, 0], normals: [], tangents: [] },
	];
	const data = MorphData.create(inputs, 2);
	assert data.ok;
	if (!data.ok) { return; }
	const bound = MorphGeometry.bind(data.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	let geometry = move bound.value;
	assert publishMorphGeometry(geometry, [0, 1]).ok;
	const previousMeshes = geometry.meshes;
	const previousWeights = geometry.weights;
	const failed = publishMorphGeometry(geometry, [2, -2]);
	assert !failed.ok && failed.error == MorphGeometryError.NonFinite;
	assert !geometry.ready && geometry.revision == 1;
	assert sameMeshes(geometry.meshes, previousMeshes);
	assert geometry.weights[0] == previousWeights[0] && geometry.weights[1] == previousWeights[1];
	assert publishMorphGeometry(geometry, [0.5, -2]).ok;
	assert geometry.ready && geometry.revision == 2;
	assert geometry.meshes[0].vertices[0] == 3;
	assert geometry.meshes[2].vertices[20] > 1.0e38;
}

test "morphGeometry refuses invalid late inputs explicit remaps weights and revision wrap" {
	let inputs = mixedPrimitives();
	inputs[1].targets[1].positions[8] = NaN as float32;
	const nonfinite = MorphData.create(inputs, 2);
	assert !nonfinite.ok && nonfinite.error == MorphGeometryError.NonFinite;
	inputs = mixedPrimitives();
	inputs[0].sourceVertices[3] = 3;
	const remap = MorphData.create(inputs, 2);
	assert !remap.ok && remap.error == MorphGeometryError.SourceVertex;
	inputs = mixedPrimitives();
	inputs[1].targets.pop();
	assert !MorphData.create(inputs, 2).ok;
	inputs = mixedPrimitives();
	inputs[0].targets[1].tangents.pop();
	assert !MorphData.create(inputs, 2).ok;
	inputs = mixedPrimitives();
	inputs[1].targets[1].tangents = [0, 0, 1, 0, 0, 1, 0, 0, 1];
	const tangent = MorphData.create(inputs, 2);
	assert !tangent.ok && tangent.error == MorphGeometryError.Semantic;
	const data = MorphData.create(mixedPrimitives(), 2);
	assert data.ok;
	if (!data.ok) { return; }
	const bound = MorphGeometry.bind(data.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	let geometry = move bound.value;
	assert publishMorphGeometry(geometry, [0.5, -2]).ok;
	const before = geometry.meshes;
	const invalid = publishMorphGeometry(geometry, [1, NaN as float32]);
	assert !invalid.ok && invalid.error == MorphGeometryError.NonFinite;
	assert sameMeshes(geometry.meshes, before);
	assert geometry.weights[0] == 0.5 && geometry.revision == 1;
	assert !publishMorphGeometry(geometry, [1]).ok;
	geometry.revision = 0xffffffffffffffff as uint64;
	const exhausted = publishMorphGeometry(geometry, [1, 0]);
	assert !exhausted.ok && exhausted.error == MorphGeometryError.Revision;
	assert sameMeshes(geometry.meshes, before);
}


test "morphGeometry preserves packed skin fields and bounds beyond empty-box sentinels" {
	let input = remappedTangentPrimitive();
	input.targets.pop();
	let packed: Vec<float32> = [];
	for (let vertex = 0; vertex < 4; vertex++) {
		for (let field = 0; field < 16; field++) {
			packed.push(field == 0 ? 1.0e30 as float32 : input.base.vertices[vertex * 16 + field]);
		}
		const skinFields: Vec<float32> = [3, 2, 1, 0, 0.25, 0.5, 0.25, 0];
		for (const value of skinFields) { packed.push(value); }
	}
	input.base.vertices = move packed;
	input.base.hasSkin = true;
	const data = MorphData.create([input], 1);
	assert data.ok;
	if (!data.ok) { return; }
	const bound = MorphGeometry.bind(data.value);
	assert bound.ok;
	if (!bound.ok) { return; }
	let geometry = move bound.value;
	assert publishMorphGeometry(geometry, [2]).ok;
	assert geometry.meshes[0].bounds.min.x == 1.0e30 as float32;
	assert geometry.meshes[0].bounds.max.x == 1.0e30 as float32;
	assert geometry.meshes[0].vertices[15] == -1;
	assert geometry.meshes[0].vertices[16] == 3 && geometry.meshes[0].vertices[17] == 2;
	assert geometry.meshes[0].vertices[20] == 0.25 && geometry.meshes[0].vertices[21] == 0.5;
	assert geometry.meshes[0].vertices[27] == 0 && geometry.meshes[0].vertices[28] == 3;
}
