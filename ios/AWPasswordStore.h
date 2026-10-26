#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Stores the WebDAV password for the app. Keychain is preferred; on RootHide
/// builds where the app has no keychain application-identifier, a local
/// NSUserDefaults fallback keeps the password across launches.
@interface AWPasswordStore : NSObject
+ (nullable NSString *)loadPassword;
+ (void)savePassword:(NSString *)password;
+ (void)clearPassword;
@end

NS_ASSUME_NONNULL_END
