import { Buffer } from "std/core/buffer";

export function shaderBytecodeFromBase64(base64: string): Vec<uint8> {
	const bytes = Buffer.fromString(base64, "base64");
	let out: Vec<uint8> = new Array(bytes.byteLength);
	for (let i = 0; i < out.length; i++) { out[i] = bytes.byteAt(i) as uint8; }
	return out;
}
