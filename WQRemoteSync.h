#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const WQRemoteSyncDidUpdateNotification;
FOUNDATION_EXPORT NSString * const WQRemoteSyncDidBlockNotification;
FOUNDATION_EXPORT NSString * const WQRemoteSyncDidApplyThemeNotification;

@interface WQRemoteSync : NSObject
+ (instancetype)shared;
- (void)start;
- (void)syncNow;
@end

NS_ASSUME_NONNULL_END
