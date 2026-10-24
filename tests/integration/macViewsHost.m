#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include "macViewsHost.h"

static NSWindow *s_window;
static NSView *s_view;
static CADisplayLink *s_link;
static int s_ticked;

@interface MacHostTick : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation MacHostTick
- (void)tick:(CADisplayLink *)link { (void)link; s_ticked = 1; }
@end

static MacHostTick *s_tick;

long long macHostOpen(int width, int height) {
	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
	s_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
		styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	[s_window setReleasedWhenClosed:NO];
	[NSApp finishLaunching];
	[s_window center];
	[s_window setLevel:NSStatusWindowLevel];
	[s_window orderFrontRegardless];
	s_view = [s_window contentView];
	return (long long)(intptr_t)(__bridge void *)s_view;
}

void macHostResize(int width, int height) { [s_window setContentSize:NSMakeSize(width, height)]; }

void macHostPump(void) {
	NSEvent *event;
	while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:nil
			inMode:NSDefaultRunLoopMode dequeue:YES])) {
		[NSApp sendEvent:event];
	}
}

void macHostAwaitVsync(void) {
	if (s_link == nil) {
		s_tick = [MacHostTick new];
		s_link = [s_view displayLinkWithTarget:s_tick selector:@selector(tick:)];
		[s_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSDefaultRunLoopMode];
	}
	s_ticked = 0;
	NSDate *giveUp = [NSDate dateWithTimeIntervalSinceNow:0.1];
	while (!s_ticked && [giveUp timeIntervalSinceNow] > 0) {
		NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:giveUp
			inMode:NSDefaultRunLoopMode dequeue:YES];
		if (event) [NSApp sendEvent:event];
	}
}

double macHostNowMs(void) { return CACurrentMediaTime() * 1000.0; }

void macHostClose(void) {
	[s_link invalidate];
	s_link = nil;
	[s_window orderOut:nil];
	[s_window close];
	s_window = nil;
	s_view = nil;
}

static NSRect backingBounds(void) { return [s_view convertRectToBacking:[s_view bounds]]; }

int macHostBackingWidth(void) { return (int)backingBounds().size.width; }
int macHostBackingHeight(void) { return (int)backingBounds().size.height; }
float macHostScale(void) { return (float)[s_window backingScaleFactor]; }
int macHostSublayerCount(void) { return (int)[[[s_view layer] sublayers] count]; }

static CAMetalLayer *hostedLayer(void) {
	return (CAMetalLayer *)[[[s_view layer] sublayers] firstObject];
}

int macHostDrawableWidth(void) { return (int)[hostedLayer() drawableSize].width; }
int macHostDrawableHeight(void) { return (int)[hostedLayer() drawableSize].height; }

int macHostLayerDrawableWidth(long long layer) {
	return (int)[(__bridge CAMetalLayer *)(void *)(intptr_t)layer drawableSize].width;
}

void macHostHide(void) { [s_window orderOut:nil]; }
void macHostShow(void) { [s_window orderFrontRegardless]; }
