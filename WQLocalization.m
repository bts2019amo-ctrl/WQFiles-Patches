#import "WQLocalization.h"
NSString * const WQLanguageCodeKey = @"WQLanguageCode";
NSString * const WQLanguageDidChangeNotification = @"WQLanguageDidChangeNotification";
NSArray<NSString *> *WQLanguageCodes(void) { return @[@"pt-BR", @"en", @"ja", @"pt-PT"]; }
NSString *WQLanguageName(NSString *code) {
    return @{ @"pt-BR": @"Português (Brasil)", @"en": @"English", @"ja": @"日本語", @"pt-PT": @"Português (Portugal)" }[code] ?: code;
}
NSString *WQCurrentLanguageCode(void) {
    NSString *code = [NSUserDefaults.standardUserDefaults stringForKey:WQLanguageCodeKey];
    return [WQLanguageCodes() containsObject:code] ? code : @"pt-BR";
}
void WQSetLanguageCode(NSString *code) {
    if (![WQLanguageCodes() containsObject:code]) code = @"pt-BR";
    [NSUserDefaults.standardUserDefaults setObject:code forKey:WQLanguageCodeKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WQLanguageDidChangeNotification object:code];
}
NSString *WQLocalized(NSString *key, NSString *fallback) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"brand": @{ @"pt-BR": @"EXTERNAL SYSTEM", @"en": @"EXTERNAL SYSTEM", @"ja": @"EXTERNAL SYSTEM", @"pt-PT": @"EXTERNAL SYSTEM" },
            @"licensed": @{ @"pt-BR": @"ACESSO LICENCIADO", @"en": @"LICENSED ACCESS", @"ja": @"ライセンスアクセス", @"pt-PT": @"ACESSO LICENCIADO" },
            @"validate": @{ @"pt-BR": @"VALIDAR KEY", @"en": @"VALIDATE KEY", @"ja": @"キーを確認", @"pt-PT": @"VALIDAR KEY" },
            @"validating": @{ @"pt-BR": @"VALIDANDO...", @"en": @"VALIDATING...", @"ja": @"確認中...", @"pt-PT": @"A VALIDAR..." },
            @"selectGame": @{ @"pt-BR": @"SELECIONE SEU JOGO", @"en": @"SELECT YOUR GAME", @"ja": @"ゲームを選択", @"pt-PT": @"SELECIONE O SEU JOGO" },
            @"chooseInstalled": @{ @"pt-BR": @"Escolha a versão instalada", @"en": @"Choose the installed version", @"ja": @"インストール済みのバージョンを選択", @"pt-PT": @"Escolha a versão instalada" },
            @"continue": @{ @"pt-BR": @"CONTINUAR", @"en": @"CONTINUE", @"ja": @"続ける", @"pt-PT": @"CONTINUAR" },
            @"settings": @{ @"pt-BR": @"Configurações", @"en": @"Settings", @"ja": @"設定", @"pt-PT": @"Definições" },
            @"patches": @{ @"pt-BR": @"Patches", @"en": @"Patches", @"ja": @"パッチ", @"pt-PT": @"Patches" },
            @"language": @{ @"pt-BR": @"Idioma", @"en": @"Language", @"ja": @"言語", @"pt-PT": @"Idioma" },
            @"appearance": @{ @"pt-BR": @"Aparência e partículas", @"en": @"Appearance and particles", @"ja": @"外観とパーティクル", @"pt-PT": @"Aparência e partículas" },
            @"normal": @{ @"pt-BR": @"Free Fire Normal", @"en": @"Free Fire Normal", @"ja": @"Free Fire 通常版", @"pt-PT": @"Free Fire Normal" },
            @"max": @{ @"pt-BR": @"Free Fire MAX", @"en": @"Free Fire MAX", @"ja": @"Free Fire MAX", @"pt-PT": @"Free Fire MAX" },
            @"normalEdition": @{ @"pt-BR": @"EDIÇÃO PADRÃO", @"en": @"STANDARD EDITION", @"ja": @"通常版", @"pt-PT": @"EDIÇÃO NORMAL" },
            @"info": @{ @"pt-BR": @"Informações", @"en": @"Information", @"ja": @"情報", @"pt-PT": @"Informações" },
            @"colorMessage": @{ @"pt-BR": @"Escolha uma cor para o EXTERNAL SYSTEM", @"en": @"Choose a color for EXTERNAL SYSTEM", @"ja": @"EXTERNAL SYSTEMの色を選択", @"pt-PT": @"Escolha uma cor para o EXTERNAL SYSTEM" },
            @"compatMessage": @{ @"pt-BR": @"O EXTERNAL SYSTEM usa o sistema de patches locais nessas versões.", @"en": @"EXTERNAL SYSTEM uses local patches on these versions.", @"ja": @"EXTERNAL SYSTEMはこれらのバージョンでローカルパッチを使用します。", @"pt-PT": @"O EXTERNAL SYSTEM usa o sistema de patches locais nestas versões." },
            @"empty": @{ @"pt-BR": @"Nenhum patch disponível", @"en": @"No patches available", @"ja": @"利用可能なパッチはありません", @"pt-PT": @"Nenhum patch disponível" },
            @"emptyDetail": @{ @"pt-BR": @"Sincronize novamente ou escolha outra categoria.", @"en": @"Sync again or choose another category.", @"ja": @"再同期するか、別のカテゴリを選択してください。", @"pt-PT": @"Sincronize novamente ou escolha outra categoria." },
            @"maxEdition": @{ @"pt-BR": @"EDIÇÃO MAX", @"en": @"MAX EDITION", @"ja": @"MAX版", @"pt-PT": @"EDIÇÃO MAX" }
        };
    });
    NSDictionary *entry = table[key];
    return entry[WQCurrentLanguageCode()] ?: fallback;
}
