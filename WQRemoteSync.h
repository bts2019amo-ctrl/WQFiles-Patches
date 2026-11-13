#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const WQRemoteSyncDidUpdateNotification;
FOUNDATION_EXPORT NSString * const WQRemoteSyncDidBlockNotification;
FOUNDATION_EXPORT NSString * const WQRemoteSyncDidApplyThemeNotification;

@interface WQRemoteSync : NSObject
@property (nonatomic, readonly, getter=isBlocked) BOOL blocked;
+ (instancetype)shared;
+ (UIColor *)themeColorForKey:(NSString *)key fallback:(UIColor *)fallback;
+ (CGFloat)themeCornerRadius;
- (void)start;
- (void)syncNow;
@end

NS_ASSUME_NONNULL_END
