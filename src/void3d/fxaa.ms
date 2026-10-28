// Heaps' h3d.pass.FXAA: post3d.ms fxaaFs drawn from a texture into a target of its size.

import { Program } from "./gpu3d";
import { LoadAction, PixelFormat, endPass } from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	Sampler,
	NO_DEPTH,
	beginPass,
} from "../gpu/target";
import { Material, Phase } from "./material";
import { Vec4 } from "../math/math3d";
import {
	DrawContext,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	releaseMaterial,
} from "./draw";
import { screenState } from "./screenFx";
import { Renderer, RendererError, drawScreen } from "./renderer";

const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

export interface FxaaPass {
	sampler: Sampler;
	material: MaterialId;
	colors: Vec<ColorAttachment>;
}

// Adds the material to `context`; no GPU object is made here.
export function reserve(this typeof FxaaPass, context: DrawContext): FxaaPass {
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Fxaa, screenState(), Phase.Opaque));
	if (!added.ok) { unreachable; }
	return {
		sampler: { filter: FilterMode.Linear, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		material: added.value,
		colors: new Array(1),
	};
}

export function adoptContext(this pass: FxaaPass): void {
	pass.sampler = Sampler.create(pass.sampler.filter, pass.sampler.wrap);
}

function stopOnSize(source: RenderTarget, target: RenderTarget): void {
	console.log(`void3d: FXAA from ${source.width}x${source.height} into ` +
		`${target.width}x${target.height}; the source is the target's size`);
	unreachable;
}

function layoutOf(format: PixelFormat): TargetLayout {
	return {
		color0: format,
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth: PixelFormat.None,
		sampleCount: 1,
	};
}

// FXAA.apply: `source` filtered into `target`, which must not be it.
export function draw(
	this pass: FxaaPass,
	core: Renderer,
	source: RenderTarget,
	target: RenderTarget,
): void {
	if (source.width != target.width || source.height != target.height) {
		stopOnSize(source, target);
	}
	const context: DrawContext = core.context;
	context.materials[pass.material.index].texture0 = source.asTexture();
	context.materials[pass.material.index].sampler0 = pass.sampler.asHandle();
	pass.colors[0] = target.asColor(LoadAction.DontCare, NO_CLEAR);
	beginPass(pass.colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(core, pass.material, layoutOf(target.format));
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: FxaaPass, context: DrawContext, call: string): void {
	pass.sampler = pass.sampler.released();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found the FXAA material ${released.error.toString()}`);
		unreachable;
	}
}
