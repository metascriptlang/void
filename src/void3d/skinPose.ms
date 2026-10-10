import { Mat4, identity } from "../math/math3d";
import { Scene3D, NodeId3D, isLive, syncWorld } from "./scene";
import { SkinPalette, SKIN_PALETTE_FLOATS, create, writePalette } from "./skinPalette";

export enum SkinPoseError {
	Shape,
	Target,
	Palette,
}

export interface SkinPose {
	readonly scene: Scene3D;
	joints: Vec<NodeId3D>;
	inverseBindMatrices: Vec<Mat4>;
	palettes: Vec<SkinPalette>;
	worlds: Vec<Mat4>;
	pendingWorlds: Vec<Mat4>;
	blocks: Vec<Vec<float32>>;
	pendingBlocks: Vec<Vec<float32>>;
	ready: boolean;
	revision: uint64;
}

function paletteBlock(): Vec<float32> {
	let block: Vec<float32> = [];
	for (let i = 0; i < SKIN_PALETTE_FLOATS; i++) { block.push(0.0); }
	return move block;
}

export function bind(
	this typeof SkinPose,
	scene: Scene3D,
	sourceJoints: Readonly<Span<int32>>,
	mappedNodes: Readonly<Span<NodeId3D>>,
	inverseBindMatrices: Readonly<Span<Mat4>>,
	palettes: Readonly<Span<SkinPalette>>,
): Result<SkinPose, SkinPoseError> {
	if (sourceJoints.length < 1 || sourceJoints.length > 0x7fffffff ||
		inverseBindMatrices.length != sourceJoints.length || palettes.length < 1) {
		return Result.err(SkinPoseError.Shape);
	}
	let pose: SkinPose = {
		scene: scene, joints: [], inverseBindMatrices: [], palettes: [],
		worlds: [], pendingWorlds: [], blocks: [], pendingBlocks: [], ready: false, revision: 0,
	};
	for (const source of sourceJoints) {
		if (source < 0 || source >= mappedNodes.length || !isLive(scene, mappedNodes[source])) {
			return Result.err(SkinPoseError.Target);
		}
		pose.joints.push(mappedNodes[source]);
		pose.worlds.push(identity());
		pose.pendingWorlds.push(identity());
	}
	for (const matrix of inverseBindMatrices) { pose.inverseBindMatrices.push({ ...matrix }); }
	for (const palette of palettes) {
		const made = SkinPalette.create(palette.joints);
		if (!made.ok) { return Result.err(SkinPoseError.Palette); }
		for (const joint of made.value.joints) {
			if (joint >= sourceJoints.length) { return Result.err(SkinPoseError.Palette); }
		}
		pose.palettes.push(made.value);
		pose.blocks.push(paletteBlock());
		pose.pendingBlocks.push(paletteBlock());
	}
	return Result.ok(pose);
}

export function syncSkinPose(this pose: SkinPose): Result<int32, SkinPoseError> {
	pose.ready = false;
	if (pose.revision == (0xffffffffffffffff as uint64)) { return Result.err(SkinPoseError.Shape); }
	const count: int32 = pose.joints.length as int32;
	if (count < 1 || pose.inverseBindMatrices.length != count || pose.worlds.length != count ||
		pose.pendingWorlds.length != count || pose.palettes.length != pose.blocks.length ||
		pose.blocks.length != pose.pendingBlocks.length) {
		return Result.err(SkinPoseError.Shape);
	}
	for (const joint of pose.joints) {
		if (!isLive(pose.scene, joint)) { return Result.err(SkinPoseError.Target); }
	}
	const _synced: int32 = syncWorld(pose.scene);
	for (let i = 0; i < count; i++) {
		pose.pendingWorlds[i] = pose.scene.nodes[pose.joints[i].index].world;
	}
	for (let part = 0; part < pose.palettes.length; part++) {
		if (pose.blocks[part].length != SKIN_PALETTE_FLOATS ||
			pose.pendingBlocks[part].length != SKIN_PALETTE_FLOATS) {
			return Result.err(SkinPoseError.Shape);
		}
		const written = pose.palettes[part].writePalette(
			pose.pendingWorlds, pose.inverseBindMatrices, pose.pendingBlocks[part],
		);
		if (!written.ok) { return Result.err(SkinPoseError.Palette); }
	}
	const oldWorlds = pose.worlds;
	pose.worlds = pose.pendingWorlds;
	pose.pendingWorlds = oldWorlds;
	const oldBlocks = pose.blocks;
	pose.blocks = pose.pendingBlocks;
	pose.pendingBlocks = oldBlocks;
	pose.revision += 1;
	pose.ready = true;
	return Result.ok(pose.palettes.length as int32);
}
