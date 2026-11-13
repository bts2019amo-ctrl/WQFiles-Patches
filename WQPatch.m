//
// WQPatch.m - reversible patch packages for WQ Files
// GPL-3.0-or-later.
//
#import "WQPatch.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const kManifest = @"manifest.plist";
static NSString *const kPayload = @"Payload.bin";
static NSString *const kOriginal = @"Original.bin";

static NSString *wq_patch_safe_name(NSString *name)
{
    NSMutableString *s = [name mutableCopy];
    [s replaceOccurrencesOfString:@"/" withString:@"-" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\\" withString:@"-" options:0 range:NSMakeRange(0, s.length)];
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSArray *parts = [s componentsSeparatedByCharactersInSet:bad];
    NSArray *nonEmpty = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *unused) { (void)unused; return p.length > 0; }]];
    NSString *joined = [nonEmpty componentsJoinedByString:@"-"];
    return joined.length ? [joined substringToIndex:MIN(joined.length, 80)] : @"Patch";
}

static NSString *wq_patch_hash(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

NSString *wq_patch_root(void)
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"Patches"];
}

static BOOL wq_patch_relative_valid(NSString *relative)
{
    if (!relative.length || [relative hasPrefix:@"/"]) return NO;
    for (NSString *part in [relative pathComponents]) {
        if ([part isEqualToString:@"."] || [part isEqualToString:@".."] || !part.length) return NO;
    }
    return YES;
}

static NSString *wq_patch_container_for_file(NSString *path, NSString **bundleOut)
{
    NSString *candidate = [path stringByStandardizingPath];
    while (candidate.length > 1) {
        NSString *bid = wq_bundle_id_for_container(candidate);
        if (!bid.length) bid = wq_container_label(candidate);
        if (bid.length && ![bid containsString:@"/"]) {
            if (bundleOut) *bundleOut = bid;
            return candidate;
        }
        NSString *parent = candidate.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:candidate]) break;
        candidate = parent;
    }
    NSArray *containers = wq_ls_container_paths(nil);
    for (NSString *root in containers) {
        NSString *r = [root stringByStandardizingPath];
        NSString *prefix = [r stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            NSString *bid = wq_bundle_id_for_container(r) ?: wq_container_label(r);
            if (bid.length) { if (bundleOut) *bundleOut = bid; return r; }
        }
    }
    return nil;
}

static NSDictionary *wq_patch_manifest(NSString *patchPath)
{
    NSDictionary *m = [NSDictionary dictionaryWithContentsOfFile:[patchPath stringByAppendingPathComponent:kManifest]];
    return [m isKindOfClass:NSDictionary.class] ? m : nil;
}

static BOOL wq_patch_save_manifest(NSDictionary *manifest, NSString *patchPath, NSString **errorText)
{
    NSString *path = [patchPath stringByAppendingPathComponent:kManifest];
    if (![manifest writeToFile:path atomically:YES]) {
        if (errorText) *errorText = @"Could not save the patch state.";
        return NO;
    }
    return YES;
}

static NSString *wq_patch_target(NSDictionary *manifest, NSString **errorText)
{
    NSString *bid = manifest[@"BundleID"];
    NSString *relative = manifest[@"RelativePath"];
    NSString *targetFileName = manifest[@"TargetFileName"];
    if (![bid isKindOfClass:NSString.class] || !bid.length) {
        if (errorText) *errorText = @"The patch manifest has an invalid Bundle ID or path.";
        return nil;
    }
    if ([targetFileName isKindOfClass:NSString.class] && targetFileName.length) {
        NSMutableArray<NSString *> *matches = [NSMutableArray array];
        for (NSString *root in wq_ls_container_paths(nil)) {
            NSString *normalizedRoot = root.stringByStandardizingPath;
            NSString *found = wq_bundle_id_for_container(normalizedRoot) ?: wq_container_label(normalizedRoot);
            if (![found isEqualToString:bid]) continue;
            NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithObject:normalizedRoot];
            NSUInteger visited = 0;
            while (pending.count && visited++ < 10000) {
                NSString *directory = pending.firstObject;
                [pending removeObjectAtIndex:0];
                for (NSString *child in wq_list(directory, nil) ?: @[]) {
                    struct stat st;
                    if (!wq_stat(child, &st)) continue;
                    if (S_ISREG(st.st_mode) && [child.lastPathComponent isEqualToString:targetFileName]) [matches addObject:child];
                    else if (S_ISDIR(st.st_mode)) [pending addObject:child];
                }
            }
        }
        if (matches.count == 1) return matches.firstObject;
        if (matches.count > 1) { if (errorText) *errorText = [NSString stringWithFormat:@"Mais de um arquivo %@ foi encontrado no app; o patch foi recusado por segurança.", targetFileName]; return nil; }
        if (errorText) *errorText = [NSString stringWithFormat:@"Não foi encontrado nenhum arquivo %@ no Bundle ID %@.", targetFileName, bid];
        return nil;
    }
    if (!wq_patch_relative_valid(relative)) {
        if (errorText) *errorText = @"The patch manifest has an invalid Bundle ID or path.";
        return nil;
    }
    NSString *savedContainer = [manifest[@"ContainerPath"] isKindOfClass:NSString.class] ? [manifest[@"ContainerPath"] stringByStandardizingPath] : nil;
    if (savedContainer.length) {
        struct stat st;
        NSString *savedTarget = [savedContainer stringByAppendingPathComponent:relative];
        if (wq_stat(savedTarget, &st) && S_ISREG(st.st_mode)) return savedTarget;
    }
    NSArray *containers = wq_ls_container_paths(nil);
    for (NSString *root in containers) {
        NSString *normalizedRoot = root.stringByStandardizingPath;
        NSString *found = wq_bundle_id_for_container(normalizedRoot) ?: wq_container_label(normalizedRoot);
        if ([found isEqualToString:bid]) return [normalizedRoot stringByAppendingPathComponent:relative];
    }
    if (errorText) *errorText = [NSString stringWithFormat:@"Could not find the container for %@.", bid];
    return nil;
}

BOOL wq_patch_create_from_file(NSString *targetPath, NSString *replacementPath, NSString *name, NSString **errorText)
{
    targetPath = targetPath.stringByStandardizingPath;
    replacementPath = replacementPath.stringByStandardizingPath;
    if ([targetPath.lastPathComponent isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"]) {
        if (errorText) *errorText = @"This is an iOS container metadata file, not app data. Choose a file inside Documents or Library.";
        return NO;
    }
    struct stat st;
    if (!wq_stat(targetPath, &st) || !S_ISREG(st.st_mode)) { if (errorText) *errorText = @"The target must be a regular file inside an app container."; return NO; }
    struct stat replacementStat;
    if (!wq_stat(replacementPath, &replacementStat) || !S_ISREG(replacementStat.st_mode)) { if (errorText) *errorText = @"The replacement must be an existing regular file."; return NO; }
    NSString *bid = nil;
    NSString *container = wq_patch_container_for_file(targetPath, &bid);
    if (!container || !bid.length) { if (errorText) *errorText = @"Could not identify this app container. Open the app's data folder first."; return NO; }
    NSString *prefix = [container stringByAppendingString:@"/"];
    if (![targetPath hasPrefix:prefix]) { if (errorText) *errorText = @"The selected target is not inside the identified container."; return NO; }
    NSString *relative = [targetPath substringFromIndex:prefix.length];
    if (!wq_patch_relative_valid(relative)) { if (errorText) *errorText = @"The selected path cannot be used in a patch."; return NO; }
    NSString *safe = wq_patch_safe_name(name.length ? name : targetPath.lastPathComponent);
    NSString *root = wq_patch_root();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) { if (errorText) *errorText = @"Could not create the Patches folder."; return NO; }
    NSString *patch = [root stringByAppendingPathComponent:[safe stringByAppendingString:@".wqpatch"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:patch]) { if (errorText) *errorText = @"A patch with that name already exists."; return NO; }
    if (![[NSFileManager defaultManager] createDirectoryAtPath:patch withIntermediateDirectories:NO attributes:nil error:nil]) { if (errorText) *errorText = @"Could not create the patch folder."; return NO; }
    NSString *payload = [patch stringByAppendingPathComponent:kPayload];
    NSString *copyError = nil;
    if (!wq_copy_to_local(replacementPath, payload, &copyError)) {
        [[NSFileManager defaultManager] removeItemAtPath:patch error:nil];
        if (errorText) *errorText = copyError ?: @"Could not copy the selected file into the patch.";
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:payload];
    NSDictionary *manifest = @{ @"Format": @1, @"Name": safe, @"BundleID": bid,
                                @"ContainerPath": container,
                                @"RelativePath": relative, @"PayloadHash": wq_patch_hash(data ?: NSData.data),
                                @"Applied": @NO, @"CreatedAt": @([NSDate date].timeIntervalSince1970) };
    if (!wq_patch_save_manifest(manifest, patch, errorText)) { [[NSFileManager defaultManager] removeItemAtPath:patch error:nil]; return NO; }
    wq_log(@"patch created: %@ (%@/%@) replacement=%@", safe, bid, relative, replacementPath);
    return YES;
}

static BOOL wq_patch_set_state(NSString *patchPath, BOOL applied, NSString *originalHash, NSString **errorText)
{
    NSMutableDictionary *m = [wq_patch_manifest(patchPath) mutableCopy];
    if (!m) { if (errorText) *errorText = @"The patch manifest is missing or invalid."; return NO; }
    m[@"Applied"] = @(applied);
    if (originalHash) m[@"OriginalHash"] = originalHash;
    return wq_patch_save_manifest(m, patchPath, errorText);
}

BOOL wq_patch_apply(NSString *patchPath, NSString **errorText)
{
    NSDictionary *m = wq_patch_manifest(patchPath);
    NSString *target = wq_patch_target(m ?: @{}, errorText);
    if (!target) return NO;
    NSData *payload = [NSData dataWithContentsOfFile:[patchPath stringByAppendingPathComponent:kPayload]];
    if (!payload) { if (errorText) *errorText = @"The patch payload is missing or unreadable."; return NO; }
    NSData *current = wq_read(target, 0, errorText);
    if (!current) return NO;
    NSString *expected = m[@"PayloadHash"];
    if ([m[@"Applied"] boolValue]) {
        if (![wq_patch_hash(current) isEqualToString:expected]) { if (errorText) *errorText = @"The patch is marked active, but the target was changed externally."; return NO; }
        return YES;
    }
    NSString *patchOriginal = [patchPath stringByAppendingPathComponent:kOriginal];
    if (![current writeToFile:patchOriginal atomically:YES]) { if (errorText) *errorText = @"Could not save the original file inside the patch."; return NO; }
    if (!wq_write(target, payload, errorText)) { [[NSFileManager defaultManager] removeItemAtPath:patchOriginal error:nil]; return NO; }
    if (!wq_patch_set_state(patchPath, YES, wq_patch_hash(current), errorText)) return NO;
    wq_log(@"patch applied: %@ -> %@", m[@"Name"] ?: patchPath.lastPathComponent, target);
    return YES;
}

BOOL wq_patch_restore(NSString *patchPath, NSString **errorText)
{
    NSDictionary *m = wq_patch_manifest(patchPath);
    NSString *target = wq_patch_target(m ?: @{}, errorText);
    if (!target) return NO;
    if (![m[@"Applied"] boolValue]) return YES;
    NSData *payload = [NSData dataWithContentsOfFile:[patchPath stringByAppendingPathComponent:kPayload]];
    NSData *original = [NSData dataWithContentsOfFile:[patchPath stringByAppendingPathComponent:kOriginal]];
    NSData *current = wq_read(target, 0, errorText);
    if (!payload || !original || !current) { if (errorText && !*errorText) *errorText = @"The patch backup is missing."; return NO; }
    if (![wq_patch_hash(current) isEqualToString:m[@"PayloadHash"]]) { if (errorText) *errorText = @"The target changed after the patch was applied; restore was refused."; return NO; }
    if (!wq_write(target, original, errorText)) return NO;
    if (!wq_patch_set_state(patchPath, NO, nil, errorText)) return NO;
    wq_log(@"patch restored: %@", m[@"Name"] ?: patchPath.lastPathComponent);
    return YES;
}

BOOL wq_patch_is_applied(NSString *patchPath)
{
    return [wq_patch_manifest(patchPath)[@"Applied"] boolValue];
}


@interface WQDashedCardView : UIView
@end
@implementation WQDashedCardView
- (void)layoutSubviews
{
    [super layoutSubviews];
    CAShapeLayer *dash = (CAShapeLayer *)[self.layer.sublayers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CALayer *obj, NSDictionary *_) { return [obj.name isEqualToString:@"wq_dash"]; }]].firstObject;
    if (!dash) {
        dash = [CAShapeLayer layer];
        dash.name = @"wq_dash";
        dash.fillColor = UIColor.clearColor.CGColor;
        dash.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.24].CGColor;
        dash.lineWidth = 1.0;
        dash.lineDashPattern = @[@5, @5];
        [self.layer addSublayer:dash];
    }
    dash.frame = self.bounds;
    dash.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 1, 1) cornerRadius:18].CGPath;
}
@end

@interface WQQuickMenuViewController : UIViewController
- (instancetype)initWithItems:(NSArray<NSArray<NSString *> *> *)items selection:(void (^)(NSString *))selection;
@end

@implementation WQQuickMenuViewController {
    NSArray<NSArray<NSString *> *> *_items;
    void (^_selection)(NSString *);
}
- (instancetype)initWithItems:(NSArray<NSArray<NSString *> *> *)items selection:(void (^)(NSString *))selection
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _items = [items copy];
        _selection = [selection copy];
    }
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.055 blue:0.065 alpha:0.98];
    UIView *grabber = [UIView new];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.32];
    grabber.layer.cornerRadius = 2.5;
    [self.view addSubview:grabber];
    UILabel *eyebrow = [UILabel new];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = @"NAVEGAÇÃO RÁPIDA";
    eyebrow.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    eyebrow.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.55];
    eyebrow.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:eyebrow];
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Escolha uma categoria";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    title.textColor = UIColor.whiteColor;
    [self.view addSubview:title];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    [self.view addSubview:stack];
    for (NSArray<NSString *> *item in _items) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = [_items indexOfObject:item];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [button addTarget:self action:@selector(selectCategory:) forControlEvents:UIControlEventTouchUpInside];
        UIView *row = [UIView new];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *name = [UILabel new];
        name.translatesAutoresizingMaskIntoConstraints = NO;
        name.text = item[0];
        name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        name.textColor = UIColor.whiteColor;
        UILabel *detail = [UILabel new];
        detail.translatesAutoresizingMaskIntoConstraints = NO;
        detail.text = item[1];
        detail.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        detail.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.52];
        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.right"]];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        arrow.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.62];
        [row addSubview:name]; [row addSubview:detail]; [row addSubview:arrow]; [row addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [name.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
            [detail.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [detail.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],
            [arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor], [arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [button.leadingAnchor constraintEqualToAnchor:row.leadingAnchor], [button.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [button.topAnchor constraintEqualToAnchor:row.topAnchor], [button.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [row.heightAnchor constraintEqualToConstant:66]
        ]];
        [stack addArrangedSubview:row];
        if (item != _items.lastObject) {
            UIView *line = [UIView new]; line.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.10];
            [stack addArrangedSubview:line]; [line.heightAnchor constraintEqualToConstant:1].active = YES;
        }
    }
    [NSLayoutConstraint activateConstraints:@[
        [grabber.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:9], [grabber.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [grabber.widthAnchor constraintEqualToConstant:38], [grabber.heightAnchor constraintEqualToConstant:5],
        [eyebrow.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:22], [eyebrow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [eyebrow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6], [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14], [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24], [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
}
- (void)selectCategory:(UIButton *)sender
{
    NSString *category = _items[(NSUInteger)sender.tag][0];
    [self dismissViewControllerAnimated:YES completion:^{ if (self->_selection) self->_selection(category); }];
}
@end

@interface WQPatchViewController : UITableViewController
@end
@implementation WQPatchViewController {
    UILabel *_categoryLabel;
    UILabel *_countLabel;
    UILabel *_instructionLabel;
    WQDashedCardView *_emptyCard;
    NSString *_selectedCategory;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    _selectedCategory = @"Avatar";
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.scrollEnabled = NO;
    UILabel *navTitle = [UILabel new];
    navTitle.text = @"3105 REMOTE PATCHES";
    navTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    navTitle.textColor = UIColor.whiteColor;
    self.navigationItem.titleView = navTitle;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"] style:UIBarButtonItemStylePlain target:self action:@selector(showQuickMenu)];
    UIButton *keyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [keyButton setTitle:@"  TROCAR KEY" forState:UIControlStateNormal];
    [keyButton setImage:[UIImage systemImageNamed:@"key.fill"] forState:UIControlStateNormal];
    keyButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [keyButton setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.82] forState:UIControlStateNormal];
    keyButton.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.82];
    keyButton.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.09];
    keyButton.layer.cornerRadius = 8;
    keyButton.contentEdgeInsets = UIEdgeInsetsMake(7, 9, 7, 9);
    [keyButton addTarget:self action:@selector(changeKey) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:keyButton];
    _categoryLabel = [UILabel new]; _categoryLabel.translatesAutoresizingMaskIntoConstraints = NO; _categoryLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold]; _categoryLabel.textColor = UIColor.whiteColor; _categoryLabel.text = @"PATCHES DE AVATAR";
    _countLabel = [UILabel new]; _countLabel.translatesAutoresizingMaskIntoConstraints = NO; _countLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; _countLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.52]; _countLabel.text = @"0 REMOTOS"; _countLabel.textAlignment = NSTextAlignmentRight;
    _instructionLabel = [UILabel new]; _instructionLabel.translatesAutoresizingMaskIntoConstraints = NO; _instructionLabel.font = [UIFont systemFontOfSize:12]; _instructionLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.48]; _instructionLabel.text = @"Toque em um patch para ver os controles. Você pode ativá-lo ou restaurar o original."; _instructionLabel.numberOfLines = 0;
    _emptyCard = [WQDashedCardView new]; _emptyCard.translatesAutoresizingMaskIntoConstraints = NO; _emptyCard.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.025]; _emptyCard.layer.cornerRadius = 18;
    UIImageView *cube = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cube.transparent"]]; cube.translatesAutoresizingMaskIntoConstraints = NO; cube.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.38]; cube.contentMode = UIViewContentModeScaleAspectFit;
    UILabel *emptyTitle = [UILabel new]; emptyTitle.translatesAutoresizingMaskIntoConstraints = NO; emptyTitle.text = @"Nenhum patch nesta categoria ainda"; emptyTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; emptyTitle.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.88]; emptyTitle.textAlignment = NSTextAlignmentCenter;
    UILabel *emptyDetail = [UILabel new]; emptyDetail.translatesAutoresizingMaskIntoConstraints = NO; emptyDetail.text = @"Atualize a lista de patches e permaneça nesta categoria para acompanhar novos itens."; emptyDetail.font = [UIFont systemFontOfSize:13]; emptyDetail.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.48]; emptyDetail.textAlignment = NSTextAlignmentCenter; emptyDetail.numberOfLines = 0;
    [self.view addSubview:_categoryLabel]; [self.view addSubview:_countLabel]; [self.view addSubview:_instructionLabel]; [self.view addSubview:_emptyCard]; [_emptyCard addSubview:cube]; [_emptyCard addSubview:emptyTitle]; [_emptyCard addSubview:emptyDetail];
    [NSLayoutConstraint activateConstraints:@[
        [_categoryLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:22], [_categoryLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_countLabel.centerYAnchor constraintEqualToAnchor:_categoryLabel.centerYAnchor], [_countLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_instructionLabel.topAnchor constraintEqualToAnchor:_categoryLabel.bottomAnchor constant:8], [_instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22], [_instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_emptyCard.topAnchor constraintEqualToAnchor:_instructionLabel.bottomAnchor constant:22], [_emptyCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22], [_emptyCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22], [_emptyCard.heightAnchor constraintEqualToConstant:250],
        [cube.centerXAnchor constraintEqualToAnchor:_emptyCard.centerXAnchor], [cube.topAnchor constraintEqualToAnchor:_emptyCard.topAnchor constant:48], [cube.widthAnchor constraintEqualToConstant:48], [cube.heightAnchor constraintEqualToConstant:48],
        [emptyTitle.topAnchor constraintEqualToAnchor:cube.bottomAnchor constant:18], [emptyTitle.leadingAnchor constraintEqualToAnchor:_emptyCard.leadingAnchor constant:20], [emptyTitle.trailingAnchor constraintEqualToAnchor:_emptyCard.trailingAnchor constant:-20],
        [emptyDetail.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:9], [emptyDetail.leadingAnchor constraintEqualToAnchor:_emptyCard.leadingAnchor constant:30], [emptyDetail.trailingAnchor constraintEqualToAnchor:_emptyCard.trailingAnchor constant:-30]
    ]];
}
- (void)showQuickMenu
{
    NSArray *items = @[@[@"Avatar", @"Patches de avatar"], @[@"Holograma", @"Patches de holograma"], @[@"Cache", @"Patches de cache"], @[@"Skin", @"Patches de skin"]];
    __weak typeof(self) weakSelf = self;
    WQQuickMenuViewController *menu = [[WQQuickMenuViewController alloc] initWithItems:items selection:^(NSString *category) { [weakSelf selectCategory:category]; }];
    menu.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) { UISheetPresentationController *sheet = menu.sheetPresentationController; sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent]]; sheet.prefersGrabberVisible = YES; sheet.preferredCornerRadius = 22; }
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)selectCategory:(NSString *)category
{
    _selectedCategory = category;
    _categoryLabel.text = [NSString stringWithFormat:@"PATCHES DE %@", category.uppercaseString];
}
- (void)changeKey { }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 0; }
@end
