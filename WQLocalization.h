#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const WQLanguageCodeKey;
FOUNDATION_EXPORT NSString * const WQLanguageDidChangeNotification;
FOUNDATION_EXPORT NSArray<NSString *> *WQLanguageCodes(void);
FOUNDATION_EXPORT NSString *WQLanguageName(NSString *code);
FOUNDATION_EXPORT NSString *WQCurrentLanguageCode(void);
FOUNDATION_EXPORT void WQSetLanguageCode(NSString *code);
FOUNDATION_EXPORT NSString *WQLocalized(NSString *key, NSString *fallback);
NS_ASSUME_NONNULL_END
