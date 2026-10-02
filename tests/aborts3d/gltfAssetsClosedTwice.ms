// expect: void3d: closeGltfAssets on glTF assets that were closed
import { DrawContext } from "../../src/void3d/draw";
import { GltfAssets, closeGltfAssets } from "../../src/void3d/gltfScene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let assets: GltfAssets = {
	context: context,
	bindings: [],
	meshes: [],
	materials: [],
	textures: [],
	closed: false,
};
let alias: GltfAssets = assets;
closeGltfAssets(assets);
closeGltfAssets(alias);
console.log("glTF assets closed twice returned");
