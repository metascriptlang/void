import {
	loadGltf, loadGlb, GltfError, GltfFileSystem, GltfMaterialImport,
} from "../void3d/gltf";
import { FilterMode, Wrap } from "../gpu/state";
import { rgbaPng } from "./imageBytes";

const PNG_PAYLOAD: string =
	"iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP4z8DwHwyBNBAw"
	+ "NAAAR0sIeRPxYNAAAAAASUVORK5CYII=";
const PNG_URI: string = "data:image/png;base64," + PNG_PAYLOAD;
const JPEG_URI: string = "data:image/jpeg;base64,"
	+ "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB"
	+ "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEB"
	+ "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAAR"
	+ "CAAIABADAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAABv/EABQQAQAAAAAAAAAAAAAA"
	+ "AAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAJCv/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAM"
	+ "AwEAAhEDEQA/AD4rzYHCuBCO/9k=";

function imageDocument(image: string, storage: string = ""): string {
	return `{"asset":{"version":"2.0"},"scenes":[{}]${storage},"images":[${image}],`
		+ '"textures":[{"source":0}],"materials":[{"alphaMode":"BLEND",'
		+ '"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}]}';
}

function uriImage(uri: string, extra: string = ""): string {
	return `{"uri":"${uri}"${extra}}`;
}

function singleViewStorage(length: int32): string {
	return `,"buffers":[{"byteLength":${length}}],`
		+ `"bufferViews":[{"buffer":0,"byteLength":${length}}]`;
}

function asciiJsonGlb(json: string): Vec<uint8> {
	const jsonLength: int32 = json.length as int32;
	const padded: int32 = ((jsonLength + 3) / 4) * 4;
	let out: Vec<uint8> = [];
	const words: Vec<uint32> = [0x46546C67, 2, (20 + padded) as uint32,
		padded as uint32, 0x4E4F534A];
	for (const word of words) {
		for (const shift of [0, 8, 16, 24]) {
			out.push(((word >> (shift as uint32)) & (0xFF as uint32)) as uint8);
		}
	}
	for (let i = 0; i < padded; i++) {
		const code: int32 = i < jsonLength ? json.charCodeAt(i) as int32 : 32;
		if (code < 0 || code > 127) { unreachable; }
		out.push(code as uint8);
	}
	return move out;
}

test "PNG data images need no binary buffer and preserve rows and blend alpha" {
	for (const mime of ["", ',"mimeType":"image/png"']) {
		const result = loadGltf(imageDocument(uriImage(PNG_URI, mime)), []);
		assert result.ok;
		if (!result.ok) { return; }
		assert result.value.textures.length == 1;
		const texture = result.value.textures[0];
		assert texture.width == 2 && texture.height == 2 && texture.pixels.length == 4;
		const expected: Vec<uint32> = [0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0x8000FFFF];
		for (let i = 0; i < 4; i++) { assert texture.pixels[i] == expected[i]; }
		assert texture.filter == FilterMode.Linear && texture.wrap == Wrap.Repeat;
	}
}

test "URI JPEG and buffer view PNG remain distinct sources in one supplied buffer document" {
	const bytes = rgbaPng();
	const json = `{"asset":{"version":"2.0"},"scenes":[{}]`
		+ `${singleViewStorage(bytes.length as int32)},`
		+ '"images":[{"bufferView":0,"mimeType":"image/png"},'
		+ uriImage(JPEG_URI, ',"mimeType":"image/jpeg"')
		+ '],"textures":[{"source":0},{"source":1}]}';
	const result = loadGltf(json, bytes);
	assert result.ok;
	if (!result.ok) { return; }
	assert result.value.textures.length == 2;
	assert result.value.textures[0].width == 2 && result.value.textures[0].height == 2;
	assert result.value.textures[0].pixels[0] == (0xFF0000FF as uint32);
	const jpeg = result.value.textures[1];
	assert jpeg.width == 16 && jpeg.height == 8 && jpeg.pixels.length == 128;
	const left: uint32 = jpeg.pixels[0];
	const right: uint32 = jpeg.pixels[8];
	assert (left & 0xFF) > ((left >> 8) & 0xFF);
	assert ((left >> 8) & 0xFF) > ((left >> 16) & 0xFF);
	assert ((right >> 16) & 0xFF) > ((right >> 8) & 0xFF);
	assert ((right >> 8) & 0xFF) > (right & 0xFF);
	assert (left >> 24) == 255 && (right >> 24) == 255;
}

test "two samplers of one embedded image retain separate texture sampling" {
	const json = '{"asset":{"version":"2.0"},"scenes":[{}],"images":['
		+ uriImage(PNG_URI) + '],'
		+ '"samplers":[{"magFilter":9728,"minFilter":9728,"wrapS":33071,"wrapT":33071}],'
		+ '"textures":[{"source":0},{"source":0,"sampler":0}],"materials":['
		+ '{"alphaMode":"BLEND","pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},'
		+ '{"alphaMode":"BLEND","pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}]}';
	const result = loadGltf(json, []);
	assert result.ok;
	if (!result.ok) { return; }
	assert result.value.textures.length == 2;
	assert result.value.textures[0].filter == FilterMode.Linear;
	assert result.value.textures[0].wrap == Wrap.Repeat;
	assert result.value.textures[1].filter == FilterMode.Nearest;
	assert result.value.textures[1].wrap == Wrap.Clamp;
	for (let i = 0; i < 4; i++) {
		assert result.value.textures[0].pixels[i] == result.value.textures[1].pixels[i];
	}
	assert result.value.textures[1].pixels[3] == (0x8000FFFF as uint32);
}

test "JSON-only GLB decodes an embedded PNG without a BIN chunk" {
	const result = loadGlb(asciiJsonGlb(imageDocument(uriImage(PNG_URI))));
	assert result.ok;
	if (!result.ok) { return; }
	assert result.value.textures.length == 1;
	assert result.value.textures[0].width == 2 && result.value.textures[0].height == 2;
	assert result.value.textures[0].pixels[3] == (0x8000FFFF as uint32);
}

test "data image decoding refuses malformed payloads and media type contradictions by name" {
	const bad: Vec<string> = [
		"data:image/png;base64,",
		"data:image/png;base64,Zg=",
		"data:image/png;base64,Zh==",
		"data:image/png;base64,!!!!",
		"data:image/png;base64,AAAA====",
		"data:image/png;base64,éAAA",
		"data:image/png;base64,Zm9v",
		"data:image/jpeg;base64," + PNG_PAYLOAD,
	];
	for (const uri of bad) {
		const result = loadGltf(imageDocument(uriImage(uri)), []);
		assert !result.ok;
		if (!result.ok) { assert result.error == GltfError.BadImage; }
	}
	const mismatch = loadGltf(imageDocument(uriImage(PNG_URI, ',"mimeType":"image/jpeg"')), []);
	assert !mismatch.ok;
	if (!mismatch.ok) { assert mismatch.error == GltfError.BadImage; }
	const raw = loadGltf(imageDocument(uriImage("data:image/png,raw")), []);
	assert !raw.ok;
	if (!raw.ok) { assert raw.error == GltfError.Unsupported; }
}

test "embedded image support neither resolves external URIs nor accepts two image sources" {
	for (const uri of ["missing.png", "https://example.invalid/a.png", "file:///C:/missing.png"]) {
		const result = loadGltf(imageDocument(uriImage(uri)), []);
		assert !result.ok;
		if (!result.ok) { assert result.error == GltfError.ImageByUri; }
	}
	const bytes = rgbaPng();
	const both = loadGltf(imageDocument(uriImage(PNG_URI, ',"bufferView":0'),
		singleViewStorage(bytes.length as int32)), bytes);
	assert !both.ok;
	if (!both.ok) { assert both.error == GltfError.Unsupported; }
}

function filesHolding(path: string, bytes: Vec<uint8>): GltfFileSystem {
	return {
		exists: (name: string): boolean => name == path,
		getBytes: (name: string): Vec<uint8> => bytes,
	};
}

test "an image named by URI decodes from the caller's file system, its type sniffed or declared" {
	const files: GltfFileSystem = filesHolding("textures/a.png", rgbaPng());
	const legacy: GltfMaterialImport = GltfMaterialImport.Legacy;
	for (const mime of ["", ',"mimeType":"image/png"']) {
		const result = loadGltf(imageDocument(uriImage("textures/a.png", mime)), [], legacy, files);
		assert result.ok;
		if (!result.ok) { return; }
		const texture = result.value.textures[0];
		assert texture.width == 2 && texture.height == 2;
		const expected: Vec<uint32> = [0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0x8000FFFF];
		for (let i = 0; i < 4; i++) { assert texture.pixels[i] == expected[i]; }
	}
	const declared = loadGltf(imageDocument(uriImage("textures/a.png", ',"mimeType":"image/jpeg"')),
		[], legacy, files);
	assert !declared.ok && declared.error == GltfError.BadImage;
	const absent = loadGltf(imageDocument(uriImage("textures/b.png")), [], legacy, files);
	assert !absent.ok && absent.error == GltfError.FileNotFound;
	const encoded = loadGltf(imageDocument(uriImage("textures/a%20b.png")), [], legacy,
		filesHolding("textures/a%20b.png", rgbaPng()));
	assert !encoded.ok && encoded.error == GltfError.Unsupported;
	const notImage = loadGltf(imageDocument(uriImage("textures/a.png")), [], legacy,
		filesHolding("textures/a.png", [1, 2, 3, 4]));
	assert !notImage.ok && notImage.error == GltfError.BadImage;
}
