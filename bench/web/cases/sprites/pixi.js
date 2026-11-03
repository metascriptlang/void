// The sprites scene on PixiJS: one Sprite per sprite in the stage, the library's own batching.
import { Application, BufferImageSource, Sprite, Texture } from 'pixi.js';
import { HEIGHT, SIZE, TEXTURE_SIZE, WIDTH, checkerPixels, sprites, step } from './scene.js';

const app = new Application();
await app.init({
	canvas: document.getElementById('canvas'), width: WIDTH, height: HEIGHT, resolution: 1,
	antialias: false, background: [0.08, 0.09, 0.11], preference: BENCH_BACKEND,
});
if (app.renderer.name !== BENCH_BACKEND) throw new Error(`pixi: asked for ${BENCH_BACKEND}, got ${app.renderer.name}`);
const texture = new Texture({ source: new BufferImageSource({ resource: checkerPixels(), width: TEXTURE_SIZE, height: TEXTURE_SIZE }) });
const s = sprites();
const nodes = [];
for (let i = 0; i < s.x.length; i++) {
	const sprite = new Sprite(texture);
	sprite.width = SIZE;
	sprite.height = SIZE;
	sprite.position.set(s.x[i], s.y[i]);
	app.stage.addChild(sprite);
	nodes.push(sprite);
}
app.ticker.add(() => {
	step(s);
	for (let i = 0; i < nodes.length; i++) nodes[i].position.set(s.x[i], s.y[i]);
});
