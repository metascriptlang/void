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

// Ghostty's coretext.zig:356-512 (b58ef1d67): one CTLine at forced embedding level 0 over the
// UTF-16 string, each CTRun's glyph, advance, position and string index read back.
enum { SHAPE_OVERFLOW = -1, SHAPE_SUBSTITUTED = -2, SHAPE_FAILED = -3 };

static int sameFont(CTFontRef a, CTFontRef b) {
	CFStringRef nameA = CTFontCopyPostScriptName(a);
	CFStringRef nameB = CTFontCopyPostScriptName(b);
	int same = nameA && nameB && CFStringCompare(nameA, nameB, 0) == kCFCompareEqualTo;
	if (nameA) { CFRelease(nameA); }
	if (nameB) { CFRelease(nameB); }
	return same;
}

int void2dPlatformShape(void *handle, const int *codepoints, int count, int capacity, int *glyphs,
                        int *advances, int *offsetsX, int *offsetsY, int *indices) {
	PlatformFace *face = (PlatformFace *)handle;
	UniChar *units = (UniChar *)malloc(sizeof(UniChar) * 2 * (size_t)count);
	int *source = (int *)malloc(sizeof(int) * 2 * (size_t)count);
	if (!units || !source) {
		free(units);
		free(source);
		return SHAPE_FAILED;
	}
	CFIndex length = 0;
	for (int i = 0; i < count; i++) {
		UInt32 cp = (UInt32)codepoints[i];
		if (cp >= 0x10000) {
			cp -= 0x10000;
			units[length] = (UniChar)(0xD800 + (cp >> 10));
			source[length++] = i;
			units[length] = (UniChar)(0xDC00 + (cp & 0x3FF));
			source[length++] = i;
		} else {
			units[length] = (UniChar)cp;
			source[length++] = i;
		}
	}
	int result = SHAPE_FAILED;
	int level = 0;
	CFNumberRef embedding = CFNumberCreate(NULL, kCFNumberIntType, &level);
	CFStringRef string = CFStringCreateWithCharacters(NULL, units, length);
	const void *attributeKeys[] = { kCTFontAttributeName };
	const void *attributeValues[] = { face->unit };
	CFDictionaryRef attributes = CFDictionaryCreate(NULL, attributeKeys, attributeValues, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	const void *optionKeys[] = { kCTTypesetterOptionForcedEmbeddingLevel };
	const void *optionValues[] = { embedding };
	CFDictionaryRef options = CFDictionaryCreate(NULL, optionKeys, optionValues, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef attributed =
		string && attributes ? CFAttributedStringCreate(NULL, string, attributes) : NULL;
	CTTypesetterRef typesetter =
		attributed ? CTTypesetterCreateWithAttributedStringAndOptions(attributed, options) : NULL;
	CTLineRef line = typesetter ? CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0)) : NULL;
	if (line) {
		int total = 0;
		double pen = 0.0;
		result = 0;
		CFArrayRef runs = CTLineGetGlyphRuns(line);
		for (CFIndex r = 0; result >= 0 && r < CFArrayGetCount(runs); r++) {
			CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
			CFIndex n = CTRunGetGlyphCount(run);
			CFDictionaryRef used = CTRunGetAttributes(run);
			CTFontRef usedFont = (CTFontRef)CFDictionaryGetValue(used, kCTFontAttributeName);
			if (!usedFont || !sameFont(usedFont, face->unit)) {
				result = SHAPE_SUBSTITUTED;
				break;
			}
			if (total + n > capacity) {
				result = SHAPE_OVERFLOW;
				break;
			}
			CGGlyph *g = (CGGlyph *)malloc(sizeof(CGGlyph) * (size_t)n);
			CGSize *a = (CGSize *)malloc(sizeof(CGSize) * (size_t)n);
			CGPoint *p = (CGPoint *)malloc(sizeof(CGPoint) * (size_t)n);
			CFIndex *s = (CFIndex *)malloc(sizeof(CFIndex) * (size_t)n);
			if (g && a && p && s) {
				CTRunGetGlyphs(run, CFRangeMake(0, 0), g);
				CTRunGetAdvances(run, CFRangeMake(0, 0), a);
				CTRunGetPositions(run, CFRangeMake(0, 0), p);
				CTRunGetStringIndices(run, CFRangeMake(0, 0), s);
				for (CFIndex k = 0; k < n; k++) {
					glyphs[total] = (int)g[k];
					advances[total] = (int)lround(a[k].width);
					offsetsX[total] = (int)lround(p[k].x - pen);
					offsetsY[total] = (int)lround(p[k].y);
					indices[total] = source[s[k]];
					pen += a[k].width;
					total++;
				}
				result = total;
			} else {
				result = SHAPE_FAILED;
			}
			free(g);
			free(a);
			free(p);
			free(s);
		}
	}
	if (line) { CFRelease(line); }
	if (typesetter) { CFRelease(typesetter); }
	if (attributed) { CFRelease(attributed); }
	if (options) { CFRelease(options); }
	if (attributes) { CFRelease(attributes); }
	if (string) { CFRelease(string); }
	if (embedding) { CFRelease(embedding); }
	free(units);
	free(source);
	return result;
}
