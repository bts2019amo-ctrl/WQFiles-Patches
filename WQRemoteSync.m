#import "WQRemoteSync.h"
#import "WQPatch.h"
#import <UIKit/UIKit.h>

NSString * const WQRemoteSyncDidUpdateNotification = @"WQRemoteSyncDidUpdateNotification";
NSString * const WQRemoteSyncDidBlockNotification = @"WQRemoteSyncDidBlockNotification";
NSString * const WQRemoteSyncDidApplyThemeNotification = @"WQRemoteSyncDidApplyThemeNotification";

@interface WQRemoteSync () <NSURLSessionDelegate>
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *etags;
@property (nonatomic) BOOL inFlight;
@property (nonatomic, copy) NSString *lastBlockFingerprint;
@end

@implementation WQRemoteSync

+ (instancetype)shared
{
    static WQRemoteSync *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [WQRemoteSync new]; });
    return instance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _etags = [NSMutableDictionary new];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
    }
    return self;
}

- (void)start
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.timer) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
        }
        [self syncNow];
    });
}

- (void)timerFired:(NSTimer *)timer
{
    (void)timer;
    [self syncNow];
}

- (NSURL *)manifestURL
{
    NSString *configured = [NSBundle.mainBundle objectForInfoDictionaryKey:@"WQRemoteManifestURL"];
    if (![configured isKindOfClass:NSString.class] || !configured.length) return nil;
    NSURL *url = [NSURL URLWithString:configured];
    if (!url || !url.scheme.length || !url.host.length) return nil;
    return url;
}

- (NSString *)currentVariant
{
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:@"WQSelectedGame"];
    return [selected isEqualToString:@"max"] ? @"max" : @"normal";
}

- (void)syncNow
{
    if (self.inFlight) return;
    NSURL *base = [self manifestURL];
    if (!base) return;
    self.inFlight = YES;
    NSString *variant = [self currentVariant];
    NSURLComponents *components = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [components.queryItems mutableCopy] ?: [NSMutableArray new];
    NSMutableArray<NSURLQueryItem *> *filteredItems = [NSMutableArray new];
    for (NSURLQueryItem *item in items) if (![item.name isEqualToString:@"variant"]) [filteredItems addObject:item];
    items = filteredItems;
    [items addObject:[NSURLQueryItem queryItemWithName:@"variant" value:variant]];
    components.queryItems = items;
    NSURL *url = components.URL;
    if (!url) { self.inFlight = NO; return; }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSString *etag = self.etags[variant];
    if (etag.length) [request setValue:etag forHTTPHeaderField:@"If-None-Match"];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.inFlight = NO;
            if (error) return;
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (http.statusCode == 304) return;
            if (http.statusCode != 200 || !data.length) return;
            NSString *responseTag = http.allHeaderFields[@"Etag"] ?: http.allHeaderFields[@"ETag"];
            if (responseTag.length) self.etags[variant] = responseTag;
            NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![manifest isKindOfClass:NSDictionary.class]) return;
            [self processManifest:manifest baseURL:url];
        });
    }];
    [task resume];
}

- (void)processManifest:(NSDictionary *)manifest baseURL:(NSURL *)baseURL
{
    NSDictionary *app = [manifest[@"app"] isKindOfClass:NSDictionary.class] ? manifest[@"app"] : @{};
    NSDictionary *update = [manifest[@"update"] isKindOfClass:NSDictionary.class] ? manifest[@"update"] : @{};
    NSDictionary *theme = [manifest[@"theme"] isKindOfClass:NSDictionary.class] ? manifest[@"theme"] : @{};
    NSArray *remotePatches = [manifest[@"patches"] isKindOfClass:NSArray.class] ? manifest[@"patches"] : @[];
    NSMutableArray<NSNumber *> *activeRemoteIDs = [NSMutableArray new];
    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *remote in remotePatches) {
        if (![remote isKindOfClass:NSDictionary.class]) continue;
        NSNumber *remoteID = [remote[@"id"] isKindOfClass:NSNumber.class] ? remote[@"id"] : nil;
        NSString *payloadURLString = [remote[@"payloadUrl"] isKindOfClass:NSString.class] ? remote[@"payloadUrl"] : nil;
        if (!remoteID || !payloadURLString.length) continue;
        [activeRemoteIDs addObject:remoteID];
        if (!wq_patch_remote_needs_update(remote)) continue;
        NSURL *payloadURL = [NSURL URLWithString:payloadURLString relativeToURL:baseURL].absoluteURL;
        if (!payloadURL) continue;
        dispatch_group_enter(group);
        NSMutableURLRequest *payloadRequest = [NSMutableURLRequest requestWithURL:payloadURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
        payloadRequest.HTTPMethod = @"GET";
        NSURLSessionDataTask *download = [self.session dataTaskWithRequest:payloadRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (!error && http.statusCode == 200 && data.length) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    NSString *message = nil;
                    if (!wq_patch_import_remote(remote, data, &message) && message.length) NSLog(@"[RemoteSync] %@", message);
                    dispatch_group_leave(group);
                });
            } else {
                dispatch_group_leave(group);
            }
        }];
        [download resume];
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *pruneError = nil;
        wq_patch_prune_remote_not_in(activeRemoteIDs, &pruneError);
        if (pruneError.length) NSLog(@"[RemoteSync] %@", pruneError);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyTheme:theme];
            [self presentBlockIfNeededWithApp:app update:update manifest:manifest];
            [[NSNotificationCenter defaultCenter] postNotificationName:WQRemoteSyncDidUpdateNotification object:self userInfo:manifest];
        });
    });
}

- (void)applyTheme:(NSDictionary *)theme
{
    if (!theme.count) return;
    UIColor *accent = [self colorFromHex:theme[@"accentColor"] fallback:UIColor.systemGreenColor];
    UIColor *background = [self colorFromHex:theme[@"backgroundColor"] fallback:UIColor.blackColor];
    UIColor *surface = [self colorFromHex:theme[@"surfaceColor"] fallback:[UIColor colorWithWhite:0.08 alpha:1.0]];
    UIColor *text = [self colorFromHex:theme[@"textColor"] fallback:UIColor.whiteColor];
    [UINavigationBar appearance].tintColor = accent;
    [UINavigationBar appearance].barTintColor = background;
    [UINavigationBar appearance].titleTextAttributes = @{ NSForegroundColorAttributeName: text };
    [UITableView appearance].backgroundColor = UIColor.clearColor;
    [UITableViewCell appearance].backgroundColor = UIColor.clearColor;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            window.tintColor = accent;
            window.backgroundColor = background;
            window.rootViewController.view.backgroundColor = background;
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:WQRemoteSyncDidApplyThemeNotification object:self userInfo:@{ @"accent": accent, @"background": background, @"surface": surface, @"text": text }];
}

- (UIColor *)colorFromHex:(id)value fallback:(UIColor *)fallback
{
    if (![value isKindOfClass:NSString.class]) return fallback;
    NSString *hex = [value substringFromIndex:[value hasPrefix:@"#"] ? 1 : 0];
    if (hex.length != 6) return fallback;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb]) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0];
}

- (UIViewController *)topViewController:(UIViewController *)controller
{
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) return [self topViewController:controller.presentedViewController];
    if ([controller isKindOfClass:UINavigationController.class]) return [self topViewController:((UINavigationController *)controller).visibleViewController];
    if ([controller isKindOfClass:UITabBarController.class]) return [self topViewController:((UITabBarController *)controller).selectedViewController];
    return controller;
}

- (void)presentBlockIfNeededWithApp:(NSDictionary *)app update:(NSDictionary *)update manifest:(NSDictionary *)manifest
{
    BOOL maintenance = [app[@"maintenanceActive"] boolValue];
    NSInteger requiredBuild = [update[@"requiredBuild"] integerValue];
    NSInteger currentBuild = [(NSNumber *)[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue];
    BOOL needsUpdate = requiredBuild > 0 && requiredBuild > currentBuild;
    if (!maintenance && !needsUpdate) return;
    NSString *kind = needsUpdate ? @"update" : @"maintenance";
    NSString *fingerprint = [NSString stringWithFormat:@"%@-%@-%@", manifest[@"manifestVersion"] ?: @"0", kind, update[@"link"] ?: @""];
    if ([fingerprint isEqualToString:self.lastBlockFingerprint]) return;
    self.lastBlockFingerprint = fingerprint;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    UIViewController *host = window ? [self topViewController:window.rootViewController] : nil;
    if (!host || host.presentedViewController) return;
    NSString *title = needsUpdate ? @"Atualização obrigatória" : @"EXTERNAL SYSTEM em manutenção";
    NSString *message = needsUpdate ? (update[@"message"] ?: @"Instale a nova IPA para continuar.") : (app[@"maintenanceMessage"] ?: @"O app está temporariamente em manutenção.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    NSString *link = [update[@"link"] isKindOfClass:NSString.class] ? update[@"link"] : nil;
    if (needsUpdate && link.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Abrir nova IPA" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:link];
            if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:WQRemoteSyncDidBlockNotification object:self userInfo:manifest];
}

@end
