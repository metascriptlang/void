import {
	Vec3, Mat4, Quat, vec3, quatOfRotation, composeTransform, identityQuat,
} from "../math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../gpu/state";
import { PixelFormat, contextGeneration, originTopLeft } from "../gpu/door";
import { RenderTarget } from "../gpu/target";
import { Scene2D, NodeRef } from "../void2d/node";
import "../void2d/scene";
import { textWidth, textHeight } from "../void2d/render";
import { Color } from "../void2d/types";
import { Anchor, ANCHOR_CENTER } from "./billboard";
import { CameraBasis, rotationOfBasis } from "./camera";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_COLOR, UNLIT_MATERIAL_UNIFORM_LENGTH, MOVING_UV_MATRIX, MOVING_UV_OFFSET,
} from "./gpu3d";
import { Material, Phase, UniformBlock, movingDefaults } from "./material";
import { MeshData, MeshError, Rgba, addTexturedVertex, addTriangle } from "./meshData";
import { TextureId, TextureUploadError, TextureAlpha } from "./texture";
import {
	MeshId, MaterialId, MeshUploadError, MaterialError, HandleError, DrawContext,
	addMeshData, addMaterial, addTargetTexture, releaseMesh, releaseMaterial, releaseTexture,
	reserveUniforms, writeUniforms, releaseUniforms,
} from "./draw";
import { UniformError } from "./uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, NO_NODE_3D, addMeshNode, setLocal, remove,
	syncWorld,
} from "./scene";

export const LABEL_PAD: int32 = 2;

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const CLEAR: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

export enum WorldLabelError {
	NotPositive,
	Mesh,
	Texture,
	Uniforms,
	Material,
	Node,
}

export struct WorldLabelStyle {
	fontSize: float32;
	color: Color;
	pixelsPerUnit: float32;
	anchor: Anchor;
	filter: FilterMode;
}

export interface WorldLabel {
	scene: Scene3D;
	ui: Scene2D;
	text: NodeRef;
	target: RenderTarget;
	texture: TextureId;
	mesh: MeshId;
	material: MaterialId;
	uniforms: UniformBlock;
	node: NodeId3D;
	pixelsPerUnit: float32;
	width: int32;
	height: int32;
	position: Vec3;
	rotation: Quat;
	posed: boolean;
	block: Vec<float32>;
	stale: boolean;
	closed: boolean;
	outline: float32;
}

export function plainStyle(this typeof WorldLabelStyle, pixelsPerUnit: float32): WorldLabelStyle {
	return {
		fontSize: 16.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
		pixelsPerUnit: pixelsPerUnit, anchor: ANCHOR_CENTER, filter: FilterMode.Linear,
	};
}

function texelsAcross(extent: float32, outline: float32): int32 {
	return (Math.ceil(extent) as int32) + 2 * padFor(outline);
}

function padFor(outline: float32): int32 {
	return LABEL_PAD + (Math.ceil(outline) as int32);
}

export function grown(have: int32, need: int32): int32 {
	return need > have ? need : have;
}

export struct LabelUv {
	scaleU: float32;
	scaleV: float32;
	offsetV: float32;
}

export function uvOfSubRect(
	this typeof LabelUv,
	width: int32,
	height: int32,
	capacityWidth: int32,
	capacityHeight: int32,
	topLeft: boolean,
): LabelUv {
	const scaleV: float32 = (height as float32) / (capacityHeight as float32);
	return {
		scaleU: (width as float32) / (capacityWidth as float32), scaleV: scaleV,
		offsetV: topLeft ? 0.0 : 1.0 - scaleV,
	};
}

export function labelKey(): ProgramKey {
	return ProgramKey.of(Program.UnlitTextured).withPremultiplied().withUvTransform();
}

export function labelQuad(anchor: Anchor, flipV: boolean): Result<MeshData, MeshError> {
	let data: MeshData = MeshData.withUvs();
	const left: float32 = -0.5 - anchor.x;
	const right: float32 = 0.5 - anchor.x;
	const bottom: float32 = -0.5 - anchor.y;
	const top: float32 = 0.5 - anchor.y;
	const bottomV: float32 = flipV ? 0.0 : 1.0;
	const topV: float32 = flipV ? 1.0 : 0.0;
	const normal: Vec3 = vec3(0.0, 0.0, 1.0);
	const first: int32 = try addTexturedVertex(
		data, vec3(left, bottom, 0.0), normal, { u: 0.0, v: bottomV }, WHITE,
	);
	const second: int32 = try addTexturedVertex(
		data, vec3(right, bottom, 0.0), normal, { u: 1.0, v: bottomV }, WHITE,
	);
	const third: int32 = try addTexturedVertex(
		data, vec3(right, top, 0.0), normal, { u: 1.0, v: topV }, WHITE,
	);
	const fourth: int32 = try addTexturedVertex(
		data, vec3(left, top, 0.0), normal, { u: 0.0, v: topV }, WHITE,
	);
	const _lower: int32 = try addTriangle(data, first, second, third);
	const _upper: int32 = try addTriangle(data, first, third, fourth);
	return Result.ok(data);
}

function premultipliedPass(): RenderState {
	const pass: RenderState = RenderState.defaults();
	return pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.AlphaAdd);
}

function dropTarget(
	context: DrawContext,
	ui: Scene2D,
	target: RenderTarget,
	texture: TextureId,
): void {
	const _texture: Result<int32, HandleError> = releaseTexture(context, texture);
	target.close();
	ui.close();
}

function dropMesh(
	context: DrawContext,
	ui: Scene2D,
	target: RenderTarget,
	texture: TextureId,
	mesh: MeshId,
): void {
	const _mesh: Result<int32, HandleError> = releaseMesh(context, mesh);
	dropTarget(context, ui, target, texture);
}

export function create(
	this typeof WorldLabel,
	scene: Scene3D,
	parent: NodeId3D,
	text: string,
	style: WorldLabelStyle,
): Result<WorldLabel, WorldLabelError> {
	if (!(style.pixelsPerUnit > 0.0) || !(style.fontSize > 0.0)) {
		return Result.err(WorldLabelError.NotPositive);
	}
	const context: DrawContext = scene.context;
	const ui: Scene2D = Scene2D.create(CLEAR);
	const words: NodeRef =
		ui.label(text, style.fontSize, style.color).at(LABEL_PAD as float32, LABEL_PAD as float32);
	ui.add(words);
	const width: int32 = texelsAcross(words.textWidth(), 0.0);
	const height: int32 = texelsAcross(words.textHeight(), 0.0);
	const target: RenderTarget = RenderTarget.allocate(width, height, PixelFormat.Rgba8, true);
	const shown: Result<TextureId, TextureUploadError> = addTargetTexture(
		context, target, style.filter, Wrap.Clamp, TextureAlpha.Premultiplied,
	);
	if (!shown.ok) {
		target.close();
		ui.close();
		return Result.err(WorldLabelError.Texture);
	}
	const shape: Result<MeshData, MeshError> = labelQuad(style.anchor, !originTopLeft());
	if (!shape.ok) { unreachable; }
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, shape.value);
	if (!uploaded.ok) {
		dropTarget(context, ui, target, shown.value);
		return Result.err(WorldLabelError.Mesh);
	}
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) {
		dropMesh(context, ui, target, shown.value, uploaded.value);
		return Result.err(WorldLabelError.Uniforms);
	}
	const block: Vec<float32> = movingDefaults(labelKey());
	if (!writeUniforms(context, reserved.value, block).ok) { unreachable; }
	const material: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(labelKey(), premultipliedPass(), Phase.Alpha),
		texture: shown.value, uniforms: reserved.value,
	});
	if (!material.ok) {
		const _block: Result<int32, UniformError> = releaseUniforms(context, reserved.value);
		dropMesh(context, ui, target, shown.value, uploaded.value);
		return Result.err(WorldLabelError.Material);
	}
	const scale: Vec3 = vec3(
		(width as float32) / style.pixelsPerUnit, (height as float32) / style.pixelsPerUnit, 1.0,
	);
	const placed: Result<NodeId3D, SceneError> = addMeshNode(
		scene, parent, { ...Transform3D.identity(), scale: scale }, uploaded.value, material.value,
	);
	if (!placed.ok) {
		const _material: Result<int32, HandleError> = releaseMaterial(context, material.value);
		const _block: Result<int32, UniformError> = releaseUniforms(context, reserved.value);
		dropMesh(context, ui, target, shown.value, uploaded.value);
		return Result.err(WorldLabelError.Node);
	}
	const label: WorldLabel = {
		scene: scene, ui: ui, text: words, target: target, texture: shown.value,
		mesh: uploaded.value, material: material.value, uniforms: reserved.value,
		node: placed.value, pixelsPerUnit: style.pixelsPerUnit, width: width, height: height,
		position: vec3(0.0, 0.0, 0.0), rotation: identityQuat(), posed: false, block: block,
		stale: true, closed: false, outline: 0.0,
	};
	return Result.ok(label);
}

function writeBlock(this label: WorldLabel): void {
	const uv: LabelUv = LabelUv.uvOfSubRect(
		label.width, label.height, label.target.width, label.target.height, originTopLeft(),
	);
	const base: int32 = UNLIT_MATERIAL_UNIFORM_LENGTH;
	label.block[base + MOVING_UV_MATRIX] = uv.scaleU;
	label.block[base + MOVING_UV_MATRIX + 3] = uv.scaleV;
	label.block[base + MOVING_UV_OFFSET + 1] = uv.offsetV;
	if (!writeUniforms(label.scene.context, label.uniforms, label.block).ok) { unreachable; }
}

export function redraw(this label: WorldLabel): void {
	label.width = texelsAcross(label.text.textWidth(), label.outline);
	label.height = texelsAcross(label.text.textHeight(), label.outline);
	const capacityWidth: int32 = grown(label.target.width, label.width);
	const capacityHeight: int32 = grown(label.target.height, label.height);
	label.target.resize(capacityWidth, capacityHeight);
	label.ui.prepare(capacityWidth as float32, capacityHeight as float32, 1.0);
	label.ui.drawTarget(label.target);
	label.stale = false;
	label.writeBlock();
	if (label.posed) { label.place(); }
}

export function setLabelText(label: WorldLabel, text: string): void {
	label.text.setText(text);
	label.stale = true;
}

export function refreshLabel(label: WorldLabel): boolean {
	if (!label.stale && label.target.generation == contextGeneration()) { return false; }
	label.redraw();
	return true;
}

// Godot's Label3D outline_size and outline_modulate: void2d's label outline (`setOutline`, built
// with -d:voidTextOutline; without it a width above 0 stops by name), the target padded by the
// width so the outline is not cut at its edge. A width of 0 clears it.
export function setLabelOutline(label: WorldLabel, width: float32, color: Color): void {
	const _outlined: NodeRef = label.text.setOutline(width, color);
	label.outline = width;
	const pad: float32 = padFor(width) as float32;
	const _moved: NodeRef = label.text.at(pad, pad);
	label.stale = true;
}

export function setLabelTint(label: WorldLabel, tint: Rgba): void {
	label.block[UNLIT_MATERIAL_COLOR] = tint.red;
	label.block[UNLIT_MATERIAL_COLOR + 1] = tint.green;
	label.block[UNLIT_MATERIAL_COLOR + 2] = tint.blue;
	label.block[UNLIT_MATERIAL_COLOR + 3] = tint.alpha;
	if (!writeUniforms(label.scene.context, label.uniforms, label.block).ok) { unreachable; }
}

function transformOf(m: Mat4): Transform3D {
	const across: float32 = Math.sqrt(m.m11 * m.m11 + m.m12 * m.m12 + m.m13 * m.m13) as float32;
	const up: float32 = Math.sqrt(m.m21 * m.m21 + m.m22 * m.m22 + m.m23 * m.m23) as float32;
	const back: float32 = Math.sqrt(m.m31 * m.m31 + m.m32 * m.m32 + m.m33 * m.m33) as float32;
	const turn: Mat4 = {
		m11: m.m11 / across, m12: m.m12 / across, m13: m.m13 / across, m14: 0.0,
		m21: m.m21 / up, m22: m.m22 / up, m23: m.m23 / up, m24: 0.0,
		m31: m.m31 / back, m32: m.m32 / back, m33: m.m33 / back, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0,
	};
	return {
		position: vec3(m.m41, m.m42, m.m43), rotation: quatOfRotation(turn),
		scale: vec3(across, up, back),
	};
}

export function localFor(world: Mat4, parentWorld: Mat4): Transform3D {
	return transformOf(world.multiplyAffine(parentWorld.inverseAffine()));
}

function stopOnMirroredParent(): void {
	console.log("void3d: faceCamera needs a parent that does not mirror");
	unreachable;
}

function place(this label: WorldLabel): void {
	const scene: Scene3D = label.scene;
	const row: int32 = scene.liveRow(label.node, "faceCamera");
	const width: float32 = (label.width as float32) / label.pixelsPerUnit;
	const height: float32 = (label.height as float32) / label.pixelsPerUnit;
	const world: Mat4 = composeTransform(label.position, label.rotation, vec3(width, height, 1.0));
	const parent: int32 = scene.nodes[row].parent;
	if (parent == NO_NODE_3D) { stopOnMirroredParent(); }
	const _synced: int32 = syncWorld(scene);
	const parentWorld: Mat4 = scene.nodes[parent].world;
	if (parentWorld.determinant3x3() < 0.0) { stopOnMirroredParent(); }
	setLocal(scene, label.node, localFor(world, parentWorld));
}

export function facingRotation(basis: CameraBasis): Quat {
	return rotationOfBasis(basis);
}

export function faceCamera(label: WorldLabel, position: Vec3, basis: CameraBasis): void {
	label.position = position;
	label.rotation = facingRotation(basis);
	label.posed = true;
	label.place();
}

export function closeLabel(label: WorldLabel): void {
	if (label.closed) {
		console.log("void3d: closeLabel on a label that was closed");
		unreachable;
	}
	const context: DrawContext = label.scene.context;
	if (!label.scene.isClosed()) { const _nodes: int32 = remove(label.scene, label.node); }
	const _material: Result<int32, HandleError> = releaseMaterial(context, label.material);
	const _block: Result<int32, UniformError> = releaseUniforms(context, label.uniforms);
	dropMesh(context, label.ui, label.target, label.texture, label.mesh);
	label.closed = true;
}
