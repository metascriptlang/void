#ifndef VOID_PLATFORM_WEB_IME_INPUT_H
#define VOID_PLATFORM_WEB_IME_INPUT_H

// The text-input decisions of the wasm window, in imeInput.ms through imeInputExports.cms.
void voidImeSetTextInput(int on);
void voidImeSetRect(int x, int y, int w, int h);
void voidImeMarkReady(void);
int voidImeReady(void);
// 1 or 0 when the hidden input should take or lose focus now, -1 when it has nothing to apply.
int voidImeFocus(void);
// x, y, w, h of the rectangle in CSS pixels.
void voidImeCssRect(double scale, double *out);
int voidImeTookKey(int composing, int type);
int voidImeKeepsFromBrowser(int type, int keyCode);

#endif
