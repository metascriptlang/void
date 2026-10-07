// expect shadow.foreign: void3d: attachShadow with a shadow map of another draw context
// expect shadow.closedAttach: void3d: attachShadow with a shadow map that was closed
// expect shadow.closedFrame: void3d: beginFrame with a shadow map that was closed
// expect shadow.closedTwice: void3d: closeDirShadow on a shadow map that was closed
// expect shadow.unlitReceiver: void3d: Core UnlitTextured has no shadowed variant
import { argv } from "std/process";
import {
	Program, ProgramKey, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../../src/void3d/gpu3d";
import { DrawContext, DrawItem } from "../../../src/void3d/draw";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	attachShadow,
	beginFrame,
} from "../../../src/void3d/renderer";
import {
	DirShadowMap,
	ShadowError,
	DIR_SHADOW_UNIFORM_LENGTH,
	closeDirShadow,
} from "../../../src/void3d/dirShadowMap";

function coreOn(context: DrawContext): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (!made.ok) { unreachable; }
	return made.value;
}

function mapOn(context: DrawContext): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	if (!made.ok) { unreachable; }
	return made.value;
}

function run(name: string): void {
	let context: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH);
	let core: Renderer = coreOn(context);
	if (name == "shadow.foreign") {
		let other: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
		attachShadow(core, mapOn(other));
	} else if (name == "shadow.closedAttach") {
		let map: DirShadowMap = mapOn(context);
		closeDirShadow(map);
		attachShadow(core, map);
	} else if (name == "shadow.closedFrame") {
		let map: DirShadowMap = mapOn(context);
		attachShadow(core, map);
		closeDirShadow(map);
		let items: Vec<DrawItem> = [];
		let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const _began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	} else if (name == "shadow.closedTwice") {
		let map: DirShadowMap = mapOn(context);
		closeDirShadow(map);
		closeDirShadow(map);
	} else if (name == "shadow.unlitReceiver") {
		const _key: ProgramKey = ProgramKey.of(Program.UnlitTextured).withShadowed();
	}
	console.log(`shadow case ${name} ran to the end`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
