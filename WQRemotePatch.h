#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Opens the remote catalog settings and downloads enabled patches into the local patch catalog.
void wq_remote_present_sync(UIViewController *presenter, dispatch_block_t _Nullable completion);

NS_ASSUME_NONNULL_END
