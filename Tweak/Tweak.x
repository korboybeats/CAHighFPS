#define CHECK_TARGET

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

// Helper function to convert Hex color string to UIColor
static UIColor *colorFromHexString(NSString *hexString) {
    if (!hexString || [hexString isEqualToString:@""]) {
        return [UIColor redColor]; // Fallback color
    }
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    if ([hexString hasPrefix:@"#"]) {
        scanner.scanLocation = 1; // bypass '#' character
    }
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

// Static variables to hold preference values for performance
static BOOL customFpsEnabled;
static CGFloat customFPSValue;
static int fpsMode;

// Other static variables
static NSInteger maxFPS = -1;
static CGFloat rangeMin;
static CGFloat rangeMax;

static NSInteger getMaxFPS() {
    if (customFpsEnabled) {
        return (NSInteger)customFPSValue;
    }
    
    if (maxFPS == -1) {
        maxFPS = [UIScreen mainScreen].maximumFramesPerSecond;
    }
    return maxFPS;
}

static BOOL isEnabledApp() {
    NSString* bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    NSDictionary *prefs = [[NSDictionary alloc] initWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.ps.cahighfps.plist"];
    id appValue = prefs[@"App"];
    if (appValue && [appValue isKindOfClass:[NSArray class]]) {
        return [appValue containsObject:bundleIdentifier];
    }
    return NO;
}

// MARK: CADisplayLink

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
%group 1
%hook CADisplayLink

- (void)setFrameInterval:(NSInteger)interval {
    %orig(1);
    self.preferredFramesPerSecond = 0;
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(0);
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    CGFloat max = getMaxFPS();
    if(customFpsEnabled) {
        range.preferred = customFPSValue;
        range.maximum = customFPSValue;
        if (customFPSValue <= 30) {
            range.minimum = 20;
        } else {
            range.minimum = 30;
        }
    } else { 
        range.preferred = max;
        range.maximum = max;
        range.minimum = 30;
    }
    rangeMin = range.minimum;
    rangeMax = range.maximum;
    %orig;
}

%end
%end //1

#pragma clang diagnostic pop

// MARK: CAMetalLayer
%group 2
%hook CAMetalLayer

- (NSUInteger)maximumDrawableCount {
    return 2;
}

- (void)setMaximumDrawableCount:(NSUInteger)count {
    %orig(2);
}

%end
%end //2
// MARK: Metal Advanced Hack
%group 3
%hook CAMetalDrawable

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
	%orig(1.0 / getMaxFPS());
}

%end

%hook MTLCommandBuffer

- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)minimumDuration {
    %orig(drawable, 1.0 / getMaxFPS());
}

%end
%end //group3

//fpsindicator
static dispatch_source_t _timer;
static UILabel *fpsLabel;
double FPSavg = 0;
double FPSPerSecond = 0;

static void loadPref() {
    NSLog(@"[CAHighFPS] Reloading preferences.");
    NSDictionary *prefs = [[NSDictionary alloc] initWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.ps.cahighfps.plist"];
    
    // Load values into high-performance static variables
    customFpsEnabled = [prefs[@"customFpsEnabled"] boolValue];
    customFPSValue = [prefs[@"customFPS"] doubleValue];
    fpsMode = [prefs[@"fpsMode"] intValue];
    if (fpsMode == 0) fpsMode = 1; // Compatibility for older versions

    NSString *colorString = prefs[@"fpsLabelColor"];
    UIColor *color = colorFromHexString(colorString);

    if (fpsLabel) {
        [fpsLabel setTextColor:color];
    }
}

static void startRefreshTimer() {
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, dispatch_walltime(NULL, 0), (1.0/5.0) * NSEC_PER_SEC, 0);

    dispatch_source_set_event_handler(_timer, ^{
        switch(fpsMode) {
            case 1: // Average FPS
                [fpsLabel setText:[NSString stringWithFormat:@"%.1lf / %ld", FPSavg, getMaxFPS()]];
                break;
            case 2: // Per-Second FPS
                [fpsLabel setText:[NSString stringWithFormat:@"%.1lf / %ld", FPSPerSecond, getMaxFPS()]];
                break;
            default:
                break;
        }
    });
    dispatch_resume(_timer); 
}

// MARK: UI
#define kFPSLabelWidth 150
#define kFPSLabelHeight 20
%group ui
%hook UIWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect bounds = [self bounds];
        CGFloat safeOffsetY = 0;
        CGFloat safeOffsetX = 0;
        if (@available(iOS 11.0, *)) {
            if (self.frame.size.width < self.frame.size.height) {
                safeOffsetY = self.safeAreaInsets.top + 5;
            } else {
                safeOffsetX = self.safeAreaInsets.right;
            }
        }
        fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(bounds.size.width - kFPSLabelWidth - 5 - safeOffsetX, safeOffsetY, kFPSLabelWidth, kFPSLabelHeight)];
        fpsLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:16];
        fpsLabel.textAlignment = NSTextAlignmentRight;
        fpsLabel.userInteractionEnabled = NO;
        
        [self addSubview:fpsLabel];
        
        // Load prefs to set initial color
        loadPref();
        startRefreshTimer();
    });
    return %orig;
}
%end
%end//ui

// credits to https://github.com/masagrator/NX-FPS/blob/master/source/main.cpp#L64
void frameTick() {
    static double FPS_temp = 0;
    static double starttick = 0;
    static double endtick = 0;
    static double deltatick = 0;
    static double frameend = 0;
    static double framedelta = 0;
    static double frameavg = 0;

    if (starttick == 0) starttick = CACurrentMediaTime() * 1000.0;
    endtick = CACurrentMediaTime() * 1000.0;
    framedelta = endtick - frameend;
    frameavg = ((9 * frameavg) + framedelta) / 10;
    if (frameavg > 0) {
        FPSavg = 1000.0f / (double)frameavg;
    }
    frameend = endtick;

    FPS_temp++;
    deltatick = endtick - starttick;
    if (deltatick >= 1000.0f) {
        starttick = CACurrentMediaTime() * 1000.0;
        FPSPerSecond = FPS_temp - 1;
        FPS_temp = 0;
    }
}

// MARK: Graphics Hooks
%group gl
%hook EAGLContext 
- (BOOL)presentRenderbuffer:(NSUInteger)target {
    BOOL ret = %orig;
    frameTick();
    return ret;
}
%end
%end//gl

%group metal
%hook CAMetalDrawable
- (void)present {
    %orig;
    frameTick();
}
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    %orig;
    frameTick();
}
- (void)presentAtTime:(CFTimeInterval)presentationTime {
    %orig;
    frameTick();
}
%end //CAMetalDrawable
%end//metal

%ctor {
    @autoreleasepool {
        NSString *settingsPath = @"/var/jb/var/mobile/Library/Preferences/com.ps.cahighfps.plist";
        NSDictionary *defaults = @{
            @"customFpsEnabled": @NO,
            @"customFPS": @60,
            @"fpsMode": @1,
            @"fpsLabelColor": @"#FF0000" // Default red color
        };

        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:settingsPath];
        if (!prefs) {
            prefs = [NSMutableDictionary dictionaryWithDictionary:defaults];
            [prefs writeToFile:settingsPath atomically:YES];
        } else {
            BOOL needsUpdate = NO;
            for (NSString *key in defaults.allKeys) {
                if (!prefs[key]) {
                    prefs[key] = defaults[key];
                    needsUpdate = YES;
                }
            }
            if (needsUpdate) {
                [prefs writeToFile:settingsPath atomically:YES];
            }
        }

        loadPref();

        if (isEnabledApp()) {
            %init(1);
            %init(2);
            %init(3);
            %init(ui);
            %init(gl);
            %init(metal);
        }

        int token = 0;
        notify_register_dispatch("com.ps.cahighfps/loadPref", &token, dispatch_get_main_queue(), ^(int token) {
            loadPref();
        });
    }
}