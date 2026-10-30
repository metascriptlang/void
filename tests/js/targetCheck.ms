// Void on --target=js: modules that reach C compile, and what needs C answers with a named error.

import { decodeImage, decodeAnimation, imageFormatOf, ImageError, ImageFormat } from "../../src/assets/image";
import { rgbaPng } from "../../src/test/imageBytes";
import { loadGlb, GltfError } from "../../src/void3d/gltf";
import { loadFace, FaceError } from "../../src/void2d/face";
import { addFont, FontError } from "../../src/void2d/font";
import "../../src/test/frameEndCheck";
import { GlyphAtlas, GlyphKey } from "../../src/void2d/glyphAtlas";

const PNG_SIGNATURE: uint8[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

// Never called on JS: it holds GlyphAtlas.acquire in the build, whose box reads must compile.
export function acquireOnJs(atlas: GlyphAtlas, key: GlyphKey): boolean {
	return atlas.acquire(key).ok;
}

test "the image format is read from its signature on JS" {
	const format = imageFormatOf(PNG_SIGNATURE);
	assert format.ok && format.value == ImageFormat.Png;
}

test "an image and an animation decode on JS" {
	const image = decodeImage(rgbaPng());
	assert image.ok;
	if (image.ok) { assert image.value.width == 2 && image.value.height == 2; }
	const refused = decodeImage(PNG_SIGNATURE);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == ImageError.Undecodable; }
	const animation = decodeAnimation(PNG_SIGNATURE);
	assert !animation.ok;
	if (!animation.ok) { assert animation.error == ImageError.NotGif; }
}

test "a glTF document parses on JS up to its first refusal" {
	const glb = loadGlb(PNG_SIGNATURE);
	assert !glb.ok;
	if (!glb.ok) { assert glb.error == GltfError.NotGlb; }
}

test "a font path with no held bytes is unreadable on JS" {
	const face = loadFace("assets/font.ttf");
	assert !face.ok;
	if (!face.ok) { assert face.error == FaceError.Unreadable; }
	const font = addFont("assets/font.ttf");
	assert !font.ok;
	if (!font.ok) { assert font.error == FontError.NotLoaded; }
}
