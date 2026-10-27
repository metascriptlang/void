#include <emscripten.h>
#include <math.h>
#include <stdlib.h>

#include "platformFace.h"

#define BROWSER_PROBE_PX 32

typedef struct {
	int id;
} BrowserFace;

EM_JS_DEPS(voidBrowserFace, "$UTF8ToString");

EM_JS(int, voidJsBrowserFaceOpen, (const char *style, const char *family), {
	const canvas = typeof OffscreenCanvas !== 'undefined'
		? new OffscreenCanvas(1, 1) : document.createElement('canvas');
	const context = canvas.getContext('2d', { willReadFrequently: true });
	if (!context) return -1;
	const faces = Module.voidBrowserFaces || (Module.voidBrowserFaces = []);
	faces.push({
		style: UTF8ToString(Number(style)), family: UTF8ToString(Number(family)),
		canvas: canvas, context: context, glyphs: new Map(),
	});
	return faces.length - 1;
});

EM_JS(int, voidJsBrowserFaceGlyph, (int id, int codepoint, int probePx), {
	const face = Module.voidBrowserFaces[id];
	const known = face.glyphs.get(codepoint);
	if (known !== undefined) return known;
	const noCharacter = codepoint <= 0 || codepoint > 0x10FFFF ||
		(codepoint >= 0xD800 && codepoint <= 0xDFFF);
	let glyph = 0;
	if (!noCharacter) {
		const side = 2 * probePx;
		face.canvas.width = side;
		face.canvas.height = side;
		const c = face.context;
		c.font = face.style + ' ' + probePx + 'px ' + face.family;
		c.fillStyle = 'black';
		c.fillText(String.fromCodePoint(codepoint), probePx / 2, probePx * 1.5);
		const data = c.getImageData(0, 0, side, side).data;
		let drawsInColour = false;
		for (let i = 0; i < data.length && !drawsInColour; i += 4) {
			drawsInColour = (data[i] | data[i + 1] | data[i + 2]) !== 0;
		}
		glyph = drawsInColour ? 0 : codepoint;
	}
	face.glyphs.set(codepoint, glyph);
	return glyph;
});

EM_JS(void, voidJsBrowserFaceMeasure, (int id, int glyph, double px, float *out), {
	const face = Module.voidBrowserFaces[id];
	const c = face.context;
	c.font = face.style + ' ' + px + 'px ' + face.family;
	const m = c.measureText(glyph > 0 ? String.fromCodePoint(glyph) : 'Mgjy|');
	let left = m.actualBoundingBoxLeft, right = m.actualBoundingBoxRight;
	let ascent = m.actualBoundingBoxAscent, descent = m.actualBoundingBoxDescent;
	const lineAscent = m.fontBoundingBoxAscent > 0 ? m.fontBoundingBoxAscent : ascent;
	const lineDescent = m.fontBoundingBoxDescent > 0 ? m.fontBoundingBoxDescent : descent;
	const boxMissing = glyph > 0 && ascent + descent < 0.001 && m.width > 0;
	if (boxMissing) {
		left = 0;
		right = m.width;
		ascent = lineAscent;
		descent = lineDescent;
	}
	const at = Number(out) >> 2;
	HEAPF32[at] = left;
	HEAPF32[at + 1] = right;
	HEAPF32[at + 2] = ascent;
	HEAPF32[at + 3] = descent;
	HEAPF32[at + 4] = m.width;
	HEAPF32[at + 5] = lineAscent;
	HEAPF32[at + 6] = lineDescent;
});

EM_JS(void, voidJsBrowserFaceFill, (int id, int glyph, double px, double penX, double penY,
                                    double skew, double emboldenPx, unsigned char *at, int w,
                                    int h, int stride), {
	const face = Module.voidBrowserFaces[id];
	face.canvas.width = w;
	face.canvas.height = h;
	const c = face.context;
	c.font = face.style + ' ' + px + 'px ' + face.family;
	c.fillStyle = 'white';
	c.strokeStyle = 'white';
	c.setTransform(1, 0, -skew, 1, penX, penY);
	const text = String.fromCodePoint(glyph);
	c.fillText(text, 0, 0);
	if (emboldenPx > 0) {
		c.lineWidth = emboldenPx;
		c.strokeText(text, 0, 0);
	}
	const data = c.getImageData(0, 0, w, h).data;
	const base = Number(at);
	for (let y = 0; y < h; y++) {
		const row = base + y * stride;
		for (let x = 0; x < w; x++) { HEAPU8[row + x] = data[(y * w + x) * 4 + 3]; }
	}
});

typedef struct {
	float left, right, ascent, descent, advance, lineAscent, lineDescent;
} BrowserMeasure;

static BrowserMeasure measure(void *handle, int glyph, float px) {
	float out[7];
	voidJsBrowserFaceMeasure(((BrowserFace *)handle)->id, glyph, (double)px, out);
	BrowserMeasure m = { out[0], out[1], out[2], out[3], out[4], out[5], out[6] };
	return m;
}

void *void2dPlatformFaceOpen(const char *path, const unsigned char *bytes, int length,
                             const char *postScriptName, int glyphCount, int unitsPerEm) {
	(void)path; (void)bytes; (void)length; (void)postScriptName; (void)glyphCount; (void)unitsPerEm;
	return NULL;
}

void *void2dPlatformFaceOpenBrowser(const char *style, const char *family) {
	int id = voidJsBrowserFaceOpen(style, family);
	if (id < 0) { return NULL; }
	BrowserFace *face = (BrowserFace *)malloc(sizeof(BrowserFace));
	if (!face) { return NULL; }
	face->id = id;
	return face;
}

int void2dPlatformFaceGlyph(void *handle, int codepoint) {
	return voidJsBrowserFaceGlyph(((BrowserFace *)handle)->id, codepoint, BROWSER_PROBE_PX);
}

void void2dPlatformFaceVMetrics(void *handle, int *ascent, int *descent, int *lineGap) {
	BrowserMeasure m = measure(handle, 0, (float)VOID2D_BROWSER_UNITS_PER_EM);
	*ascent = (int)lroundf(m.lineAscent);
	*descent = -(int)lroundf(m.lineDescent);
	*lineGap = 0;
}

int void2dPlatformFaceAdvance(void *handle, int glyph) {
	return (int)lroundf(measure(handle, glyph, (float)VOID2D_BROWSER_UNITS_PER_EM).advance);
}

void void2dPlatformFaceUnitsBox(void *handle, int glyph, float *box) {
	BrowserMeasure m = measure(handle, glyph, (float)VOID2D_BROWSER_UNITS_PER_EM);
	box[0] = -m.left;
	box[1] = -m.descent;
	box[2] = m.right;
	box[3] = m.ascent;
}

void void2dPlatformFaceBox(void *handle, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, int *box) {
	box[0] = box[1] = box[2] = box[3] = 0;
	BrowserMeasure m = measure(handle, glyph, sizePx);
	if (!(m.right + m.left > 0.0f) || !(m.ascent + m.descent > 0.0f)) { return; }
	double half = (double)emboldenPx * 0.5;
	double x0 = -m.left - half, x1 = m.right + half;
	double y0 = -m.descent - half, y1 = m.ascent + half;
	double slant0 = skew * (skew > 0.0f ? y0 : y1), slant1 = skew * (skew > 0.0f ? y1 : y0);
	box[0] = (int)floor(x0 + slant0 + shiftX);
	box[1] = (int)floor(-y1);
	box[2] = (int)ceil(x1 + slant1 + shiftX);
	box[3] = (int)ceil(-y0);
}

int void2dPlatformFaceFill(void *handle, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, unsigned char *at, int w, int h, int stride) {
	int box[4];
	void2dPlatformFaceBox(handle, glyph, sizePx, shiftX, skew, emboldenPx, box);
	if (box[2] - box[0] != w || box[3] - box[1] != h || w <= 0 || h <= 0) { return 0; }
	voidJsBrowserFaceFill(((BrowserFace *)handle)->id, glyph, (double)sizePx,
		(double)(shiftX - (float)box[0]), (double)-box[1], (double)skew, (double)emboldenPx,
		at, w, h, stride);
	return 1;
}
