#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// App-side view of the daemon configuration. Passwords are held only for the
/// current editing session; the daemon persists the credential.
@interface AWConfig : NSObject

@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, copy) NSString *watchPath;
@property(nonatomic, copy) NSString *server;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, copy) NSString *testFingerprint;
@property(nonatomic, assign) NSTimeInterval testedAt;
@property(nonatomic, assign) NSTimeInterval updatedAt;
@property(nonatomic, assign) BOOL hasPassword;
@property(nonatomic, assign) BOOL verified;

+ (instancetype)loadLocal;
+ (void)clearLocal;
+ (void)clearTestLeftovers;
+ (instancetype)configFromDaemonDictionary:(NSDictionary *)dictionary;
- (void)saveLocal;
- (BOOL)markVerifiedWithPassword:(NSString *)password;
- (void)invalidateVerification;
- (NSDictionary *)daemonPayloadWithPassword:(nullable NSString *)password;
- (NSDictionary *)localDictionary;

@end

NS_ASSUME_NONNULL_END
