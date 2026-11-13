//
// WQEntry.h
// Calculator gate and API-key login flow.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQCalculatorViewController : UIViewController
@property (nonatomic, copy) void (^onContinue)(void);
@end

@interface WQLoginViewController : UIViewController
@property (nonatomic, copy) void (^onAuthenticated)(void);
@end

NS_ASSUME_NONNULL_END
