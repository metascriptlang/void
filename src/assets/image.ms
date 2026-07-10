// Void Asset — Image loading (PNG, JPEG via stb_image)
// C/POSIX backend — sync file I/O via stb_image.

import {
	void_load_image, void_image_width, void_image_height, void_free_image
} from "./image.h";

export async function loadImage(path: string, channels: int32): Promise<Ptr<void>> {
	return void_load_image(path, channels);
}

export function loadImageSync(path: string, channels: int32): Ptr<void> {
	return void_load_image(path, channels);
}

export function imageWidth(): int32 {
	return void_image_width();
}

export function imageHeight(): int32 {
	return void_image_height();
}

export function freeImage(data: Ptr<void>): void {
	void_free_image(data);
}
