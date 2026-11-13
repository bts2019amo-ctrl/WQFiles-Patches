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
