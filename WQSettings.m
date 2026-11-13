#import "WQSettings.h"
#import <sys/utsname.h>

@interface WQSettingsViewController ()
@property (nonatomic, copy) NSString *deviceModel;
@property (nonatomic, copy) NSString *systemVersion;
@property (nonatomic, copy) NSString *architecture;
@property (nonatomic, copy) NSString *appVersion;
@end

@implementation WQSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Configurações";
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 72.0;
    self.deviceModel = UIDevice.currentDevice.model ?: @"iPhone/iPad";
    self.systemVersion = UIDevice.currentDevice.systemVersion ?: @"Desconhecido";
    self.appVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.7.7";
    struct utsname name;
    uname(&name);
    self.architecture = [NSString stringWithUTF8String:name.machine] ?: @"arm64";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"settings"];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.systemVersion = UIDevice.currentDevice.systemVersion ?: @"Desconhecido";
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 3 : (section == 1 ? 4 : (section == 2 ? 4 : 3));
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return @"Compatibilidade";
    if (section == 1) return @"Informações do dispositivo";
    if (section == 2) return @"Sobre o WQ Files";
    return @"Categorias de patches";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return @"Compatibilidade validada para iOS 26.0 até iOS 27.2 estável. Recursos de acesso a dados podem variar conforme o sistema e o dispositivo.";
    if (section == 2) return @"Interface redesenhada no estilo iOS 26, mantendo o aplicativo focado em patches locais.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"settings" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.adjustsFontSizeToFitWidth = NO;
    content.secondaryTextProperties.adjustsFontSizeToFitWidth = NO;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    content.imageProperties.tintColor = UIColor.systemBlueColor;
    if (indexPath.section == 0) {
        NSArray *compatibility = @[
            @[@"iOS 26.0 – iOS 26.x", @"Compatível · interface e patches locais"],
            @[@"iOS 27.0 – iOS 27.1", @"Compatível · versão estável"],
            @[@"iOS 27.2 estável", [NSString stringWithFormat:@"Compatível · sistema atual: iOS %@", self.systemVersion]]
        ];
        NSArray *row = compatibility[(NSUInteger)indexPath.row];
        content.text = row[0]; content.secondaryText = row[1];
        content.image = [UIImage systemImageNamed:@"checkmark.shield.fill"];
        content.imageProperties.tintColor = UIColor.systemGreenColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 1) {
        NSArray *rows = @[
            @[@"Dispositivo", self.deviceModel, @"iphone"],
            @[@"Sistema", [NSString stringWithFormat:@"iOS %@", self.systemVersion], @"gear"],
            @[@"Arquitetura", self.architecture, @"cpu"],
            @[@"Status", @"Compatível com a interface iOS 26", @"checkmark.circle.fill"]
        ];
        NSArray *row = rows[(NSUInteger)indexPath.row];
        content.text = row[0]; content.secondaryText = row[1]; content.image = [UIImage systemImageNamed:row[2]];
    } else if (indexPath.section == 2) {
        NSArray *rows = @[
            @[@"Versão do aplicativo", self.appVersion, @"app.badge"],
            @[@"Patches locais", @"Aplicação e restauração seguras", @"square.stack.3d.up.fill"],
            @[@"Interface", @"Visual nativo inspirado no iOS 26", @"paintbrush.pointed.fill"],
            @[@"Sincronização remota", @"Catálogo público automático, sem token", @"arrow.triangle.2.circlepath"]
        ];
        NSArray *row = rows[(NSUInteger)indexPath.row];
        content.text = row[0]; content.secondaryText = row[1]; content.image = [UIImage systemImageNamed:row[2]];
    } else {
        NSArray *rows = @[
            @[@"Cache", @"Arquivos temporários e dados armazenados", @"internaldrive.fill"],
            @[@"Avatar / Skin", @"Personalização visual", @"person.crop.circle.fill"],
            @[@"Holograma / External", @"Efeitos e arquivos externos", @"sparkles"]
        ];
        NSArray *row = rows[(NSUInteger)indexPath.row];
        content.text = row[0]; content.secondaryText = row[1]; content.image = [UIImage systemImageNamed:row[2]];
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Compatibilidade do iOS" message:[NSString stringWithFormat:@"iOS 26.0 até iOS 27.2 estável\nSeu sistema: iOS %@\n\nO WQ Files usa o sistema de patches locais nessas versões.", self.systemVersion] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
