#import "WQRemoteSync.h"
#import "WQPatch.h"
#import <UIKit/UIKit.h>
#import <math.h>

NSString * const WQRemoteSyncDidUpdateNotification = @"WQRemoteSyncDidUpdateNotification";
NSString * const WQRemoteSyncDidBlockNotification = @"WQRemoteSyncDidBlockNotification";
NSString * const WQRemoteSyncDidApplyThemeNotification = @"WQRemoteSyncDidApplyThemeNotification";

static NSString * const WQRemoteThemePrefix = @"WQRemoteTheme.";

@interface WQRemoteSync ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *etags;
@property (nonatomic, strong) NSURLSessionDataTask *currentTask;
@property (nonatomic) BOOL inFlight;
@property (nonatomic) BOOL blocked;
@property (nonatomic, copy) NSString *lastBlockFingerprint;
@property (nonatomic) NSUInteger consecutiveFailures;
@property (nonatomic, strong) NSDate *nextAllowedSyncDate;
@property (nonatomic) BOOL observingLifecycle;
@end

@implementation WQRemoteSync

+ (instancetype)shared
{
    static WQRemoteSync *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [WQRemoteSync new]; });
    return instance;
}

+ (UIColor *)themeColorForKey:(NSString *)key fallback:(UIColor *)fallback
{
    NSString *hex = [NSUserDefaults.standardUserDefaults stringForKey:[WQRemoteThemePrefix stringByAppendingString:key]];
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *normalized = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
    if (normalized.length != 6) return fallback;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:normalized];
    if (![scanner scanHexInt:&rgb]) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0];
}

+ (CGFloat)themeCornerRadius
{
    NSString *radius = [NSUserDefaults.standardUserDefaults stringForKey:[WQRemoteThemePrefix stringByAppendingString:@"radius"]];
    if ([radius isEqualToString:@"12px"]) return 12.0;
    if ([radius isEqualToString:@"24px"]) return 24.0;
    return 18.0;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _etags = [NSMutableDictionary new];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)start
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.observingLifecycle) {
            self.observingLifecycle = YES;
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
            [center addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
        }
        if (!self.timer) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
        }
        [self syncNow];
    });
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    (void)notification;
    [self.timer invalidate];
    self.timer = nil;
    [self.currentTask cancel];
    self.currentTask = nil;
    self.inFlight = NO;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    (void)notification;
    self.consecutiveFailures = 0;
    self.nextAllowedSyncDate = nil;
    [self start];
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

- (void)noteSyncFailure
{
    self.consecutiveFailures = MIN(self.consecutiveFailures + 1, (NSUInteger)5);
    NSTimeInterval delay = pow(2.0, (double)self.consecutiveFailures - 1.0);
    self.nextAllowedSyncDate = [NSDate dateWithTimeIntervalSinceNow:MIN(delay, 30.0)];
}

- (void)noteSyncSuccess
{
    self.consecutiveFailures = 0;
    self.nextAllowedSyncDate = nil;
}

- (void)syncNow
{
    if (self.inFlight) return;
    if (self.nextAllowedSyncDate && [self.nextAllowedSyncDate timeIntervalSinceNow] > 0) return;
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
    self.currentTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentTask = nil;
            self.inFlight = NO;
            if (error) { [self noteSyncFailure]; return; }
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (http.statusCode == 304) { [self noteSyncSuccess]; return; }
            if (http.statusCode != 200 || !data.length) { [self noteSyncFailure]; return; }
            NSString *responseTag = http.allHeaderFields[@"Etag"] ?: http.allHeaderFields[@"ETag"];
            if (responseTag.length) self.etags[variant] = responseTag;
            NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![manifest isKindOfClass:NSDictionary.class]) { [self noteSyncFailure]; return; }
            [self noteSyncSuccess];
            [self processManifest:manifest baseURL:url];
        });
    }];
    [self.currentTask resume];
}

- (BOOL)version:(NSString *)current meetsTarget:(NSString *)target
{
    if (!target.length) return YES;
    NSArray<NSString *> *currentParts = [current componentsSeparatedByString:@"."];
    NSArray<NSString *> *targetParts = [target componentsSeparatedByString:@"."];
    NSUInteger count = MAX(currentParts.count, targetParts.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSInteger currentValue = index < currentParts.count ? [currentParts[index] integerValue] : 0;
        NSInteger targetValue = index < targetParts.count ? [targetParts[index] integerValue] : 0;
        if (currentValue != targetValue) return currentValue > targetValue;
    }
    return YES;
}

- (BOOL)manifestNeedsBlockWithApp:(NSDictionary *)app update:(NSDictionary *)update
{
    BOOL maintenance = [app[@"maintenanceActive"] boolValue];
    NSInteger requiredBuild = [update[@"requiredBuild"] integerValue];
    NSInteger currentBuild = [(NSNumber *)[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue];
    NSString *targetVersion = [update[@"version"] isKindOfClass:NSString.class] ? update[@"version"] : @"";
    NSString *currentVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    BOOL needsUpdate = (requiredBuild > 0 && requiredBuild > currentBuild) || (targetVersion.length && ![self version:currentVersion ?: @"0" meetsTarget:targetVersion]);
    return maintenance || needsUpdate;
}

- (void)processManifest:(NSDictionary *)manifest baseURL:(NSURL *)baseURL
{
    NSDictionary *app = [manifest[@"app"] isKindOfClass:NSDictionary.class] ? manifest[@"app"] : @{};
    NSDictionary *update = [manifest[@"update"] isKindOfClass:NSDictionary.class] ? manifest[@"update"] : @{};
    NSDictionary *theme = [manifest[@"theme"] isKindOfClass:NSDictionary.class] ? manifest[@"theme"] : @{};
    NSArray *remotePatches = [manifest[@"patches"] isKindOfClass:NSArray.class] ? manifest[@"patches"] : @[];
    self.blocked = [self manifestNeedsBlockWithApp:app update:update];
    NSMutableArray<NSNumber *> *activeRemoteIDs = [NSMutableArray new];
    dispatch_group_t group = dispatch_group_create();

    if (!self.blocked) {
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
    NSDictionary<NSString *, NSString *> *defaults = @{
        @"accentColor": @"#a3ff12",
        @"backgroundColor": @"#07100d",
        @"surfaceColor": @"#0d1b16",
        @"textColor": @"#f1f7f2",
        @"mutedColor": @"#8da69a",
        @"borderColor": @"#234238",
        @"radius": @"18px",
    };
    NSMutableDictionary *resolved = [NSMutableDictionary new];
    for (NSString *key in defaults) {
        NSString *value = [theme[key] isKindOfClass:NSString.class] ? theme[key] : defaults[key];
        if ([key hasSuffix:@"Color"] && ![self colorFromHex:value fallback:nil]) value = defaults[key];
        if ([key isEqualToString:@"radius"] && ![@[@"12px", @"18px", @"24px"] containsObject:value]) value = defaults[key];
        resolved[key] = value;
        [NSUserDefaults.standardUserDefaults setObject:value forKey:[WQRemoteThemePrefix stringByAppendingString:key]];
    }
    UIColor *accent = [self colorFromHex:resolved[@"accentColor"] fallback:UIColor.systemGreenColor];
    UIColor *background = [self colorFromHex:resolved[@"backgroundColor"] fallback:UIColor.blackColor];
    UIColor *surface = [self colorFromHex:resolved[@"surfaceColor"] fallback:[UIColor colorWithWhite:0.08 alpha:1.0]];
    UIColor *text = [self colorFromHex:resolved[@"textColor"] fallback:UIColor.whiteColor];
    UIColor *muted = [self colorFromHex:resolved[@"mutedColor"] fallback:[UIColor colorWithWhite:0.65 alpha:1.0]];
    UIColor *border = [self colorFromHex:resolved[@"borderColor"] fallback:[UIColor colorWithWhite:0.2 alpha:1.0]];
    [UINavigationBar appearance].tintColor = accent;
    [UINavigationBar appearance].barTintColor = background;
    [UINavigationBar appearance].titleTextAttributes = @{ NSForegroundColorAttributeName: text };
    [UITableView appearance].backgroundColor = background;
    [UITableView appearance].separatorColor = [border colorWithAlphaComponent:0.55];
    [UITableViewCell appearance].backgroundColor = surface;
    [UILabel appearance].textColor = text;
    [UITextField appearance].textColor = text;
    [UITextView appearance].textColor = text;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            window.tintColor = accent;
            window.backgroundColor = background;
            window.rootViewController.view.backgroundColor = background;
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:WQRemoteSyncDidApplyThemeNotification object:self userInfo:@{ @"accent": accent, @"background": background, @"surface": surface, @"text": text, @"muted": muted, @"border": border, @"radius": resolved[@"radius"] }];
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
    if (!self.blocked) return;
    BOOL maintenance = [app[@"maintenanceActive"] boolValue];
    NSString *title = maintenance ? @"EXTERNAL SYSTEM em manutenção" : @"Atualização obrigatória";
    NSString *message = maintenance ? (app[@"maintenanceMessage"] ?: @"O app está temporariamente em manutenção.") : (update[@"message"] ?: @"Instale a nova IPA para continuar.");
    NSString *kind = maintenance ? @"maintenance" : @"update";
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    NSString *link = [update[@"link"] isKindOfClass:NSString.class] ? update[@"link"] : nil;
    if (!maintenance && link.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Abrir nova IPA" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:link];
            if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:maintenance ? @"Entendi" : @"Abrir depois" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:WQRemoteSyncDidBlockNotification object:self userInfo:manifest];
}

@end
