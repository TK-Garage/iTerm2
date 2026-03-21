//
//  iTermStatusBarPlaceholderComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 09/03/19.
//

#import "iTermStatusBarPlaceholderComponent.h"

#define ITLocalizedMenuString(key) NSLocalizedStringFromTableInBundle(key, @"iTerm", [NSBundle bundleForClass:[self class]], nil)

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarPlaceholderComponent

- (NSString *)statusBarComponentShortDescription {
    return ITLocalizedMenuString(@"Placeholder");
}

- (NSString *)statusBarComponentDetailedDescription {
    return ITLocalizedMenuString(@"Placeholder");
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    assert(NO);
    return @"";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (BOOL)statusBarComponentIsInternal {
    return YES;
}

- (nullable NSString *)stringValue {
    return ITLocalizedMenuString(@"Click here to configure status bar");
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ?: @"" ];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self.delegate statusBarComponentOpenStatusBarPreferences:self];
}

- (BOOL)statusBarComponentIsEmpty {
    // This is used to ensure there is at least one component, so it mustn't be hidden due to emptiness.
    return NO;
}

@end

NS_ASSUME_NONNULL_END
