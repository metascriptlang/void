import { fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, vec3 } from "../../src/math/math3d";
import { LowResView } from "../../src/void3d/blit";
import { CameraView, CameraError } from "../../src/void3d/camera";
import { WorldLabel } from "../../src/void3d/worldLabel";
import {
	CardTableError,
	SWAP_LOW,
	HIGHLIGHTED,
	LABEL_POSITION,
	LABEL_PIXELS_PER_UNIT,
	TORCH_X,
	TORCH_Z,
	FLAME_BASE,
	setupCardTable,
	frameCardTable,
	tableView,
	handNode,
	discardCardNode,
	ownLabel,
	cardPoint,
	shadowOf,
} from "../../src/examples/cardTableScene";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// What the sample draws is checked at three frames, every fact a relation between two places in
// one image, so no number is a golden: frame 8 is before the first render-order swap, frame 16
// is inside it, and frame 21 is where the dissolve has reached its hold.
const WIDTH: int32 = 640;
const HEIGHT: int32 = 480;
const BEFORE_SWAP: int32 = 8;
const AFTER_SWAP: int32 = 16;
const LAST: int32 = 21;
const SCREEN: LowResView = { width: 640, height: 480, scale: 1, offsetX: 0.0, offsetY: 0.0 };
// The strip where cards SWAP_LOW and SWAP_HIGH overlap, seen in each card's own unit coordinates,
// below the letter.
const STRIP_LOW_ACROSS: float32 = 0.33;
const STRIP_UP: float32 = -0.2;
// A point above a card's upper edge, inside the highlight's margin.
const MARGIN_UP: float32 = 0.62;
const BRIGHT: int32 = 200;
const MIN_LABEL_PIXELS: int32 = 30;
const MIN_FLAME_PIXELS: int32 = 6;
const SHADOW_RATIO_PERCENT: int32 = 75;
const OVERLAY_RED_GAIN: int32 = 60;
let control: boolean = voidCaptureEnvInt("VOID_CARD_TABLE_CONTROL", 0) != 0;
let frames: int32 = 0;
let failures: int32 = 0;

struct Pixel {
	red: int32;
	green: int32;
	blue: int32;
}

function fail(message: string): void {
	console.log(`FAIL card table: frame ${frames}: ${message}`);
	failures = failures + 1;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	setupCardTable(control);
}

function viewOf(): CameraView {
	const view: Result<CameraView, CameraError> = tableView(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	fail(`the camera was refused: ${view.error.toString()}`);
	unreachable;
}

function channel(pixel: int64, shift: int64): int32 {
	return ((pixel >> shift) & 255) as int32;
}

function pixelOf(x: int32, y: int32): Pixel {
	const pixel: int64 = voidCapturePixel(0, x, y);
	return { red: channel(pixel, 24), green: channel(pixel, 16), blue: channel(pixel, 8) };
}

// The mean of the square of pixels `radius` around a world point, so the board's grain and the
// stitch lines do not decide a fact.
function meanAt(view: CameraView, point: Vec3, radius: int32): Pixel {
	const at: Vec3 = view.project(point, SCREEN, true);
	let red: int32 = 0;
	let green: int32 = 0;
	let blue: int32 = 0;
	let count: int32 = 0;
	for (let y = (at.y as int32) - radius; y <= (at.y as int32) + radius; y++) {
		for (let x = (at.x as int32) - radius; x <= (at.x as int32) + radius; x++) {
			const pixel: Pixel = pixelOf(x, y);
			red = red + pixel.red;
			green = green + pixel.green;
			blue = blue + pixel.blue;
			count = count + 1;
		}
	}
	return { red: red / count, green: green / count, blue: blue / count };
}

function text(pixel: Pixel): string {
	return `${pixel.red},${pixel.green},${pixel.blue}`;
}

function checkBoard(view: CameraView): void {
	const points: Vec<Vec3> = [vec3(1.3, 0.0, -1.0), vec3(-1.5, 0.0, -1.0), vec3(0.0, 0.0, -2.0)];
	for (let i = 0; i < 3; i++) {
		const seen: Pixel = meanAt(view, points[i], 3);
		if (seen.green < 60 || seen.green < seen.red + 30 || seen.green < seen.blue + 20) {
			fail(`the board is not visible at ${points[i].x},${points[i].z}: ${text(seen)}`);
		}
	}
}

// The sun's ray from a hand card's centre reaches the table in front of the card; the same
// distance to its left is open table.
function checkShadow(view: CameraView): void {
	const shaded: Vec3 = shadowOf(cardPoint(handNode(0), 0.0, 0.0));
	const lit: Vec3 = shaded + vec3(-1.0, 0.0, 0.0);
	const dark: Pixel = meanAt(view, shaded, 2);
	const open: Pixel = meanAt(view, lit, 2);
	console.log(`card table: shadow ${text(dark)}, open table ${text(open)}`);
	if (dark.green * 100 >= open.green * SHADOW_RATIO_PERCENT) {
		fail(`the shadow is not darker than the lit board: ${text(dark)} against ${text(open)}`);
	}
}

// Two overlapping cards, the lower order drawn first: blue is on top before the swap and red
// is on top inside it.
function checkOrder(view: CameraView, blueOnTop: boolean): void {
	const point: Vec3 = cardPoint(handNode(SWAP_LOW), STRIP_LOW_ACROSS, STRIP_UP);
	const seen: Pixel = meanAt(view, point, 2);
	console.log(`card table: overlap ${text(seen)}`);
	if (blueOnTop && seen.blue < seen.red + 60) {
		fail(`the card of the higher render order did not draw last: ${text(seen)}`);
	}
	if (!blueOnTop && seen.red < seen.blue + 60) {
		fail(`the swapped render orders did not put the first card on top: ${text(seen)}`);
	}
}

// A card's face is magenta, its dissolved side shows the board, and the band at the threshold
// takes the edge colour.
function checkDissolve(view: CameraView): void {
	const gone: Pixel = meanAt(view, cardPoint(discardCardNode(), -0.3, -0.15), 2);
	const edge: Pixel = meanAt(view, cardPoint(discardCardNode(), 0.06, -0.15), 1);
	const kept: Pixel = meanAt(view, cardPoint(discardCardNode(), 0.35, -0.15), 2);
	console.log(`card table: dissolved ${text(gone)}, edge ${text(edge)}, kept ${text(kept)}`);
	if (kept.red < kept.green + 60 || kept.blue < kept.green + 50) {
		fail(`the kept side did not draw the card: ${text(kept)}`);
	}
	if (gone.green < gone.red + 25 || gone.green < gone.blue) {
		fail(`the dissolved region does not show the board: ${text(gone)}`);
	}
	if (edge.red < BRIGHT || edge.red < edge.blue + 100 || edge.green < 60) {
		fail(`the dissolve's edge is not its edge colour: ${text(edge)}`);
	}
}

// Above the highlighted card, over the board, the second camera's yellow adds red; above a plain
// card it does not.
function checkOverlay(view: CameraView): void {
	const lit: Pixel = meanAt(view, cardPoint(handNode(HIGHLIGHTED), 0.0, MARGIN_UP), 2);
	const plain: Pixel = meanAt(view, cardPoint(handNode(0), 0.0, MARGIN_UP), 2);
	console.log(`card table: highlight margin ${text(lit)}, plain margin ${text(plain)}`);
	if (lit.red < plain.red + OVERLAY_RED_GAIN) {
		fail(`the overlay is not composited over the board: ${text(lit)} against ${text(plain)}`);
	}
}

// Bright pixels inside the label's box on the screen.
function checkLabel(view: CameraView): void {
	const own: WorldLabel | null = ownLabel();
	if (own === null) {
		fail("the sample has no label");
		return;
	}
	const halfWidth: float32 = (own.target.width as float32) / LABEL_PIXELS_PER_UNIT * 0.5;
	const halfHeight: float32 = (own.target.height as float32) / LABEL_PIXELS_PER_UNIT * 0.5;
	let left: float32 = 100000.0;
	let right: float32 = -100000.0;
	let top: float32 = 100000.0;
	let bottom: float32 = -100000.0;
	for (let i = 0; i < 4; i++) {
		const sideways: float32 = i % 2 == 0 ? -halfWidth : halfWidth;
		const upward: float32 = i < 2 ? -halfHeight : halfHeight;
		const corner: Vec3 = LABEL_POSITION + view.basis.right.scaled(sideways) +
			view.basis.up.scaled(upward);
		const at: Vec3 = view.project(corner, SCREEN, true);
		left = Math.min(left, at.x);
		right = Math.max(right, at.x);
		top = Math.min(top, at.y);
		bottom = Math.max(bottom, at.y);
	}
	let bright: int32 = 0;
	for (let y = top as int32; y <= (bottom as int32); y++) {
		for (let x = left as int32; x <= (right as int32); x++) {
			const pixel: Pixel = pixelOf(x, y);
			if (pixel.red >= BRIGHT && pixel.green >= BRIGHT && pixel.blue >= BRIGHT) {
				bright = bright + 1;
			}
		}
	}
	console.log(`card table: ${bright} label pixels in ${left},${top} to ${right},${bottom}`);
	if (bright < MIN_LABEL_PIXELS) { fail(`only ${bright} label pixels`); }
}

// Flame-coloured pixels in a box above each torch's bowl, over the dark background.
function checkFlames(view: CameraView): void {
	for (let torch = 0; torch < 2; torch++) {
		const x: float32 = torch == 0 ? -TORCH_X : TORCH_X;
		let left: float32 = 100000.0;
		let right: float32 = -100000.0;
		let top: float32 = 100000.0;
		let bottom: float32 = -100000.0;
		for (let i = 0; i < 4; i++) {
			const sideways: float32 = i % 2 == 0 ? -0.3 : 0.3;
			const height: float32 = i < 2 ? 0.25 : 0.85;
			const corner: Vec3 = vec3(x + sideways, FLAME_BASE + height, TORCH_Z);
			const at: Vec3 = view.project(corner, SCREEN, true);
			left = Math.min(left, at.x);
			right = Math.max(right, at.x);
			top = Math.min(top, at.y);
			bottom = Math.max(bottom, at.y);
		}
		let flame: int32 = 0;
		for (let y = top as int32; y <= (bottom as int32); y++) {
			for (let px = left as int32; px <= (right as int32); px++) {
				const pixel: Pixel = pixelOf(px, y);
				if (pixel.red >= 170 && pixel.blue <= 130 && pixel.red >= pixel.blue + 80) {
					flame = flame + 1;
				}
			}
		}
		console.log(`card table: ${flame} flame pixels over torch ${torch}`);
		if (flame < MIN_FLAME_PIXELS) { fail(`no flames above torch ${torch}: ${flame} pixels`); }
	}
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) {
		fail("the framebuffer size changed");
		voidCaptureExit(1);
		return;
	}
	const drawn: Result<int32, CardTableError> = frameCardTable(frames, WIDTH, HEIGHT);
	if (!drawn.ok) {
		fail(`the frame was refused: ${drawn.error.toString()}`);
		voidCaptureExit(1);
		return;
	}
	if (frames == BEFORE_SWAP || frames == AFTER_SWAP || frames == LAST) {
		if (voidCaptureGrab(0) == 0) {
			fail("readback failed");
			voidCaptureExit(1);
			return;
		}
		const view: CameraView = viewOf();
		if (frames == BEFORE_SWAP) { checkOrder(view, true); }
		if (frames == AFTER_SWAP) { checkOrder(view, false); }
		if (frames == LAST) {
			checkBoard(view);
			checkShadow(view);
			checkDissolve(view);
			checkOverlay(view);
			checkLabel(view);
			checkFlames(view);
		}
	}
	frames = frames + 1;
	if (frames <= LAST) { return; }
	if (failures > 0) {
		console.log(`FAIL card table: ${failures} facts did not hold`);
		voidCaptureExit(1);
		return;
	}
	console.log("PASS card table: board, order swap, dissolve, shadow, overlay, label, flames");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
