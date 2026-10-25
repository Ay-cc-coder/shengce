#import "AWPasswordStore.h"
#import <Security/Security.h>

static NSString *const AWPasswordService = @"com.liseng.audiowatch.webdav";
static NSString *const AWPasswordAccount = @"webdav";
static NSString *const AWPasswordFallbackKey = @"AudioWatch.savedPassword";

@implementation AWPasswordStore

+ (NSMutableDictionary *)baseQuery {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: AWPasswordService,
        (__bridge id)kSecAttrAccount: AWPasswordAccount,
    } mutableCopy];
}

+ (NSString *)loadPassword {
    NSMutableDictionary *query = [self baseQuery];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *password = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (password.length) return password;
    }
    NSString *fallback = [NSUserDefaults.standardUserDefaults stringForKey:AWPasswordFallbackKey];
    return fallback.length ? fallback : nil;
}

+ (void)savePassword:(NSString *)password {
    if (password.length == 0) {
        [self clearPassword];
        return;
    }
    SecItemDelete((__bridge CFDictionaryRef)[self baseQuery]);
    NSMutableDictionary *add = [self baseQuery];
    add[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status == errSecSuccess) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:AWPasswordFallbackKey];
    } else {
        // RootHide system apps may not have a usable keychain access group.
        // Keep a local fallback rather than forcing a password re-entry.
        [NSUserDefaults.standardUserDefaults setObject:password forKey:AWPasswordFallbackKey];
    }
    [NSUserDefaults.standardUserDefaults synchronize];
}

+ (void)clearPassword {
    SecItemDelete((__bridge CFDictionaryRef)[self baseQuery]);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:AWPasswordFallbackKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
