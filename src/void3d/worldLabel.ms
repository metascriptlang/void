import { Vec3, Quat, vec3, quatOfRotation } from "../math/math3d";
import { RenderState, BlendMode, FilterMode, Wrap } from "../gpu/state";
import { PixelFormat, contextGeneration, originTopLeft } from "../gpu/door";
import { RenderTarget } from "../gpu/target";
import { Scene2D, NodeRef } from "../void2d/node";
import "../void2d/scene";
import { textWidth, textHeight } from "../void2d/render";
import { Color } from "../void2d/types";
import { Anchor, ANCHOR_CENTER } from "./billboard";
import { CameraBasis } from "./camera";
import {
	Program, ProgramKey, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH,
	UNLIT_MATERIAL_COLOR,
} from "./gpu3d";
import { Material, Phase, UniformBlock } from "./material";
import { MeshData, MeshError, Rgba, addTexturedVertex, addTriangle } from "./meshData";
import { TextureId, TextureUploadError, TextureAlpha } from "./texture";
import {
	MeshId, MaterialId, MeshUploadError, MaterialError, HandleError, DrawContext,
	addMeshData, addMaterial, addTargetTexture, releaseMesh, releaseMaterial, releaseTexture,
	reserveUniforms, writeUniforms, releaseUniforms,
} from "./draw";
import { UniformError } from "./uniformPool";
import {
	Scene3D, Transform3D, NodeId3D, SceneError, addMeshNode, setLocal, remove,
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
	tint: Vec<float32>;
	stale: boolean;
	closed: boolean;
}

export function plainStyle(this typeof WorldLabelStyle, pixelsPerUnit: float32): WorldLabelStyle {
	return {
		fontSize: 16.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
		pixelsPerUnit: pixelsPerUnit, anchor: ANCHOR_CENTER, filter: FilterMode.Linear,
	};
}

function texelsAcross(extent: float32): int32 {
	return (Math.ceil(extent) as int32) + 2 * LABEL_PAD;
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
	const width: int32 = texelsAcross(words.textWidth());
	const height: int32 = texelsAcross(words.textHeight());
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
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) {
		dropMesh(context, ui, target, shown.value, uploaded.value);
		return Result.err(WorldLabelError.Uniforms);
	}
	let tint: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, reserved.value, tint).ok) { unreachable; }
	const material: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(
			ProgramKey.of(Program.UnlitTextured).withPremultiplied(), premultipliedPass(),
			Phase.Alpha,
		),
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
		dropMesh(context, ui, target, shown.value, uploaded.value);
		return Result.err(WorldLabelError.Node);
	}
	const label: WorldLabel = {
		scene: scene, ui: ui, text: words, target: target, texture: shown.value,
		mesh: uploaded.value, material: material.value, uniforms: reserved.value,
		node: placed.value, pixelsPerUnit: style.pixelsPerUnit, tint: tint, stale: true,
		closed: false,
	};
	label.redraw();
	return Result.ok(label);
}

export function redraw(this label: WorldLabel): void {
	const width: int32 = texelsAcross(label.text.textWidth());
	const height: int32 = texelsAcross(label.text.textHeight());
	label.target.resize(width, height);
	label.ui.prepare(width as float32, height as float32, 1.0);
	label.ui.drawTarget(label.target);
	label.stale = false;
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

export function setLabelTint(label: WorldLabel, tint: Rgba): void {
	label.tint[UNLIT_MATERIAL_COLOR] = tint.red;
	label.tint[UNLIT_MATERIAL_COLOR + 1] = tint.green;
	label.tint[UNLIT_MATERIAL_COLOR + 2] = tint.blue;
	label.tint[UNLIT_MATERIAL_COLOR + 3] = tint.alpha;
	if (!writeUniforms(label.scene.context, label.uniforms, label.tint).ok) { unreachable; }
}

export function facingRotation(basis: CameraBasis): Quat {
	return quatOfRotation({
		m11: basis.right.x, m12: basis.right.y, m13: basis.right.z, m14: 0.0,
		m21: basis.up.x, m22: basis.up.y, m23: basis.up.z, m24: 0.0,
		m31: -basis.forward.x, m32: -basis.forward.y, m33: -basis.forward.z, m34: 0.0,
		m41: 0.0, m42: 0.0, m43: 0.0, m44: 1.0,
	});
}

export function faceCamera(label: WorldLabel, position: Vec3, basis: CameraBasis): void {
	const width: float32 = (label.target.width as float32) / label.pixelsPerUnit;
	const height: float32 = (label.target.height as float32) / label.pixelsPerUnit;
	setLocal(label.scene, label.node, {
		position: position, rotation: facingRotation(basis), scale: vec3(width, height, 1.0),
	});
}

export function closeLabel(label: WorldLabel): void {
	if (label.closed) {
		console.log("void3d: closeLabel on a label that was closed");
		unreachable;
	}
	const context: DrawContext = label.scene.context;
	if (!label.scene.isClosed()) { const _nodes: int32 = remove(label.scene, label.node); }
	const _material: Result<int32, HandleError> = releaseMaterial(context, label.material);
	dropMesh(context, label.ui, label.target, label.texture, label.mesh);
	label.closed = true;
}
