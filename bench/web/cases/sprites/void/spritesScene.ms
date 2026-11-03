// The sprites scene of bench/web/README.md for Void: the same workload ../pixi.js and ../three.js run.

import { Texture } from "../../../../../src/gpu/texture";
import { gfxSetup, makeImage, makeView } from "../../../../../src/host/gpu";
import { BlendMode } from "../../../../../src/gpu/state";
import { setup2d, preparePipelines } from "../../../../../src/void2d/draw";
import { NodeRef, Scene2D } from "../../../../../src/void2d/node";
import { add, present } from "../../../../../src/void2d/scene";
import { rgba, tile } from "../../../../../src/void2d/types";

const COUNT: int32 = 10000;
const WIDTH: float32 = 1280.0;
const HEIGHT: float32 = 720.0;
const SIZE: float32 = 16.0;
const TEXTURE_SIZE: int32 = 32;
const CHECKER: int32 = 8;

let seed: uint32 = 1;
let scene: Scene2D | null = null;
let nodes: Vec<NodeRef> = [];
let xs: Vec<float32> = [];
let ys: Vec<float32> = [];
let vxs: Vec<float32> = [];
let vys: Vec<float32> = [];

function random(): float32 {
	seed = seed * 1664525 + 1013904223;
	return ((seed as float64) / 4294967296.0) as float32;
}

function checker(): Vec<uint32> {
	let pixels: Vec<uint32> = [];
	for (let y: int32 = 0; y < TEXTURE_SIZE; y++) {
		for (let x: int32 = 0; x < TEXTURE_SIZE; x++) {
			const warm = ((x / CHECKER) + (y / CHECKER)) % 2 == 0;
			pixels.push(warm ? 0xff40c8ff : 0xffffa040);
		}
	}
	return pixels;
}

function bounce(p: float32, v: float32, limit: float32): [float32, float32] {
	const q = p + v;
	if (q < 0.0) {
		return [-q, -v];
	}
	if (q > limit) {
		return [2.0 * limit - q, -v];
	}
	return [q, v];
}

export function spritesInit(): void {
	gfxSetup();
	setup2d();
	const prepared: Vec<BlendMode> = [BlendMode.Alpha];
	preparePipelines(prepared);
	const s = Scene2D.create(rgba(0.08, 0.09, 0.11, 1.0));
	const image: uint32 = makeImage(checker() as Span<uint32>, TEXTURE_SIZE, TEXTURE_SIZE);
	const view: Texture = Texture.adopt(image, makeView(image), TEXTURE_SIZE, TEXTURE_SIZE);
	for (let i: int32 = 0; i < COUNT; i++) {
		const x = random() * (WIDTH - SIZE);
		const y = random() * (HEIGHT - SIZE);
		vxs.push((random() * 2.0 - 1.0) * 2.0);
		vys.push((random() * 2.0 - 1.0) * 2.0);
		xs.push(x);
		ys.push(y);
		nodes.push(s.add(s.sprite(tile(view, SIZE, SIZE)).at(x, y)));
	}
	scene = s;
	console.log(`bench.scene sprites count=${COUNT} size=${SIZE}`);
}

export function spritesFrame(): void {
	if (scene === null) {
		return;
	}
	for (let i: int32 = 0; i < COUNT; i++) {
		const [x, vx] = bounce(xs[i], vxs[i], WIDTH - SIZE);
		const [y, vy] = bounce(ys[i], vys[i], HEIGHT - SIZE);
		xs[i] = x;
		ys[i] = y;
		vxs[i] = vx;
		vys[i] = vy;
		nodes[i].setPosition(x, y);
	}
	scene.present();
}
