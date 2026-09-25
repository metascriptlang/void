// The golden scene table as data: one row per capture, no renderer and no GPU.
//
// Kept apart from tests/golden/scenes.ms, which holds the builders, so the comparator —
// which needs neither a window nor a GPU — can read the table without linking sokol.
// tests/golden/scenes.ms holds one builder per row in this order, and the runner refuses
// to start if the two lengths disagree.
//
// `phase` is the phase whose renderer the row belongs to. Only what today's renderer can
// draw is listed; every other row of the table in docs/TESTING.md is an entry in
// tests/PENDING.md, "scene not renderable until <phase>", and the phase that lands the
// feature adds the row here and deletes the entry in the same commit.
//
// Sizes: the width of every scene is at least 256 device pixels because Windows refuses to
// make a window narrower than about 120 client pixels and silently widens it, which the
// runner's shape check catches as a size mismatch. The narrow scenes just get more
// background. Heights are free.

export interface SceneRow {
	name: string;
	phase: string;
	width: int32;
	height: int32;
	dpi: float32;
	steps: int32;
	demo: boolean;
}

// `prim/aaRotatedBox` as numbers, because it is the one golden a second tier reads back.
// tests/oracle/captureCheck.ms recomputes every pixel of it from GEOMETRY - the rotation and
// the two colours below and nothing else - and says whether the antialiasing in the capture
// is CORRECT, which no golden can: a golden reports that the AA has not changed since last
// week, and that is exactly the check a squared alpha survived a whole phase behind
// (docs/REVIEWS.md, P1).
//
// B6 as well: off the default axis on purpose. A mode whose only golden is axis-aligned at
// alpha 1 is how that squared alpha lived, so the box mode's own scene is rotated AND
// translucent, and either being wrong changes these pixels.
export const AA_BOX_SCENE: string = "prim/aaRotatedBox";
export const AA_BOX_W: float32 = 90.0;
export const AA_BOX_H: float32 = 58.0;
export const AA_BOX_X: float32 = 128.0;   // where the node's local (0,0) sits before rotation
export const AA_BOX_Y: float32 = 80.0;
export const AA_BOX_PIVOT_X: float32 = 45.0;
export const AA_BOX_PIVOT_Y: float32 = 29.0;
export const AA_BOX_ROTATION: float32 = 0.6458;   // 37 degrees
export const AA_BOX_ALPHA: float32 = 0.5;
export const AA_BOX_FILL_R: float32 = 0.92;
export const AA_BOX_FILL_G: float32 = 0.52;
export const AA_BOX_FILL_B: float32 = 0.20;
export const AA_BOX_BG_R: float32 = 0.08;
export const AA_BOX_BG_G: float32 = 0.09;
export const AA_BOX_BG_B: float32 = 0.12;

// text/filteredDpi125 draws one line twice at the same device phase, plain and inside a
// radius-0 blur, a whole number of device pixels apart, so the capture check can compare them.
export const FILTERED_TEXT_SCENE: string = "text/filteredDpi125";
export const FILTERED_TEXT_DPI: float32 = 1.25;
export const FILTERED_TEXT_X: float32 = 10.3;
export const FILTERED_TEXT_Y: float32 = 14.3;
export const FILTERED_TEXT_SHIFT: float32 = 48.0;
export const FILTERED_TEXT_W: float32 = 236.0;
export const FILTERED_TEXT_H: float32 = 22.0;

export function sceneRows(): SceneRow[] {
	return [
		{ name: "harness/solid", phase: "P0", width: 256, height: 128, dpi: 1.0, steps: 0, demo: false },
		{ name: "harness/mustFail", phase: "P0", width: 256, height: 128, dpi: 1.0, steps: 0, demo: false },

		{ name: "prim/roundedRect", phase: "P0", width: 256, height: 156, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/strokeRect", phase: "P0", width: 256, height: 156, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/ellipsePieRing", phase: "P0", width: 256, height: 176, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/polygonBezier", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/gradientLinear", phase: "P0", width: 256, height: 156, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/gradientRadial", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/gradientOklab", phase: "P2", width: 320, height: 220, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/gradientMultiStop", phase: "P2", width: 320, height: 220, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/ditherBand", phase: "P2", width: 320, height: 206, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/patterns", phase: "P2", width: 320, height: 216, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/textModes", phase: "P2", width: 320, height: 220, dpi: 1.0, steps: 0, demo: false },

		{ name: "prim/aaRotatedBox", phase: "P2", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/perCornerRadii", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/perSideBorders", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/dashedBorder", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/cardWithLabel", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/dropShadow", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/insetShadow", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },
		{ name: "prim/aaShadow", phase: "P2", width: 256, height: 200, dpi: 1.0, steps: 0, demo: false },
		{ name: "prim/cardOneInstance", phase: "P2", width: 320, height: 250, dpi: 1.25, steps: 0, demo: false },

		{ name: "xform/rotate", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "xform/scale", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "xform/pivot", phase: "P0", width: 256, height: 128, dpi: 1.0, steps: 0, demo: false },
		{ name: "xform/tilePivot", phase: "P2", width: 320, height: 180, dpi: 1.0, steps: 0, demo: false },
		{ name: "xform/nonUniform", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },

		{ name: "snap/hairlineDpi100", phase: "P0", width: 256, height: 100, dpi: 1.0, steps: 0, demo: false },
		{ name: "snap/hairlineDpi125", phase: "P0", width: 320, height: 125, dpi: 1.25, steps: 0, demo: false },
		{ name: "snap/hairlineDpi150", phase: "P0", width: 384, height: 150, dpi: 1.5, steps: 0, demo: false },
		{ name: "snap/fractionalSplit", phase: "P0", width: 256, height: 100, dpi: 1.0, steps: 0, demo: false },
		{ name: "snap/fractionalOrigin", phase: "P0", width: 256, height: 96, dpi: 1.0, steps: 0, demo: false },
		{ name: "snap/zeroBorder", phase: "P2", width: 320, height: 125, dpi: 1.25, steps: 0, demo: false },

		{ name: "clip/nestedMasks", phase: "P0", width: 256, height: 156, dpi: 1.0, steps: 0, demo: false },
		{ name: "clip/rotatedMask", phase: "P0", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "clip/scrolledList", phase: "P0", width: 256, height: 150, dpi: 1.0, steps: 0, demo: false },

		{ name: "text/code13Dpi100", phase: "P0", width: 256, height: 120, dpi: 1.0, steps: 0, demo: false },
		{ name: "text/code13Dpi125", phase: "P0", width: 320, height: 150, dpi: 1.25, steps: 0, demo: false },
		{ name: "text/code13Dpi150", phase: "P0", width: 384, height: 180, dpi: 1.5, steps: 0, demo: false },
		{ name: "text/wrapped", phase: "P0", width: 256, height: 120, dpi: 1.0, steps: 0, demo: false },
		{ name: "text/multilineAlign", phase: "P0", width: 384, height: 96, dpi: 1.0, steps: 0, demo: false },
		{ name: "text/cjkFallback", phase: "P3", width: 320, height: 120, dpi: 1.25, steps: 0, demo: false },
		{ name: "text/fontStyles", phase: "P3", width: 320, height: 150, dpi: 1.25, steps: 0, demo: false },
		{ name: "text/filteredDpi125", phase: "P4", width: 320, height: 150, dpi: 1.25, steps: 0, demo: false },

		{ name: "image/nearestLinear", phase: "P0", width: 256, height: 136, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/tileWrap", phase: "P1", width: 256, height: 136, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/sceneSmooth", phase: "P1", width: 256, height: 136, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/subFlip", phase: "P0", width: 256, height: 176, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/colorPipeline", phase: "P0", width: 256, height: 170, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/objectFit", phase: "P2", width: 320, height: 214, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/cornerRadii", phase: "P2", width: 320, height: 220, dpi: 1.25, steps: 0, demo: false },
		{ name: "image/grayscale", phase: "P2", width: 320, height: 188, dpi: 1.0, steps: 0, demo: false },
		{ name: "image/scaleGrid", phase: "P0", width: 256, height: 148, dpi: 1.0, steps: 0, demo: false },

		// Turned on at P1, once the per-target command lists were hoisted out of the swapchain
		// list: a filter no longer opens a pass during the walk, it brackets a region of the
		// display list that the replay runs as its own pass beforehand.
		{ name: "filter/blur", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "filter/glow", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "filter/dropShadow", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "filter/afterTintedSibling", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "filter/maskAtDpi150", phase: "P1", width: 256, height: 160, dpi: 1.5, steps: 0, demo: false },
		{ name: "filter/dropShadowAlpha", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },
		{ name: "filter/groupOpacity", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },

		// Turned on at P1: FONS_ATLAS_FULL grows the atlas and lets fontstash retry, so every
		// glyph is placed and the scene is the same every run. Before that it had no row,
		// because which glyphs survived varied between runs of the same binary - three
		// distinct outputs in ten runs, worst pair 28 740 of 80 000 pixels (35.9%) at max
		// delta 207. That was the defect, not a tolerance. P3 removed the class with fontstash.
		{ name: "regress/atlasFull", phase: "P1", width: 320, height: 250, dpi: 1.0, steps: 0, demo: false },
		{ name: "regress/nodeCap", phase: "P0", width: 528, height: 168, dpi: 1.0, steps: 0, demo: false },
		{ name: "regress/dpiTruncation", phase: "P0", width: 256, height: 170, dpi: 1.5, steps: 0, demo: false },
		{ name: "regress/samplerRepeat", phase: "P0", width: 256, height: 152, dpi: 1.0, steps: 0, demo: false },
		{ name: "regress/vertexCap", phase: "P0", width: 256, height: 168, dpi: 1.0, steps: 0, demo: false },
		// The siblings drawn before and after a filtered node used to disappear with it, because
		// the nested begin2d reset the list the frame was being recorded into. P1.
		{ name: "regress/filterNestedPass", phase: "P1", width: 256, height: 160, dpi: 1.0, steps: 0, demo: false },

		{ name: "demo/frame001", phase: "P0", width: 800, height: 600, dpi: 1.0, steps: 1, demo: true },
		{ name: "demo/frame030", phase: "P0", width: 800, height: 600, dpi: 1.0, steps: 30, demo: true },
		{ name: "demo/frame090", phase: "P0", width: 800, height: 600, dpi: 1.0, steps: 90, demo: true },
		{ name: "demo/frame200", phase: "P0", width: 800, height: 600, dpi: 1.0, steps: 200, demo: true },
	];
}

export function sceneCount(): int32 { return sceneRows().length as int32; }

// Deterministic renderer counters captured beside the pixel goldens, in sceneRows order.
// A pixel-identical change that multiplies draw calls or leaks a pooled target is still a
// regression. The runner refuses to start unless both vectors cover every row.
export function sceneDrawCounts(): int32[] {
	return [
		1, 1, 1, 1, 1, 1, 3, 2, 2, 2, 1, 2, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2,
		1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 2, 2, 2, 1, 6, 2, 1,
		1, 1, 6, 6, 6, 6, 4, 4, 3, 1, 1, 1, 1, 1, 7, 30, 30,
		30, 30,
	];
}

export function sceneRenderTargetCounts(): int32[] {
	return [
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 5, 5, 5, 5, 4, 4, 1, 0, 0, 0, 0, 0, 5, 5, 5,
		5, 5,
	];
}

// The one row whose golden is deliberately wrong, so that a comparator which cannot fail is
// itself a failure (docs/TESTING.md, "A scene that must fail").
export const MUST_FAIL_SCENE: string = "harness/mustFail";

// The row whose expected pixels are arithmetic rather than a capture. Its clear colour and
// its rect are exact 8-bit values, so a UNORM swapchain returns them unchanged and the
// comparator can predict every byte — which is what checks the hand-written BGRA -> RGBA
// swizzle in tests/capture/capture.c.
export const HAND_COMPUTED_SCENE: string = "harness/solid";
export const HARNESS_CLEAR_R: int32 = 0;
export const HARNESS_CLEAR_G: int32 = 128;
export const HARNESS_CLEAR_B: int32 = 255;
export const HARNESS_FILL_R: int32 = 255;
export const HARNESS_FILL_G: int32 = 64;
export const HARNESS_FILL_B: int32 = 0;
export const HARNESS_RECT_X: int32 = 10;
export const HARNESS_RECT_Y: int32 = 20;
export const HARNESS_RECT_W: int32 = 30;
export const HARNESS_RECT_H: int32 = 24;

export function backendDirectory(backend: int32): string {
	if (backend == 1) { return "d3d11"; }
	if (backend == 2) { return "gles3"; }
	if (backend == 3) { return "webgl2"; }
	return "none";
}
