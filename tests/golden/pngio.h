// PNG reading and image diffing for the golden comparator (tests/golden/compare.ms).
//
// Separate from tests/capture/capture.c on purpose: that file is linked into the golden
// runner, which needs a GPU and a window, and this one is linked into the comparator, which
// needs neither. It also keeps STB_IMAGE_IMPLEMENTATION in exactly one binary — the runner
// already gets it from src/assets/image.c, and a second definition would be a duplicate
// symbol at link.
#ifndef VOID_PNGIO_H
#define VOID_PNGIO_H

#define VOID_PNG_SLOTS 2

// Load an 8-bit RGBA PNG into `slot`. 1 on success, 0 if the file is missing or unreadable.
int voidPngLoad(int slot, const char *path);

int voidPngWidth(int slot);
int voidPngHeight(int slot);

// One channel (0=R 1=G 2=B 3=A) of one pixel. Out of range reads give -1.
int voidPngPixel(int slot, int x, int y, int channel);

// Compare the two loaded slots and keep the summary for the accessors below.
// Returns the number of differing pixels, or -1 when the two sizes differ.
int voidPngDiff(void);

int voidPngDiffMaxDelta(void);
// Pixels of the last diff whose largest channel delta is 2 or more: the cross-backend bound
// ignores a delta of 1 (docs/TESTING.md "Guardrail 9").
int voidPngDiffOverOne(void);
int voidPngDiffMinX(void);
int voidPngDiffMinY(void);
int voidPngDiffMaxX(void);
int voidPngDiffMaxY(void);

// White where the last voidPngDiff() found a difference, black elsewhere — the review
// artifact a regenerated golden is supposed to come with. 1 on success.
int voidPngWriteDiffMask(const char *path);

#endif
