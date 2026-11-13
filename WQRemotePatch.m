#import "WQRemotePatch.h"
#import "WQPatch.h"
#import "WQAccess.h"
#import "WQUI.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kRemoteTokenKey = @"WQRemotePatchToken";
static NSString * const kRemoteHubURL = @"https://patchhub-58az32uq.manus.space";

static NSString *wq_remote_sha256(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *wq_remote_token(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kRemoteTokenKey] ?: @"";
}

static BOOL wq_remote_valid_filename(NSString *filename)
{
    return filename.length > 0 && ![filename containsString:@"/"] && ![filename containsString:@"\\"] &&
        ![filename isEqualToString:@"."] && ![filename isEqualToString:@".."] &&
        ![filename isEqualToString:@".com.apple.mobile_container_manager.metadata.plist"];
}

static BOOL wq_remote_store(NSDictionary *remote, NSData *payload, NSString **errorText)
{
    NSNumber *remoteId = remote[@"id"];
    NSString *name = remote[@"name"];
    NSString *bundleId = remote[@"bundleId"];
    NSString *targetFileName = remote[@"targetFileName"] ?: remote[@"fileName"];
    NSString *expectedHash = remote[@"sha256"];
    NSNumber *version = remote[@"version"];
    if (![remoteId isKindOfClass:NSNumber.class] || ![name isKindOfClass:NSString.class] ||
        ![bundleId isKindOfClass:NSString.class] || ![targetFileName isKindOfClass:NSString.class] ||
        ![expectedHash isKindOfClass:NSString.class] || ![version isKindOfClass:NSNumber.class] ||
        [bundleId rangeOfString:@"."].location == NSNotFound || !wq_remote_valid_filename(targetFileName)) {
        if (errorText) *errorText = @"O catálogo remoto contém um alvo inválido.";
        return NO;
    }
    NSString *actualHash = wq_remote_sha256(payload);
    if ([actualHash caseInsensitiveCompare:expectedHash] != NSOrderedSame) {
        if (errorText) *errorText = @"O hash do payload remoto não confere.";
        return NO;
    }
    NSString *safe = [NSString stringWithFormat:@"Remote_%@_%@", remoteId, name];
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    safe = [[safe componentsSeparatedByCharactersInSet:bad] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *part, NSDictionary *unused) { (void)unused; return part.length > 0; }]].componentsJoinedByString:@"-";
    if (!safe.length) safe = @"RemotePatch";
    NSString *patchPath = [wq_patch_root() stringByAppendingPathComponent:[safe stringByAppendingString:@".wqpatch"]];
    NSString *oldManifestPath = [patchPath stringByAppendingPathComponent:@"manifest.plist"];
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:oldManifestPath];
    if ([old[@"Applied"] boolValue]) {
        if ([old[@"Version"] integerValue] == version.integerValue) return YES;
        if (errorText) *errorText = [NSString stringWithFormat:@"O patch %@ está aplicado; desligue-o antes de atualizar.", name];
        return NO;
    }
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtPath:patchPath withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (errorText) *errorText = @"Não foi possível criar o diretório do patch remoto.";
        return NO;
    }
    if (![payload writeToFile:[patchPath stringByAppendingPathComponent:@"Payload.bin"] atomically:YES]) {
        if (errorText) *errorText = @"Não foi possível salvar o payload remoto.";
        return NO;
    }
    [files removeItemAtPath:[patchPath stringByAppendingPathComponent:@"Original.bin"] error:nil];
    NSDictionary *manifest = @{
        @"Format": @1,
        @"Name": name,
        @"BundleID": bundleId,
        @"RelativePath": @"",
        @"TargetFileName": targetFileName,
        @"PayloadHash": actualHash,
        @"Version": version,
        @"RemoteID": remoteId,
        @"Remote": @YES,
        @"Applied": @NO,
        @"CreatedAt": @([NSDate date].timeIntervalSince1970)
    };
    if (![manifest writeToFile:oldManifestPath atomically:YES]) {
        if (errorText) *errorText = @"Não foi possível salvar o manifesto remoto.";
        return NO;
    }
    return YES;
}

static void wq_remote_sync(NSString *token, void (^completion)(BOOL, NSString *))
{
    NSURL *endpoint = [NSURL URLWithString:[kRemoteHubURL stringByAppendingString:@"/api/patches/sync"]];
    if (!endpoint || !token.length) { completion(NO, @"Token do WQ Patch Hub não configurado."); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"WQFiles/AutoSync" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
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
            NSURL *downloadURL = [NSURL URLWithString:[kRemoteHubURL stringByAppendingString:downloadPath]];
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
            else completion(YES, [NSString stringWithFormat:@"%lu patch(es) sincronizado(s).", (unsigned long)items.count]);
        });
    }] resume];
}

static void wq_remote_ask_token(UIViewController *presenter, dispatch_block_t completion)
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ativar sincronização automática" message:@"Cole uma vez o token criado no WQ Patch Hub. A URL já está configurada e os patches serão sincronizados automaticamente." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"wqpt_..."; field.secureTextEntry = YES; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Agora não" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Salvar e sincronizar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) {
        NSString *token = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (token.length) { [[NSUserDefaults standardUserDefaults] setObject:token forKey:kRemoteTokenKey]; [[NSUserDefaults standardUserDefaults] synchronize]; wq_remote_sync(token, ^(BOOL ok, NSString *message) { if (!ok) dispatch_async(dispatch_get_main_queue(), ^{ wq_alert(presenter, @"Sincronização falhou", message); }); else if (completion) completion(); }); }
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

void wq_remote_sync_for_view(UIViewController *presenter, dispatch_block_t completion)
{
    NSString *token = wq_remote_token();
    if (!token.length) { wq_remote_ask_token(presenter, completion); return; }
    wq_remote_sync(token, ^(BOOL ok, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (!ok) wq_alert(presenter, @"Sincronização automática falhou", message); else if (completion) completion(); });
    });
}
