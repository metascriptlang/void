@include("gltfDecode.h");
@compile("./gltfDecode.c");

extern function gltfDecodeFloat32At(bytes: Span<uint8>, at: int32): float32;

export function float32At(bytes: Span<uint8>, at: int32): float32 {
	return gltfDecodeFloat32At(bytes, at);
}
