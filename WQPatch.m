//
// WQPatch.m - reversible patch packages for WQ Files
// GPL-3.0-or-later.
//
#import "WQPatch.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQUI.h"
#import "WQSettings.h"
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

BOOL wq_patch_create_from_file_in_category(NSString *targetPath, NSString *replacementPath, NSString *name, NSString *category, NSString **errorText)
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
    NSDictionary *manifest = @{ @"Format": @1, @"Name": safe, @"Category": category.length ? category : @"External", @"BundleID": bid,
                                @"ContainerPath": container,
                                @"RelativePath": relative, @"PayloadHash": wq_patch_hash(data ?: NSData.data),
                                @"Applied": @NO, @"CreatedAt": @([NSDate date].timeIntervalSince1970) };
    if (!wq_patch_save_manifest(manifest, patch, errorText)) { [[NSFileManager defaultManager] removeItemAtPath:patch error:nil]; return NO; }
    wq_log(@"patch created: %@ (%@/%@) replacement=%@", safe, bid, relative, replacementPath);
    return YES;
}

BOOL wq_patch_create_from_file(NSString *targetPath, NSString *replacementPath, NSString *name, NSString **errorText)
{
    return wq_patch_create_from_file_in_category(targetPath, replacementPath, name, @"External", errorText);
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

@interface WQPatchViewController ()
@property (nonatomic, strong) NSArray<NSString *> *patches;
@property (nonatomic, copy) NSString *category;
@end

@implementation WQPatchViewController
- (instancetype)initWithCategory:(NSString *)category
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) self.category = category.length ? category : @"External";
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.category ?: @"Patches";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 82.0;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 60.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPatch)];
    self.navigationItem.rightBarButtonItem = add;
    [self reloadPatches];
}
- (void)openSettings
{
    [self.navigationController pushViewController:[WQSettingsViewController new] animated:YES];
}
- (void)reloadPatches
{
    dispatch_async(wq_io(), ^{
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:wq_patch_root() error:nil] ?: @[];
        NSMutableArray *paths = [NSMutableArray new];
        for (NSString *n in names) if ([n.pathExtension isEqualToString:@"wqpatch"]) {
            NSString *path = [wq_patch_root() stringByAppendingPathComponent:n];
            NSDictionary *manifest = wq_patch_manifest(path);
            NSString *category = manifest[@"Category"] ?: @"External";
            if ([category isEqualToString:self.category]) [paths addObject:path];
        }
        [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent]; }];
        dispatch_async(dispatch_get_main_queue(), ^{ self.patches = paths; [self.tableView reloadData]; });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.patches.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patch"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"patch"];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.layer.cornerRadius = 16.0;
    cell.layer.masksToBounds = YES;
    cell.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    NSString *path = self.patches[(NSUInteger)indexPath.row]; NSDictionary *m = wq_patch_manifest(path);
    cell.textLabel.text = m[@"Name"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", m[@"BundleID"] ?: @"?", m[@"TargetFileName"] ?: m[@"RelativePath"] ?: @"?"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    UISwitch *toggle = [UISwitch new]; toggle.on = wq_patch_is_applied(path); toggle.tag = indexPath.row; toggle.onTintColor = UIColor.systemBlueColor; [toggle addTarget:self action:@selector(togglePatch:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    cell.imageView.image = [UIImage systemImageNamed:toggle.on ? @"checkmark.seal.fill" : @"wand.and.stars"] ?: [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
    cell.imageView.tintColor = toggle.on ? UIColor.systemGreenColor : UIColor.systemBlueColor;
    return cell;
}
- (void)togglePatch:(UISwitch *)sender
{
    NSInteger row = sender.tag; if (row < 0 || row >= (NSInteger)self.patches.count) return;
    NSString *path = self.patches[(NSUInteger)row]; BOOL on = sender.isOn; sender.enabled = NO;
    dispatch_async(wq_io(), ^{
        NSString *error = nil; BOOL ok = on ? wq_patch_apply(path, &error) : wq_patch_restore(path, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            if (!ok) { sender.on = !on; wq_alert(self, on ? @"Patch not applied" : @"Patch not restored", error ?: @"Unknown error"); }
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        });
    });
}
- (void)addPatch
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Novo patch · %@", self.category] message:@"O arquivo-alvo será substituído pelo arquivo escolhido quando o toggle estiver ativado." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Target path in App Data"; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Replacement file path"; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"Patch name"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) {
        NSString *target = a.textFields[0].text.stringByStandardizingPath;
        NSString *replacement = a.textFields[1].text.stringByStandardizingPath;
        NSString *name = a.textFields[2].text;
        dispatch_async(wq_io(), ^{ NSString *error = nil; BOOL ok = wq_patch_create_from_file_in_category(target, replacement, name, self.category, &error); dispatch_async(dispatch_get_main_queue(), ^{ if (!ok) wq_alert(self, @"Patch não criado", error ?: @"Erro desconhecido"); else [self reloadPatches]; }); });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end


@implementation WQPatchCategoryViewController
- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"Patches";
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(syncRemote)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 82.0;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self syncRemote];
}
- (void)syncRemote
{
    self.navigationItem.rightBarButtonItem.enabled = NO;
    wq_remote_sync(self, ^(NSString *message) {
        (void)message;
        self.navigationItem.rightBarButtonItem.enabled = YES;
    });
}
- (NSArray *)categories
{
    return @[
        @[@"Cache", @"Arquivos temporários e dados armazenados", @"internaldrive.fill", UIColor.systemOrangeColor],
        @[@"Avatar", @"Personalização de avatar", @"person.crop.circle.fill", UIColor.systemBlueColor],
        @[@"Skin", @"Visual e aparência", @"paintpalette.fill", UIColor.systemPurpleColor],
        @[@"Holograma", @"Efeitos holográficos", @"sparkles", UIColor.systemTealColor],
        @[@"External", @"Patches externos e outros arquivos", @"externaldrive.fill", UIColor.systemGreenColor]
    ];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.categories.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Categorias de patches"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Entre em uma categoria para adicionar, ativar ou restaurar seus patches."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"category"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"category"];
    NSArray *row = self.categories[(NSUInteger)indexPath.row];
    cell.textLabel.text = row[0]; cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = row[1]; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.detailTextLabel.numberOfLines = 0;
    cell.imageView.image = [UIImage systemImageNamed:row[2]]; cell.imageView.tintColor = row[3];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *category = self.categories[(NSUInteger)indexPath.row][0];
    [self.navigationController pushViewController:[[WQPatchViewController alloc] initWithCategory:category] animated:YES];
}
@end


void wq_remote_sync(UIViewController *host, void (^completion)(NSString *message))
{
    (void)host;
    NSURL *catalogURL = [NSURL URLWithString:@"https://patchhub-58az32uq.manus.space/api/patches/public-sync"];
    if (!catalogURL) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@"URL do catálogo inválida."); }); return; }
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:catalogURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data || ![(NSHTTPURLResponse *)response isKindOfClass:NSHTTPURLResponse.class] || [(NSHTTPURLResponse *)response statusCode] != 200) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error.localizedDescription ?: @"Não foi possível consultar o catálogo remoto."); });
            return;
        }
        NSError *jsonError = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        NSArray *items = [root isKindOfClass:NSDictionary.class] && [root[@"patches"] isKindOfClass:NSArray.class] ? root[@"patches"] : nil;
        if (!items) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(jsonError.localizedDescription ?: @"Resposta remota inválida."); }); return; }
        dispatch_async(wq_io(), ^{
            NSString *rootPath = wq_patch_root();
            [[NSFileManager defaultManager] createDirectoryAtPath:rootPath withIntermediateDirectories:YES attributes:nil error:nil];
            NSMutableSet *remoteIDs = [NSMutableSet set];
            NSUInteger synced = 0;
            for (NSDictionary *item in items) {
                NSNumber *remoteID = item[@"id"];
                NSString *name = item[@"name"], *category = item[@"category"], *bundleID = item[@"bundleId"], *relative = item[@"relativePath"], *fileName = item[@"fileName"], *downloadPath = item[@"downloadPath"];
                if (![remoteID isKindOfClass:NSNumber.class] || !name.length || !bundleID.length || (!relative.length && !fileName.length) || !fileName.length || !downloadPath.length) continue;
                [remoteIDs addObject:remoteID.stringValue];
                NSURL *payloadURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://patchhub-58az32uq.manus.space%@", downloadPath]];
                if (!payloadURL) continue;
                NSURLRequest *request = [NSURLRequest requestWithURL:payloadURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:45.0];
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                __block NSData *payload = nil;
                __block NSInteger status = 0;
                NSURLSessionDataTask *download = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { (void)e; payload = d; status = [(NSHTTPURLResponse *)r statusCode]; dispatch_semaphore_signal(sem); }];
                [download resume];
                dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_SEC)));
                if (!payload.length || status != 200) continue;
                NSString *safe = wq_patch_safe_name(name);
                NSString *patchPath = [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"remote-%@-%@.wqpatch", remoteID, safe]];
                NSString *oldManifestPath = [patchPath stringByAppendingPathComponent:kManifest];
                NSDictionary *old = wq_patch_manifest(patchPath);
                BOOL wasApplied = [old[@"Applied"] boolValue];
                if (wasApplied && ![old[@"PayloadHash"] isEqualToString:wq_patch_hash(payload)]) {
                    NSString *restoreError = nil;
                    if (!wq_patch_restore(patchPath, &restoreError)) continue;
                    wasApplied = NO;
                }
                [[NSFileManager defaultManager] createDirectoryAtPath:patchPath withIntermediateDirectories:YES attributes:nil error:nil];
                if (![payload writeToFile:[patchPath stringByAppendingPathComponent:kPayload] options:NSDataWritingAtomic error:nil]) continue;
                NSDictionary *manifest = @{ @"Format": @1, @"Name": name, @"Category": category.length ? category : @"External", @"BundleID": bundleID, @"RelativePath": relative, @"TargetFileName": fileName, @"PayloadHash": wq_patch_hash(payload), @"Applied": @(wasApplied), @"RemoteID": remoteID, @"RemoteVersion": item[@"version"] ?: @1, @"CreatedAt": @([NSDate date].timeIntervalSince1970) };
                if ([manifest writeToFile:oldManifestPath atomically:YES]) synced++;
            }
            NSArray *localNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil] ?: @[];
            for (NSString *n in localNames) if ([n.pathExtension isEqualToString:@"wqpatch"]) {
                NSString *path = [rootPath stringByAppendingPathComponent:n];
                NSDictionary *manifest = wq_patch_manifest(path);
                NSString *remoteID = [manifest[@"RemoteID"] description];
                if (remoteID.length && ![remoteIDs containsObject:remoteID]) {
                    if ([manifest[@"Applied"] boolValue]) { NSString *restoreError = nil; if (!wq_patch_restore(path, &restoreError)) continue; }
                    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                }
            }
            NSString *message = [NSString stringWithFormat:@"%lu patch(es) sincronizado(s). Patches em manutenção ou despublicados não aparecem no app.", (unsigned long)synced];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(message); });
        });
    }];
    [task resume];
}
