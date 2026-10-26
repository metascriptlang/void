import { gfxSetup, fbWidth, fbHeight } from "../../src/host/gpu";
import { Vec3, Vec4, vec3 } from "../../src/math/math3d";
import { RenderState, Face } from "../../src/gpu/state";
import { IndexType } from "../../src/gpu/pipeline";
import {
	liveBuffers, liveImages, liveViews, liveSamplers, liveShaders, livePipelines, contextGeneration,
} from "../../src/gpu/door";
import { boundingRadius } from "../../src/void3d/bounds";
import { MeshData, Rgba, addVertex, addTriangle } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, NO_MESH,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
	releaseMesh, releaseMaterial, closeContext, rebuildMeshes,
} from "../../src/void3d/draw";
import {
	Scene3D, NodeId3D, Transform3D, addMeshNode, addLodMeshNode, setForcedLod, remove, closeScene,
	setAmbient, collectLights, refresh,
} from "../../src/void3d/scene";
import { Camera3D, CameraView, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, FORWARD_UNIFORM_LENGTH, FORWARD_OUTLINE_UNIFORM_LENGTH,
	setOutlineBlend, closeForward, renderFrame,
} from "../../src/void3d/forwardRenderer";
import {
	MeshLod, MeshLodRanges, MeshLodProjectedSize,
	referenceScreenRatioHeuristic,
} from "../../src/void3d/meshLod";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const FIRST_ELEMENT: int32 = 65538;
const WORLD_PER_TEXEL: float32 = 0.02;
const BACKGROUND: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const SURFACE: Rgba = { red: 1.0, green: 0.2, blue: 0.1, alpha: 1.0 };
const SCREEN: LowResView = { width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0.0, offsetY: 0.0 };
let control: int32 = voidCaptureEnvInt("VOID_MESH_LOD_CONTROL", 0);
let outlined: boolean = voidCaptureEnvInt("VOID_MESH_LOD_OUTLINE", 0) != 0;
let wide: boolean = voidCaptureEnvInt("VOID_MESH_LOD_INDEX32", 0) != 0;
let scenePicked: boolean = voidCaptureEnvInt("VOID_MESH_LOD_SCENE", 0) != 0;
let context: DrawContext = DrawContext.withUniformCapacity(
	(outlined ? FORWARD_OUTLINE_UNIFORM_LENGTH : FORWARD_UNIFORM_LENGTH) +
	2 * MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = createForward();
let scene: Scene3D = Scene3D.create(context);
let mesh: MeshId = NO_MESH;
let materials: Vec<MaterialId> = [];
let nodes: Vec<NodeId3D> = [];
let source: Vec<DrawItem> = [];
let selected: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let lod: MeshLod = createLod();
let ranges: MeshLodRanges = createRanges();
let radius: float64 = 0.0;
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL mesh LOD: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function createForward(): ForwardRenderer {
	const made = ForwardRenderer.create(context, BACKGROUND);
	if (made.ok) { return made.value; }
	unreachable;
}

function createLod(): MeshLod {
	const made = MeshLod.create(2, [0.1], control == 5 ? 0.0 : 0.02);
	if (made.ok) { return made.value; }
	unreachable;
}

function createRanges(): MeshLodRanges {
	const made = MeshLodRanges.fromElementRanges(2, 2, FIRST_ELEMENT + 12, [
		{ base: FIRST_ELEMENT, count: 3 },
		{ base: FIRST_ELEMENT + 3, count: 3 },
		{ base: FIRST_ELEMENT + 6, count: 3 },
		{ base: FIRST_ELEMENT + 9, count: 3 },
	]);
	if (made.ok) { return made.value; }
	unreachable;
}

function centerAt(group: int32): Vec3 {
	return match (group) {
		0 => vec3(-1.0, -0.6, 0.0),
		1 => vec3(1.0, -0.6, 0.0),
		2 => vec3(-0.7, 0.6, 0.0),
		3 => vec3(0.7, 0.6, 0.0),
		_ => { unreachable; },
	};
}

function appendGroup(ref data: MeshData, group: int32): void {
	const p: Vec3 = centerAt(group);
	const normal: Vec3 = vec3(0.0, 0.0, 1.0);
	const a = addVertex(data, vec3(p.x - 0.25, p.y - 0.2, 0.0), normal, SURFACE);
	const b = addVertex(data, vec3(p.x + 0.25, p.y - 0.2, 0.0), normal, SURFACE);
	const c = addVertex(data, vec3(p.x, p.y + 0.3, 0.0), normal, SURFACE);
	if (!a.ok || !b.ok || !c.ok) { unreachable; }
}

function materialAt(amount: float32): MaterialId {
	const block = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	const owned: UniformBlock = block.value;
	const values: Vec<float32> = [4.0, amount, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0];
	if (!writeUniforms(context, owned, values).ok) { unreachable; }
	const made = addMaterial(context, {
		...Material.plain(Program.Lit, RenderState.defaults().withCulling(Face.None), Phase.Opaque),
		uniforms: owned,
	});
	if (made.ok) { return made.value; }
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	const known: boolean = scenePicked ? control == 0 || control == 8 :
		control >= 0 && control <= (wide ? 7 : 5);
	if (!known) { fail("unknown control"); }
	gfxSetup();
	let data: MeshData = MeshData.empty();
	const vertexBase: int32 = wide ? 65536 : 0;
	for (let i = 0; i < vertexBase; i++) {
		if (!addVertex(data, vec3(0, 0, 0), vec3(0, 0, 1), SURFACE).ok) { unreachable; }
	}
	if (wide) { data.wideIndices = []; }
	for (let group = 0; group < 4; group++) { appendGroup(data, group); }
	for (let i = 0; i < FIRST_ELEMENT; i++) {
		if (data.wideIndices !== null) { data.wideIndices.push(0); }
		else { data.indices.push(0); }
	}
	for (let group = 0; group < 4; group++) {
		const base: int32 = (control == 7 ? 0 : vertexBase) + group * 3;
		if (!addTriangle(data, base, base + 1, base + 2).ok) { unreachable; }
	}
	radius = data.bounds.boundingRadius();
	const uploaded = addMeshData(context, data);
	if (!uploaded.ok) { fail(`mesh upload ${uploaded.error.toString()}`); unreachable; }
	mesh = uploaded.value;
	materials.push(materialAt(0.0));
	materials.push(materialAt(-1.0));
	for (let slot = 0; slot < 2; slot++) {
		const node = scenePicked ?
			addLodMeshNode(scene, scene.rootId(), Transform3D.identity(), mesh, materials[slot], lod,
				ranges, slot) :
			addMeshNode(scene, scene.rootId(), Transform3D.identity(), mesh, materials[slot]);
		if (!node.ok) { fail(`node attachment ${node.error.toString()}`); unreachable; }
		nodes.push(node.value);
		if (control == 8 && !setForcedLod(scene, node.value, 0).ok) { unreachable; }
	}
	if (!releaseMesh(context, mesh).ok) { unreachable; }
	for (const material of materials) {
		if (!releaseMaterial(context, material).ok) { unreachable; }
	}
	if (context.meshPinned(mesh) != 2) { fail("shared mesh lost its two pins"); }
	setAmbient(scene, vec3(1.0, 1.0, 1.0));
}

function cameraAt(): Camera3D {
	const distance: float32 = stage == 0 ? 4.0 : (stage == 4 ? 128.0 : 32.0);
	return {
		position: vec3(0.0, 0.0, distance), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 256.0,
		projection: {
			kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false,
		},
	};
}

function selectItems(camera: Camera3D): void {
	while (selected.length > 0) { selected.pop(); }
	if (scenePicked) {
		for (const item of source) { selected.push(item); }
		return;
	}
	const projection = camera.orthoBounds(WIDTH, HEIGHT).projectionMatrix();
	const size: MeshLodProjectedSize = {
		localOriginRadius: radius,
		worldScaleX: 1.0, worldScaleY: 1.0, worldScaleZ: 1.0, worldMirrored: false,
		cameraDistanceFromWorldOrigin: camera.position.z as float64,
		projectionDiagonalX: projection.m11 as float64,
		projectionDiagonalY: projection.m22 as float64,
		nearPlane: camera.nearPlane as float64, meshLodScale: 1.0,
	};
	const ratio = size.referenceScreenRatioHeuristic();
	if (!ratio.ok) { fail(`size ${ratio.error.toString()}`); unreachable; }
	const chosen = lod.select(ratio.value);
	if (!chosen.ok) { fail(`selection ${chosen.error.toString()}`); unreachable; }
	if (chosen.value.culled) { return; }
	const level: int32 = control == 1 ? 0 : chosen.value.lod;
	for (const item of source) {
		const material: int32 = item.material.index == materials[0].index ? 0 : 1;
		const range = ranges.rangeAt(material, level);
		if (!range.ok) { fail(`range ${range.error.toString()}`); unreachable; }
		let base: int32 = range.value.base;
		if (control == 2) { base = FIRST_ELEMENT + (material * 2 + level) * 3; }
		if (control == 4) { base = base & 65535; }
		selected.push({
			...item, range: {
				base: control == 3 ? 0 : base,
				count: control == 3 ? FIRST_ELEMENT + 12 : range.value.count,
			},
		});
	}
}

function rgbAt(view: CameraView, group: int32): int64 {
	const p: Vec3 = view.project(centerAt(group), SCREEN, true);
	return voidCapturePixel(0, p.x as int32, p.y as int32) >> 8;
}

function visibleGroup(group: int32): boolean {
	return stage == 0 ? group < 2 :
		(stage == 4 ? false : (stage == 3 ? group == 3 : group >= 2));
}

function checkPixels(view: CameraView): void {
	for (let group = 0; group < 4; group++) {
		const visible: boolean = visibleGroup(group);
		const rgb: int64 = rgbAt(view, group);
		if ((rgb != 0) != visible) {
			fail(`group ${group} silhouette did not match LOD/culling: ${rgb}`);
		}
		if (!visible) { continue; }
		const red: int64 = (rgb >> 16) & 255;
		const green: int64 = (rgb >> 8) & 255;
		const blue: int64 = rgb & 255;
		if (group % 2 == 0 && red <= green + 30) { fail("colored material was replaced"); }
		if (group % 2 == 1 && (Math.abs((red - green) as float64) > 3 ||
			Math.abs((red - blue) as float64) > 3)) {
			fail("desaturated material was replaced");
		}
	}
}

function visibleItems(): int32 {
	return stage == 4 ? 0 : (stage == 3 ? 1 : 2);
}

function checkOutlinedFrame(view: CameraView): void {
	const plain: Vec<DrawItem> = selected;
	setOutlineBlend(forward, 1.0);
	const drawn = renderFrame(forward, selected, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`outline renderer ${drawn.error.toString()}`); unreachable; }
	if (drawn.value != visibleItems() || selected.length != plain.length) {
		fail("outline changed selected item count");
	}
	for (let i = 0; i < (plain.length as int32); i++) {
		const before = plain[i].drawnRange();
		const after = selected[i].drawnRange();
		if (before == null || after == null) { fail("outline lost selected range"); unreachable; }
		if (before.base != after.base || before.count != after.count) {
			fail("outline changed selected range");
		}
	}
	if (voidCaptureGrab(0) == 0) { fail("outline readback failed"); }
	for (let group = 0; group < 4; group++) {
		const p: Vec3 = view.project(centerAt(group), SCREEN, true);
		let coverage: int32 = 0;
		for (let y = -20; y <= 20; y++) {
			for (let x = -20; x <= 20; x++) {
				if ((voidCapturePixel(0, (p.x as int32) + x, (p.y as int32) + y) & 255) != 0) {
					coverage++;
				}
			}
		}
		if ((coverage != 0) != visibleGroup(group)) {
			fail(`outline group ${group} silhouette did not match selected LOD: ${coverage}`);
		}
	}
	setOutlineBlend(forward, 0.0);
	console.log(`PASS mesh LOD: stage ${stage}, outline-selected silhouettes and ranges matched`);
}

function reuploadSameContext(): void {
	const generation: int32 = contextGeneration();
	const old = context.meshes[mesh.index];
	if (old.generation != generation || old.vertexBuffer == 0 || old.indexBuffer == 0) {
		fail("reupload started without current owned buffers");
	}
	context.doomed.push({ buffer: old.vertexBuffer, generation: generation });
	context.doomed.push({ buffer: old.indexBuffer, generation: generation });
	context.meshes[mesh.index] = {
		...old, vertexBuffer: 0, indexBuffer: 0, generation: 0,
	};
	if (rebuildMeshes(context) != 1) { fail("reupload did not rebuild exactly one mesh"); }
	const rebuilt = context.meshes[mesh.index];
	if (rebuilt.generation != generation || rebuilt.vertexBuffer == 0 || rebuilt.indexBuffer == 0 ||
		rebuilt.vertexBuffer == old.vertexBuffer || rebuilt.indexBuffer == old.indexBuffer) {
		fail("reupload did not replace buffers in current generation");
	}
	if (context.meshPinned(mesh) != 2) { fail("reupload changed retained mesh pins"); }
	if (rebuilt.indexType() != (wide ? IndexType.Uint32 : IndexType.Uint16)) {
		fail("reupload changed index width");
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer size changed"); }
	if (stage == 2) { reuploadSameContext(); }
	if (control != 6 &&
		context.meshes[mesh.index].indexType() != (wide ? IndexType.Uint32 : IndexType.Uint16)) {
		fail("uploaded mesh lost index width");
	}
	if (control == 6) { context.meshes[mesh.index].index32 = false; }
	if (stage == 3) {
		if (remove(scene, nodes[0]) != 1 || context.meshPinned(mesh) != 1) {
			fail("removing one consumer released the shared mesh");
		}
	}
	refresh(scene, source);
	const consumers: int32 = stage >= 3 ? 1 : 2;
	if ((source.length as int32) != consumers || context.meshPinned(mesh) != consumers) {
		fail("retained consumer count or shared pins changed");
	}
	for (const item of source) {
		if (item.mesh.store != mesh.store || item.mesh.index != mesh.index ||
			item.mesh.generation != mesh.generation) {
			fail("retained consumer changed shared mesh identity");
		}
	}
	const camera: Camera3D = cameraAt();
	selectItems(camera);
	const resolved = camera.resolve(WIDTH, HEIGHT);
	if (!resolved.ok) { fail(`camera ${resolved.error.toString()}`); unreachable; }
	const view: CameraView = resolved.value;
	view.writeCameraBlock(cameraValues);
	if (!collectLights(scene, lights).ok) { unreachable; }
	const drawn = renderFrame(forward, selected, cameraValues, lights, WIDTH, HEIGHT);
	if (!drawn.ok) { fail(`renderer ${drawn.error.toString()}`); unreachable; }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	checkPixels(view);
	if (outlined) { checkOutlinedFrame(view); }
	const expectedItems: int32 = visibleItems();
	const handed: int32 = scenePicked ? consumers : expectedItems;
	const culled: int32 = scenePicked ? handed - expectedItems : 0;
	if ((selected.length as int32) != handed || drawn.value != expectedItems ||
		forward.core.culledCount != culled) {
		fail(`selected ${selected.length}, rendered ${drawn.value} or culled ` +
			`${forward.core.culledCount} items changed`);
	}
	console.log(`mesh LOD: stage ${stage}, selected ${selected.length}, ` +
		`renderedItems ${drawn.value}`);
	stage++;
	if (stage < 5) { return; }
	closeScene(scene);
	if (context.hasMesh(mesh)) { fail("last consumer left the mesh live"); }
	closeForward(forward);
	if (context.liveMeshes() != 0 || context.liveMaterials() != 0) {
		fail("close left resource holders live");
	}
	closeContext(context);
	if (liveBuffers() != 0 || liveImages() != 0 || liveViews() != 0 || liveSamplers() != 0 ||
		liveShaders() != 0 || livePipelines() != 0) {
		fail("close left GPU resources live");
	}
	console.log("PASS mesh LOD: ranges/materials, culling, same-context reupload, pins, close");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
