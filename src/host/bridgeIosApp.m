// Void sokol driver — iOS app (Metal). voidRun is a UIApplication whose root view renders
// through the views driver (bridgeIos.m, views.c) and feeds the window event surface
// (appWindow.c), as bridgeEmbed.m's voidRun is a Cocoa window. The app's main() runs MsMain,
// whose main_ calls voidRun, which enters UIApplicationMain and does not return.

#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <string.h>
#include <unistd.h>

#include "bridge.h"
#include "views.h"
#include "appWindow.h"
#include "iosApp.h"
#include "../platform/frameTiming.h"

#if !__has_feature(objc_arc)
#error "bridgeIosApp.m is written for ARC"
#endif

extern int cmdCount;
extern char **cmdLine;

static int s_running;
static int s_highDpi = 1;
static int s_reqW, s_reqH;
static uint64_t s_frameCount;
static VoidFrameTiming s_timing;
static double s_frameDuration;
static CFTimeInterval s_stamp;
static int s_fbW = 1, s_fbH = 1;
static float s_scale = 1.0f;
static uint32_t s_modifiers;
static uint32_t s_heldModifiers;
static int s_textInput;
static CGRect s_imeRect;
static BOOL s_backspaceHeld, s_backspaceSent;

uint64_t voidIosFrameCount(void) { return s_frameCount; }
int voidIosWidth(void) { return s_fbW; }
int voidIosHeight(void) { return s_fbH; }
bool voidIosValid(void) { return s_running != 0; }
float voidIosScale(void) { return s_scale; }
uint32_t voidIosModifiers(void) { return s_modifiers; }
double voidIosFrameDuration(void) { return s_frameDuration; }

static VoidKeyCode keyOfHid(long usage) {
	if (usage >= 0x04 && usage <= 0x1D) return (VoidKeyCode)(VOID_KEY_A + (usage - 0x04));
	if (usage >= 0x1E && usage <= 0x26) return (VoidKeyCode)(VOID_KEY_1 + (usage - 0x1E));
	if (usage >= 0x3A && usage <= 0x45) return (VoidKeyCode)(VOID_KEY_F1 + (usage - 0x3A));
	switch (usage) {
		case 0x27: return VOID_KEY_0;
		case 0x28: return VOID_KEY_ENTER;
		case 0x29: return VOID_KEY_ESCAPE;
		case 0x2A: return VOID_KEY_BACKSPACE;
		case 0x2B: return VOID_KEY_TAB;
		case 0x2C: return VOID_KEY_SPACE;
		case 0x2D: return VOID_KEY_MINUS;
		case 0x2E: return VOID_KEY_EQUAL;
		case 0x2F: return VOID_KEY_LEFT_BRACKET;
		case 0x30: return VOID_KEY_RIGHT_BRACKET;
		case 0x31: return VOID_KEY_BACKSLASH;
		case 0x33: return VOID_KEY_SEMICOLON;
		case 0x34: return VOID_KEY_APOSTROPHE;
		case 0x35: return VOID_KEY_GRAVE_ACCENT;
		case 0x36: return VOID_KEY_COMMA;
		case 0x37: return VOID_KEY_PERIOD;
		case 0x38: return VOID_KEY_SLASH;
		case 0x39: return VOID_KEY_CAPS_LOCK;
		case 0x49: return VOID_KEY_INSERT;
		case 0x4A: return VOID_KEY_HOME;
		case 0x4B: return VOID_KEY_PAGE_UP;
		case 0x4C: return VOID_KEY_DELETE;
		case 0x4D: return VOID_KEY_END;
		case 0x4E: return VOID_KEY_PAGE_DOWN;
		case 0x4F: return VOID_KEY_RIGHT;
		case 0x50: return VOID_KEY_LEFT;
		case 0x51: return VOID_KEY_DOWN;
		case 0x52: return VOID_KEY_UP;
		case 0x64: return VOID_KEY_WORLD_1;
		case 0xE0: return VOID_KEY_LEFT_CONTROL;
		case 0xE1: return VOID_KEY_LEFT_SHIFT;
		case 0xE2: return VOID_KEY_LEFT_ALT;
		case 0xE3: return VOID_KEY_LEFT_SUPER;
		case 0xE4: return VOID_KEY_RIGHT_CONTROL;
		case 0xE5: return VOID_KEY_RIGHT_SHIFT;
		case 0xE6: return VOID_KEY_RIGHT_ALT;
		case 0xE7: return VOID_KEY_RIGHT_SUPER;
		default: return VOID_KEY_INVALID;
	}
}

static uint32_t modifiersOf(UIKeyModifierFlags flags) {
	uint32_t m = 0;
	if (flags & UIKeyModifierShift) m |= VOID_MODIFIER_SHIFT;
	if (flags & UIKeyModifierControl) m |= VOID_MODIFIER_CTRL;
	if (flags & UIKeyModifierAlternate) m |= VOID_MODIFIER_ALT;
	if (flags & UIKeyModifierCommand) m |= VOID_MODIFIER_SUPER;
	return m;
}

static uint32_t modifierOfKey(VoidKeyCode code) {
	switch (code) {
		case VOID_KEY_LEFT_SHIFT: case VOID_KEY_RIGHT_SHIFT: return VOID_MODIFIER_SHIFT;
		case VOID_KEY_LEFT_CONTROL: case VOID_KEY_RIGHT_CONTROL: return VOID_MODIFIER_CTRL;
		case VOID_KEY_LEFT_ALT: case VOID_KEY_RIGHT_ALT: return VOID_MODIFIER_ALT;
		case VOID_KEY_LEFT_SUPER: case VOID_KEY_RIGHT_SUPER: return VOID_MODIFIER_SUPER;
		default: return 0;
	}
}

@interface VoidTextPosition : UITextPosition
@property(nonatomic) NSInteger offset;
+ (instancetype)at:(NSInteger)offset;
@end

@implementation VoidTextPosition
+ (instancetype)at:(NSInteger)offset {
	VoidTextPosition *p = [self new];
	p.offset = offset;
	return p;
}
@end

@interface VoidTextRange : UITextRange
@property(nonatomic) NSRange range;
+ (instancetype)with:(NSRange)range;
@end

@implementation VoidTextRange
+ (instancetype)with:(NSRange)range {
	VoidTextRange *r = [self new];
	r.range = range;
	return r;
}
- (UITextPosition *)start { return [VoidTextPosition at:(NSInteger)self.range.location]; }
- (UITextPosition *)end { return [VoidTextPosition at:(NSInteger)NSMaxRange(self.range)]; }
- (BOOL)isEmpty { return self.range.length == 0; }
@end

static NSRange clampRange(NSRange r, NSUInteger length) {
	const NSUInteger at = MIN(r.location, length);
	return NSMakeRange(at, MIN(r.length, length - at));
}

static NSInteger offsetOf(UITextPosition *p) { return ((VoidTextPosition *)p).offset; }

@interface VoidAppView : UIView <UITextInput>
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic) VoidViewId viewId;
@property(nonatomic) UIEdgeInsets insets;
@property(nonatomic, strong) NSString *marked;
@property(nonatomic) NSRange markedSelection;
@property(nonatomic, strong) UIView *noKeyboard;
@property(nonatomic, strong) UITextInputStringTokenizer *stringTokenizer;
@property(nonatomic, weak) id<UITextInputDelegate> inputDelegate;
@property(nonatomic, copy) NSDictionary<NSAttributedStringKey, id> *markedTextStyle;
@property(nonatomic) UITextAutocorrectionType autocorrectionType;
@property(nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property(nonatomic) UITextSpellCheckingType spellCheckingType;
@property(nonatomic) UITextSmartQuotesType smartQuotesType;
@property(nonatomic) UITextSmartDashesType smartDashesType;
@property(nonatomic) UITextSmartInsertDeleteType smartInsertDeleteType;
@end

static VoidAppView *s_view;

@implementation VoidAppView

+ (Class)layerClass { return [CAMetalLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	self.multipleTouchEnabled = YES;
	self.marked = @"";
	self.noKeyboard = [[UIView alloc] initWithFrame:CGRectZero];
	self.autocorrectionType = UITextAutocorrectionTypeNo;
	self.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.spellCheckingType = UITextSpellCheckingTypeNo;
	self.smartQuotesType = UITextSmartQuotesTypeNo;
	self.smartDashesType = UITextSmartDashesTypeNo;
	self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(keyboardFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
	[center addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
	return self;
}

- (void)setKeyboard:(float)height {
	if (height == voidKeyboardHeight()) return;
	voidAppSetKeyboard(height);
	if (self.viewId != 0) voidMobileSend(VOID_EVENT_RESIZED);
}

- (void)keyboardFrame:(NSNotification *)notification {
	UIScreen *screen = self.window ? self.window.screen : UIScreen.mainScreen;
	const CGRect end = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	if (CGRectGetMaxY(end) < CGRectGetMaxY(screen.bounds)) {
		[self setKeyboard:0];
		return;
	}
	const CGRect local = [self convertRect:end fromCoordinateSpace:screen.coordinateSpace];
	const CGFloat covered = CGRectGetMaxY(self.bounds) - MAX(CGRectGetMinY(local), CGRectGetMinY(self.bounds));
	[self setKeyboard:(float)(MAX(0, covered) * [self pixelScale])];
}

- (void)keyboardHidden:(NSNotification *)notification { [self setKeyboard:0]; }

- (BOOL)canBecomeFirstResponder { return YES; }
- (UIView *)inputView { return s_textInput ? nil : self.noKeyboard; }

- (CGFloat)pixelScale { return s_highDpi ? self.window.screen.scale : 1.0; }

- (void)measure {
	const CGFloat scale = [self pixelScale];
	s_scale = (float)scale;
	s_fbW = MAX(1, (int)lround(self.bounds.size.width * scale));
	s_fbH = MAX(1, (int)lround(self.bounds.size.height * scale));
	// highDpi 0 is the capture configuration (tests/golden/runner.ms): the framebuffer is the
	// size the program asked for, as a desktop window gives it, and the screen shows it scaled.
	if (!s_highDpi && s_reqW > 0 && s_reqH > 0) {
		s_fbW = s_reqW;
		s_fbH = s_reqH;
	}
	const UIEdgeInsets in = self.safeAreaInsets;
	voidAppSetSafeArea((float)(in.top * scale), (float)(in.left * scale),
		(float)(in.bottom * scale), (float)(in.right * scale));
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window || self.viewId != 0) return;
	self.contentScaleFactor = [self pixelScale];
	CAMetalLayer *layer = (CAMetalLayer *)self.layer;
	layer.framebufferOnly = NO;
	layer.contentsScale = [self pixelScale];
	if (!s_highDpi && s_reqW > 0 && s_reqH > 0) layer.contentsGravity = kCAGravityResizeAspect;
	[self measure];
	self.insets = self.safeAreaInsets;
	self.viewId = voidViewCreate((long long)(intptr_t)(__bridge void *)layer, s_fbW, s_fbH, s_scale);
	self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	if (@available(iOS 15.0, *)) {
		const float maxFps = (float)self.window.screen.maximumFramesPerSecond;
		self.link.preferredFrameRateRange = CAFrameRateRangeMake(maxFps, maxFps, maxFps);
	}
	[self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	[self becomeFirstResponder];
}

- (void)relayout {
	if (self.viewId == 0) return;
	const int w = s_fbW, h = s_fbH;
	[self measure];
	if (w == s_fbW && h == s_fbH && UIEdgeInsetsEqualToEdgeInsets(self.insets, self.safeAreaInsets)) return;
	self.insets = self.safeAreaInsets;
	voidViewResize(self.viewId, s_fbW, s_fbH, s_scale);
	voidMobileSend(VOID_EVENT_RESIZED);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self relayout];
}

- (void)safeAreaInsetsDidChange {
	[super safeAreaInsetsDidChange];
	[self relayout];
}

- (void)tick {
	if (s_stamp > 0.0) s_frameDuration = voidFrameTimingClamp(&s_timing, self.link.timestamp - s_stamp);
	s_stamp = self.link.timestamp;
	s_frameCount++;
	voidViewFrame(self.viewId);
}

- (void)sendTouches:(NSSet<UITouch *> *)changed event:(UIEvent *)event type:(VoidAppEventType)type {
	VoidAppEvent e = voidMobileEvent(type);
	NSSet<UITouch *> *all = event.allTouches ? event.allTouches : changed;
	for (UITouch *t in all) {
		if (e.touchCount == VOID_MAX_TOUCHPOINTS) break;
		const CGPoint p = [t locationInView:self];
		VoidTouchPoint *point = &e.touches[e.touchCount++];
		point->identifier = (uintptr_t)(__bridge void *)t;
		point->x = (float)(p.x * s_scale);
		point->y = (float)(p.y * s_scale);
		point->changed = [changed containsObject:t];
	}
	voidAppDeliver(&e);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:VOID_EVENT_TOUCHES_BEGAN];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:VOID_EVENT_TOUCHES_MOVED];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:VOID_EVENT_TOUCHES_ENDED];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:VOID_EVENT_TOUCHES_CANCELLED];
}

- (void)sendPresses:(NSSet<UIPress *> *)presses event:(UIPressesEvent *)event down:(BOOL)down {
	for (UIPress *press in presses) {
		UIKey *key = press.key;
		if (!key) continue;
		const VoidKeyCode code = keyOfHid((long)key.keyCode);
		const uint32_t own = modifierOfKey(code);
		s_heldModifiers = down ? (s_heldModifiers | own) : (s_heldModifiers & ~own);
		s_modifiers = modifiersOf(key.modifierFlags) | modifiersOf(event.modifierFlags) | s_heldModifiers;
		if (code == VOID_KEY_INVALID) continue;
		if (code == VOID_KEY_BACKSPACE) {
			if (down) {
				s_backspaceHeld = YES;
				s_backspaceSent = NO;
				continue;
			}
			s_backspaceHeld = NO;
			if (!s_backspaceSent) voidMobileKey(VOID_EVENT_KEY_DOWN, code, false);
			voidMobileKey(VOID_EVENT_KEY_UP, code, false);
			continue;
		}
		voidMobileKey(down ? VOID_EVENT_KEY_DOWN : VOID_EVENT_KEY_UP, code, false);
	}
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses event:event down:YES];
	[super pressesBegan:presses withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses event:event down:NO];
	[super pressesEnded:presses withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses event:event down:NO];
	[super pressesCancelled:presses withEvent:event];
}

- (void)sendPreedit {
	if (!s_textInput) return;
	voidAppTextDeliver(VOID_EVENT_PREEDIT, self.marked.UTF8String, (int)NSMaxRange(self.markedSelection));
}

- (void)commit:(NSString *)text {
	NSData *codepoints = [text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
	voidMobileCommit(s_textInput, text.UTF8String, (const uint32_t *)codepoints.bytes, codepoints.length / 4);
}

- (void)clearMarked {
	if (self.marked.length == 0) return;
	self.marked = @"";
	self.markedSelection = NSMakeRange(0, 0);
	[self sendPreedit];
}

- (BOOL)hasText { return YES; }

- (void)insertText:(NSString *)text {
	if (s_modifiers & (VOID_MODIFIER_CTRL | VOID_MODIFIER_SUPER)) return;
	[self clearMarked];
	[self commit:text];
}

- (void)deleteBackward {
	if (self.marked.length > 0) {
		const NSRange last = [self.marked rangeOfComposedCharacterSequenceAtIndex:self.marked.length - 1];
		self.marked = [self.marked substringToIndex:last.location];
		self.markedSelection = NSMakeRange(self.marked.length, 0);
		[self sendPreedit];
		return;
	}
	voidMobileKey(VOID_EVENT_KEY_DOWN, VOID_KEY_BACKSPACE, s_backspaceHeld && s_backspaceSent);
	if (s_backspaceHeld) {
		s_backspaceSent = YES;
	} else {
		voidMobileKey(VOID_EVENT_KEY_UP, VOID_KEY_BACKSPACE, false);
	}
}

- (NSInteger)documentLength { return (NSInteger)self.marked.length; }

- (NSString *)textInRange:(UITextRange *)range {
	const NSRange r = clampRange(((VoidTextRange *)range).range, self.marked.length);
	return [self.marked substringWithRange:r];
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
	if (self.marked.length == 0) {
		[self insertText:text];
		return;
	}
	const NSRange r = clampRange(((VoidTextRange *)range).range, self.marked.length);
	self.marked = [self.marked stringByReplacingCharactersInRange:r withString:text];
	self.markedSelection = NSMakeRange(r.location + text.length, 0);
	[self sendPreedit];
}

- (UITextRange *)selectedTextRange {
	return [VoidTextRange with:self.marked.length > 0 ? self.markedSelection : NSMakeRange(0, 0)];
}

- (void)setSelectedTextRange:(UITextRange *)range {
	if (self.marked.length == 0) return;
	self.markedSelection = clampRange(((VoidTextRange *)range).range, self.marked.length);
	[self sendPreedit];
}

- (UITextRange *)markedTextRange {
	return self.marked.length > 0 ? [VoidTextRange with:NSMakeRange(0, self.marked.length)] : nil;
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
	self.marked = markedText ? [markedText copy] : @"";
	self.markedSelection = clampRange(selectedRange, self.marked.length);
	[self sendPreedit];
}

- (void)unmarkText {
	NSString *text = self.marked;
	if (text.length == 0) return;
	[self clearMarked];
	[self commit:text];
}

- (UITextPosition *)beginningOfDocument { return [VoidTextPosition at:0]; }
- (UITextPosition *)endOfDocument { return [VoidTextPosition at:[self documentLength]]; }

- (UITextRange *)textRangeFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)to {
	const NSInteger a = offsetOf(from), b = offsetOf(to);
	return [VoidTextRange with:NSMakeRange((NSUInteger)MIN(a, b), (NSUInteger)labs(b - a))];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset {
	const NSInteger at = offsetOf(position) + offset;
	if (at < 0 || at > [self documentLength]) return nil;
	return [VoidTextPosition at:at];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position
	inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
	const BOOL back = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp;
	return [self positionFromPosition:position offset:back ? -offset : offset];
}

- (NSComparisonResult)comparePosition:(UITextPosition *)position toPosition:(UITextPosition *)other {
	const NSInteger a = offsetOf(position), b = offsetOf(other);
	return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)to {
	return offsetOf(to) - offsetOf(from);
}

- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)direction {
	const BOOL back = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp;
	return back ? range.start : range.end;
}

- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position
	inDirection:(UITextLayoutDirection)direction {
	const NSInteger at = offsetOf(position);
	const BOOL back = direction == UITextLayoutDirectionLeft || direction == UITextLayoutDirectionUp;
	const NSInteger other = MAX(0, MIN([self documentLength], back ? at - 1 : at + 1));
	return [self textRangeFromPosition:position toPosition:[VoidTextPosition at:other]];
}

- (NSWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position
	inDirection:(UITextStorageDirection)direction {
	(void)position; (void)direction;
	return NSWritingDirectionNatural;
}

- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection forRange:(UITextRange *)range {
	(void)writingDirection; (void)range;
}

- (CGRect)firstRectForRange:(UITextRange *)range { (void)range; return s_imeRect; }
- (CGRect)caretRectForPosition:(UITextPosition *)position { (void)position; return s_imeRect; }
- (NSArray<UITextSelectionRect *> *)selectionRectsForRange:(UITextRange *)range { (void)range; return @[]; }
- (UITextPosition *)closestPositionToPoint:(CGPoint)point { (void)point; return [self endOfDocument]; }
- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range {
	(void)point;
	return range.end;
}
- (UITextRange *)characterRangeAtPoint:(CGPoint)point { (void)point; return nil; }

- (id<UITextInputTokenizer>)tokenizer {
	if (!self.stringTokenizer) self.stringTokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
	return self.stringTokenizer;
}

@end

@interface VoidAppController : UIViewController
@end

@implementation VoidAppController
- (void)loadView {
	s_view = [[VoidAppView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view = s_view;
}
@end

@interface VoidAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation VoidAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
	(void)application; (void)options;
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [VoidAppController new];
	[self.window makeKeyAndVisible];
	return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
	(void)application;
	if (s_view.viewId != 0) voidMobileSend(VOID_EVENT_FOCUSED);
}
- (void)applicationWillResignActive:(UIApplication *)application {
	(void)application;
	s_heldModifiers = 0;
	s_modifiers = 0;
	voidMobileReleaseKeys();
	if (s_view.viewId != 0) voidMobileSend(VOID_EVENT_UNFOCUSED);
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
	(void)application;
	s_view.link.paused = YES;
	if (s_view.viewId != 0) voidMobileSend(VOID_EVENT_SUSPENDED);
}
- (void)applicationWillEnterForeground:(UIApplication *)application {
	(void)application;
	s_view.link.paused = NO;
	if (s_view.viewId != 0) voidMobileSend(VOID_EVENT_RESUMED);
}
@end

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_running) voidFail("voidRun: the iOS app is already running");
	s_running = 1;
	voidFrameTimingInit(&s_timing);
	s_frameDuration = 1.0 / (double)[UIScreen mainScreen].maximumFramesPerSecond;
	s_reqW = w;
	s_reqH = h;
	s_highDpi = highDpi;
	voidEmbedRegister(init, frame);
	voidViewsSetSampleCount(sampleCount);
	const char *resources = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
	if (resources) chdir(resources);
	@autoreleasepool {
		UIApplicationMain(cmdCount, cmdLine, nil, NSStringFromClass([VoidAppDelegate class]));
	}
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 1, 1, init, frame);
}

void voidSetTextInput(int on) {
	const int was = s_textInput;
	s_textInput = on ? 1 : 0;
	if (!s_view || was == s_textInput) return;
	if (!s_textInput) [s_view unmarkText];
	[s_view reloadInputViews];
	[s_view becomeFirstResponder];
}

void voidSetImeRect(int x, int y, int w, int h) {
	s_imeRect = CGRectMake(x / s_scale, y / s_scale, w / s_scale, h / s_scale);
}
