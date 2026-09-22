import { GltfData, validateGltfGraph } from "./gltf";
import {
	Scene, NodeId, SceneError, Transform3D,
	addGroup, addMeshNode, setName, isLive,
} from "./scene";

export enum GltfSceneError {
	InvalidData,
	BadMeshBinding,
	SceneRefused,
}

export struct GltfMeshBinding {
	mesh: int32;
	material: int32;
}

function transformOf(data: GltfData, index: int32): Transform3D {
	return {
		position: data.nodes[index].local.position,
		rotation: data.nodes[index].local.rotation,
		scale: data.nodes[index].local.scale,
	};
}

export function addGltfNodes(
	ref scene: Scene,
	parent: NodeId,
	data: GltfData,
	bindings: Span<GltfMeshBinding>,
): Result<int32, GltfSceneError> {
	if (!isLive(scene, parent)) { return Result.err(GltfSceneError.SceneRefused); }
	if ((bindings.length as int32) != (data.meshes.length as int32)) {
		return Result.err(GltfSceneError.BadMeshBinding);
	}
	for (const binding of bindings) {
		if (binding.mesh < 0 || binding.material < 0) {
			return Result.err(GltfSceneError.BadMeshBinding);
		}
	}
	const valid = validateGltfGraph(data);
	if (!valid.ok) { return Result.err(GltfSceneError.InvalidData); }
	const nodes: Vec<int32> = [];
	const parents: Vec<NodeId> = [];
	for (let i = (data.sceneRoots.length as int32) - 1; i >= 0; i--) {
		nodes.push(data.sceneRoots[i]);
		parents.push(parent);
	}
	let count: int32 = 0;
	while ((nodes.length as int32) > 0) {
		const last: int32 = (nodes.length as int32) - 1;
		const index: int32 = nodes[last];
		const under: NodeId = parents[last];
		nodes.pop();
		parents.pop();
		let id: NodeId = { index: -1, generation: 0 };
		const mesh: int32 = data.nodes[index].mesh;
		if (mesh < 0) {
			const added: Result<NodeId, SceneError> =
				addGroup(scene, under, transformOf(data, index));
			if (!added.ok) { return Result.err(GltfSceneError.SceneRefused); }
			id = added.value;
		} else {
			const added: Result<NodeId, SceneError> = addMeshNode(
				scene, under, transformOf(data, index),
				bindings[mesh].mesh, bindings[mesh].material,
			);
			if (!added.ok) { return Result.err(GltfSceneError.SceneRefused); }
			id = added.value;
		}
		const named: Result<int32, SceneError> = setName(scene, id, data.nodes[index].name);
		if (!named.ok) { return Result.err(GltfSceneError.SceneRefused); }
		count = count + 1;
		const childCount: int32 = data.nodes[index].children.length as int32;
		for (let i = childCount - 1; i >= 0; i--) {
			nodes.push(data.nodes[index].children[i]);
			parents.push(id);
		}
	}
	return Result.ok(count);
}
