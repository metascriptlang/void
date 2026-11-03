// The renderer bench/web three cases get for BENCH_BACKEND 'webgl'.
import { WebGLRenderer } from 'three';

export async function createRenderer(canvas, width, height) {
	const renderer = new WebGLRenderer({ canvas, antialias: false });
	renderer.setPixelRatio(1);
	renderer.setSize(width, height, false);
	return renderer;
}
