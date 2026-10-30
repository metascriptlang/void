// Void Asset — an image file's bytes and pixels, for the entries and checks that read one.

import { sfntSourceRead, sfntSourceSize } from "../void2d/sfntSource";
import { decodeImage } from "./image";
import { Pixels } from "./imageTypes";

// A file that is not there or does not decode stops the program: the callers are demos and
// checks whose asset ships beside them.
export function readFileBytes(path: string): Vec<uint8> {
	const size = sfntSourceSize(path);
	if (size < 0) { throw new Error(`cannot read ${path}`); }
	let bytes: Vec<uint8> = new Array<uint8>(size as int32);
	if (size > 0 && !sfntSourceRead(path, 0, bytes)) { throw new Error(`cannot read ${path}`); }
	return bytes;
}

export function loadImageFile(path: string): Pixels {
	const decoded = decodeImage(readFileBytes(path));
	if (!decoded.ok) { throw new Error(`cannot decode ${path}: ${decoded.error}`); }
	return decoded.value;
}
