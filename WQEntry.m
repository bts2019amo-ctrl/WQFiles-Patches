//
// WQEntry.m
// Calculator gate and API-key login flow.
// GPL-3.0-or-later.
//
#import "WQEntry.h"
#import <Security/Security.h>

#pragma mark - Calculator

@interface WQCalculatorViewController ()
@property (nonatomic, strong) UILabel *display;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@property (nonatomic) double storedValue;
@property (nonatomic) NSInteger operation;
@property (nonatomic) BOOL waitingForInput;
@property (nonatomic, copy) NSString *currentInput;
@end

@implementation WQCalculatorViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.currentInput = @"0";
    self.history = [NSMutableArray new];
    [self buildCalculator];
}

- (void)buildCalculator
{
    UILabel *brand = [UILabel new];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.text = @"WQ  /  CALCULATOR";
    brand.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    brand.textColor = [UIColor colorWithWhite:1 alpha:0.52];
    brand.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:brand];

    UIButton *history = [UIButton buttonWithType:UIButtonTypeSystem];
    history.translatesAutoresizingMaskIntoConstraints = NO;
    [history setImage:[UIImage systemImageNamed:@"clock"] forState:UIControlStateNormal];
    history.tintColor = [UIColor colorWithWhite:1 alpha:0.82];
    history.accessibilityLabel = @"History";
    [history addTarget:self action:@selector(showHistory) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:history];

    UIButton *mode = [UIButton buttonWithType:UIButtonTypeSystem];
    mode.translatesAutoresizingMaskIntoConstraints = NO;
    [mode setImage:[UIImage systemImageNamed:@"function"] forState:UIControlStateNormal];
    mode.tintColor = [UIColor colorWithWhite:1 alpha:0.82];
    mode.accessibilityLabel = @"Calculator modes";
    [mode addTarget:self action:@selector(showModeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:mode];

    self.modeLabel = [UILabel new];
    self.modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeLabel.text = @"BÁSICA";
    self.modeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    self.modeLabel.textColor = [UIColor colorWithWhite:1 alpha:0.48];
    self.modeLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.modeLabel];

    self.display = [UILabel new];
    self.display.translatesAutoresizingMaskIntoConstraints = NO;
    self.display.text = @"0";
    self.display.textColor = UIColor.whiteColor;
    self.display.font = [UIFont systemFontOfSize:72 weight:UIFontWeightLight];
    self.display.adjustsFontSizeToFitWidth = YES;
    self.display.minimumScaleFactor = 0.28;
    self.display.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:self.display];

    NSArray *rows = @[
        @[@"⌫", @"AC", @"%", @"÷"],
        @[@"7", @"8", @"9", @"×"],
        @[@"4", @"5", @"6", @"−"],
        @[@"1", @"2", @"3", @"+"],
        @[@"+/−", @"0", @",", @"="]
    ];
    UIStackView *keypad = [[UIStackView alloc] initWithFrame:CGRectZero];
    keypad.translatesAutoresizingMaskIntoConstraints = NO;
    keypad.axis = UILayoutConstraintAxisVertical;
    keypad.spacing = 9;
    keypad.distribution = UIStackViewDistributionFillEqually;
    [self.view addSubview:keypad];
    for (NSArray *row in rows) {
        UIStackView *line = [[UIStackView alloc] initWithFrame:CGRectZero];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 9;
        line.distribution = UIStackViewDistributionFillEqually;
        for (NSString *title in row) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.translatesAutoresizingMaskIntoConstraints = NO;
            button.tag = [row indexOfObject:title];
            button.accessibilityLabel = title;
            [button setTitle:title forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:[title isEqualToString:@"+/−"] ? 22 : 31 weight:UIFontWeightRegular];
            BOOL isOperator = [@[@"÷", @"×", @"−", @"+", @"="] containsObject:title];
            BOOL isFunction = [@[@"⌫", @"AC", @"%"] containsObject:title];
            UIColor *color = isOperator ? [UIColor colorWithRed:1 green:0.584 blue:0 alpha:1]
                : isFunction ? [UIColor colorWithWhite:0.64 alpha:1]
                : [UIColor colorWithRed:0.20 green:0.20 blue:0.20 alpha:1];
            [button setTitleColor:isFunction ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
            button.backgroundColor = color;
            button.layer.cornerRadius = 45;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            button.accessibilityTraits = UIAccessibilityTraitButton;
            [button addTarget:self action:@selector(keyPressed:) forControlEvents:UIControlEventTouchUpInside];
            [line addArrangedSubview:button];
        }
        [keypad addArrangedSubview:line];
    }
    UIButton *continueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    continueButton.translatesAutoresizingMaskIntoConstraints = NO;
    [continueButton setTitle:@"Entrar no WQ Files  →" forState:UIControlStateNormal];
    [continueButton setTitleColor:[UIColor colorWithRed:0.35 green:0.78 blue:1 alpha:1] forState:UIControlStateNormal];
    continueButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [continueButton addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:continueButton];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [brand.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10], [brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [history.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18], [history.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:18],
        [history.widthAnchor constraintEqualToConstant:42], [history.heightAnchor constraintEqualToConstant:42],
        [mode.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18], [mode.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:18],
        [mode.widthAnchor constraintEqualToConstant:42], [mode.heightAnchor constraintEqualToConstant:42],
        [self.modeLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [self.modeLabel.centerYAnchor constraintEqualToAnchor:mode.centerYAnchor],
        [self.display.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28], [self.display.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
        [self.display.topAnchor constraintEqualToAnchor:history.bottomAnchor constant:18], [self.display.heightAnchor constraintEqualToConstant:86],
        [keypad.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14], [keypad.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14],
        [keypad.bottomAnchor constraintEqualToAnchor:continueButton.topAnchor constant:-8], [keypad.heightAnchor constraintEqualToConstant:5 * 78 + 4 * 9],
        [continueButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [continueButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [continueButton.heightAnchor constraintEqualToConstant:32]
    ]];
}

- (void)continueTapped
{
    if (self.onContinue) self.onContinue();
}

- (void)showHistory
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Histórico" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (!self.history.count) alert.message = @"Nenhum cálculo salvo ainda.";
    for (NSString *entry in self.history) [alert addAction:[UIAlertAction actionWithTitle:entry style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Limpar histórico" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *__unused a) { [self.history removeAllObjects]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showModeMenu
{
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Modo da calculadora" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Básica" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) { self.modeLabel.text = @"BÁSICA"; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Científica" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) { self.modeLabel.text = @"CIENTÍFICA"; [self scientificPrompt]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Conversão BRL ↔ EUR" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) { self.modeLabel.text = @"CONVERSÃO"; [self conversionPrompt]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)scientificPrompt
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Científica" message:@"Digite um número e escolha a operação." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Número"; field.keyboardType = UIKeyboardTypeDecimalPad; }];
    NSArray *operations = @[@"√x", @"x²", @"sen", @"cos", @"tg", @"ln"];
    for (NSString *operation in operations) {
        [alert addAction:[UIAlertAction actionWithTitle:operation style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) {
            double value = alert.textFields.firstObject.text.doubleValue, result = 0;
            if ([operation isEqualToString:@"√x"]) result = value >= 0 ? sqrt(value) : 0;
            else if ([operation isEqualToString:@"x²"]) result = pow(value, 2);
            else if ([operation isEqualToString:@"sen"]) result = sin(value);
            else if ([operation isEqualToString:@"cos"]) result = cos(value);
            else if ([operation isEqualToString:@"tg"]) result = tan(value);
            else result = value > 0 ? log(value) : 0;
            self.currentInput = [self formatted:result]; self.display.text = [self.currentInput stringByReplacingOccurrencesOfString:@"." withString:@","];
            [self.history insertObject:[NSString stringWithFormat:@"%@(%g) = %@", operation, value, self.display.text] atIndex:0];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)conversionPrompt
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Conversão BRL ↔ EUR" message:@"Taxa demonstrativa: 1 EUR = R$ 6,00" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Valor"; field.keyboardType = UIKeyboardTypeDecimalPad; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"BRL → EUR" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) { [self convertValue:alert.textFields.firstObject.text.doubleValue divisor:6.0 label:@"BRL → EUR"]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"EUR → BRL" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused action) { [self convertValue:alert.textFields.firstObject.text.doubleValue divisor:1.0 label:@"EUR → BRL"]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)convertValue:(double)value divisor:(double)divisor label:(NSString *)label
{
    double result = [label hasPrefix:@"BRL"] ? value / divisor : value * 6.0;
    self.currentInput = [self formatted:result]; self.display.text = [self.currentInput stringByReplacingOccurrencesOfString:@"." withString:@","];
    [self.history insertObject:[NSString stringWithFormat:@"%@ = %@", label, self.display.text] atIndex:0];
}

- (void)keyPressed:(UIButton *)sender
{
    NSString *key = sender.currentTitle ?: @"";
    if ([key isEqualToString:@"AC"]) { self.currentInput = @"0"; self.storedValue = 0; self.operation = 0; self.waitingForInput = NO; }
    else if ([key isEqualToString:@"⌫"]) { if (self.currentInput.length > 1) self.currentInput = [self.currentInput substringToIndex:self.currentInput.length - 1]; else self.currentInput = @"0"; }
    else if ([key isEqualToString:@"%"]) { self.currentInput = [self formatted:[self.currentInput doubleValue] / 100.0]; }
    else if ([key isEqualToString:@"+/−"]) { if (![self.currentInput isEqualToString:@"0"]) self.currentInput = [self.currentInput hasPrefix:@"-"] ? [self.currentInput substringFromIndex:1] : [@"-" stringByAppendingString:self.currentInput]; }
    else if ([key isEqualToString:@","]) { if (![self.currentInput containsString:@"."]) self.currentInput = [self.currentInput stringByAppendingString:@"."]; }
    else if ([@[@"÷", @"×", @"−", @"+"] containsObject:key]) { self.storedValue = self.currentInput.doubleValue; self.operation = [@[@"÷", @"×", @"−", @"+"] indexOfObject:key] + 1; self.waitingForInput = YES; }
    else if ([key isEqualToString:@"="]) { [self calculate]; }
    else if (key.length) { if (self.waitingForInput) { self.currentInput = key; self.waitingForInput = NO; } else if ([self.currentInput isEqualToString:@"0"]) self.currentInput = key; else if (self.currentInput.length < 14) self.currentInput = [self.currentInput stringByAppendingString:key]; }
    self.display.text = [self.currentInput stringByReplacingOccurrencesOfString:@"." withString:@","];
}

- (void)calculate
{
    double rhs = self.currentInput.doubleValue, result = self.storedValue;
    switch (self.operation) { case 1: result = rhs == 0 ? 0 : self.storedValue / rhs; break; case 2: result = self.storedValue * rhs; break; case 3: result = self.storedValue - rhs; break; case 4: result = self.storedValue + rhs; break; default: return; }
    NSString *before = self.currentInput;
    self.currentInput = [self formatted:result]; self.waitingForInput = YES; self.operation = 0;
    [self.history insertObject:[NSString stringWithFormat:@"%@ = %@", before, self.currentInput] atIndex:0];
    if (self.history.count > 20) [self.history removeLastObject];
}

- (NSString *)formatted:(double)value
{
    NSNumberFormatter *f = [NSNumberFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"pt_BR"]; f.maximumFractionDigits = 8; f.minimumFractionDigits = 0; f.usesGroupingSeparator = NO;
    return [f stringFromNumber:@(value)] ?: @"0";
}
@end

#pragma mark - Login

static NSString *const WQKeychainService = @"cz.kolbi.wqfiles.api-key";
static NSString *const WQKeychainAccount = @"license-key";
static NSString *const WQKeyEndpoint = @"https://proxysystem.org/api/trpc/proxyKeys.publicCheckKey";

@interface WQLoginViewController ()
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation WQLoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *eyebrow = [UILabel new]; eyebrow.text = @"WQ FILES"; eyebrow.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold]; eyebrow.textColor = UIColor.systemBlueColor; eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *title = [UILabel new]; title.text = @"Unlock your workspace"; title.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold]; title.numberOfLines = 0; title.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *subtitle = [UILabel new]; subtitle.text = @"Digite sua chave de acesso para continuar com as ferramentas de arquivos e patches."; subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; subtitle.textColor = UIColor.secondaryLabelColor; subtitle.numberOfLines = 0; subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyField = [UITextField new]; self.keyField.translatesAutoresizingMaskIntoConstraints = NO; self.keyField.placeholder = @"Chave iOS"; self.keyField.borderStyle = UITextBorderStyleRoundedRect; self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone; self.keyField.autocorrectionType = UITextAutocorrectionTypeNo; self.keyField.clearButtonMode = UITextFieldViewModeWhileEditing; self.keyField.returnKeyType = UIReturnKeyDone; self.keyField.secureTextEntry = NO;
    UIButton *login = [UIButton buttonWithType:UIButtonTypeSystem]; login.translatesAutoresizingMaskIntoConstraints = NO; [login setTitle:@"Verificar chave" forState:UIControlStateNormal]; login.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; login.backgroundColor = UIColor.systemBlueColor; [login setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; login.layer.cornerRadius = 14; [login addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spinner.translatesAutoresizingMaskIntoConstraints = NO; self.spinner.hidesWhenStopped = YES;
    self.statusLabel = [UILabel new]; self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO; self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.statusLabel.textColor = UIColor.secondaryLabelColor; self.statusLabel.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[eyebrow, title, subtitle, self.keyField, login, self.statusLabel]]; stack.translatesAutoresizingMaskIntoConstraints = NO; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14;
    [self.view addSubview:stack]; [self.view addSubview:self.spinner]; UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24], [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24], [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor], [self.keyField.heightAnchor constraintEqualToConstant:52], [login.heightAnchor constraintEqualToConstant:52], [self.spinner.centerYAnchor constraintEqualToAnchor:login.centerYAnchor], [self.spinner.trailingAnchor constraintEqualToAnchor:login.trailingAnchor constant:-18]]];
    [self.keyField addTarget:self action:@selector(submit) forControlEvents:UIControlEventEditingDidEndOnExit];
}

- (void)submit
{
    NSString *key = [self.keyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!key.length) { self.statusLabel.text = @"Digite sua chave iOS."; return; }
    [self.keyField resignFirstResponder]; [self.spinner startAnimating]; self.statusLabel.text = @"Verificando chave…";
    NSString *device = [self deviceIdentifier];
    NSDictionary *input = @{ @"json": @{ @"key": key, @"deviceId": device } };
    NSData *json = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
    NSString *jsonText = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *encoded = [jsonText stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?input=%@", WQKeyEndpoint, encoded]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *__unused response, NSError *error) {
        BOOL accepted = NO; NSString *message = nil;
        if (!error && data) { NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; NSDictionary *result = root[@"result"][@"data"][@"json"]; accepted = [result[@"success"] boolValue] && [result[@"active"] boolValue] && [result[@"status"] isEqualToString:@"active"]; message = result[@"message"] ?: result[@"reason"]; }
        dispatch_async(dispatch_get_main_queue(), ^{ [self.spinner stopAnimating]; if (accepted) { [self saveKey:key]; if (self.onAuthenticated) self.onAuthenticated(); } else self.statusLabel.text = message.length ? message : @"Não foi possível verificar a chave. Verifique sua conexão."; });
    }] resume];
}

- (NSString *)deviceIdentifier
{
    NSString *value = [self readKeychain:WQKeychainService account:@"device-id"];
    if (value.length) return value;
    value = NSUUID.UUID.UUIDString;
    [self saveKey:value service:WQKeychainService account:@"device-id"]; return value;
}
- (void)saveKey:(NSString *)key { [self saveKey:key service:WQKeychainService account:WQKeychainAccount]; }
- (void)saveKey:(NSString *)value service:(NSString *)service account:(NSString *)account { NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding]; NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: service, (__bridge id)kSecAttrAccount: account}; SecItemDelete((__bridge CFDictionaryRef)query); NSMutableDictionary *item = [query mutableCopy]; item[(__bridge id)kSecValueData] = data; item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; SecItemAdd((__bridge CFDictionaryRef)item, NULL); }
- (NSString *)readKeychain:(NSString *)service account:(NSString *)account { NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: service, (__bridge id)kSecAttrAccount: account, (__bridge id)kSecReturnData: @YES, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne}; CFTypeRef result = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result); if (status != errSecSuccess) return nil; NSData *data = CFBridgingRelease(result); return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; }
@end
