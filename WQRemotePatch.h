#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Uses the built-in WQ Patch Hub URL, asks for the token once if needed, and syncs silently afterward.
void wq_remote_sync_for_view(UIViewController *presenter, dispatch_block_t _Nullable completion);

NS_ASSUME_NONNULL_END
