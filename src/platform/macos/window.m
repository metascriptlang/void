#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "window.h"

#if !__has_feature(objc_arc)
#error "window.m is written for ARC"
#endif

#define KEY_TABLE_SIZE 128

static const int16_t keyTable[KEY_TABLE_SIZE] = {
	[0x1D] = VOID_KEY_0,
	[0x12] = VOID_KEY_1,
	[0x13] = VOID_KEY_2,
	[0x14] = VOID_KEY_3,
	[0x15] = VOID_KEY_4,
	[0x17] = VOID_KEY_5,
	[0x16] = VOID_KEY_6,
	[0x1A] = VOID_KEY_7,
	[0x1C] = VOID_KEY_8,
	[0x19] = VOID_KEY_9,
	[0x00] = VOID_KEY_A,
	[0x0B] = VOID_KEY_B,
	[0x08] = VOID_KEY_C,
	[0x02] = VOID_KEY_D,
	[0x0E] = VOID_KEY_E,
	[0x03] = VOID_KEY_F,
	[0x05] = VOID_KEY_G,
	[0x04] = VOID_KEY_H,
	[0x22] = VOID_KEY_I,
	[0x26] = VOID_KEY_J,
	[0x28] = VOID_KEY_K,
	[0x25] = VOID_KEY_L,
	[0x2E] = VOID_KEY_M,
	[0x2D] = VOID_KEY_N,
	[0x1F] = VOID_KEY_O,
	[0x23] = VOID_KEY_P,
	[0x0C] = VOID_KEY_Q,
	[0x0F] = VOID_KEY_R,
	[0x01] = VOID_KEY_S,
	[0x11] = VOID_KEY_T,
	[0x20] = VOID_KEY_U,
	[0x09] = VOID_KEY_V,
	[0x0D] = VOID_KEY_W,
	[0x07] = VOID_KEY_X,
	[0x10] = VOID_KEY_Y,
	[0x06] = VOID_KEY_Z,
	[0x27] = VOID_KEY_APOSTROPHE,
	[0x2A] = VOID_KEY_BACKSLASH,
	[0x2B] = VOID_KEY_COMMA,
	[0x18] = VOID_KEY_EQUAL,
	[0x32] = VOID_KEY_GRAVE_ACCENT,
	[0x21] = VOID_KEY_LEFT_BRACKET,
	[0x1B] = VOID_KEY_MINUS,
	[0x2F] = VOID_KEY_PERIOD,
	[0x1E] = VOID_KEY_RIGHT_BRACKET,
	[0x29] = VOID_KEY_SEMICOLON,
	[0x2C] = VOID_KEY_SLASH,
	[0x0A] = VOID_KEY_WORLD_1,
	[0x33] = VOID_KEY_BACKSPACE,
	[0x39] = VOID_KEY_CAPS_LOCK,
	[0x75] = VOID_KEY_DELETE,
	[0x7D] = VOID_KEY_DOWN,
	[0x77] = VOID_KEY_END,
	[0x24] = VOID_KEY_ENTER,
	[0x35] = VOID_KEY_ESCAPE,
	[0x7A] = VOID_KEY_F1,
	[0x78] = VOID_KEY_F2,
	[0x63] = VOID_KEY_F3,
	[0x76] = VOID_KEY_F4,
	[0x60] = VOID_KEY_F5,
	[0x61] = VOID_KEY_F6,
	[0x62] = VOID_KEY_F7,
	[0x64] = VOID_KEY_F8,
	[0x65] = VOID_KEY_F9,
	[0x6D] = VOID_KEY_F10,
	[0x67] = VOID_KEY_F11,
	[0x6F] = VOID_KEY_F12,
	[0x69] = VOID_KEY_F13,
	[0x6B] = VOID_KEY_F14,
	[0x71] = VOID_KEY_F15,
	[0x6A] = VOID_KEY_F16,
	[0x40] = VOID_KEY_F17,
	[0x4F] = VOID_KEY_F18,
	[0x50] = VOID_KEY_F19,
	[0x5A] = VOID_KEY_F20,
	[0x73] = VOID_KEY_HOME,
	[0x72] = VOID_KEY_INSERT,
	[0x7B] = VOID_KEY_LEFT,
	[0x3A] = VOID_KEY_LEFT_ALT,
	[0x3B] = VOID_KEY_LEFT_CONTROL,
	[0x38] = VOID_KEY_LEFT_SHIFT,
	[0x37] = VOID_KEY_LEFT_SUPER,
	[0x6E] = VOID_KEY_MENU,
	[0x47] = VOID_KEY_NUM_LOCK,
	[0x79] = VOID_KEY_PAGE_DOWN,
	[0x74] = VOID_KEY_PAGE_UP,
	[0x7C] = VOID_KEY_RIGHT,
	[0x3D] = VOID_KEY_RIGHT_ALT,
	[0x3E] = VOID_KEY_RIGHT_CONTROL,
	[0x3C] = VOID_KEY_RIGHT_SHIFT,
	[0x36] = VOID_KEY_RIGHT_SUPER,
	[0x31] = VOID_KEY_SPACE,
	[0x30] = VOID_KEY_TAB,
	[0x7E] = VOID_KEY_UP,
	[0x52] = VOID_KEY_KP_0,
	[0x53] = VOID_KEY_KP_1,
	[0x54] = VOID_KEY_KP_2,
	[0x55] = VOID_KEY_KP_3,
	[0x56] = VOID_KEY_KP_4,
	[0x57] = VOID_KEY_KP_5,
	[0x58] = VOID_KEY_KP_6,
	[0x59] = VOID_KEY_KP_7,
	[0x5B] = VOID_KEY_KP_8,
	[0x5C] = VOID_KEY_KP_9,
	[0x45] = VOID_KEY_KP_ADD,
	[0x41] = VOID_KEY_KP_DECIMAL,
	[0x4B] = VOID_KEY_KP_DIVIDE,
	[0x4C] = VOID_KEY_KP_ENTER,
	[0x51] = VOID_KEY_KP_EQUAL,
	[0x43] = VOID_KEY_KP_MULTIPLY,
	[0x4E] = VOID_KEY_KP_SUBTRACT,
};

static struct {
	VoidMacosDesc desc;
	bool textInput;
	uint8_t mouseButtons;
	uint32_t flagsChanged;
	NSRange markedSelection;
	NSRect imeRect;
} s;

VoidWindow voidWindow;

static NSWindow *s_window;
static NSView *s_view;
static NSTrackingArea *s_trackingArea;
static NSString *s_marked;
static NSCursor *s_cursors[VOID_CURSOR_COUNT];
static id s_appDelegate;
static id s_windowDelegate;
static id s_keyUpMonitor;
static CADisplayLink *s_displayLink;
static NSTimer *s_frameTimer;

__attribute__((noreturn)) static void fail(const char *what) {
	fprintf(stderr, "void: %s\n", what);
	abort();
}

static int roundAtLeastOne(CGFloat f) {
	int v = (int)lround(f);
	return v <= 0 ? 1 : v;
}

static uint32_t mods(NSEvent *ev) {
	const NSEventModifierFlags f = ev == nil ? NSEvent.modifierFlags : ev.modifierFlags;
	const NSUInteger b = NSEvent.pressedMouseButtons;
	uint32_t m = 0;
	if (f & NSEventModifierFlagShift) m |= VOID_MODIFIER_SHIFT;
	if (f & NSEventModifierFlagControl) m |= VOID_MODIFIER_CTRL;
	if (f & NSEventModifierFlagOption) m |= VOID_MODIFIER_ALT;
	if (f & NSEventModifierFlagCommand) m |= VOID_MODIFIER_SUPER;
	if (b & (1 << 0)) m |= VOID_MODIFIER_LMB;
	if (b & (1 << 1)) m |= VOID_MODIFIER_RMB;
	if (b & (1 << 2)) m |= VOID_MODIFIER_MMB;
	return m;
}

static void mouseEvent(VoidAppEventType type, VoidMouseButton button, uint32_t modifiers) {
	if (!voidWindowEventsEnabled()) return;
	voidWindowInitEvent(type);
	voidWindow.event.mouseButton = button;
	voidWindow.event.modifiers = modifiers;
	voidWindowCallEvent();
}

static void keyEvent(VoidAppEventType type, VoidKeyCode key, bool repeat, uint32_t modifiers) {
	if (!voidWindowEventsEnabled()) return;
	voidKeysHeldTrack(&voidWindow.keysHeld, type, key);
	voidWindowInitEvent(type);
	voidWindow.event.keyCode = key;
	voidWindow.event.keyRepeat = repeat;
	voidWindow.event.modifiers = modifiers;
	voidWindowCallEvent();
}

static void releaseKey(VoidKeyCode key) { keyEvent(VOID_EVENT_KEY_UP, key, false, 0); }

static VoidKeyCode translateKey(int scanCode) {
	if (scanCode < 0 || scanCode >= KEY_TABLE_SIZE) return VOID_KEY_INVALID;
	return (VoidKeyCode)keyTable[scanCode];
}

static void initDefaultDimensions(void) {
	const NSRect screen = NSScreen.mainScreen.frame;
	if (voidWindow.windowWidth == 0) voidWindow.windowWidth = roundAtLeastOne(screen.size.width * 4.0 / 5.0);
	if (voidWindow.windowHeight == 0) voidWindow.windowHeight = roundAtLeastOne(screen.size.height * 4.0 / 5.0);
}

static void updateDimensions(void) {
	voidWindow.dpiScale = s.desc.highDpi ? (float)s_window.screen.backingScaleFactor : 1.0f;
	s_view.layer.contentsScale = voidWindow.dpiScale;
	const NSRect bounds = s_view.bounds;
	voidWindow.windowWidth = roundAtLeastOne(bounds.size.width);
	voidWindow.windowHeight = roundAtLeastOne(bounds.size.height);
	const int fbWidth = roundAtLeastOne(bounds.size.width * voidWindow.dpiScale);
	const int fbHeight = roundAtLeastOne(bounds.size.height * voidWindow.dpiScale);
	const bool changed = fbWidth != voidWindow.framebufferWidth || fbHeight != voidWindow.framebufferHeight;
	voidWindow.framebufferWidth = fbWidth;
	voidWindow.framebufferHeight = fbHeight;
	if (changed) voidWindowAppEvent(VOID_EVENT_RESIZED);
}

static void mouseUpdateFromPoint(NSPoint p, bool clearDxDy) {
	if (voidWindow.mouse.locked) return;
	const float x = (float)p.x * voidWindow.dpiScale;
	const float y = (float)voidWindow.framebufferHeight - (float)p.y * voidWindow.dpiScale - 1.0f;
	if (clearDxDy) {
		voidWindow.mouse.dx = 0.0f;
		voidWindow.mouse.dy = 0.0f;
	} else if (voidWindow.mouse.posValid) {
		voidWindow.mouse.dx = x - voidWindow.mouse.x;
		voidWindow.mouse.dy = y - voidWindow.mouse.y;
	}
	voidWindow.mouse.x = x;
	voidWindow.mouse.y = y;
	voidWindow.mouse.posValid = true;
}

static void updateCursor(int cursor, bool shown) {
	if (shown != voidWindow.mouse.shown) {
		if (shown) [NSCursor unhide];
		else [NSCursor hide];
	}
	NSCursor *ns = s_cursors[cursor] != nil ? s_cursors[cursor] : [NSCursor arrowCursor];
	[ns set];
	voidWindow.mouse.cursor = cursor;
	voidWindow.mouse.shown = shown;
}

@interface NSCursor ()
+ (id)_windowResizeNorthWestSouthEastCursor;
+ (id)_windowResizeNorthEastSouthWestCursor;
+ (id)_windowResizeNorthSouthCursor;
+ (id)_windowResizeEastWestCursor;
@end

static void initCursors(void) {
	s_cursors[VOID_CURSOR_ARROW] = [NSCursor arrowCursor];
	s_cursors[VOID_CURSOR_IBEAM] = [NSCursor IBeamCursor];
	s_cursors[VOID_CURSOR_CROSSHAIR] = [NSCursor crosshairCursor];
	s_cursors[VOID_CURSOR_POINTING_HAND] = [NSCursor pointingHandCursor];
	s_cursors[VOID_CURSOR_RESIZE_EW] = [NSCursor respondsToSelector:@selector(_windowResizeEastWestCursor)] ? [NSCursor _windowResizeEastWestCursor] : [NSCursor resizeLeftRightCursor];
	s_cursors[VOID_CURSOR_RESIZE_NS] = [NSCursor respondsToSelector:@selector(_windowResizeNorthSouthCursor)] ? [NSCursor _windowResizeNorthSouthCursor] : [NSCursor resizeUpDownCursor];
	s_cursors[VOID_CURSOR_RESIZE_NWSE] = [NSCursor respondsToSelector:@selector(_windowResizeNorthWestSouthEastCursor)] ? [NSCursor _windowResizeNorthWestSouthEastCursor] : [NSCursor closedHandCursor];
	s_cursors[VOID_CURSOR_RESIZE_NESW] = [NSCursor respondsToSelector:@selector(_windowResizeNorthEastSouthWestCursor)] ? [NSCursor _windowResizeNorthEastSouthWestCursor] : [NSCursor closedHandCursor];
	s_cursors[VOID_CURSOR_RESIZE_ALL] = [NSCursor closedHandCursor];
	s_cursors[VOID_CURSOR_NOT_ALLOWED] = [NSCursor operationNotAllowedCursor];
}

static void textEvent(int type, NSString *text, NSUInteger cursor) {
	if (!voidWindow.initCalled) return;
	s.desc.text(type, text.UTF8String, (int)cursor);
}

static void clearMarked(void) {
	if (s_marked.length == 0) return;
	s_marked = @"";
	s.markedSelection = NSMakeRange(0, 0);
	textEvent(VOID_EVENT_PREEDIT, @"", 0);
}

static void frame(void) {
	voidFrameTimingUpdate(&voidWindow.timing, 0.0);
	@autoreleasepool {
		voidWindowFrame();
	}
	if (voidWindow.quitRequested || voidWindow.quitOrdered) [s_window performClose:nil];
}

static bool displayLinkActive(void) { return s_displayLink != nil && !s_displayLink.paused; }

static void startFrameTimer(void) {
	if (s_frameTimer != nil) return;
	s_frameTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *t) { (void)t; frame(); }];
	[[NSRunLoop currentRunLoop] addTimer:s_frameTimer forMode:NSRunLoopCommonModes];
}

static void stopFrameTimer(void) {
	[s_frameTimer invalidate];
	s_frameTimer = nil;
}

static void startDisplayLink(void) {
	if (s_displayLink != nil) {
		s_displayLink.paused = NO;
		return;
	}
	const float maxFps = (float)NSScreen.mainScreen.maximumFramesPerSecond;
	s_displayLink = [s_view displayLinkWithTarget:s_view selector:@selector(displayLinkFired:)];
	s_displayLink.preferredFrameRateRange = CAFrameRateRangeMake(maxFps, maxFps, maxFps);
	[s_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

static void startFrames(void) {
	if (@available(macOS 14.0, *)) startDisplayLink();
	else startFrameTimer();
}

static void transitionToOccluded(void) {
	if (!displayLinkActive()) return;
	s_displayLink.paused = YES;
	startFrameTimer();
}

static void transitionToVisible(void) {
	if (displayLinkActive() || s_displayLink == nil) return;
	stopFrameTimer();
	startDisplayLink();
}

@interface VoidMacosAppDelegate : NSObject <NSApplicationDelegate>
@end

@interface VoidMacosWindowDelegate : NSObject <NSWindowDelegate>
@end

@interface VoidMacosWindow : NSWindow
@end

@interface VoidMacosView : NSView <NSTextInputClient>
@end

@implementation VoidMacosAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	(void)notification;
	const char *quietValue = getenv("VOID_QUIET_WINDOW");
	const bool quiet = quietValue != NULL && strcmp(quietValue, "1") == 0;
	NSApp.activationPolicy = quiet ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular;
	initCursors();
	voidWindow.dpiScale = s.desc.highDpi ? (float)NSScreen.mainScreen.backingScaleFactor : 1.0f;
	initDefaultDimensions();
	const NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		| NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	s_window = [[VoidMacosWindow alloc] initWithContentRect:NSMakeRect(0, 0, voidWindow.windowWidth, voidWindow.windowHeight)
		styleMask:style backing:NSBackingStoreBuffered defer:NO];
	s_window.releasedWhenClosed = NO;
	s_window.title = [NSString stringWithUTF8String:s.desc.title];
	s_window.acceptsMouseMovedEvents = YES;
	s_windowDelegate = [VoidMacosWindowDelegate new];
	s_window.delegate = s_windowDelegate;
	s_view = [VoidMacosView new];
	[s_view updateTrackingAreas];
	s_window.contentView = s_view;
	[s_window makeFirstResponder:s_view];
	[s_window center];
	voidWindow.valid = true;
	if (quiet) {
		s_window.alphaValue = 0;
		s_window.ignoresMouseEvents = YES;
		[s_window orderFrontRegardless];
		[s_window makeKeyWindow];
	} else {
		[NSApp activateIgnoringOtherApps:YES];
		[s_window makeKeyAndOrderFront:nil];
	}
	updateDimensions();
	NSEvent *focus = [NSEvent otherEventWithType:NSEventTypeAppKitDefined location:NSZeroPoint
		modifierFlags:0x40 timestamp:0 windowNumber:0 context:nil
		subtype:NSEventSubtypeApplicationActivated data1:0 data2:0];
	[NSApp postEvent:focus atStart:YES];
	startFrames();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	(void)sender;
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	(void)notification;
	voidWindowCleanup();
}
@end

@implementation VoidMacosWindowDelegate
- (BOOL)windowShouldClose:(id)sender {
	(void)sender;
	voidWindowAskQuit();
	return voidWindow.quitOrdered ? YES : NO;
}

- (void)windowWillStartLiveResize:(NSNotification *)notification {
	(void)notification;
	const bool fromLeft = voidWindow.mouse.x < (float)voidWindow.windowWidth / 2;
	const bool fromTop = voidWindow.mouse.y < (float)voidWindow.windowHeight / 2;
	NSViewLayerContentsPlacement placement;
	if (fromLeft) placement = fromTop ? NSViewLayerContentsPlacementBottomRight : NSViewLayerContentsPlacementTopRight;
	else placement = fromTop ? NSViewLayerContentsPlacementBottomLeft : NSViewLayerContentsPlacementTopLeft;
	s_view.layerContentsPlacement = placement;
}

- (void)windowDidResize:(NSNotification *)notification {
	(void)notification;
	updateDimensions();
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
	(void)notification;
	updateDimensions();
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
	(void)notification;
	transitionToOccluded();
	voidWindowAppEvent(VOID_EVENT_ICONIFIED);
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
	(void)notification;
	transitionToVisible();
	voidWindowAppEvent(VOID_EVENT_RESTORED);
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
	(void)notification;
	if (s_window.occlusionState & NSWindowOcclusionStateVisible) transitionToVisible();
	else transitionToOccluded();
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
	(void)notification;
	voidWindowAppEvent(VOID_EVENT_FOCUSED);
}

- (void)windowDidResignKey:(NSNotification *)notification {
	(void)notification;
	voidKeysHeldRelease(&voidWindow.keysHeld, releaseKey);
	s.flagsChanged = 0;
	voidWindowAppEvent(VOID_EVENT_UNFOCUSED);
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
	(void)notification;
	voidWindow.fullscreen = true;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
	(void)notification;
	voidWindow.fullscreen = false;
}
@end

@implementation VoidMacosWindow
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style
	backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
	if (self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag]) {
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	(void)sender;
	return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	(void)sender;
	return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSPasteboard *pboard = [sender draggingPasteboard];
	if (![pboard.types containsObject:NSPasteboardTypeFileURL]) return NO;
	const int count = (int)pboard.pasteboardItems.count;
	voidWindowBeginDrop((size_t)count);
	for (int i = 0; i < count; i++) {
		NSURL *url = [NSURL fileURLWithPath:[pboard.pasteboardItems[(NSUInteger)i] stringForType:NSPasteboardTypeFileURL]];
		voidWindow.droppedPaths[i] = strdup(url.standardizedURL.path.UTF8String);
		if (voidWindow.droppedPaths[i] == NULL) fail("strdup for a dropped file path");
	}
	voidWindow.droppedCount = count;
	if (voidWindowEventsEnabled()) {
		mouseUpdateFromPoint(sender.draggingLocation, true);
		voidWindowInitEvent(VOID_EVENT_FILES_DROPPED);
		voidWindow.event.modifiers = mods(nil);
		voidWindowCallEvent();
	}
	return YES;
}
@end

@implementation VoidMacosView
- (BOOL)isOpaque { return YES; }

- (void)displayLinkFired:(id)sender {
	(void)sender;
	if (s_frameTimer == nil) frame();
}

- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)updateTrackingAreas {
	if (s_trackingArea != nil) {
		[self removeTrackingArea:s_trackingArea];
		s_trackingArea = nil;
	}
	const NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
		| NSTrackingEnabledDuringMouseDrag | NSTrackingCursorUpdate | NSTrackingInVisibleRect | NSTrackingAssumeInside;
	s_trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:options owner:self userInfo:nil];
	[self addTrackingArea:s_trackingArea];
	[super updateTrackingAreas];
}

- (void)mouseEntered:(NSEvent *)event {
	mouseUpdateFromPoint(event.locationInWindow, true);
	if (s.mouseButtons == 0) mouseEvent(VOID_EVENT_MOUSE_ENTER, VOID_MOUSE_INVALID, mods(event));
}

- (void)mouseExited:(NSEvent *)event {
	mouseUpdateFromPoint(event.locationInWindow, true);
	if (s.mouseButtons == 0) mouseEvent(VOID_EVENT_MOUSE_LEAVE, VOID_MOUSE_INVALID, mods(event));
}

- (void)button:(VoidMouseButton)button down:(BOOL)down event:(NSEvent *)event {
	mouseUpdateFromPoint(event.locationInWindow, false);
	mouseEvent(down ? VOID_EVENT_MOUSE_DOWN : VOID_EVENT_MOUSE_UP, button, mods(event));
	if (down) s.mouseButtons |= (uint8_t)(1 << button);
	else s.mouseButtons &= (uint8_t)~(1 << button);
}

- (void)mouseDown:(NSEvent *)event { [self button:VOID_MOUSE_LEFT down:YES event:event]; }
- (void)mouseUp:(NSEvent *)event { [self button:VOID_MOUSE_LEFT down:NO event:event]; }
- (void)rightMouseDown:(NSEvent *)event { [self button:VOID_MOUSE_RIGHT down:YES event:event]; }
- (void)rightMouseUp:(NSEvent *)event { [self button:VOID_MOUSE_RIGHT down:NO event:event]; }
- (void)otherMouseDown:(NSEvent *)event {
	if (event.buttonNumber == 2) [self button:VOID_MOUSE_MIDDLE down:YES event:event];
	else mouseUpdateFromPoint(event.locationInWindow, false);
}
- (void)otherMouseUp:(NSEvent *)event {
	if (event.buttonNumber == 2) [self button:VOID_MOUSE_MIDDLE down:NO event:event];
	else mouseUpdateFromPoint(event.locationInWindow, false);
}

- (void)moved:(NSEvent *)event {
	mouseUpdateFromPoint(event.locationInWindow, false);
	if (voidWindow.mouse.locked) {
		voidWindow.mouse.dx = (float)event.deltaX;
		voidWindow.mouse.dy = (float)event.deltaY;
	}
	mouseEvent(VOID_EVENT_MOUSE_MOVE, VOID_MOUSE_INVALID, mods(event));
}

- (void)mouseMoved:(NSEvent *)event { [self moved:event]; }
- (void)mouseDragged:(NSEvent *)event { [self moved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self moved:event]; }
- (void)otherMouseDragged:(NSEvent *)event {
	if (event.buttonNumber == 2) [self moved:event];
	else mouseUpdateFromPoint(event.locationInWindow, false);
}

- (void)scrollWheel:(NSEvent *)event {
	mouseUpdateFromPoint(event.locationInWindow, true);
	if (!voidWindowEventsEnabled()) return;
	float dx = (float)event.scrollingDeltaX;
	float dy = (float)event.scrollingDeltaY;
	if (event.hasPreciseScrollingDeltas) {
		dx *= 0.1f;
		dy *= 0.1f;
	}
	if (fabsf(dx) > 0.0f || fabsf(dy) > 0.0f) {
		voidWindowInitEvent(VOID_EVENT_MOUSE_SCROLL);
		voidWindow.event.modifiers = mods(event);
		voidWindow.event.scrollX = dx;
		voidWindow.event.scrollY = dy;
		voidWindowCallEvent();
	}
}

- (void)keyDown:(NSEvent *)event {
	if (!voidWindowEventsEnabled()) return;
	const uint32_t modifiers = mods(event);
	const VoidKeyCode key = translateKey(event.keyCode);
	keyEvent(VOID_EVENT_KEY_DOWN, key, event.isARepeat, modifiers);
	if (s.textInput) {
		if (!(modifiers & (VOID_MODIFIER_CTRL | VOID_MODIFIER_SUPER))) [self interpretKeyEvents:@[event]];
	} else {
		NSString *chars = event.characters;
		uint32_t high = 0;
		for (NSUInteger i = 0; i < chars.length; i++) {
			uint32_t c = [chars characterAtIndex:i];
			if ((c & 0xFF00) == 0xF700) continue;
			if (c >= 0xD800 && c <= 0xDBFF) {
				high = c;
				continue;
			}
			if (c >= 0xDC00 && c <= 0xDFFF) {
				if (high == 0) continue;
				c = ((high - 0xD800) << 10 | (c - 0xDC00)) + 0x10000;
				high = 0;
			}
			voidWindowInitEvent(VOID_EVENT_CHAR);
			voidWindow.event.modifiers = modifiers;
			voidWindow.event.charCode = c;
			voidWindow.event.keyRepeat = event.isARepeat;
			voidWindowCallEvent();
		}
	}
	if (modifiers == VOID_MODIFIER_SUPER && key == VOID_KEY_V) voidWindowAppEvent(VOID_EVENT_CLIPBOARD_PASTED);
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
	if (translateKey(event.keyCode) != VOID_KEY_TAB) return NO;
	[self keyDown:event];
	return YES;
}

- (void)keyUp:(NSEvent *)event {
	keyEvent(VOID_EVENT_KEY_UP, translateKey(event.keyCode), event.isARepeat, mods(event));
}

- (void)flagsChanged:(NSEvent *)event {
	const uint32_t oldFlags = s.flagsChanged;
	const uint32_t newFlags = (uint32_t)event.modifierFlags;
	s.flagsChanged = newFlags;
	VoidKeyCode key = VOID_KEY_INVALID;
	bool down = false;
	if ((newFlags ^ oldFlags) & NSEventModifierFlagShift) {
		key = VOID_KEY_LEFT_SHIFT;
		down = (newFlags & NSEventModifierFlagShift) != 0;
	}
	if ((newFlags ^ oldFlags) & NSEventModifierFlagControl) {
		key = VOID_KEY_LEFT_CONTROL;
		down = (newFlags & NSEventModifierFlagControl) != 0;
	}
	if ((newFlags ^ oldFlags) & NSEventModifierFlagOption) {
		key = VOID_KEY_LEFT_ALT;
		down = (newFlags & NSEventModifierFlagOption) != 0;
	}
	if ((newFlags ^ oldFlags) & NSEventModifierFlagCommand) {
		key = VOID_KEY_LEFT_SUPER;
		down = (newFlags & NSEventModifierFlagCommand) != 0;
	}
	if (key != VOID_KEY_INVALID) keyEvent(down ? VOID_EVENT_KEY_DOWN : VOID_EVENT_KEY_UP, key, false, mods(event));
}

- (void)cursorUpdate:(NSEvent *)event {
	(void)event;
	updateCursor(voidWindow.mouse.cursor, voidWindow.mouse.shown);
}

- (BOOL)hasMarkedText { return s_marked.length > 0; }

- (NSRange)markedRange {
	return s_marked.length > 0 ? NSMakeRange(0, s_marked.length) : NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange { return NSMakeRange(NSNotFound, 0); }

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
	(void)replacementRange;
	NSString *text = [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : string;
	s_marked = [text copy];
	const NSUInteger caret = MIN(selectedRange.location, s_marked.length);
	s.markedSelection = NSMakeRange(caret, MIN(selectedRange.length, s_marked.length - caret));
	textEvent(VOID_EVENT_PREEDIT, s_marked, NSMaxRange(s.markedSelection));
}

- (void)unmarkText {
	NSString *text = s_marked;
	if (text.length == 0) return;
	clearMarked();
	textEvent(VOID_EVENT_TEXT_INPUT, text, 0);
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
	(void)range;
	(void)actualRange;
	return nil;
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
	(void)replacementRange;
	NSString *text = [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : string;
	clearMarked();
	NSString *printable = [text stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
	if (printable.length > 0) textEvent(VOID_EVENT_TEXT_INPUT, text, 0);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
	(void)point;
	return NSNotFound;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
	(void)range;
	(void)actualRange;
	return [s_window convertRectToScreen:[self convertRect:s.imeRect toView:nil]];
}

- (void)doCommandBySelector:(SEL)selector { (void)selector; }
@end

void voidMacosRun(const VoidMacosDesc *desc) {
	if (desc->text == NULL) fail("voidMacosRun: the desc has no text callback");
	s.desc = *desc;
	voidWindowStart(desc->init, desc->frame, desc->event, desc->cleanup, desc->width, desc->height);
	s_marked = @"";
	@autoreleasepool {
		[NSApplication sharedApplication];
		s_appDelegate = [VoidMacosAppDelegate new];
		NSApp.delegate = s_appDelegate;
		s_keyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp
			handler:^NSEvent *(NSEvent *event) {
				if (event.modifierFlags & NSEventModifierFlagCommand) [[NSApp keyWindow] sendEvent:event];
				return event;
			}];
		[NSApp run];
	}
}

void *voidMacosView(void) { return (__bridge void *)s_view; }

void voidWindowSetTitle(const char *title) {
	s_window.title = [NSString stringWithUTF8String:title];
}

void voidWindowSetClipboard(const char *utf8) {
	@autoreleasepool {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		[pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
		if (![pasteboard setString:@(utf8) forType:NSPasteboardTypeString]) fail("setting the clipboard");
	}
}

const char *voidWindowClipboard(void) {
	free(voidWindow.clipboard);
	voidWindow.clipboard = strdup("");
	@autoreleasepool {
		NSString *str = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
		if (str != nil) {
			free(voidWindow.clipboard);
			voidWindow.clipboard = strdup(str.UTF8String);
		}
	}
	if (voidWindow.clipboard == NULL) fail("strdup for the clipboard");
	return voidWindow.clipboard;
}

void voidWindowSetCursor(int cursor) { updateCursor(cursor, voidWindow.mouse.shown); }

void voidWindowShowMouse(bool shown) {
	if (voidWindow.mouse.shown != shown) updateCursor(voidWindow.mouse.cursor, shown);
}

void voidWindowLockMouse(bool locked) {
	if (locked == voidWindow.mouse.locked) return;
	voidWindow.mouse.dx = 0.0f;
	voidWindow.mouse.dy = 0.0f;
	voidWindow.mouse.locked = locked;
	if (locked) {
		CGAssociateMouseAndMouseCursorPosition(NO);
		[NSCursor hide];
	} else {
		[NSCursor unhide];
		CGAssociateMouseAndMouseCursorPosition(YES);
	}
}

void voidWindowToggleFullscreen(void) {
	voidWindow.fullscreen = !voidWindow.fullscreen;
	[s_window toggleFullScreen:nil];
}

void voidMacosSetTextInput(bool on) {
	if (s.textInput == on) return;
	s.textInput = on;
	if (!on && s_marked.length > 0) {
		[s_view.inputContext discardMarkedText];
		clearMarked();
	}
}

void voidMacosSetImeRect(int x, int y, int w, int h) {
	const CGFloat scale = voidWindow.dpiScale > 0 ? voidWindow.dpiScale : 1.0;
	const CGFloat height = s_view != nil ? s_view.bounds.size.height : 0;
	s.imeRect = NSMakeRect(x / scale, height - (y + h) / scale, w / scale, h / scale);
	[s_view.inputContext invalidateCharacterCoordinates];
}
