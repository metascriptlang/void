import { decodeJpeg } from "../assets/jpeg";
import { decodeGif, gifScan, GifScanError } from "../assets/gif";
import { decodeImage, decodeAnimation } from "../assets/image";
import { ImageError, isGif } from "../assets/imageTypes";
import {
	DecodeOutcome, digestStart, hashBytes, hashInts, hashWords, hex64, hexBytes, mixOutcome, mixWide,
} from "./imageDigest";
import { imageCases } from "./imageCases";

const MAX_SIDE: int32 = 4096;

// An enum prints as its name on native and as its number on JS, so the digest names it.
function errName(e: ImageError): string {
	return match (e) {
		ImageError.NotPngOrJpeg => "NotPngOrJpeg",
		ImageError.Undecodable => "Undecodable",
		ImageError.TooLarge => "TooLarge",
		ImageError.NotGif => "NotGif",
		ImageError.UnsupportedDisposal => "UnsupportedDisposal",
	};
}

function jpegOutcome(bytes: uint8[], req: int32): DecodeOutcome {
	const o = new DecodeOutcome();
	const r = decodeJpeg(bytes, req, MAX_SIDE);
	if (!r.ok) {
		o.text = r.error;
		return o;
	}
	o.ok = true;
	o.width = r.value.width;
	o.height = r.value.height;
	o.channels = r.value.channels;
	o.pixels = hashBytes(r.value.pixels);
	return o;
}

function imageOutcome(bytes: uint8[]): DecodeOutcome {
	const o = new DecodeOutcome();
	const r = decodeImage(bytes);
	if (!r.ok) {
		o.text = errName(r.error);
		return o;
	}
	o.ok = true;
	o.width = r.value.width;
	o.height = r.value.height;
	o.pixels = hashWords(r.value.pixels);
	return o;
}

function gifOutcome(bytes: uint8[]): DecodeOutcome {
	const o = new DecodeOutcome();
	const r = decodeGif(bytes, MAX_SIDE);
	if (!r.ok) {
		o.text = r.error;
		return o;
	}
	o.ok = true;
	o.width = r.value.width;
	o.height = r.value.height;
	o.frames = r.value.frameCount;
	o.pixels = hashWords(r.value.pixels);
	o.delays = hashInts(r.value.delays);
	return o;
}

function animationOutcome(bytes: uint8[]): DecodeOutcome {
	const o = new DecodeOutcome();
	const r = decodeAnimation(bytes);
	if (!r.ok) {
		o.text = errName(r.error);
		return o;
	}
	o.ok = true;
	o.width = r.value.width;
	o.height = r.value.height;
	o.frames = r.value.frameCount;
	o.pixels = hashWords(r.value.pixels);
	o.delays = hashInts(r.value.delays);
	return o;
}

// void_gif_scan's answer: -1 undecodable, -2 disposal 3, else canvas and frame count packed.
function scanCode(bytes: uint8[]): int64 {
	const r = gifScan(bytes);
	if (!r.ok) { return r.error == GifScanError.Disposal3 ? (-2 as int64) : (-1 as int64); }
	return ((r.value.width as int64) << (44 as int64)) | ((r.value.height as int64) << (28 as int64))
		| (r.value.frameCount as int64);
}

// A GIF folds its scan, its frames (unless the scan refuses a disposal that stb_image reads
// before its buffer on) and its animation; a JPEG folds a decode at each requested channel
// count; both fold the decodeImage or decodeAnimation answer.
function digestOf(bytes: uint8[], withText: boolean): string {
	let h = digestStart();
	if (isGif(bytes)) {
		const scan = scanCode(bytes);
		h = mixWide(h, scan as uint64);
		if (scan != (-2 as int64)) { h = mixOutcome(h, gifOutcome(bytes), withText); }
		h = mixOutcome(h, animationOutcome(bytes), true);
		return hex64(h);
	}
	if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
		for (let req: int32 = 0; req <= 4; req++) { h = mixOutcome(h, jpegOutcome(bytes, req), withText); }
	}
	h = mixOutcome(h, imageOutcome(bytes), true);
	return hex64(h);
}

// Each case is "name digest hex". The digest was recorded from the stb_image C decoders
// (image.c's JPEG, GIF and PNG paths) before they were deleted; a name starting "nr_" is a
// refusal whose C failure text names the last format stb_image tried, so only its outcome
// is folded.
test "the JPEG and GIF decoders reproduce the digests recorded from stb_image" {
	let bad: int32 = 0;
	for (const row of imageCases) {
		const parts = row.split(" ");
		const got = digestOf(hexBytes(parts[2]), !parts[0].startsWith("nr_"));
		if (got != parts[1]) {
			bad++;
			console.log(`DIFFERS ${parts[0]}: ${got} vs ${parts[1]}`);
		}
	}
	assert imageCases.length == 304;
	assert bad == 0;
}
