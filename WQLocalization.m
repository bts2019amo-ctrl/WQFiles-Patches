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
            @"maxEdition": @{ @"pt-BR": @"EDIÇÃO MAX", @"en": @"MAX EDITION", @"ja": @"MAX版", @"pt-PT": @"EDIÇÃO MAX" },
            @"appData": @{ @"pt-BR": @"Dados de aplicativos", @"en": @"App Data", @"ja": @"アプリデータ", @"pt-PT": @"Dados de aplicações" },
            @"appGroups": @{ @"pt-BR": @"Grupos de aplicativos", @"en": @"App Groups", @"ja": @"アプリグループ", @"pt-PT": @"Grupos de aplicações" },
            @"extensionData": @{ @"pt-BR": @"Dados de extensões", @"en": @"Extension Data", @"ja": @"拡張データ", @"pt-PT": @"Dados de extensões" },
            @"internalDaemons": @{ @"pt-BR": @"Daemons internos", @"en": @"Internal Daemons", @"ja": @"内部デーモン", @"pt-PT": @"Daemons internos" },
            @"systemData": @{ @"pt-BR": @"Dados do sistema", @"en": @"System Data", @"ja": @"システムデータ", @"pt-PT": @"Dados do sistema" },
            @"patchesDesc": @{ @"pt-BR": @"Aplicar e restaurar patches locais com segurança", @"en": @"Safely apply and restore local patches", @"ja": @"ローカルパッチを安全に適用・復元", @"pt-PT": @"Aplicar e restaurar patches locais com segurança" },
            @"rootFooter": @{ @"pt-BR": @"Aplicação e restauração seguras de arquivos locais. Use as configurações no canto superior direito.", @"en": @"Safely apply and restore local files. Use Settings in the upper-right corner.", @"ja": @"ローカルファイルを安全に適用・復元します。右上の設定を使用してください。", @"pt-PT": @"Aplicação e restauração seguras de ficheiros locais. Use as definições no canto superior direito." },
            @"categoriesFooter": @{ @"pt-BR": @"Entre em uma categoria para adicionar, ativar ou restaurar seus patches.", @"en": @"Choose a category to add, activate or restore your patches.", @"ja": @"カテゴリを選択してパッチを追加、適用、復元します。", @"pt-PT": @"Entre numa categoria para adicionar, ativar ou restaurar os seus patches." },
            @"cache": @{ @"pt-BR": @"Cache", @"en": @"Cache", @"ja": @"キャッシュ", @"pt-PT": @"Cache" },
            @"cacheDesc": @{ @"pt-BR": @"Arquivos temporários e dados armazenados", @"en": @"Temporary files and stored data", @"ja": @"一時ファイルと保存データ", @"pt-PT": @"Ficheiros temporários e dados armazenados" },
            @"avatar": @{ @"pt-BR": @"Avatar", @"en": @"Avatar", @"ja": @"アバター", @"pt-PT": @"Avatar" },
            @"avatarDesc": @{ @"pt-BR": @"Personalização de avatar", @"en": @"Avatar customization", @"ja": @"アバターのカスタマイズ", @"pt-PT": @"Personalização de avatar" },
            @"skin": @{ @"pt-BR": @"Skin", @"en": @"Skin", @"ja": @"スキン", @"pt-PT": @"Skin" },
            @"skinDesc": @{ @"pt-BR": @"Visual e aparência", @"en": @"Visuals and appearance", @"ja": @"外観とビジュアル", @"pt-PT": @"Visual e aparência" },
            @"hologram": @{ @"pt-BR": @"Holograma", @"en": @"Hologram", @"ja": @"ホログラム", @"pt-PT": @"Holograma" },
            @"hologramDesc": @{ @"pt-BR": @"Efeitos holográficos", @"en": @"Holographic effects", @"ja": @"ホログラム効果", @"pt-PT": @"Efeitos holográficos" },
            @"external": @{ @"pt-BR": @"Externo", @"en": @"External", @"ja": @"外部", @"pt-PT": @"Externo" },
            @"externalDesc": @{ @"pt-BR": @"Patches externos e outros arquivos", @"en": @"External patches and other files", @"ja": @"外部パッチとその他のファイル", @"pt-PT": @"Patches externos e outros ficheiros" }
            ,@"compatibility": @{ @"pt-BR": @"Compatibilidade", @"en": @"Compatibility", @"ja": @"互換性", @"pt-PT": @"Compatibilidade" }
            ,@"deviceInfo": @{ @"pt-BR": @"Informações do dispositivo", @"en": @"Device information", @"ja": @"デバイス情報", @"pt-PT": @"Informações do dispositivo" }
            ,@"patchCategories": @{ @"pt-BR": @"Categorias de patches", @"en": @"Patch categories", @"ja": @"パッチカテゴリ", @"pt-PT": @"Categorias de patches" }
            ,@"appearanceHeader": @{ @"pt-BR": @"Aparência e partículas", @"en": @"Appearance and particles", @"ja": @"外観とパーティクル", @"pt-PT": @"Aparência e partículas" }
            ,@"appColor": @{ @"pt-BR": @"Cor do aplicativo", @"en": @"App color", @"ja": @"アプリの色", @"pt-PT": @"Cor da aplicação" }
            ,@"particleModel": @{ @"pt-BR": @"Modelo de partículas", @"en": @"Particle model", @"ja": @"パーティクルモデル", @"pt-PT": @"Modelo de partículas" }
            ,@"appearanceMode": @{ @"pt-BR": @"Modo de aparência", @"en": @"Appearance mode", @"ja": @"外観モード", @"pt-PT": @"Modo de aparência" }
            ,@"cancel": @{ @"pt-BR": @"Cancelar", @"en": @"Cancel", @"ja": @"キャンセル", @"pt-PT": @"Cancelar" }
            ,@"create": @{ @"pt-BR": @"Criar", @"en": @"Create", @"ja": @"作成", @"pt-PT": @"Criar" }
            ,@"addPatchMessage": @{ @"pt-BR": @"O arquivo-alvo será substituído pelo arquivo escolhido quando o toggle estiver ativado.", @"en": @"The target file will be replaced by the selected file when the toggle is enabled.", @"ja": @"トグルを有効にすると、対象ファイルが選択したファイルに置き換えられます。", @"pt-PT": @"O ficheiro-alvo será substituído pelo ficheiro escolhido quando o interruptor estiver ativo." }
            ,@"targetPath": @{ @"pt-BR": @"Caminho do alvo em App Data", @"en": @"Target path in App Data", @"ja": @"App Data内の対象パス", @"pt-PT": @"Caminho do alvo em App Data" }
            ,@"replacementPath": @{ @"pt-BR": @"Caminho do arquivo substituto", @"en": @"Replacement file path", @"ja": @"置換ファイルのパス", @"pt-PT": @"Caminho do ficheiro substituto" }
            ,@"patchName": @{ @"pt-BR": @"Nome do patch", @"en": @"Patch name", @"ja": @"パッチ名", @"pt-PT": @"Nome do patch" }
        };
    });
    NSDictionary *entry = table[key];
    return entry[WQCurrentLanguageCode()] ?: fallback;
}
