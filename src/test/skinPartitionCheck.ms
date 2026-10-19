import { SkinPartition, SkinPartitionError, fromTriangles } from "../void3d/skinPartition";

struct PartitionFixture {
	joints: Vec<int32>;
	weights: Vec<float32>;
	indices: Vec<uint16>;
	materials: Vec<int32>;
}

function rigFixture(jointCount: int32, fourInfluences: boolean = false): PartitionFixture {
	let data: PartitionFixture = { joints: [], weights: [], indices: [], materials: [] };
	for (let triangle = 0; triangle < jointCount; triangle++) {
		data.materials.push(fourInfluences ? triangle % 2 : 0);
		for (let corner = 0; corner < 3; corner++) {
			data.indices.push((triangle * 3 + corner) as uint16);
			for (let influence = 0; influence < 4; influence++) {
				const joint: int32 = fourInfluences ?
					((triangle * 3 + corner) * 4 + influence) % jointCount : triangle;
				data.joints.push(joint);
				data.weights.push(fourInfluences ? 0.25 : influence == 0 ? 1.0 : 0.0);
			}
		}
	}
	return move data;
}

function matchesPartition(this data: PartitionFixture, split: SkinPartition): boolean {
	if (split.remappedJoints.length != data.joints.length ||
		split.triangleGroups.length != data.materials.length) { return false; }
	let seen: Vec<int32> = [];
	for (let triangle = 0; triangle < data.materials.length; triangle++) { seen.push(0); }
	for (let group = 0; group < split.parts.length; group++) {
		const part = split.parts[group];
		if (part.palette.joints.length < 1 || part.palette.joints.length > 64) { return false; }
		for (const triangle of part.triangles) {
			if (triangle < 0 || triangle >= seen.length) { return false; }
			seen[triangle]++;
			if (split.triangleGroups[triangle] != group ||
				part.material != data.materials[triangle]) { return false; }
			for (let corner = 0; corner < 3; corner++) {
				const vertex: int32 = data.indices[triangle * 3 + corner] as int32;
				for (let influence = 0; influence < 4; influence++) {
					const at: int32 = vertex * 4 + influence;
					if (data.weights[at] == 0.0) { continue; }
					const local: int32 = split.remappedJoints[at];
					if (local < 0 || local >= part.palette.joints.length) { return false; }
					if (part.palette.joints[local] != data.joints[at]) { return false; }
				}
			}
		}
	}
	for (const count of seen) { if (count != 1) { return false; } }
	return true;
}

test "a 65-joint rig uses two bounded draw palettes, with no rig truncation" {
	const data = rigFixture(65);
	const made = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 65);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.parts.length == 2;
	assert data.matchesPartition(made.value);
	let max: int32 = 0;
	for (const part of made.value.parts) {
		if (part.palette.joints.length > max) { max = part.palette.joints.length as int32; }
	}
	assert max == 33;
}

test "a 129-joint rig spans three palettes without changing source joints" {
	const data = rigFixture(129);
	const made = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 129);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.parts.length == 3;
	assert data.matchesPartition(made.value);
	let max: int32 = 0;
	for (const part of made.value.parts) {
		if (part.palette.joints.length > max) { max = part.palette.joints.length as int32; }
	}
	assert max == 64;
	assert data.joints[128 * 12] == 128;
}

test "four influences and two materials preserve every positive-weight joint" {
	const data = rigFixture(97, true);
	const made = SkinPartition.fromTriangles(
		data.joints, data.weights, data.indices, 97, data.materials,
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert data.matchesPartition(made.value);
	assert made.value.parts.length == 4;
	let max: int32 = 0;
	for (const part of made.value.parts) {
		if (part.palette.joints.length > max) { max = part.palette.joints.length as int32; }
	}
	assert max == 47;
	for (let at = 0; at < data.joints.length; at++) {
		assert data.joints[at] == at % 97 && data.weights[at] == 0.25;
	}
}

test "a triangle sharing vertices across palettes uses one coherent vertex remap" {
	let data = rigFixture(129);
	data.indices[3] = data.indices[0];
	data.indices[6] = data.indices[0];
	data.indices[126 * 3] = data.indices[0];
	const made = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 129);
	assert made.ok;
	if (!made.ok) { return; }
	assert data.matchesPartition(made.value);
}

test "small rigs partition materials and ignore zero-weight joint entries" {
	const data = rigFixture(4, true);
	const made = SkinPartition.fromTriangles(
		data.joints, data.weights, data.indices, 4, data.materials,
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.parts.length == 2;
	assert data.matchesPartition(made.value);
	const single = SkinPartition.fromTriangles(
		[0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1],
		[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
		[0, 1, 2], 2,
	);
	assert single.ok;
	if (single.ok) { assert single.value.parts[0].palette.joints.length == 1; }
}

test "palette-joint and material loss controls fail the consumer correspondence check" {
	const data = rigFixture(65);
	const made = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 65);
	assert made.ok;
	if (!made.ok) { return; }
	let broken = made.value;
	for (let at = 0; at < broken.remappedJoints.length; at++) { broken.remappedJoints[at] = 0; }
	assert !data.matchesPartition(broken);
	const correct = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 65);
	assert correct.ok;
	if (!correct.ok) { return; }
	let wrongMaterial = correct.value;
	let part = wrongMaterial.parts[0];
	part.material = -1;
	wrongMaterial.parts[0] = move part;
	assert !data.matchesPartition(wrongMaterial);
}

test "uint32 triangle vertices keep canonical joint identities above 65535" {
	let joints: Vec<int32> = new Array(65539 * 4);
	let weights: Vec<float32> = new Array(65539 * 4);
	for (let vertex = 0; vertex < 65539; vertex++) { weights[vertex * 4] = 1.0; }
	joints[65536 * 4] = 64;
	joints[65537 * 4] = 1;
	joints[65538 * 4] = 2;
	const wide: Vec<uint32> = [65536, 65537, 65538];
	const made = SkinPartition.fromTriangles(joints, weights, [], 65, [7], wide);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.parts.length == 1 && made.value.parts[0].material == 7;
	const slot: int32 = made.value.remappedJoints[65536 * 4];
	assert slot >= 0 && slot < 64;
	assert made.value.parts[0].palette.joints[slot] == 64;
	assert made.value.triangleGroups.length == 1 && made.value.triangleGroups[0] == 0;
}

test "wide partition bounds are checked before signed narrowing and mixed storage is refused" {
	const data = rigFixture(4);
	const outside: Vec<uint32> = [0, 1, 0xffffffff as uint32];
	const bad = SkinPartition.fromTriangles(data.joints, data.weights, [], 4, [], outside);
	assert !bad.ok && bad.error == SkinPartitionError.IndexOutOfRange;
	const mixed = SkinPartition.fromTriangles(data.joints, data.weights, [0, 1, 2], 4,
		[], [0, 1, 2]);
	assert !mixed.ok && mixed.error == SkinPartitionError.TriangleLength;
}

test "malformed influence and triangle inputs refuse before partition construction" {
	const data = rigFixture(4);
	const badJoint = SkinPartition.fromTriangles(data.joints, data.weights, data.indices, 3);
	assert !badJoint.ok;
	if (!badJoint.ok) { assert badJoint.error == SkinPartitionError.JointOutOfRange; }
	const shortWeights = SkinPartition.fromTriangles(data.joints, [1.0], data.indices, 4);
	assert !shortWeights.ok;
	if (!shortWeights.ok) { assert shortWeights.error == SkinPartitionError.InfluenceLength; }
	const shortTriangle = SkinPartition.fromTriangles(data.joints, data.weights, [0, 1, 2, 0], 4);
	assert !shortTriangle.ok;
	if (!shortTriangle.ok) { assert shortTriangle.error == SkinPartitionError.TriangleLength; }
	const badIndex = SkinPartition.fromTriangles(data.joints, data.weights, [0, 1, 65535], 4);
	assert !badIndex.ok;
	if (!badIndex.ok) { assert badIndex.error == SkinPartitionError.IndexOutOfRange; }
	const badMaterial = SkinPartition.fromTriangles(
		data.joints, data.weights, data.indices, 4, [0],
	);
	assert !badMaterial.ok;
	if (!badMaterial.ok) { assert badMaterial.error == SkinPartitionError.MaterialLength; }
}
