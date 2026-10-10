import {
	SkinPalette,
	MAX_SKIN_PALETTE_JOINTS,
	create,
} from "./skinPalette";

export enum SkinPartitionError {
	Empty,
	InfluenceLength,
	JointOutOfRange,
	BadWeight,
	IndexOutOfRange,
	TriangleLength,
	MaterialLength,
	PaletteAssignment,
}

export struct SkinPart {
	material: int32;
	palette: SkinPalette;
	triangles: Vec<int32>;
}

export struct SkinPartition {
	parts: Vec<SkinPart>;
	triangleGroups: Vec<int32>;
	remappedJoints: Vec<int32>;
}

struct JointGroup {
	material: int32;
	joints: Vec<int32>;
	triangles: Vec<int32>;
	assigned: Vec<int32>;
}

function isJointSubset(small: Readonly<Span<int32>>, large: Readonly<Span<int32>>): boolean {
	let at: int32 = 0;
	for (const joint of small) {
		while (at < large.length && large[at] < joint) { at++; }
		if (at >= large.length || large[at] != joint) { return false; }
		at++;
	}
	return true;
}

function jointDifference(first: Readonly<Span<int32>>, second: Readonly<Span<int32>>): int32 {
	let left: int32 = 0;
	let right: int32 = 0;
	let difference: int32 = 0;
	while (left < first.length && right < second.length) {
		if (first[left] == second[right]) { left++; right++; }
		else if (first[left] < second[right]) { left++; difference++; }
		else { right++; difference++; }
	}
	return difference + (first.length as int32) - left + (second.length as int32) - right;
}

function addSortedJoint(ref joints: Vec<int32>, joint: int32): void {
	let at: int32 = 0;
	while (at < joints.length && joints[at] < joint) { at++; }
	if (at < joints.length && joints[at] == joint) { return; }
	joints.push(joint);
	for (let i = (joints.length as int32) - 1; i > at; i--) { joints[i] = joints[i - 1]; }
	joints[at] = joint;
}

function removeGroup(ref groups: Vec<JointGroup>, at: int32): void {
	for (let i = at; i + 1 < groups.length; i++) { groups[i] = groups[i + 1]; }
	groups.pop();
}

function mergeGroupPair(ref groups: Vec<JointGroup>, first: int32, second: int32): void {
	for (const joint of groups[first].joints) { addSortedJoint(groups[second].joints, joint); }
	for (const triangle of groups[first].triangles) { groups[second].triangles.push(triangle); }
	removeGroup(groups, first);
}

function mergeOneSubset(ref groups: Vec<JointGroup>): boolean {
	for (let first = 0; first < groups.length; first++) {
		for (let second = 0; second < groups.length; second++) {
			if (first == second || groups[first].material != groups[second].material) { continue; }
			if (isJointSubset(groups[first].joints, groups[second].joints)) {
				mergeGroupPair(groups, first, second);
				return true;
			}
		}
	}
	return false;
}

function mergeJointGroups(ref groups: Vec<JointGroup>): void {
	while (true) {
		while (mergeOneSubset(groups)) { }
		let bestFirst: int32 = -1;
		let bestSecond: int32 = -1;
		let bestTotal: int32 = 100000;
		let bestDifference: int32 = 100000;
		for (let first = 0; first < groups.length; first++) {
			if (groups[first].joints.length == MAX_SKIN_PALETTE_JOINTS) { continue; }
			for (let second = first + 1; second < groups.length; second++) {
				if (groups[second].joints.length == MAX_SKIN_PALETTE_JOINTS ||
					groups[first].material != groups[second].material) { continue; }
				const difference: int32 = jointDifference(
					groups[first].joints, groups[second].joints,
				);
				const total: int32 = difference +
					(((groups[first].joints.length as int32) +
					(groups[second].joints.length as int32) - difference) >> 1);
				if (total > MAX_SKIN_PALETTE_JOINTS || total > bestTotal ||
					(total == bestTotal && difference > bestDifference)) { continue; }
				bestFirst = first;
				bestSecond = second;
				bestTotal = total;
				bestDifference = difference;
			}
		}
		if (bestFirst < 0) { return; }
		mergeGroupPair(groups, bestFirst, bestSecond);
	}
}

function membershipCount(groups: Readonly<Span<JointGroup>>, joint: int32): int32 {
	let count: int32 = 0;
	for (let i = 0; i < groups.length; i++) {
		for (const member of groups[i].joints) {
			if (member == joint) { count++; break; }
		}
	}
	return count;
}

function groupContains(this group: JointGroup, joint: int32): boolean {
	for (const member of group.joints) { if (member == joint) { return true; } }
	return false;
}

function assignJointSlots(
	ref groups: Vec<JointGroup>,
	used: Readonly<Span<int32>>,
	jointCount: int32,
): Result<Vec<int32>, SkinPartitionError> {
	let order: Vec<int32> = [];
	let priority: Vec<int32> = [];
	let slots: Vec<int32> = [];
	let memberships: Vec<int32> = [];
	for (let joint = 0; joint < jointCount; joint++) {
		priority.push(0);
		slots.push(-1);
		memberships.push(membershipCount(groups, joint));
	}
	for (const joint of used) { order.push(joint); }
	while (true) {
		for (let i = 1; i < order.length; i++) {
			const joint: int32 = order[i];
			const rank: int32 = memberships[joint] + priority[joint] * 100;
			let at: int32 = i;
			while (at > 0) {
				const previous: int32 = order[at - 1];
				if (memberships[previous] + priority[previous] * 100 >= rank) { break; }
				order[at] = previous;
				at--;
			}
			order[at] = joint;
		}
		for (let group = 0; group < groups.length; group++) {
			while (groups[group].assigned.length > 0) { groups[group].assigned.pop(); }
			for (let slot = 0; slot < MAX_SKIN_PALETTE_JOINTS; slot++) {
				groups[group].assigned.push(-1);
			}
		}
		let failed: int32 = -1;
		for (const joint of order) {
			slots[joint] = -1;
			for (let slot = 0; slot < MAX_SKIN_PALETTE_JOINTS; slot++) {
				let free: boolean = true;
				for (let group = 0; group < groups.length; group++) {
					if (groups[group].groupContains(joint) && groups[group].assigned[slot] >= 0) {
						free = false;
						break;
					}
				}
				if (!free) { continue; }
				slots[joint] = slot;
				for (let group = 0; group < groups.length; group++) {
					if (groups[group].groupContains(joint)) {
						groups[group].assigned[slot] = joint;
					}
				}
				break;
			}
			if (slots[joint] < 0) {
				priority[joint]++;
				if (priority[joint] > 10) {
					return Result.err(SkinPartitionError.PaletteAssignment);
				}
				failed = joint;
				break;
			}
		}
		if (failed < 0) { return Result.ok(move slots); }
	}
}

export function fromTriangles(
	this typeof SkinPartition,
	jointIndices: Readonly<Span<int32>>,
	weights: Readonly<Span<float32>>,
	indices: Readonly<Span<uint16>>,
	jointCount: int32,
	materials: Readonly<Span<int32>> = [],
): Result<SkinPartition, SkinPartitionError> {
	if (jointCount < 1 || jointIndices.length < 4 || indices.length < 3) {
		return Result.err(SkinPartitionError.Empty);
	}
	if (jointIndices.length > 0x7fffffff ||
		jointIndices.length != weights.length || jointIndices.length % 4 != 0) {
		return Result.err(SkinPartitionError.InfluenceLength);
	}
	if (indices.length > 0x7fffffff || indices.length % 3 != 0) {
		return Result.err(SkinPartitionError.TriangleLength);
	}
	const triangles: int32 = (indices.length as int32) / 3;
	if (materials.length != 0 && materials.length != triangles) {
		return Result.err(SkinPartitionError.MaterialLength);
	}
	let used: Vec<int32> = [];
	for (let vertex = 0; vertex < jointIndices.length / 4; vertex++) {
		let total: float64 = 0.0;
		for (let influence = 0; influence < 4; influence++) {
			const at: int32 = vertex * 4 + influence;
			const joint: int32 = jointIndices[at];
			const weight: float32 = weights[at];
			if (joint < 0 || joint >= jointCount) {
				return Result.err(SkinPartitionError.JointOutOfRange);
			}
			if (!Number.isFinite(weight) || weight < 0.0) {
				return Result.err(SkinPartitionError.BadWeight);
			}
			total = total + (weight as float64);
			if (weight > 0.0) { addSortedJoint(used, joint); }
		}
		if (total < 0.99999 || total > 1.00001) {
			return Result.err(SkinPartitionError.BadWeight);
		}
	}
	let groups: Vec<JointGroup> = [];
	for (let triangle = 0; triangle < triangles; triangle++) {
		let joints: Vec<int32> = [];
		for (let corner = 0; corner < 3; corner++) {
			const vertex: int32 = indices[triangle * 3 + corner] as int32;
			if (vertex >= jointIndices.length / 4) {
				return Result.err(SkinPartitionError.IndexOutOfRange);
			}
			for (let influence = 0; influence < 4; influence++) {
				const at: int32 = vertex * 4 + influence;
				if (weights[at] > 0.0) { addSortedJoint(joints, jointIndices[at]); }
			}
		}
		const material: int32 = materials.length == 0 ? 0 : materials[triangle];
		let found: boolean = false;
		for (let group = 0; group < groups.length; group++) {
			if (groups[group].material == material && isJointSubset(joints, groups[group].joints)) {
				groups[group].triangles.push(triangle);
				found = true;
				break;
			}
		}
		if (found) { continue; }
		for (let group = 0; group < groups.length; group++) {
			if (groups[group].material == material && isJointSubset(groups[group].joints, joints)) {
				groups[group].joints = joints;
				groups[group].triangles.push(triangle);
				found = true;
				break;
			}
		}
		if (!found) {
			groups.push({
				material: material,
				joints: move joints,
				triangles: [triangle],
				assigned: [],
			});
		}
	}
	mergeJointGroups(groups);
	const slots = try assignJointSlots(groups, used, jointCount);
	let result: SkinPartition = { parts: [], triangleGroups: [], remappedJoints: [] };
	for (let triangle = 0; triangle < triangles; triangle++) { result.triangleGroups.push(-1); }
	for (let group = 0; group < groups.length; group++) {
		let last: int32 = MAX_SKIN_PALETTE_JOINTS - 1;
		while (last > 0 && groups[group].assigned[last] < 0) { last--; }
		let joints: Vec<int32> = [];
		for (let slot = 0; slot <= last; slot++) {
			const joint: int32 = groups[group].assigned[slot];
			joints.push(joint < 0 ? used[0] : joint);
		}
		const made = SkinPalette.create(joints);
		if (!made.ok) { return Result.err(SkinPartitionError.PaletteAssignment); }
		for (const triangle of groups[group].triangles) { result.triangleGroups[triangle] = group; }
		result.parts.push({
			material: groups[group].material,
			palette: made.value,
			triangles: groups[group].triangles,
		});
	}
	for (let at = 0; at < jointIndices.length; at++) {
		result.remappedJoints.push(weights[at] == 0.0 ? 0 : slots[jointIndices[at]]);
	}
	return Result.ok(move result);
}
