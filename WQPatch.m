//
// WQPatch.m - reversible patch packages for WQ Files
// GPL-3.0-or-later.
//
#import "WQPatch.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import "WQRemoteSync.h"
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

static NSNumber *wq_remote_id_from_manifest(NSDictionary *manifest)
{
    id value = manifest[@"RemoteID"];
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static BOOL wq_remote_id_in_array(NSNumber *remoteID, NSArray<NSNumber *> *ids)
{
    for (NSNumber *candidate in ids) if ([candidate isEqualToNumber:remoteID]) return YES;
    return NO;
}

BOOL wq_patch_remote_needs_update(NSDictionary *remoteManifest)
{
    NSNumber *remoteID = [remoteManifest[@"id"] isKindOfClass:NSNumber.class] ? remoteManifest[@"id"] : nil;
    NSString *updatedAt = [remoteManifest[@"updatedAt"] isKindOfClass:NSString.class] ? remoteManifest[@"updatedAt"] : nil;
    if (!remoteID || !updatedAt.length) return YES;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:wq_patch_root() error:nil] ?: @[];
    for (NSString *name in names) {
        if (![name.pathExtension isEqualToString:@"wqpatch"]) continue;
        NSDictionary *manifest = wq_patch_manifest([wq_patch_root() stringByAppendingPathComponent:name]);
        NSNumber *localID = wq_remote_id_from_manifest(manifest ?: @{});
        NSString *localDate = [manifest[@"RemoteUpdatedAt"] isKindOfClass:NSString.class] ? manifest[@"RemoteUpdatedAt"] : nil;
        if ([localID isEqualToNumber:remoteID]) return ![localDate isEqualToString:updatedAt];
    }
    return YES;
}

BOOL wq_patch_import_remote(NSDictionary *remoteManifest, NSData *payload, NSString **errorText)
{
    NSNumber *remoteID = [remoteManifest[@"id"] isKindOfClass:NSNumber.class] ? remoteManifest[@"id"] : nil;
    NSString *name = [remoteManifest[@"name"] isKindOfClass:NSString.class] ? remoteManifest[@"name"] : nil;
    NSString *bundleID = [remoteManifest[@"bundleId"] isKindOfClass:NSString.class] ? remoteManifest[@"bundleId"] : nil;
    NSString *relative = [remoteManifest[@"relativePath"] isKindOfClass:NSString.class] ? remoteManifest[@"relativePath"] : nil;
    NSString *updatedAt = [remoteManifest[@"updatedAt"] isKindOfClass:NSString.class] ? remoteManifest[@"updatedAt"] : nil;
    if (!remoteID || !name.length || !bundleID.length || !wq_patch_relative_valid(relative) || [bundleID containsString:@"/"] || [bundleID containsString:@"\\"] || !payload.length) {
        if (errorText) *errorText = @"O manifesto remoto foi recusado por validação de segurança.";
        return NO;
    }
    NSString *root = wq_patch_root();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (errorText) *errorText = @"Não foi possível preparar a pasta de patches.";
        return NO;
    }
    NSString *patchPath = nil;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *fileName in names) {
        if (![fileName.pathExtension isEqualToString:@"wqpatch"]) continue;
        NSString *candidate = [root stringByAppendingPathComponent:fileName];
        NSDictionary *existing = wq_patch_manifest(candidate);
        if ([wq_remote_id_from_manifest(existing ?: @{}) isEqualToNumber:remoteID]) { patchPath = candidate; break; }
    }
    if (!patchPath) {
        NSString *directoryName = [NSString stringWithFormat:@"Remote-%@-%@.wqpatch", remoteID, wq_patch_safe_name(name)];
        patchPath = [root stringByAppendingPathComponent:directoryName];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:patchPath withIntermediateDirectories:NO attributes:nil error:nil]) {
            if (errorText) *errorText = @"Não foi possível criar o pacote remoto.";
            return NO;
        }
    }
    NSDictionary *existing = wq_patch_manifest(patchPath);
    if ([existing[@"Applied"] boolValue] && ![existing[@"RemoteUpdatedAt"] isEqual:updatedAt]) {
        if (errorText) *errorText = @"O patch remoto está aplicado; restaure-o antes de aceitar uma nova versão.";
        return NO;
    }
    NSString *payloadPath = [patchPath stringByAppendingPathComponent:kPayload];
    if (![payload writeToFile:payloadPath atomically:YES]) {
        if (errorText) *errorText = @"Não foi possível salvar o payload remoto.";
        return NO;
    }
    NSDictionary *manifest = @{
        @"Format": @1,
        @"Name": wq_patch_safe_name(name),
        @"BundleID": bundleID,
        @"RelativePath": relative,
        @"PayloadHash": wq_patch_hash(payload),
        @"Applied": @NO,
        @"CreatedAt": @([NSDate date].timeIntervalSince1970),
        @"RemoteID": remoteID,
        @"RemoteUpdatedAt": updatedAt ?: @"",
        @"RemoteCategory": remoteManifest[@"category"] ?: @"external",
        @"RemoteVariant": remoteManifest[@"variant"] ?: @"normal",
        @"Source": @"remote",
    };
    if (!wq_patch_save_manifest(manifest, patchPath, errorText)) return NO;
    return YES;
}

BOOL wq_patch_prune_remote_not_in(NSArray<NSNumber *> *activeRemoteIDs, NSString **errorText)
{
    NSString *firstError = nil;
    NSString *root = wq_patch_root();
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *name in names) {
        if (![name.pathExtension isEqualToString:@"wqpatch"]) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        NSDictionary *manifest = wq_patch_manifest(path);
        NSNumber *remoteID = wq_remote_id_from_manifest(manifest ?: @{});
        if (!remoteID || wq_remote_id_in_array(remoteID, activeRemoteIDs)) continue;
        if ([manifest[@"Applied"] boolValue]) {
            NSString *restoreError = nil;
            if (!wq_patch_restore(path, &restoreError)) { if (!firstError) firstError = restoreError; continue; }
        }
        if (![[NSFileManager defaultManager] removeItemAtPath:path error:nil] && !firstError) firstError = @"Um patch remoto saiu do manifesto, mas não pôde ser removido.";
    }
    if (errorText) *errorText = firstError;
    return firstError == nil;
}

@interface WQPatchViewController ()
@property (nonatomic, strong) NSArray<NSString *> *patches;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *menuItems;
@property (nonatomic) BOOL menuExpanded;
@end

@interface WQPatchCategoryViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol;
@end

@implementation WQPatchCategoryViewController {
    NSString *_categoryTitle;
    NSString *_categorySymbol;
}

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _categoryTitle = [title copy];
        _categorySymbol = [symbol copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = _categoryTitle;
    self.view.backgroundColor = UIColor.clearColor;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_categorySymbol]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.86];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightMedium];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = _categoryTitle;
    title.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.94];
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Área preparada para receber os patches.";
    subtitle.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.56];
    subtitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    subtitle.textAlignment = NSTextAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, subtitle]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:58],
        [icon.heightAnchor constraintEqualToConstant:58],
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
}
@end

@implementation WQPatchViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Patches";
    self.view.backgroundColor = UIColor.clearColor;
    WQParticleBackgroundView *particles = [WQParticleBackgroundView new];
    particles.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:particles atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [particles.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [particles.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [particles.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [particles.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = [[WQRemoteSync themeColorForKey:@"borderColor" fallback:UIColor.whiteColor] colorWithAlphaComponent:0.55];
    self.menuItems = @[
        @[@"Cache", @"archivebox"],
        @[@"Avatar", @"person.crop.circle"],
        @[@"Skin", @"paintbrush"],
        @[@"Holograma", @"cube.transparent"],
        @[@"EXTERNAL", @"shield.lefthalf.filled"],
    ];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPatch)];
    self.navigationItem.rightBarButtonItem = add;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(remoteManifestDidUpdate:) name:WQRemoteSyncDidUpdateNotification object:nil];
    [[WQRemoteSync shared] start];
    [self reloadPatches];
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)remoteManifestDidUpdate:(NSNotification *)notification
{
    (void)notification;
    [self reloadPatches];
}
- (void)reloadPatches
{
    dispatch_async(wq_io(), ^{
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:wq_patch_root() error:nil] ?: @[];
        NSMutableArray *paths = [NSMutableArray new];
        for (NSString *n in names) if ([n.pathExtension isEqualToString:@"wqpatch"]) [paths addObject:[wq_patch_root() stringByAppendingPathComponent:n]];
        [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent]; }];
        dispatch_async(dispatch_get_main_queue(), ^{ self.patches = paths; [self.tableView reloadData]; });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? (self.menuExpanded ? self.menuItems.count + 1 : 1) : self.patches.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"Categorias" : @"Patches";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patch"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"patch"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.backgroundColor = [WQRemoteSync themeColorForKey:@"surfaceColor" fallback:UIColor.clearColor];
    cell.contentView.backgroundColor = [WQRemoteSync themeColorForKey:@"surfaceColor" fallback:UIColor.clearColor];
    cell.textLabel.textColor = [WQRemoteSync themeColorForKey:@"textColor" fallback:[UIColor.whiteColor colorWithAlphaComponent:0.92]];
    cell.tintColor = [WQRemoteSync themeColorForKey:@"accentColor" fallback:[UIColor.whiteColor colorWithAlphaComponent:0.78]];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Menu";
            cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            cell.imageView.image = [UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"];
            cell.imageView.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.86];
            cell.accessoryType = self.menuExpanded ? UITableViewCellAccessoryDetailDisclosureButton : UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        NSArray<NSString *> *item = self.menuItems[(NSUInteger)indexPath.row - 1];
        cell.textLabel.text = item[0];
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        cell.imageView.image = [UIImage systemImageNamed:item[1]];
        cell.imageView.tintColor = [UIColor.whiteColor colorWithAlphaComponent:0.82];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSString *path = self.patches[(NSUInteger)indexPath.row]; NSDictionary *m = wq_patch_manifest(path);
    cell.textLabel.text = m[@"Name"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", m[@"BundleID"] ?: @"?", m[@"TargetFileName"] ?: m[@"RelativePath"] ?: @"?"];
    cell.detailTextLabel.textColor = [WQRemoteSync themeColorForKey:@"mutedColor" fallback:[UIColor.whiteColor colorWithAlphaComponent:0.56]];
    UISwitch *toggle = [UISwitch new]; toggle.on = wq_patch_is_applied(path); toggle.enabled = ![WQRemoteSync shared].isBlocked; toggle.tag = indexPath.row; [toggle addTarget:self action:@selector(togglePatch:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    cell.imageView.image = [UIImage systemImageNamed:toggle.on ? @"checkmark.circle.fill" : @"circle"];
    return cell;
}
- (void)togglePatch:(UISwitch *)sender
{
    if ([WQRemoteSync shared].isBlocked) {
        sender.on = !sender.isOn;
        sender.enabled = YES;
        wq_alert(self, @"Ação bloqueada", @"O app está em manutenção ou precisa da nova IPA antes de aplicar patches.");
        return;
    }
    NSInteger row = sender.tag; if (row < 0 || row >= (NSInteger)self.patches.count) return;
    NSString *path = self.patches[(NSUInteger)row]; BOOL on = sender.isOn; sender.enabled = NO;
    dispatch_async(wq_io(), ^{
        NSString *error = nil; BOOL ok = ![WQRemoteSync shared].isBlocked && (on ? wq_patch_apply(path, &error) : wq_patch_restore(path, &error));
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            if (!ok) { sender.on = !on; wq_alert(self, on ? @"Patch not applied" : @"Patch not restored", error ?: @"Unknown error"); }
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
        });
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    if (indexPath.row == 0) {
        self.menuExpanded = !self.menuExpanded;
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }
    NSArray<NSString *> *item = self.menuItems[(NSUInteger)indexPath.row - 1];
    [self.navigationController pushViewController:[[WQPatchCategoryViewController alloc] initWithTitle:item[0] symbol:item[1]] animated:YES];
}

- (void)addPatch
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Create Patch" message:@"The target is the file that will be replaced. The replacement is the file whose contents will be applied when the toggle is on." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Target path in App Data"; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Replacement file path"; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Patch name"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) {
        NSString *target = a.textFields[0].text.stringByStandardizingPath;
        NSString *replacement = a.textFields[1].text.stringByStandardizingPath;
        NSString *name = a.textFields[2].text;
        dispatch_async(wq_io(), ^{ NSString *error = nil; BOOL ok = wq_patch_create_from_file(target, replacement, name, &error); dispatch_async(dispatch_get_main_queue(), ^{ if (!ok) wq_alert(self, @"Patch not created", error ?: @"Unknown error"); else [self reloadPatches]; }); });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
