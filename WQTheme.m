#import "WQTheme.h"

NSString * const WQAccentColorDidChangeNotification = @"WQAccentColorDidChangeNotification";
NSString * const WQAccentColorNameKey = @"WQAccentColorName";

static NSDictionary<NSString *, UIColor *> *WQAccentPalette(void)
{
    return @{
        @"blue": UIColor.systemBlueColor,
        @"purple": UIColor.systemPurpleColor,
        @"teal": UIColor.systemTealColor,
        @"orange": UIColor.systemOrangeColor,
        @"pink": UIColor.systemPinkColor,
        @"mint": UIColor.systemMintColor,
        @"indigo": UIColor.systemIndigoColor,
        @"red": UIColor.systemRedColor,
        @"yellow": UIColor.systemYellowColor,
    };
}

NSArray<NSString *> *WQAccentColorNames(void)
{
    return @[@"blue", @"purple", @"teal", @"orange", @"pink", @"mint", @"indigo", @"red", @"yellow"];
}

NSString *WQAccentColorName(void)
{
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:WQAccentColorNameKey];
    return [WQAccentPalette()[value] isKindOfClass:UIColor.class] ? value : @"blue";
}

UIColor *WQAccentColorForName(NSString *name)
{
    return WQAccentPalette()[name] ?: UIColor.systemBlueColor;
}

UIColor *WQAccentColor(void)
{
    return WQAccentColorForName(WQAccentColorName());
}

void WQSetAccentColorName(NSString *name)
{
    if (![WQAccentPalette()[name] isKindOfClass:UIColor.class]) name = @"blue";
    [NSUserDefaults.standardUserDefaults setObject:name forKey:WQAccentColorNameKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WQAccentColorDidChangeNotification object:name];
}

UIImage *WQProfessionalIcon(NSString *symbolName, UIColor *color, CGSize size)
{
    if (!symbolName.length || size.width <= 0 || size.height <= 0) return nil;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:MIN(size.width, size.height) * 0.43 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleMedium];
    UIImage *symbol = [[UIImage systemImageNamed:symbolName withConfiguration:configuration] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!symbol) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        CGRect rect = (CGRect){CGPointZero, size};
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 1, 1) cornerRadius:MIN(size.width, size.height) * 0.24];
        [color setFill];
        [path fill];
        CGRect symbolRect = CGRectMake((size.width - symbol.size.width) / 2.0, (size.height - symbol.size.height) / 2.0, symbol.size.width, symbol.size.height);
        [symbol drawInRect:symbolRect];
    }];
}
