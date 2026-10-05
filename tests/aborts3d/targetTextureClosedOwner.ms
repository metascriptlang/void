// expect: void3d: addTargetTexture on a render target that was closed
import { PixelFormat } from "../../src/gpu/door";
import { RenderTarget } from "../../src/gpu/target";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { TextureAlpha } from "../../src/void3d/texture";
import { DrawContext, addTargetTexture } from "../../src/void3d/draw";
const context: DrawContext = DrawContext.withUniformCapacity(0);
const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
target.close();
const added =
	addTargetTexture(context, target, FilterMode.Nearest, Wrap.Clamp, TextureAlpha.Premultiplied);
console.log(`a closed target was taken: ${added.ok}`);
