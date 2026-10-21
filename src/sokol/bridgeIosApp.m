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

#if !__has_feature(objc_arc)
#error "bridgeIosApp.m is written for ARC"
#endif

extern int cmdCount;
extern char **cmdLine;

static int s_running;
static int s_highDpi = 1;
static int s_reqW, s_reqH;
static uint64_t s_frameCount;
static int s_fbW = 1, s_fbH = 1;
static float s_scale = 1.0f;
static uint32_t s_modifiers;
static int s_textInput;
static CGRect s_imeRect;
static BOOL s_backspaceHeld, s_backspaceSent;
static BOOL s_enterHeld, s_tabHeld;

uint64_t sapp_frame_count(void) { return s_frameCount; }
int sapp_width(void) { return s_fbW; }
int sapp_height(void) { return s_fbH; }
bool sapp_isvalid(void) { return s_running != 0; }
void sapp_set_window_title(const char *title) { (void)title; }

static sapp_event makeEvent(sapp_event_type type) {
	sapp_event e;
	memset(&e, 0, sizeof e);
	e.type = type;
	e.frame_count = s_frameCount;
	e.modifiers = s_modifiers;
	e.framebuffer_width = s_fbW;
	e.framebuffer_height = s_fbH;
	e.window_width = (int)(s_fbW / s_scale);
	e.window_height = (int)(s_fbH / s_scale);
	return e;
}

static void send(sapp_event_type type) {
	sapp_event e = makeEvent(type);
	voidAppEventDeliver(&e);
}

static void sendKey(sapp_event_type type, sapp_keycode code, bool repeat) {
	sapp_event e = makeEvent(type);
	e.key_code = code;
	e.key_repeat = repeat;
	voidAppEventDeliver(&e);
}

static void sendTap(sapp_keycode code) {
	sendKey(SAPP_EVENTTYPE_KEY_DOWN, code, false);
	sendKey(SAPP_EVENTTYPE_KEY_UP, code, false);
}

static sapp_keycode keyOfHid(long usage) {
	if (usage >= 0x04 && usage <= 0x1D) return (sapp_keycode)(SAPP_KEYCODE_A + (usage - 0x04));
	if (usage >= 0x1E && usage <= 0x26) return (sapp_keycode)(SAPP_KEYCODE_1 + (usage - 0x1E));
	if (usage >= 0x3A && usage <= 0x45) return (sapp_keycode)(SAPP_KEYCODE_F1 + (usage - 0x3A));
	switch (usage) {
		case 0x27: return SAPP_KEYCODE_0;
		case 0x28: return SAPP_KEYCODE_ENTER;
		case 0x29: return SAPP_KEYCODE_ESCAPE;
		case 0x2A: return SAPP_KEYCODE_BACKSPACE;
		case 0x2B: return SAPP_KEYCODE_TAB;
		case 0x2C: return SAPP_KEYCODE_SPACE;
		case 0x2D: return SAPP_KEYCODE_MINUS;
		case 0x2E: return SAPP_KEYCODE_EQUAL;
		case 0x2F: return SAPP_KEYCODE_LEFT_BRACKET;
		case 0x30: return SAPP_KEYCODE_RIGHT_BRACKET;
		case 0x31: return SAPP_KEYCODE_BACKSLASH;
		case 0x33: return SAPP_KEYCODE_SEMICOLON;
		case 0x34: return SAPP_KEYCODE_APOSTROPHE;
		case 0x35: return SAPP_KEYCODE_GRAVE_ACCENT;
		case 0x36: return SAPP_KEYCODE_COMMA;
		case 0x37: return SAPP_KEYCODE_PERIOD;
		case 0x38: return SAPP_KEYCODE_SLASH;
		case 0x39: return SAPP_KEYCODE_CAPS_LOCK;
		case 0x49: return SAPP_KEYCODE_INSERT;
		case 0x4A: return SAPP_KEYCODE_HOME;
		case 0x4B: return SAPP_KEYCODE_PAGE_UP;
		case 0x4C: return SAPP_KEYCODE_DELETE;
		case 0x4D: return SAPP_KEYCODE_END;
		case 0x4E: return SAPP_KEYCODE_PAGE_DOWN;
		case 0x4F: return SAPP_KEYCODE_RIGHT;
		case 0x50: return SAPP_KEYCODE_LEFT;
		case 0x51: return SAPP_KEYCODE_DOWN;
		case 0x52: return SAPP_KEYCODE_UP;
		case 0x64: return SAPP_KEYCODE_WORLD_1;
		case 0xE0: return SAPP_KEYCODE_LEFT_CONTROL;
		case 0xE1: return SAPP_KEYCODE_LEFT_SHIFT;
		case 0xE2: return SAPP_KEYCODE_LEFT_ALT;
		case 0xE3: return SAPP_KEYCODE_LEFT_SUPER;
		case 0xE4: return SAPP_KEYCODE_RIGHT_CONTROL;
		case 0xE5: return SAPP_KEYCODE_RIGHT_SHIFT;
		case 0xE6: return SAPP_KEYCODE_RIGHT_ALT;
		case 0xE7: return SAPP_KEYCODE_RIGHT_SUPER;
		default: return SAPP_KEYCODE_INVALID;
	}
}

static uint32_t modifiersOf(UIKeyModifierFlags flags) {
	uint32_t m = 0;
	if (flags & UIKeyModifierShift) m |= SAPP_MODIFIER_SHIFT;
	if (flags & UIKeyModifierControl) m |= SAPP_MODIFIER_CTRL;
	if (flags & UIKeyModifierAlternate) m |= SAPP_MODIFIER_ALT;
	if (flags & UIKeyModifierCommand) m |= SAPP_MODIFIER_SUPER;
	return m;
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
	return self;
}

- (BOOL)canBecomeFirstResponder { return YES; }
- (UIView *)inputView { return s_textInput ? nil : self.noKeyboard; }

- (CGFloat)pixelScale { return s_highDpi ? self.window.screen.scale : 1.0; }

- (void)measure {
	const CGFloat scale = [self pixelScale];
	s_scale = (float)scale;
	s_fbW = MAX(1, (int)lround(self.bounds.size.width * scale));
	s_fbH = MAX(1, (int)lround(self.bounds.size.height * scale));
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
	[self measure];
	self.insets = self.safeAreaInsets;
	self.viewId = voidViewCreate((long long)(intptr_t)(__bridge void *)layer, s_fbW, s_fbH, s_scale);
	self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
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
	send(SAPP_EVENTTYPE_RESIZED);
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
	s_frameCount++;
	voidViewFrame(self.viewId);
}

- (void)sendTouches:(NSSet<UITouch *> *)changed event:(UIEvent *)event type:(sapp_event_type)type {
	sapp_event e = makeEvent(type);
	NSSet<UITouch *> *all = event.allTouches ? event.allTouches : changed;
	for (UITouch *t in all) {
		if (e.num_touches == SAPP_MAX_TOUCHPOINTS) break;
		const CGPoint p = [t locationInView:self];
		sapp_touchpoint *point = &e.touches[e.num_touches++];
		point->identifier = (uintptr_t)(__bridge void *)t;
		point->pos_x = (float)(p.x * s_scale);
		point->pos_y = (float)(p.y * s_scale);
		point->changed = [changed containsObject:t];
	}
	voidAppEventDeliver(&e);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:SAPP_EVENTTYPE_TOUCHES_BEGAN];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:SAPP_EVENTTYPE_TOUCHES_MOVED];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:SAPP_EVENTTYPE_TOUCHES_ENDED];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:touches event:event type:SAPP_EVENTTYPE_TOUCHES_CANCELLED];
}

- (void)sendPresses:(NSSet<UIPress *> *)presses down:(BOOL)down {
	for (UIPress *press in presses) {
		UIKey *key = press.key;
		if (!key) continue;
		s_modifiers = modifiersOf(key.modifierFlags);
		const sapp_keycode code = keyOfHid((long)key.keyCode);
		if (code == SAPP_KEYCODE_INVALID) continue;
		if (code == SAPP_KEYCODE_BACKSPACE) {
			if (down) {
				s_backspaceHeld = YES;
				s_backspaceSent = NO;
				continue;
			}
			s_backspaceHeld = NO;
			if (!s_backspaceSent) sendKey(SAPP_EVENTTYPE_KEY_DOWN, code, false);
			sendKey(SAPP_EVENTTYPE_KEY_UP, code, false);
			continue;
		}
		if (code == SAPP_KEYCODE_ENTER) s_enterHeld = down;
		if (code == SAPP_KEYCODE_TAB) s_tabHeld = down;
		sendKey(down ? SAPP_EVENTTYPE_KEY_DOWN : SAPP_EVENTTYPE_KEY_UP, code, false);
	}
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses down:YES];
	[super pressesBegan:presses withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses down:NO];
	[super pressesEnded:presses withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	[self sendPresses:presses down:NO];
	[super pressesCancelled:presses withEvent:event];
}

- (void)sendPreedit {
	if (!s_textInput) return;
	voidAppTextDeliver(VOID_EVENT_PREEDIT, self.marked.UTF8String, (int)NSMaxRange(self.markedSelection));
}

- (void)commit:(NSString *)text {
	if (s_textInput) {
		NSString *printable = [text stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
		if (printable.length > 0) voidAppTextDeliver(VOID_EVENT_TEXT_INPUT, text.UTF8String, 0);
	} else {
		[text enumerateSubstringsInRange:NSMakeRange(0, text.length)
			options:NSStringEnumerationByComposedCharacterSequences
			usingBlock:^(NSString *piece, NSRange r, NSRange er, BOOL *stop) {
				(void)r; (void)er; (void)stop;
				NSUInteger used = 0;
				uint32_t codepoints[16];
				[piece getBytes:codepoints maxLength:sizeof codepoints usedLength:&used
					encoding:NSUTF32LittleEndianStringEncoding options:0
					range:NSMakeRange(0, piece.length) remainingRange:NULL];
				for (NSUInteger i = 0; i < used / 4; i++) {
					if (codepoints[i] < 0x20 || codepoints[i] == 0x7F) continue;
					sapp_event e = makeEvent(SAPP_EVENTTYPE_CHAR);
					e.char_code = codepoints[i];
					voidAppEventDeliver(&e);
				}
			}];
	}
}

- (void)clearMarked {
	if (self.marked.length == 0) return;
	self.marked = @"";
	self.markedSelection = NSMakeRange(0, 0);
	[self sendPreedit];
}

- (BOOL)hasText { return YES; }

- (void)insertText:(NSString *)text {
	[self clearMarked];
	if ([text isEqualToString:@"\n"] || [text isEqualToString:@"\r"]) {
		if (!s_enterHeld) sendTap(SAPP_KEYCODE_ENTER);
		return;
	}
	if ([text isEqualToString:@"\t"]) {
		if (!s_tabHeld) sendTap(SAPP_KEYCODE_TAB);
		return;
	}
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
	sendKey(SAPP_EVENTTYPE_KEY_DOWN, SAPP_KEYCODE_BACKSPACE, s_backspaceHeld && s_backspaceSent);
	if (s_backspaceHeld) {
		s_backspaceSent = YES;
	} else {
		sendKey(SAPP_EVENTTYPE_KEY_UP, SAPP_KEYCODE_BACKSPACE, false);
	}
}

- (NSInteger)documentLength { return (NSInteger)self.marked.length; }

- (NSString *)textInRange:(UITextRange *)range {
	const NSRange r = NSIntersectionRange(((VoidTextRange *)range).range, NSMakeRange(0, self.marked.length));
	return [self.marked substringWithRange:r];
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
	if (self.marked.length == 0) {
		[self insertText:text];
		return;
	}
	const NSRange r = NSIntersectionRange(((VoidTextRange *)range).range, NSMakeRange(0, self.marked.length));
	self.marked = [self.marked stringByReplacingCharactersInRange:r withString:text];
	self.markedSelection = NSMakeRange(r.location + text.length, 0);
	[self sendPreedit];
}

- (UITextRange *)selectedTextRange {
	return [VoidTextRange with:self.marked.length > 0 ? self.markedSelection : NSMakeRange(0, 0)];
}

- (void)setSelectedTextRange:(UITextRange *)range {
	if (self.marked.length == 0) return;
	self.markedSelection = NSIntersectionRange(((VoidTextRange *)range).range, NSMakeRange(0, self.marked.length));
	[self sendPreedit];
}

- (UITextRange *)markedTextRange {
	return self.marked.length > 0 ? [VoidTextRange with:NSMakeRange(0, self.marked.length)] : nil;
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
	self.marked = markedText ? [markedText copy] : @"";
	self.markedSelection = NSIntersectionRange(selectedRange, NSMakeRange(0, self.marked.length));
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
	if (s_view.viewId != 0) send(SAPP_EVENTTYPE_FOCUSED);
}
- (void)applicationWillResignActive:(UIApplication *)application {
	(void)application;
	if (s_view.viewId != 0) send(SAPP_EVENTTYPE_UNFOCUSED);
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
	(void)application;
	s_view.link.paused = YES;
	if (s_view.viewId != 0) send(SAPP_EVENTTYPE_SUSPENDED);
}
- (void)applicationWillEnterForeground:(UIApplication *)application {
	(void)application;
	s_view.link.paused = NO;
	if (s_view.viewId != 0) send(SAPP_EVENTTYPE_RESUMED);
}
@end

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_running) voidFail("voidRun: the iOS app is already running");
	s_running = 1;
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

int voidIosAppFbWidth(void) { return s_running && voidCurrentView() == 0 ? s_fbW : voidViewsFbWidth(); }
int voidIosAppFbHeight(void) { return s_running && voidCurrentView() == 0 ? s_fbH : voidViewsFbHeight(); }
float voidIosAppDpiScale(void) { return s_running && voidCurrentView() == 0 ? s_scale : voidViewsDpiScale(); }
