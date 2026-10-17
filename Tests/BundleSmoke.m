#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) { NSLog(@"%@", error); return 1; }
        Class cls = bundle.principalClass;
        if (![cls isSubclassOfClass:ScreenSaverView.class]) return 2;
        if (argc > 3 && strcmp(argv[2], "--localization") == 0) {
            ScreenSaverView *view = [[cls alloc] initWithFrame:NSMakeRect(0,0,800,600) isPreview:YES];
            NSString *expected = strcmp(argv[3], "cs") == 0 ? @"Nastavení ARose" : @"ARose Settings";
            if (![view.configureSheet.title isEqualToString:expected]) {
                NSLog(@"Unexpected localized title: %@ (expected %@)", view.configureSheet.title, expected);
                return 8;
            }
            printf("OK: localized saver dialog (%s).\n", argv[3]);
            return 0;
        }
        // Model a remote host taking the view, closing its pane and requesting
        // another dialog. Previously the cached window returned detached content.
        ScreenSaverView *configurationView = [[cls alloc] initWithFrame:NSMakeRect(0,0,800,600) isPreview:YES];
        NSWindow *previousSheet = nil;
        for (int cycle=0; cycle<10; cycle++) {
            NSWindow *sheet = configurationView.configureSheet;
            if (!sheet || sheet == previousSheet || !sheet.contentView ||
                sheet.contentView.frame.size.width <= 0 || sheet.contentView.frame.size.height <= 0) return 9;
            previousSheet = sheet;
            sheet.contentView = nil;
        }
        puts("OK: repeated configuration requests create fresh, valid content after host detachment.");
        ScreenSaverDefaults *settings = [ScreenSaverDefaults defaultsForModuleWithName:@"cz.coolajz.ARose"];
        id oldAppearance = [settings objectForKey:@"appearance"];
        for (NSNumber *appearance in @[@0, @1]) {
        [settings setInteger:appearance.integerValue forKey:@"appearance"];
        [settings synchronize];
        for (NSNumber *preview in @[@YES, @NO]) {
            ScreenSaverView *view = [[cls alloc] initWithFrame:NSMakeRect(0,0,800,600) isPreview:preview.boolValue];
            if (!view || !view.hasConfigureSheet || !view.configureSheet) return 3;
            [view startAnimation];
            for (int n=0;n<100;n++) { [view animateOneFrame]; [NSThread sleepForTimeInterval:0.02]; }
            NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
            if (!rep || rep.pixelsWide != 800) return 4;
            if (argc>2) {
                NSString *path = [[NSString stringWithUTF8String:argv[2]] stringByAppendingPathComponent:preview.boolValue ? @"bundle-preview.png" : @"bundle-full.png"];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            }
            if (appearance.integerValue == 1) {
                view.frame = NSMakeRect(0,0,1920,1080);
                NSBitmapImageRep *wide = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:wide];
                if (wide.pixelsWide != 1920 || wide.pixelsHigh != 1080) return 5;
                if (argc>2) [[wide representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                    writeToFile:[[NSString stringWithUTF8String:argv[2]] stringByAppendingPathComponent:@"modern-wide.png"] atomically:YES];
                view.frame = NSMakeRect(0,0,600,1000);
                NSBitmapImageRep *portrait = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:portrait];
                if (portrait.pixelsWide != 600 || portrait.pixelsHigh != 1000) return 6;
            }
            [view stopAnimation];
            [view startAnimation]; [view animateOneFrame]; [view stopAnimation];
        }
        }
        id oldGlow = [settings objectForKey:@"glow"];
        for (NSNumber *appearance in @[@0, @1]) {
            [settings setInteger:appearance.integerValue forKey:@"appearance"];
        [settings synchronize];
            double previousLight = -1;
            for (NSNumber *glow in @[@0.0, @0.5, @1.0]) {
                [settings setDouble:glow.doubleValue forKey:@"glow"];
                [settings synchronize];
                ScreenSaverView *view = [[cls alloc] initWithFrame:NSMakeRect(0,0,800,600) isPreview:NO];
                [view animateOneFrame]; // Same deterministic frame for every intensity.
                NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
                double light = 0;
                for (NSInteger y=270;y<330;y++) for (NSInteger x=370;x<430;x++) {
                    NSColor *color = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                    light += color.redComponent + color.greenComponent + color.blueComponent;
                }
                printf("appearance=%d glow=%.1f light=%.5f previous=%.5f\n", appearance.intValue, glow.doubleValue, light, previousLight);
                if (previousLight >= 0 && (appearance.intValue == 1 ? light <= previousLight : fabs(light-previousLight)>0.001)) return 7;
                previousLight = light;
            }
        }
        if (oldGlow) [settings setObject:oldGlow forKey:@"glow"];
        else [settings removeObjectForKey:@"glow"];
        puts("OK: záře 0/50/100 % zvyšuje světelnost moderní verze a nemění originál.");
        if (oldAppearance) [settings setObject:oldAppearance forKey:@"appearance"];
        else [settings removeObjectForKey:@"appearance"];
        [settings synchronize];
        id oldDebug = [settings objectForKey:@"debugCPU"];
        BOOL overlayOK = YES;
        @try {
            [settings setBool:YES forKey:@"debugCPU"]; [settings synchronize];
            ScreenSaverView *debugView = [[cls alloc] initWithFrame:NSMakeRect(0,0,800,600) isPreview:YES];
            [debugView animateOneFrame];
            NSBitmapImageRep *debugImage = [debugView bitmapImageRepForCachingDisplayInRect:debugView.bounds];
            [debugView cacheDisplayInRect:debugView.bounds toBitmapImageRep:debugImage];
            [NSThread sleepForTimeInterval:1.1];
            [debugView cacheDisplayInRect:debugView.bounds toBitmapImageRep:debugImage];
            double light = 0;
            for (NSInteger y=550;y<600;y++) for (NSInteger x=550;x<800;x++) {
                NSColor *c = [[debugImage colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                light += c.redComponent + c.greenComponent + c.blueComponent;
            }
            overlayOK = light > 5;
            if (argc>2) [[debugImage representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[[NSString stringWithUTF8String:argv[2]] stringByAppendingPathComponent:@"debug-cpu.png"] atomically:YES];
        } @finally {
            if (oldDebug) [settings setObject:oldDebug forKey:@"debugCPU"];
            else [settings removeObjectForKey:@"debugCPU"];
            [settings synchronize];
        }
        if (!overlayOK) return 9;
        puts("OK: CPU debug overlay renders in the bottom-right corner.");
        puts("OK: načtení .saver, principal class, náhled, plná velikost, nastavení, kreslení a restart.");
    }
    return 0;
}
