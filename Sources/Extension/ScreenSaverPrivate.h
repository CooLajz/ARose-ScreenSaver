// Narrow declarations for the private com.apple.screensaver extension point.
// Based on Apple's runtime and AerialScreensaver/AppexSaverMinimal (MIT).
#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

@interface ScreenSaverExtension : NSObject
@end

@interface ScreenSaverViewController : NSViewController
@end

// The runtime superclass is NSServiceViewController (a private AppKit type).
// Plain NSViewController is rejected by ViewBridge when opening Options.
@interface ScreenSaverConfigurationViewController : NSViewController
- (void)configureSheetDidEnd;
- (void)configureSheetWillPresent;
@end
