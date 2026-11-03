// The sprites scene on Three.js: one InstancedMesh of textured quads under an orthographic camera
// in pixels, the library's fast path for many equal sprites.
import {
	Color, DataTexture, InstancedMesh, Matrix4, MeshBasicMaterial, NearestFilter, OrthographicCamera, PlaneGeometry, SRGBColorSpace, Scene,
} from 'three';
import { createRenderer } from 'bench-three-renderer';
import { HEIGHT, SIZE, TEXTURE_SIZE, WIDTH, checkerPixels, sprites, step } from './scene.js';

const renderer = await createRenderer(document.getElementById('canvas'), WIDTH, HEIGHT);
const scene = new Scene();
scene.background = new Color(0.08, 0.09, 0.11);
const camera = new OrthographicCamera(0, WIDTH, 0, -HEIGHT, -1, 1);
const texture = new DataTexture(checkerPixels(), TEXTURE_SIZE, TEXTURE_SIZE);
texture.colorSpace = SRGBColorSpace;
texture.magFilter = NearestFilter;
texture.needsUpdate = true;
const geometry = new PlaneGeometry(SIZE, SIZE);
geometry.translate(SIZE / 2, -SIZE / 2, 0);
const material = new MeshBasicMaterial({ map: texture, transparent: true });
const s = sprites();
const mesh = new InstancedMesh(geometry, material, s.x.length);
mesh.frustumCulled = false;
scene.add(mesh);
const matrix = new Matrix4();
const place = () => {
	for (let i = 0; i < s.x.length; i++) {
		matrix.makeTranslation(s.x[i], -s.y[i], 0);
		mesh.setMatrixAt(i, matrix);
	}
	mesh.instanceMatrix.needsUpdate = true;
};
place();
renderer.setAnimationLoop(() => {
	step(s);
	place();
	renderer.render(scene, camera);
});
