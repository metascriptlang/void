#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include "macWindowHost.h"

static NSWindow *window(void) { return NSApp.windows.firstObject; }
static NSView *view(void) { return window().contentView; }

int macHostWindowCount(void) { return (int)NSApp.windows.count; }
msString macHostTitle(void) { return msStringFromCStr(window().title.UTF8String); }

msString macHostPasteboard(void) {
	NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
	return msStringFromCStr(s ? s.UTF8String : "");
}

void macHostClearPasteboard(void) { [[NSPasteboard generalPasteboard] clearContents]; }

int macHostCursorIs(int cursor) {
	NSCursor *want = cursor == 2 ? [NSCursor IBeamCursor] : cursor == 4 ? [NSCursor pointingHandCursor] : [NSCursor arrowCursor];
	return NSCursor.currentCursor == want;
}

static NSEvent *keyEvent(NSEventType type, int keyCode, const char *chars, unsigned flags) {
	NSString *s = @(chars);
	return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:0
		windowNumber:window().windowNumber context:nil characters:s charactersIgnoringModifiers:s
		isARepeat:NO keyCode:(unsigned short)keyCode];
}

void macHostKey(int down, int keyCode, const char *chars, unsigned flags) {
	[window() sendEvent:keyEvent(down ? NSEventTypeKeyDown : NSEventTypeKeyUp, keyCode, chars, flags)];
}

void macHostFlags(unsigned flags) {
	NSEvent *e = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:flags
		timestamp:0 windowNumber:window().windowNumber context:nil characters:@"" charactersIgnoringModifiers:@""
		isARepeat:NO keyCode:56];
	[window() sendEvent:e];
}

void macHostMouse(int type, double x, double y, unsigned flags) {
	NSEvent *e = [NSEvent mouseEventWithType:(NSEventType)type location:NSMakePoint(x, y) modifierFlags:flags
		timestamp:0 windowNumber:window().windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
	[window() sendEvent:e];
}

void macHostScroll(int lines) {
	CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, lines);
	NSEvent *e = [NSEvent eventWithCGEvent:cg];
	CFRelease(cg);
	[view() scrollWheel:e];
}

void macHostEnter(int enter, double x, double y) {
	NSEvent *e = [NSEvent enterExitEventWithType:enter ? NSEventTypeMouseEntered : NSEventTypeMouseExited
		location:NSMakePoint(x, y) modifierFlags:0 timestamp:0 windowNumber:window().windowNumber
		context:nil eventNumber:0 trackingNumber:0 userData:NULL];
	if (enter) [view() mouseEntered:e];
	else [view() mouseExited:e];
}

void macHostMark(const char *text, int caret) {
	[(id<NSTextInputClient>)view() setMarkedText:@(text) selectedRange:NSMakeRange((NSUInteger)caret, 0)
		replacementRange:NSMakeRange(NSNotFound, 0)];
}

void macHostInsert(const char *text) {
	[(id<NSTextInputClient>)view() insertText:@(text) replacementRange:NSMakeRange(NSNotFound, 0)];
}

void macHostUnmark(void) { [(id<NSTextInputClient>)view() unmarkText]; }

int macHostImeRectFits(double x, double y, double w, double h) {
	NSRect screen = [(id<NSTextInputClient>)view() firstRectForCharacterRange:NSMakeRange(0, 0) actualRange:NULL];
	NSRect local = [view() convertRect:[window() convertRectFromScreen:screen] fromView:nil];
	const double top = view().bounds.size.height - (local.origin.y + local.size.height);
	return fabs(local.origin.x - x) < 0.01 && fabs(top - y) < 0.01 && fabs(local.size.width - w) < 0.01
		&& fabs(local.size.height - h) < 0.01;
}

void macHostResignKey(void) { [window() resignKeyWindow]; }
void macHostBecomeKey(void) { [window() becomeKeyWindow]; }

void macHostMiniaturize(int on) {
	if (on) [window() miniaturize:nil];
	else [window() deminiaturize:nil];
}

int macHostMiniaturized(void) { return window().miniaturized ? 1 : 0; }
int macHostFullscreenStyle(void) { return (window().styleMask & NSWindowStyleMaskFullScreen) ? 1 : 0; }
void macHostSetContentSize(int w, int h) { [window() setContentSize:NSMakeSize(w, h)]; }
int macHostContentWidth(void) { return (int)view().bounds.size.width; }

int macHostLayerDrawableWidth(void) { return (int)((CAMetalLayer *)view().layer).drawableSize.width; }
int macHostLayerDrawableHeight(void) { return (int)((CAMetalLayer *)view().layer).drawableSize.height; }
float macHostScale(void) { return (float)window().backingScaleFactor; }

@interface HostDrag : NSObject <NSDraggingInfo>
@property(nonatomic, strong) NSPasteboard *board;
@end

@implementation HostDrag
- (NSPasteboard *)draggingPasteboard { return self.board; }
- (NSPoint)draggingLocation { return NSMakePoint(30, 40); }
- (NSWindow *)draggingDestinationWindow { return window(); }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy; }
- (NSPoint)draggedImageLocation { return NSZeroPoint; }
- (NSImage *)draggedImage { return nil; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 0; }
- (NSInteger)numberOfValidItemsForDrop { return 0; }
- (void)setNumberOfValidItemsForDrop:(NSInteger)n { (void)n; }
- (NSDraggingFormation)draggingFormation { return NSDraggingFormationDefault; }
- (void)setDraggingFormation:(NSDraggingFormation)f { (void)f; }
- (BOOL)animatesToDestination { return NO; }
- (void)setAnimatesToDestination:(BOOL)a { (void)a; }
- (NSSpringLoadingHighlight)springLoadingHighlight { return NSSpringLoadingHighlightNone; }
- (void)resetSpringLoading {}
- (void)slideDraggedImageTo:(NSPoint)p { (void)p; }
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)o forView:(NSView *)v classes:(NSArray<Class> *)c searchOptions:(NSDictionary<NSPasteboardReadingOptionKey, id> *)s usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))b {
	(void)o; (void)v; (void)c; (void)s; (void)b;
}
@end

int macHostDrop(const char *path) {
	HostDrag *drag = [HostDrag new];
	drag.board = [NSPasteboard pasteboardWithUniqueName];
	[drag.board writeObjects:@[[NSURL fileURLWithPath:@(path)]]];
	return [(id)window() performDragOperation:drag] ? 1 : 0;
}
