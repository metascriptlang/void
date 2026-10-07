#include "svgMask.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NANOSVG_IMPLEMENTATION
#define NANOSVGRAST_IMPLEMENTATION
#include "../../deps/nanosvg/src/nanosvg.h"
#include "../../deps/nanosvg/src/nanosvgrast.h"

#define MAX_SOURCE_BYTES (16 * 1024 * 1024)
#define MAX_PARSED_SIDE 1000000.0f
#define REASON_BYTES 192
#define NAME_SHOWN 48
#define DOT_POINTS 13
#define TINY_PATH_OF_STROKE 0.05f
#define RASTER_TESSELLATION_TOLERANCE 0.05f

static char s_reason[REASON_BYTES];
static NSVGimage **s_images;
static int s_capacity;
static NSVGrasterizer *s_rasterizer;

static const char *const k_elements[] = {
	"svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs",
	"linearGradient", "radialGradient", "stop", "style", "title", "desc", "metadata",
};

static const char *const k_deniedProperties[] = {
	"clip-path", "clip", "mask", "filter", "marker", "marker-start", "marker-mid", "marker-end",
	"visibility", "vector-effect", "mix-blend-mode", "isolation", "shape-rendering",
	"transform-origin", "transform-box",
};

static const char *const k_caps[] = {"butt", "round", "square"};
static const char *const k_joins[] = {"miter", "round", "bevel"};
static const char *const k_fillRules[] = {"nonzero", "evenodd"};

static const char *const k_opacities[] = {
	"opacity", "fill-opacity", "stroke-opacity", "stop-opacity",
};

static int refuse(int code, const char *kind, const char *name, size_t length, const char *tail) {
	if (length > NAME_SHOWN) { length = NAME_SHOWN; }
	snprintf(s_reason, REASON_BYTES, "%s%.*s%s", kind, (int)length, name, tail);
	return code;
}

static int isSpace(char c) {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

static int sameName(const char *name, size_t length, const char *literal) {
	return strlen(literal) == length && memcmp(name, literal, length) == 0;
}

static int inList(const char *name, size_t length, const char *const *list, size_t count) {
	for (size_t i = 0; i < count; i++) {
		if (sameName(name, length, list[i])) { return 1; }
	}
	return 0;
}

#define LIST_COUNT(list) (sizeof(list) / sizeof((list)[0]))

static void trim(const char **text, size_t *length) {
	while (*length > 0 && isSpace((*text)[0])) { (*text)++; (*length)--; }
	while (*length > 0 && isSpace((*text)[*length - 1])) { (*length)--; }
}

static int startsWith(const char *text, size_t length, const char *prefix) {
	size_t n = strlen(prefix);
	return length >= n && memcmp(text, prefix, n) == 0;
}

static int colourRefused(const char *value, size_t length) {
	trim(&value, &length);
	if (sameName(value, length, "none") || sameName(value, length, "currentColor")) { return 0; }
	if (startsWith(value, length, "url(") || startsWith(value, length, "rgb(")) { return 0; }
	if (length > 0 && value[0] == '#') {
		if (length != 4 && length != 7) { return 1; }
		for (size_t i = 1; i < length; i++) {
			char c = value[i];
			int hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
			if (!hex) { return 1; }
		}
		return 0;
	}
	if (length == 0) { return 1; }
	for (size_t i = 0; i < length; i++) {
		char c = value[i];
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) { return 1; }
	}
	return sameName(value, length, "transparent") || startsWith(value, length, "context");
}

static int valueRefused(const char *value, size_t length, const char *const *allowed,
	size_t count) {
	trim(&value, &length);
	return !inList(value, length, allowed, count);
}

static int checkDeclarations(const char *text, size_t length);
static size_t findText(const char *text, size_t length, size_t from, const char *needle);
static int notSvg(const char *what);

static int checkProperty(const char *name, size_t nameLength, const char *value, size_t valueLength,
	int isStyleText) {
	const char *trimmed = value;
	size_t trimmedLength = valueLength;
	trim(&trimmed, &trimmedLength);
	if (inList(name, nameLength, k_deniedProperties, LIST_COUNT(k_deniedProperties))) {
		return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, "");
	}
	if (sameName(trimmed, trimmedLength, "inherit")) {
		return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " value inherit");
	}
	if (sameName(name, nameLength, "style") && !isStyleText) {
		return checkDeclarations(value, valueLength);
	}
	if (sameName(name, nameLength, "fill") || sameName(name, nameLength, "stroke")
		|| sameName(name, nameLength, "stop-color")) {
		if (colourRefused(value, valueLength)) {
			return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " colour value");
		}
	} else if (inList(name, nameLength, k_opacities, LIST_COUNT(k_opacities))) {
		if (memchr(value, '%', valueLength)) {
			return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " as a percentage");
		}
	} else if (sameName(name, nameLength, "stroke-linecap")) {
		if (valueRefused(value, valueLength, k_caps, LIST_COUNT(k_caps))) {
			return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " value");
		}
	} else if (sameName(name, nameLength, "stroke-linejoin")) {
		if (valueRefused(value, valueLength, k_joins, LIST_COUNT(k_joins))) {
			return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " value");
		}
	} else if (sameName(name, nameLength, "fill-rule")) {
		if (valueRefused(value, valueLength, k_fillRules, LIST_COUNT(k_fillRules))) {
			return refuse(VOID2D_SVG_REFUSED, "attribute ", name, nameLength, " value");
		}
	}
	return 0;
}

static int checkDeclarations(const char *text, size_t length) {
	size_t i = 0;
	while (i < length) {
		size_t end = i;
		while (end < length && text[end] != ';') { end++; }
		const char *colon = memchr(text + i, ':', end - i);
		if (colon) {
			const char *name = text + i;
			size_t nameLength = (size_t)(colon - name);
			const char *value = colon + 1;
			size_t valueLength = (size_t)(text + end - value);
			trim(&name, &nameLength);
			trim(&value, &valueLength);
			int code = checkProperty(name, nameLength, value, valueLength, 1);
			if (code) { return code; }
		}
		i = end + 1;
	}
	return 0;
}

static int isClassSelector(const char *text, size_t length) {
	if (length < 2 || text[0] != '.') { return 0; }
	for (size_t i = 1; i < length; i++) {
		char c = text[i];
		int ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
			|| c == '_' || c == '-';
		if (!ok) { return 0; }
	}
	return 1;
}

static int checkSelectors(const char *text, size_t length) {
	size_t i = 0;
	while (i <= length) {
		size_t end = i;
		while (end < length && text[end] != ',') { end++; }
		const char *part = text + i;
		size_t partLength = end - i;
		trim(&part, &partLength);
		if (!isClassSelector(part, partLength)) {
			return refuse(VOID2D_SVG_REFUSED, "css selector ", part, partLength, "");
		}
		i = end + 1;
	}
	return 0;
}

static int checkStyleElement(const char *text, size_t length) {
	size_t i = 0;
	while (i < length) {
		if (isSpace(text[i])) { i++; continue; }
		if (startsWith(text + i, length - i, "/*")) {
			size_t close = findText(text, length, i + 2, "*/");
			if (close == length) { return notSvg("an unterminated css comment"); }
			i = close + 2;
			continue;
		}
		if (startsWith(text + i, length - i, "<![CDATA[")) { i += 9; continue; }
		if (startsWith(text + i, length - i, "]]>")) { i += 3; continue; }
		if (text[i] == '@') {
			return refuse(VOID2D_SVG_REFUSED, "css at-rule ", text + i, length - i, "");
		}
		size_t open = i;
		while (open < length && text[open] != '{') { open++; }
		if (open == length) {
			return notSvg("a css rule without a block");
		}
		int code = checkSelectors(text + i, open - i);
		if (code) { return code; }
		size_t close = open + 1;
		while (close < length && text[close] != '}') { close++; }
		if (close == length) {
			return notSvg("a css block without its closing brace");
		}
		code = checkDeclarations(text + open + 1, close - open - 1);
		if (code) { return code; }
		i = close + 1;
	}
	return 0;
}

static size_t findText(const char *text, size_t length, size_t from, const char *needle) {
	size_t n = strlen(needle);
	for (size_t i = from; i + n <= length; i++) {
		if (memcmp(text + i, needle, n) == 0) { return i; }
	}
	return length;
}

static int notSvg(const char *what) {
	return refuse(VOID2D_SVG_NOT_SVG, what, "", 0, "");
}

static int scanTag(const char *s, size_t length, size_t *cursor, int *svgCount) {
	size_t i = *cursor + 1;
	size_t nameStart = i;
	while (i < length && !isSpace(s[i]) && s[i] != '/' && s[i] != '>') { i++; }
	const char *name = s + nameStart;
	size_t nameLength = i - nameStart;
	if (nameLength == 0) { return notSvg("a tag without a name"); }
	if (!inList(name, nameLength, k_elements, LIST_COUNT(k_elements))) {
		return refuse(VOID2D_SVG_REFUSED, "element <", name, nameLength, ">");
	}
	if (sameName(name, nameLength, "svg")) {
		(*svgCount)++;
		if (*svgCount > 1) {
			return refuse(VOID2D_SVG_REFUSED, "element <svg>", "", 0, " inside <svg>");
		}
	} else if (*svgCount == 0) {
		return refuse(VOID2D_SVG_NOT_SVG, "root element <", name, nameLength, "> is not <svg>");
	}
	int selfClosing = 0;
	for (;;) {
		while (i < length && isSpace(s[i])) { i++; }
		if (i >= length) { return notSvg("an unterminated tag"); }
		if (s[i] == '>') { i++; break; }
		if (s[i] == '/' && i + 1 < length && s[i + 1] == '>') { selfClosing = 1; i += 2; break; }
		size_t attrStart = i;
		while (i < length && !isSpace(s[i]) && s[i] != '=' && s[i] != '/' && s[i] != '>') { i++; }
		const char *attr = s + attrStart;
		size_t attrLength = i - attrStart;
		if (attrLength == 0) { return notSvg("a malformed attribute"); }
		while (i < length && isSpace(s[i])) { i++; }
		const char *value = "";
		size_t valueLength = 0;
		if (i < length && s[i] == '=') {
			i++;
			while (i < length && isSpace(s[i])) { i++; }
			if (i >= length || (s[i] != '"' && s[i] != '\'')) {
				return refuse(VOID2D_SVG_NOT_SVG, "attribute ", attr, attrLength,
					" without a quoted value");
			}
			char quote = s[i++];
			size_t valueStart = i;
			while (i < length && s[i] != quote) { i++; }
			if (i >= length) { return notSvg("an unterminated attribute value"); }
			value = s + valueStart;
			valueLength = i - valueStart;
			i++;
		}
		int code = checkProperty(attr, attrLength, value, valueLength, 0);
		if (code) { return code; }
	}
	if (sameName(name, nameLength, "style") && !selfClosing) {
		size_t close = findText(s, length, i, "</style");
		if (close == length) { return notSvg("a <style> element without its end tag"); }
		int code = checkStyleElement(s + i, close - i);
		if (code) { return code; }
		i = close;
	}
	*cursor = i;
	return 0;
}

static int scan(const char *s, size_t length) {
	size_t i = 0;
	int svgCount = 0;
	while (i < length) {
		if (s[i] != '<') { i++; continue; }
		size_t rest = length - i;
		if (startsWith(s + i, rest, "<!--")) {
			i = findText(s, length, i + 4, "-->");
			if (i == length) { return notSvg("an unterminated comment"); }
			i += 3;
		} else if (startsWith(s + i, rest, "<![CDATA[")) {
			i = findText(s, length, i + 9, "]]>");
			if (i == length) { return notSvg("an unterminated CDATA section"); }
			i += 3;
		} else if (startsWith(s + i, rest, "<?")) {
			i = findText(s, length, i + 2, "?>");
			if (i == length) { return notSvg("an unterminated processing instruction"); }
			i += 2;
		} else if (startsWith(s + i, rest, "<!")) {
			int depth = 0;
			i += 2;
			while (i < length && !(s[i] == '>' && depth == 0)) {
				if (s[i] == '[') { depth++; }
				if (s[i] == ']') { depth--; }
				i++;
			}
			if (i == length) { return notSvg("an unterminated declaration"); }
			i++;
		} else if (startsWith(s + i, rest, "</")) {
			i = findText(s, length, i + 2, ">");
			if (i == length) { return notSvg("an unterminated end tag"); }
			i++;
		} else {
			int code = scanTag(s, length, &i, &svgCount);
			if (code) { return code; }
		}
	}
	if (svgCount == 0) { return notSvg("no <svg> element"); }
	return 0;
}

static NSVGpath *dotPath(float x, float y, float radius, int round) {
	NSVGpath *path = (NSVGpath *)calloc(1, sizeof(NSVGpath));
	float *pts = (float *)malloc(DOT_POINTS * 2 * sizeof(float));
	if (!path || !pts) { free(path); free(pts); return NULL; }
	const float k = 0.5522847498f * radius;
	const float r = radius;
	if (round) {
		const float circle[DOT_POINTS * 2] = {
			x + r, y,
			x + r, y + k, x + k, y + r, x, y + r,
			x - k, y + r, x - r, y + k, x - r, y,
			x - r, y - k, x - k, y - r, x, y - r,
			x + k, y - r, x + r, y - k, x + r, y,
		};
		memcpy(pts, circle, sizeof(circle));
	} else {
		const float square[DOT_POINTS * 2] = {
			x - r, y - r,
			x - r, y - r, x + r, y - r, x + r, y - r,
			x + r, y - r, x + r, y + r, x + r, y + r,
			x + r, y + r, x - r, y + r, x - r, y + r,
			x - r, y + r, x - r, y - r, x - r, y - r,
		};
		memcpy(pts, square, sizeof(square));
	}
	path->pts = pts;
	path->npts = DOT_POINTS;
	path->closed = 1;
	path->bounds[0] = x - r;
	path->bounds[1] = y - r;
	path->bounds[2] = x + r;
	path->bounds[3] = y + r;
	return path;
}

static float extentOf(const NSVGpath *path) {
	float width = path->bounds[2] - path->bounds[0];
	float height = path->bounds[3] - path->bounds[1];
	return width > height ? width : height;
}

static int drawTinyPaths(NSVGimage *image) {
	for (NSVGshape *shape = image->shapes; shape; shape = shape->next) {
		int stroked = shape->stroke.type != NSVG_PAINT_NONE && shape->strokeWidth > 0.0f
			&& (shape->flags & NSVG_FLAGS_VISIBLE);
		if (!stroked) { continue; }
		NSVGpath **link = &shape->paths;
		while (*link) {
			NSVGpath *path = *link;
			float extent = extentOf(path);
			int tiny = extent <= shape->strokeWidth * TINY_PATH_OF_STROKE;
			int round = path->closed ? shape->strokeLineJoin == NSVG_JOIN_ROUND
				: shape->strokeLineCap == NSVG_CAP_ROUND;
			int square = !path->closed && shape->strokeLineCap == NSVG_CAP_SQUARE;
			int butt = !path->closed && shape->strokeLineCap == NSVG_CAP_BUTT;
			if (!tiny || butt) { link = &path->next; continue; }
			if (!round && !square) {
				return refuse(VOID2D_SVG_REFUSED,
					"a stroked path much smaller than its stroke width without round joins", "", 0,
					"");
			}
			if (shape->stroke.type != NSVG_PAINT_COLOR) {
				return refuse(VOID2D_SVG_REFUSED, "a tiny stroked path with a gradient stroke", "",
					0, "");
			}
			if (shape->strokeDashCount > 0) {
				return refuse(VOID2D_SVG_REFUSED, "a tiny stroked path with a dash array", "", 0,
					"");
			}
			NSVGshape *dot = (NSVGshape *)malloc(sizeof(NSVGshape));
			NSVGpath *cap = dotPath((path->bounds[0] + path->bounds[2]) * 0.5f,
				(path->bounds[1] + path->bounds[3]) * 0.5f, shape->strokeWidth * 0.5f, round);
			if (!dot || !cap) { free(dot); free(cap); return VOID2D_SVG_NO_MEMORY; }
			memcpy(dot, shape, sizeof(NSVGshape));
			dot->fill = shape->stroke;
			dot->stroke.type = NSVG_PAINT_NONE;
			dot->stroke.color = 0;
			dot->fillRule = NSVG_FILLRULE_NONZERO;
			dot->paths = cap;
			memcpy(dot->bounds, cap->bounds, sizeof(dot->bounds));
			dot->next = shape->next;
			shape->next = dot;
			*link = path->next;
			free(path->pts);
			free(path);
		}
	}
	return 0;
}

static int takeSlot(NSVGimage *image) {
	for (int i = 0; i < s_capacity; i++) {
		if (!s_images[i]) { s_images[i] = image; return i + 1; }
	}
	int grown = s_capacity ? s_capacity * 2 : 16;
	NSVGimage **images = (NSVGimage **)realloc(s_images, (size_t)grown * sizeof(NSVGimage *));
	if (!images) { return 0; }
	memset(images + s_capacity, 0, (size_t)(grown - s_capacity) * sizeof(NSVGimage *));
	s_images = images;
	int slot = s_capacity;
	s_capacity = grown;
	s_images[slot] = image;
	return slot + 1;
}

static NSVGimage *imageOf(int handle) {
	if (handle < 1 || handle > s_capacity) { return NULL; }
	return s_images[handle - 1];
}

const char *void2dSvgMaskReason(void) {
	return s_reason;
}

int void2dSvgMaskParse(const char *source) {
	s_reason[0] = 0;
	size_t length = strlen(source);
	if (length > MAX_SOURCE_BYTES) {
		snprintf(s_reason, REASON_BYTES, "source of %zu bytes, over the %d byte limit", length,
			MAX_SOURCE_BYTES);
		return VOID2D_SVG_TOO_LARGE;
	}
	int code = scan(source, length);
	if (code) { return code; }
	char *copy = (char *)malloc(length + 1);
	if (!copy) { return VOID2D_SVG_NO_MEMORY; }
	memcpy(copy, source, length + 1);
	NSVGimage *image = nsvgParse(copy, "px", 96.0f);
	free(copy);
	if (!image) { return notSvg("a document nanosvg could not parse"); }
	if (!(image->width > 0.0f && image->height > 0.0f && image->width < MAX_PARSED_SIDE
		&& image->height < MAX_PARSED_SIDE)) {
		snprintf(s_reason, REASON_BYTES, "size %gx%g", (double)image->width, (double)image->height);
		nsvgDelete(image);
		return VOID2D_SVG_NO_SIZE;
	}
	code = drawTinyPaths(image);
	if (code) { nsvgDelete(image); return code; }
	int handle = takeSlot(image);
	if (!handle) { nsvgDelete(image); return VOID2D_SVG_NO_MEMORY; }
	return handle;
}

float void2dSvgMaskWidth(int handle) {
	NSVGimage *image = imageOf(handle);
	return image ? image->width : 0.0f;
}

float void2dSvgMaskHeight(int handle) {
	NSVGimage *image = imageOf(handle);
	return image ? image->height : 0.0f;
}

int void2dSvgMaskFree(int handle) {
	NSVGimage *image = imageOf(handle);
	if (!image) { return VOID2D_SVG_BAD_HANDLE; }
	nsvgDelete(image);
	s_images[handle - 1] = NULL;
	return 0;
}

int void2dSvgMaskLive(void) {
	int live = 0;
	for (int i = 0; i < s_capacity; i++) {
		if (s_images[i]) { live++; }
	}
	return live;
}

int void2dSvgMaskRasterize(int handle, int width, int height, uint8_t *alpha, int64_t count) {
	NSVGimage *image = imageOf(handle);
	if (!image) { return VOID2D_SVG_BAD_HANDLE; }
	if (width < 1 || height < 1 || count != (int64_t)width * height) {
		snprintf(s_reason, REASON_BYTES, "mask buffer of %lld bytes for %dx%d", (long long)count,
			width, height);
		return VOID2D_SVG_BAD_SIZE;
	}
	if (!s_rasterizer) {
		s_rasterizer = nsvgCreateRasterizer();
		if (s_rasterizer) { s_rasterizer->tessTol = RASTER_TESSELLATION_TOLERANCE; }
	}
	if (!s_rasterizer) { return VOID2D_SVG_NO_MEMORY; }
	uint8_t *rgba = (uint8_t *)malloc((size_t)width * height * 4);
	if (!rgba) { return VOID2D_SVG_NO_MEMORY; }
	float scaleX = (float)width / image->width;
	float scaleY = (float)height / image->height;
	float scale = scaleX < scaleY ? scaleX : scaleY;
	float offsetX = ((float)width - image->width * scale) * 0.5f;
	float offsetY = ((float)height - image->height * scale) * 0.5f;
	nsvgRasterize(s_rasterizer, image, offsetX, offsetY, scale, rgba, width, height, width * 4);
	for (int64_t i = 0; i < count; i++) { alpha[i] = rgba[i * 4 + 3]; }
	free(rgba);
	return 0;
}
