#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const WQAccentColorDidChangeNotification;
FOUNDATION_EXPORT NSString * const WQAccentColorNameKey;

FOUNDATION_EXPORT UIColor *WQAccentColor(void);
FOUNDATION_EXPORT UIColor *WQAccentColorForName(NSString *name);
FOUNDATION_EXPORT NSString *WQAccentColorName(void);
FOUNDATION_EXPORT NSArray<NSString *> *WQAccentColorNames(void);
FOUNDATION_EXPORT void WQSetAccentColorName(NSString *name);
FOUNDATION_EXPORT UIImage *WQProfessionalIcon(NSString *symbolName, UIColor *color, CGSize size);

NS_ASSUME_NONNULL_END
