//
// WQPatch.h - reversible patch packages for WQ Files
// GPL-3.0-or-later.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *wq_patch_root(void);
BOOL wq_patch_create_from_file(NSString *targetPath, NSString *replacementPath, NSString *name, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_create_from_file_in_category(NSString *targetPath, NSString *replacementPath, NSString *name, NSString *category, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_apply(NSString *patchPath, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_restore(NSString *patchPath, NSString * _Nullable *_Nullable errorText);
BOOL wq_patch_is_applied(NSString *patchPath);

@interface WQPatchViewController : UITableViewController
- (instancetype)initWithCategory:(NSString *)category;
@end

@interface WQPatchCategoryViewController : UITableViewController
@end

void wq_remote_sync(UIViewController *host, void (^ _Nullable completion)(NSString *message));

NS_ASSUME_NONNULL_END
