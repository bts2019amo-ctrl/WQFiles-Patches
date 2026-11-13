#import "WQRemotePatch.h"
#import "WQPatch.h"
#import "WQAccess.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kRemoteBaseURLKey = @"WQRemotePatchBaseURL";
static NSString * const kRemoteTokenKey = @"WQRemotePatchToken";

static NSString *wq_remote_sha256(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *wq_remote_safe_name(NSString *name)
{
    NSMutableString *safe = [NSMutableString string];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        [safe appendString:[allowed characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"_"];
    }
    while ([safe hasPrefix:@"."]) [safe deleteCharactersInRange:NSMakeRange(0, 1)];
    return safe.length ? safe : @"remote_patch";
}

static NSString *wq_remote_base(void)
{
    NSString *base = [[NSUserDefaults standardUserDefaults] stringForKey:kRemoteBaseURLKey];
    return [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *wq_remote_token(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kRemoteTokenKey] ?: @"";
}

static void wq_remote_save_settings(NSString *base, NSString *token)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] forKey:kRemoteBaseURLKey];
    [defaults setObject:[token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] forKey:kRemoteTokenKey];
    [defaults synchronize];
}

static BOOL wq_remote_valid_target(NSString *bundleId, NSString *relative)
{
    if (!bundleId.length || !relative.length || [relative hasPrefix:@"/"] || [relative containsString:@"\\"]) return NO;
    NSArray *parts = [relative componentsSeparatedByString:@"/"];
    for (NSString *part in parts) if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."])
        return NO;
    return [bundleId rangeOfString:@"."].location != NSNotFound &&
        [relative.lastPathComponent isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"] == NO;
}

static BOOL wq_remote_store(NSDictionary *remote, NSData *payload, NSString **errorText)
{
    NSNumber *remoteId = remote[@"id"];
    NSString *name = remote[@"name"];
    NSString *bundleId = remote[@"bundleId"];
    NSString *relative = remote[@"relativePath"];
    NSString *expectedHash = remote[@"sha256"];
    NSNumber *version = remote[@"version"];
    if (![remoteId isKindOfClass:NSNumber.class] || ![name isKindOfClass:NSString.class] ||
        ![bundleId isKindOfClass:NSString.class] || ![relative isKindOfClass:NSString.class] ||
        ![expectedHash isKindOfClass:NSString.class] || ![version isKindOfClass:NSNumber.class] ||
        !wq_remote_valid_target(bundleId, relative)) {
        if (errorText) *errorText = @"O catálogo remoto contém um alvo inválido.";
        return NO;
    }
    NSString *actualHash = wq_remote_sha256(payload);
    if ([actualHash caseInsensitiveCompare:expectedHash] != NSOrderedSame) {
        if (errorText) *errorText = @"O hash do payload remoto não confere.";
        return NO;
    }
    NSString *safe = wq_remote_safe_name([NSString stringWithFormat:@"Remote_%@_%@", remoteId, name]);
    NSString *patchPath = [wq_patch_root() stringByAppendingPathComponent:[safe stringByAppendingString:@".wqpatch"]];
    NSDictionary *old = nil;
    NSString *oldManifest = [patchPath stringByAppendingPathComponent:@"manifest.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:oldManifest]) old = [NSDictionary dictionaryWithContentsOfFile:oldManifest];
    if ([old[@"Applied"] boolValue] && [old[@"Version"] integerValue] != version.integerValue) {
        if (errorText) *errorText = [NSString stringWithFormat:@"O patch %@ está aplicado; desligue-o antes de atualizar.", name];
        return NO;
    }
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtPath:patchPath withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (errorText) *errorText = @"Não foi possível criar o diretório do patch remoto.";
        return NO;
    }
    NSString *payloadPath = [patchPath stringByAppendingPathComponent:@"Payload.bin"];
    if (![payload writeToFile:payloadPath atomically:YES]) {
        if (errorText) *errorText = @"Não foi possível salvar o payload remoto.";
        return NO;
    }
    [files removeItemAtPath:[patchPath stringByAppendingPathComponent:@"Original.bin"] error:nil];
    NSDictionary *manifest = @{
        @"Format": @1,
        @"Name": name,
        @"BundleID": bundleId,
        @"RelativePath": relative,
        @"PayloadHash": actualHash,
        @"Version": version,
        @"RemoteID": remoteId,
        @"Remote": @YES,
        @"Applied": @NO,
        @"CreatedAt": @([NSDate date].timeIntervalSince1970)
    };
    if (![manifest writeToFile:oldManifest atomically:YES]) {
        if (errorText) *errorText = @"Não foi possível salvar o manifesto remoto.";
        return NO;
    }
    return YES;
}

static void wq_remote_sync(NSString *baseURL, NSString *token, void (^completion)(BOOL, NSString *))
{
    NSString *base = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *endpoint = [NSURL URLWithString:[base stringByAppendingString:@"/api/patches/sync"]];
    if (!endpoint || !endpoint.scheme.length || !endpoint.host.length || !token.length) {
        completion(NO, @"Informe uma URL HTTPS válida e o token do WQ Patch Hub.");
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"WQFiles/RemoteSync" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError || !data) { completion(NO, networkError.localizedDescription ?: @"Falha de conexão com o hub."); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode < 200 || http.statusCode >= 300) { completion(NO, [NSString stringWithFormat:@"O hub respondeu HTTP %ld.", (long)http.statusCode]); return; }
        NSError *jsonError = nil;
        NSDictionary *catalog = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        NSArray *items = [catalog isKindOfClass:NSDictionary.class] ? catalog[@"patches"] : nil;
        if (jsonError || ![items isKindOfClass:NSArray.class]) { completion(NO, @"Resposta inválida do catálogo remoto."); return; }
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        for (NSDictionary *remote in items) {
            if (![remote isKindOfClass:NSDictionary.class]) continue;
            NSString *downloadPath = remote[@"downloadPath"];
            NSNumber *remoteId = remote[@"id"];
            if (![downloadPath isKindOfClass:NSString.class] || ![remoteId isKindOfClass:NSNumber.class]) continue;
            NSURL *downloadURL = [NSURL URLWithString:[base stringByAppendingString:downloadPath]];
            if (!downloadURL) continue;
            dispatch_group_enter(group);
            NSMutableURLRequest *download = [NSMutableURLRequest requestWithURL:downloadURL];
            [download setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
            [[[NSURLSession sharedSession] dataTaskWithRequest:download completionHandler:^(NSData *payload, NSURLResponse *__unused downloadResponse, NSError *downloadError) {
                if (downloadError || !payload) {
                    @synchronized (errors) { [errors addObject:[NSString stringWithFormat:@"%@: download falhou", remote[@"name"] ?: remoteId]]; }
                } else {
                    NSString *storeError = nil;
                    if (!wq_remote_store(remote, payload, &storeError)) @synchronized (errors) { [errors addObject:storeError ?: @"patch remoto recusado"]; };
                }
                dispatch_group_leave(group);
            }] resume];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (errors.count) completion(NO, [errors componentsJoinedByString:@"\n"]);
            else completion(YES, [NSString stringWithFormat:@"%lu patch(es) remoto(s) sincronizado(s).", (unsigned long)items.count]);
        });
    }];
    [task resume];
}

@interface WQRemoteSyncViewController : UITableViewController
@property (nonatomic, copy) dispatch_block_t completion;
@end

@implementation WQRemoteSyncViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Remote Sync";
    self.tableView.tableFooterView = [UIView new];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(syncNow)];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"remote" ] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"remote"];
    NSString *base = wq_remote_base();
    if (indexPath.row == 0) { cell.textLabel.text = @"Hub URL"; cell.detailTextLabel.text = base.length ? base : @"Não configurado"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    else { cell.textLabel.text = @"Sincronizar patches"; cell.detailTextLabel.text = @"Baixa somente os patches publicados"; cell.accessoryType = UITableViewCellAccessoryNone; }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) [self configure]; else [self syncNow];
}
- (void)configure
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remote Sync" message:@"Cole a URL publicada do WQ Patch Hub e o token criado no painel Manus." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"https://seu-hub.manus.space"; field.text = wq_remote_base(); field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; field.keyboardType = UIKeyboardTypeURL; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"wqpt_..."; field.text = wq_remote_token(); field.secureTextEntry = YES; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar e sincronizar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) { wq_remote_save_settings(alert.textFields[0].text, alert.textFields[1].text); [self syncNow]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)syncNow
{
    NSString *base = wq_remote_base(); NSString *token = wq_remote_token();
    if (!base.length || !token.length) { [self configure]; return; }
    self.navigationItem.rightBarButtonItem.enabled = NO;
    wq_remote_sync(base, token, ^(BOOL ok, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.rightBarButtonItem.enabled = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:ok ? @"Sincronização concluída" : @"Sincronização falhou" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            if (ok && self.completion) self.completion();
            [self.tableView reloadData];
        });
    });
}
@end

void wq_remote_present_sync(UIViewController *presenter, dispatch_block_t completion)
{
    WQRemoteSyncViewController *controller = [WQRemoteSyncViewController new];
    controller.completion = completion;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    [presenter presentViewController:navigation animated:YES completion:nil];
}
