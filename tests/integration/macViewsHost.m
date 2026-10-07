#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

#include "macViewsHost.h"

static NSWindow *s_window;
static NSView *s_view;

long long macHostOpen(int width, int height) {
	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
	s_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
		styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	[s_window setReleasedWhenClosed:NO];
	[s_window center];
	[s_window makeKeyAndOrderFront:nil];
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

void macHostClose(void) {
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
