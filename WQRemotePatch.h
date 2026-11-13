#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Uses the built-in public WQ Patch Hub URL and syncs enabled patches silently.
void wq_remote_sync_for_view(UIViewController *presenter, dispatch_block_t _Nullable completion);

NS_ASSUME_NONNULL_END
