#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WQGateHostControllerDelegate <NSObject>
- (void)wqGateDidFinishWithGame:(NSString *)game;
@end

@interface WQGateHostController : UIViewController
@property (nonatomic, weak, nullable) id<WQGateHostControllerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
