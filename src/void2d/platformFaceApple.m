#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "platformFace.h"

typedef struct {
	CTFontRef unit;
	CTFontRef sized;
	float size;
	float unitsPerEm;
} PlatformFace;

// A system collection the OS reserves for itself opens by URL and not from data, and a URL lists
// each variable face's named instances too, so the face is found by its PostScript name.
static CFArrayRef descriptorsOf(const char *path, const unsigned char *bytes, int length) {
	if (path) {
		CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path,
			(CFIndex)strlen(path), false);
		CFArrayRef found = url ? CTFontManagerCreateFontDescriptorsFromURL(url) : NULL;
		if (url) { CFRelease(url); }
		if (found && CFArrayGetCount(found) > 0) { return found; }
		if (found) { CFRelease(found); }
	}
	CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, bytes, length, kCFAllocatorNull);
	if (!data) { return NULL; }
	CFArrayRef found = CTFontManagerCreateFontDescriptorsFromData(data);
	CFRelease(data);
	return found;
}

void *void2dPlatformFaceOpen(const char *path, const unsigned char *bytes, int length,
                             const char *postScriptName, int glyphCount, int unitsPerEm) {
	CFArrayRef descriptors = descriptorsOf(path, bytes, length);
	if (!descriptors) { return NULL; }
	CFStringRef wanted = CFStringCreateWithCString(NULL, postScriptName, kCFStringEncodingASCII);
	CTFontRef font = NULL;
	for (CFIndex i = 0; wanted && !font && i < CFArrayGetCount(descriptors); i++) {
		CTFontDescriptorRef descriptor = CFArrayGetValueAtIndex(descriptors, i);
		CFStringRef name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
		if (name && CFStringCompare(name, wanted, 0) == kCFCompareEqualTo) {
			font = CTFontCreateWithFontDescriptor(descriptor, (CGFloat)unitsPerEm, NULL);
		}
		if (name) { CFRelease(name); }
	}
	if (wanted) { CFRelease(wanted); }
	CFRelease(descriptors);
	if (!font) { return NULL; }
	if (CTFontGetGlyphCount(font) != glyphCount || (int)CTFontGetUnitsPerEm(font) != unitsPerEm) {
		CFRelease(font);
		return NULL;
	}
	PlatformFace *face = (PlatformFace *)calloc(1, sizeof(PlatformFace));
	if (!face) {
		CFRelease(font);
		return NULL;
	}
	face->unit = font;
	face->unitsPerEm = (float)unitsPerEm;
	return face;
}

static CTFontRef sizedFont(PlatformFace *face, float sizePx) {
	if (face->sized && face->size == sizePx) { return face->sized; }
	if (face->sized) { CFRelease(face->sized); }
	face->sized = CTFontCreateCopyWithAttributes(face->unit, (CGFloat)sizePx, NULL, NULL);
	face->size = sizePx;
	return face->sized;
}

void void2dPlatformFaceUnitsBox(void *handle, int glyph, float *box) {
	PlatformFace *face = (PlatformFace *)handle;
	CGGlyph g = (CGGlyph)glyph;
	CGRect ink =
		CTFontGetBoundingRectsForGlyphs(face->unit, kCTFontOrientationHorizontal, &g, NULL, 1);
	box[0] = (float)CGRectGetMinX(ink);
	box[1] = (float)CGRectGetMinY(ink);
	box[2] = (float)CGRectGetMaxX(ink);
	box[3] = (float)CGRectGetMaxY(ink);
}

void void2dPlatformFaceBox(void *handle, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, int *box) {
	box[0] = box[1] = box[2] = box[3] = 0;
	PlatformFace *face = (PlatformFace *)handle;
	CTFontRef font = sizedFont(face, sizePx);
	if (!font) { return; }
	CGGlyph g = (CGGlyph)glyph;
	CGRect ink = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, &g, NULL, 1);
	if (CGRectIsEmpty(ink)) { return; }
	double half = (double)emboldenPx * 0.5;
	double x0 = CGRectGetMinX(ink) - half, x1 = CGRectGetMaxX(ink) + half;
	double y0 = CGRectGetMinY(ink) - half, y1 = CGRectGetMaxY(ink) + half;
	double slant0 = skew * (skew > 0.0f ? y0 : y1), slant1 = skew * (skew > 0.0f ? y1 : y0);
	box[0] = (int)floor(x0 + slant0 + shiftX);
	box[1] = (int)floor(-y1);
	box[2] = (int)ceil(x1 + slant1 + shiftX);
	box[3] = (int)ceil(-y0);
}

int void2dPlatformFaceFill(void *handle, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, unsigned char *at, int w, int h, int stride) {
	PlatformFace *face = (PlatformFace *)handle;
	CTFontRef font = sizedFont(face, sizePx);
	if (!font) { return 0; }
	int box[4];
	void2dPlatformFaceBox(handle, glyph, sizePx, shiftX, skew, emboldenPx, box);
	if (box[2] - box[0] != w || box[3] - box[1] != h) { return 0; }
	for (int row = 0; row < h; row++) { memset(at + (size_t)row * (size_t)stride, 0, (size_t)w); }
	CGContextRef context = CGBitmapContextCreate(at, (size_t)w, (size_t)h, 8, (size_t)stride, NULL,
		(CGBitmapInfo)kCGImageAlphaOnly);
	if (!context) { return 0; }
	// Void applies its own gamma to linear coverage in the shader, so the OS must not thicken
	// or quantize; subpixel positioning stays on so shiftX lands where the box put it.
	CGContextSetAllowsAntialiasing(context, true);
	CGContextSetShouldAntialias(context, true);
	CGContextSetAllowsFontSmoothing(context, false);
	CGContextSetShouldSmoothFonts(context, false);
	CGContextSetAllowsFontSubpixelPositioning(context, true);
	CGContextSetShouldSubpixelPositionFonts(context, true);
	CGContextSetAllowsFontSubpixelQuantization(context, false);
	CGContextSetShouldSubpixelQuantizeFonts(context, false);
	CGContextSetGrayFillColor(context, 1.0, 1.0);
	CGContextSetGrayStrokeColor(context, 1.0, 1.0);
	if (emboldenPx > 0.0f) {
		CGContextSetTextDrawingMode(context, kCGTextFillStroke);
		CGContextSetLineWidth(context, emboldenPx);
	}
	CGContextSetTextMatrix(context, CGAffineTransformMake(1.0, 0.0, skew, 1.0, 0.0, 0.0));
	CGGlyph g = (CGGlyph)glyph;
	CGPoint pen = CGPointMake(shiftX - box[0], h + box[1]);
	CTFontDrawGlyphs(font, &g, &pen, 1, context);
	CGContextRelease(context);
	return 1;
}
