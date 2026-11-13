//
// WQPatch.h - reversible patch packages for WQ Files
// GPL-3.0-or-later.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *wq_patch_root(void);
BOOL wq_patch_create_from_file(NSString *targetPath, NSString *replacementPath, NSString *name, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_apply(NSString *patchPath, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_restore(NSString *patchPath, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_is_applied(NSString *patchPath);
BOOL wq_patch_remote_needs_update(NSDictionary *remoteManifest);
BOOL wq_patch_import_remote(NSDictionary *remoteManifest, NSData *payload, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_prune_remote_not_in(NSArray<NSNumber *> *activeRemoteIDs, NSString * _Nullable *_Nullable errorText);

@interface WQPatchViewController : UITableViewController
@end

NS_ASSUME_NONNULL_END
