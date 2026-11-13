#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const WQParticleStyleNameKey;
FOUNDATION_EXPORT NSString * const WQAppearanceModeKey;
FOUNDATION_EXPORT NSString *WQParticleStyleName(void);
FOUNDATION_EXPORT NSArray<NSString *> *WQParticleStyleNames(void);
FOUNDATION_EXPORT void WQSetParticleStyleName(NSString *name);
FOUNDATION_EXPORT NSString *WQAppearanceModeName(void);
FOUNDATION_EXPORT void WQSetAppearanceModeName(NSString *name);

@interface WQParticleView : UIView
- (void)refreshStyle;
@end
NS_ASSUME_NONNULL_END
