import { Vec3, vec3 } from "../../src/math/math3d";
import { NodeRef, Scene2D } from "../../src/void2d/node";
import { tick } from "../../src/void2d/scene";
import { renderTargetsAlive } from "../../src/void2d/render";
import { Tile, tile, rgba } from "../../src/void2d/types";
import { vertexCount } from "../../src/void2d/displayList";
import { GlyphAtlas } from "../../src/void2d/glyphAtlas";
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { draw } from "../../src/void3d/gpu3d";
import { Bounds3D } from "../../src/void3d/bounds";
import { MeshData, MeshError, Rgba, BOX_VERTICES, addBox } from "../../src/void3d/meshData";
import { AnimationClock, AnimationError, Interpolation, update } from "../../src/void3d/animation";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	removeChildren,
} from "../../src/void3d/scene";
import { Renderer, RendererError, beginFrame } from "../../src/void3d/renderer";
import { RenderTarget } from "../../src/gpu/target";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };

let failures: int32 = 0;

function check(what: string, holds: boolean): void {
	if (holds) { return; }
	console.log(`FAIL both layers: ${what}`);
	failures = failures + 1;
}

function resolvesOnGpu(
	box: NodeRef,
	atlas: GlyphAtlas,
	target: RenderTarget,
	renderer: Renderer,
	context: DrawContext,
): void {
	box.draw(1.0, 8.0, 8.0);
	draw(0, 3, 1);
	atlas.beginFrame(1);
	atlas.release(0);
	const _released: RenderTarget = target.released();
	let core: Renderer = renderer;
	let drawing: DrawContext = context;
	const items: Vec<DrawItem> = [];
	const blocks: Vec<float32> = [];
	const _began: Result<boolean, RendererError> = beginFrame(core, items, blocks, blocks);
}

function main(): int32 {
	const layer: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const box: NodeRef = layer.rect(4.0, 4.0, rgba(1.0, 1.0, 1.0, 1.0));
	box.addChild(layer.rect(2.0, 2.0, rgba(1.0, 0.0, 0.0, 1.0)));
	box.removeChildren();
	check("void2d removeChildren on a node", box.numChildren() == 0);
	box.setVisible(false);
	check("void2d visibility binder", !box.order().visible);
	layer.tick(0.5);
	const centred: Tile = tile(0, 8.0, 8.0).center();
	check("void2d center on a tile", centred.dx == -4.0 && centred.dy == -4.0);
	check("void2d vertexCount of the display list", vertexCount() == 0);
	check("void2d render module", renderTargetsAlive() == 0);

	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const _child: NodeId3D = addGroup(scene, group, Transform3D.identity());
	const removed: Result<int32, SceneError> = removeChildren(scene, group);
	check("void3d removeChildren on a scene", removed.ok && removed.value == 1);
	const made: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(2, 1.0, Interpolation.Step);
	if (made.ok) {
		let clock: AnimationClock = made.value;
		const moved: Result<boolean, AnimationError> = update(clock, 1.0);
		check("void3d update on a clock", moved.ok);
	} else {
		check("void3d clock", false);
	}
	const box3: Bounds3D = { min: vec3(0.0, 0.0, 0.0), max: vec3(2.0, 4.0, 6.0) };
	const middle: Vec3 = box3.center();
	check("void3d center on bounds", middle.x == 1.0 && middle.y == 2.0 && middle.z == 3.0);
	let data: MeshData = MeshData.empty();
	const boxed: Result<int32, MeshError> = addBox(data, {
		base: vec3(0.0, 0.0, 0.0),
		size: vec3(1.0, 1.0, 1.0),
		yaw: 0.0,
		tilt: 0.0,
		color: WHITE,
	});
	check("void3d vertexCount of a mesh", boxed.ok && data.vertexCount() == BOX_VERTICES);

	if (failures > 0) { return 1; }
	console.log("PASS both layers: every name the two layers share resolves to its own layer");
	return 0;
}

process.exit(main());
