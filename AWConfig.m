#import "AWConfig.h"
#import "AWShared.h"

static NSString *const AWLocalServer = @"AudioWatch.server";
static NSString *const AWLocalUsername = @"AudioWatch.username";
static NSString *const AWLocalWatchPath = @"AudioWatch.watchPath";
static NSString *const AWLocalTestedAt = @"AudioWatch.testedAt";

@implementation AWConfig

+ (instancetype)loadLocal {
    AWConfig *config = [AWConfig new];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    config.server = [defaults stringForKey:AWLocalServer] ?: @"";
    config.username = [defaults stringForKey:AWLocalUsername] ?: @"";
    config.watchPath = [defaults stringForKey:AWLocalWatchPath] ?: @"";
    config.testedAt = [defaults doubleForKey:AWLocalTestedAt];
    config.hasPassword = NO;
    config.verified = NO;
    return config;
}

+ (void)clearLocal {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:AWLocalServer];
    [defaults removeObjectForKey:AWLocalUsername];
    [defaults removeObjectForKey:AWLocalWatchPath];
    [defaults removeObjectForKey:AWLocalTestedAt];
    [defaults synchronize];
}

+ (void)clearTestLeftovers {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *server = [defaults stringForKey:AWLocalServer] ?: @"";
    NSString *username = [defaults stringForKey:AWLocalUsername] ?: @"";
    NSString *watchPath = [defaults stringForKey:AWLocalWatchPath] ?: @"";
    BOOL isTest = [server.lowercaseString containsString:@"trycloudflare"]
               || [username.lowercaseString isEqualToString:@"awtest"]
               || [watchPath containsString:@"AudioWatchTest"];
    if (isTest) [self clearLocal];
}

+ (instancetype)configFromDaemonDictionary:(NSDictionary *)dictionary {
    AWConfig *config = [AWConfig new];
    if (![dictionary isKindOfClass:NSDictionary.class]) return config;
    config.enabled = [dictionary[@"enabled"] boolValue];
    config.watchPath = [dictionary[@"watchPath"] isKindOfClass:NSString.class] ? dictionary[@"watchPath"] : @"";
    config.server = [dictionary[@"server"] isKindOfClass:NSString.class] ? dictionary[@"server"] : @"";
    config.username = [dictionary[@"username"] isKindOfClass:NSString.class] ? dictionary[@"username"] : @"";
    config.testedAt = [dictionary[@"testedAt"] doubleValue];
    config.updatedAt = [dictionary[@"updatedAt"] doubleValue];
    config.hasPassword = [dictionary[@"hasPassword"] boolValue];
    config.verified = [dictionary[@"verified"] boolValue];
    return config;
}

- (void)saveLocal {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:self.server ?: @"" forKey:AWLocalServer];
    [defaults setObject:self.username ?: @"" forKey:AWLocalUsername];
    [defaults setObject:self.watchPath ?: @"" forKey:AWLocalWatchPath];
    [defaults setDouble:self.testedAt forKey:AWLocalTestedAt];
    [defaults synchronize];
}

- (BOOL)markVerifiedWithPassword:(NSString *)password {
    if (password.length == 0) return NO;
    NSString *error = nil;
    NSURL *base = AWBaseURLFromString(self.server ?: @"", &error);
    if (!base || self.username.length == 0) return NO;
    self.server = base.absoluteString;
    self.password = password;
    self.testedAt = AWUnixTime();
    self.testFingerprint = AWFingerprint(self.server, self.username, password);
    self.hasPassword = YES;
    self.verified = YES;
    return YES;
}

- (void)invalidateVerification {
    self.testFingerprint = @"";
    self.testedAt = 0;
    self.password = @"";
    self.verified = NO;
}

- (NSDictionary *)daemonPayloadWithPassword:(NSString *)password {
    NSMutableDictionary *payload = [@{
        @"server": self.server ?: @"",
        @"username": self.username ?: @"",
        @"watchPath": self.watchPath ?: @"",
        @"enabled": @(self.enabled),
        @"testedAt": @(self.testedAt),
        @"testFingerprint": self.testFingerprint ?: @"",
    } mutableCopy];
    if (password.length) {
        payload[@"password"] = password;
        payload[@"useStoredPassword"] = @NO;
    } else {
        payload[@"useStoredPassword"] = @YES;
    }
    return payload;
}

- (NSDictionary *)localDictionary {
    return @{
        @"server": self.server ?: @"",
        @"username": self.username ?: @"",
        @"watchPath": self.watchPath ?: @"",
        @"testedAt": @(self.testedAt),
        @"hasPassword": @(self.hasPassword),
        @"verified": @(self.verified),
        @"enabled": @(self.enabled),
    };
}

@end
