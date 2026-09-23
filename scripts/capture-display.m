// A temporary 2x display for scripts/capture-screenshots.sh on a Mac without a Retina
// screen. Development tooling only: never compiled into WindowHop, never shipped.
//
// Why: the published screenshots are on-screen captures (`screencapture -l`), which keep
// the window's rounded corners, glass material and shadow, at the backing scale of the
// display the window is on. On a 1x-only Mac that halves every image. A virtual HiDPI
// display is a real display to the window server, so a demo window drawn there is
// composited exactly as on a Retina screen, at 2x.
//
// It uses CGVirtualDisplay, a private CoreGraphics class (the one display utilities such
// as BetterDisplay use). The app's "public Apple APIs only" rule (AGENTS.md) governs
// Sources/; this file is the recorded exception for local capture tooling (Decided on
// #116). If a macOS update removes the class, the capture refuses the 1x scale again,
// exactly as before.
//
// The display is extended to the right of the main display with kCGConfigureForAppOnly,
// so the arrangement reverts when this process exits, and the display disappears with it.
//
// Build: clang -fobjc-arc -framework Foundation -framework CoreGraphics \
//          scripts/capture-display.m -o <binary>
// Run:   <binary> [width height]   (points; default 1920 x 1200)
// Prints `DISPLAY <id>` once the display is ready, then runs until terminated.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property uint32_t maxPixelsWide;
@property uint32_t maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property uint32_t productID;
@property uint32_t vendorID;
@property uint32_t serialNum;
@property (copy) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain) NSArray *modes;
@property uint32_t hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) CGDirectDisplayID displayID;
@end

static BOOL isOnline(CGDirectDisplayID display) {
    uint32_t count = 0;
    CGDirectDisplayID displays[32];
    CGGetOnlineDisplayList(32, displays, &count);
    for (uint32_t index = 0; index < count; index++) {
        if (displays[index] == display) return YES;
    }
    return NO;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (NSClassFromString(@"CGVirtualDisplay") == nil) {
            fprintf(stderr, "capture-display: CGVirtualDisplay is not available on this macOS\n");
            return 1;
        }
        NSUInteger width = argc > 2 ? (NSUInteger)atoi(argv[1]) : 1920;
        NSUInteger height = argc > 2 ? (NSUInteger)atoi(argv[2]) : 1200;

        CGVirtualDisplayDescriptor *descriptor = [CGVirtualDisplayDescriptor new];
        descriptor.queue = dispatch_get_main_queue();
        descriptor.name = @"WindowHop Capture";
        descriptor.maxPixelsWide = (uint32_t)(width * 2);
        descriptor.maxPixelsHigh = (uint32_t)(height * 2);
        // about 220 pixels per inch, like a Retina laptop screen
        descriptor.sizeInMillimeters = CGSizeMake(width * 2 * 25.4 / 220, height * 2 * 25.4 / 220);
        descriptor.vendorID = 0x5748;
        descriptor.productID = 0x5748;
        descriptor.serialNum = 1;
        descriptor.terminationHandler = ^(id display, id error) {};

        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
        CGVirtualDisplaySettings *settings = [CGVirtualDisplaySettings new];
        settings.hiDPI = 1;
        settings.modes = @[ [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:60] ];
        if (display == nil || ![display applySettings:settings]) {
            fprintf(stderr, "capture-display: the virtual display could not be created\n");
            return 1;
        }
        CGDirectDisplayID displayID = display.displayID;
        for (int attempt = 0; attempt < 100 && !isOnline(displayID); attempt++) usleep(50000);

        // A new display can join an existing mirror set, which would show it on the
        // operator's monitor. Unmirror it and place it to the right of the main display.
        CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
        CGDisplayConfigRef config;
        CGBeginDisplayConfiguration(&config);
        CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay);
        CGConfigureDisplayOrigin(config, displayID,
                                 (int32_t)(mainBounds.origin.x + mainBounds.size.width), 0);
        CGError error = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
        if (error != kCGErrorSuccess) {
            fprintf(stderr, "capture-display: display configuration failed (%d)\n", error);
            return 1;
        }
        printf("DISPLAY %u\n", displayID);
        fflush(stdout);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
