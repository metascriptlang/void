// The renderer bench/web three cases get for BENCH_BACKEND 'webgpu'. bench/web/run.mjs aliases 'three' to
// three's WebGPU build for those builds, so this import and the scene's classes come from one module.
import { WebGPURenderer } from 'three';

export async function createRenderer(canvas, width, height) {
	const renderer = new WebGPURenderer({ canvas, antialias: false });
	renderer.setPixelRatio(1);
	renderer.setSize(width, height, false);
	await renderer.init();
	if (!renderer.backend.isWebGPUBackend) throw new Error('three: WebGPURenderer fell back to WebGL');
	return renderer;
}
