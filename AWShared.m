#import "AWShared.h"

#import <CommonCrypto/CommonDigest.h>
#include <notify.h>
#include <pwd.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>

NSString *const AWSharedDirectory = @"/var/mobile/Library/Preferences/com.liseng.audiowatch";
NSString *const AWConfigDirectory = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/config";
NSString *const AWStateDirectory = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/state";
NSString *const AWConfigPath = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/config/config.json";
NSString *const AWSecretPath = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/config/secret";
NSString *const AWStatusPath = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/state/status.json";
NSString *const AWQueuePath = @"/var/mobile/Library/Preferences/com.liseng.audiowatch/state/queue.json";
NSString *const AWLogPath = @"/var/mobile/Library/Logs/AudioWatch.log";
NSString *const AWAPIToken = @"aw-7f3c9a1d2e5b4c60";
const uint16_t AWAPIPort = 47821;

NSString *const AWStatusChangedNotification = @"com.liseng.audiowatch.status.changed";
NSString *const AWConfigChangedNotification = @"com.liseng.audiowatch.config.changed";
NSString *const AWRescanNotification = @"com.liseng.audiowatch.rescan";

NSString *AWNowISO8601(void) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return [formatter stringFromDate:[NSDate date]];
}

NSTimeInterval AWUnixTime(void) {
    return [NSDate date].timeIntervalSince1970;
}

uid_t AWMobileUID(void) {
    static uid_t uid;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct passwd *pw = getpwnam("mobile");
        uid = pw ? pw->pw_uid : (uid_t)501;
    });
    return uid;
}

gid_t AWMobileGID(void) {
    static gid_t gid;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct passwd *pw = getpwnam("mobile");
        gid = pw ? pw->pw_gid : (gid_t)501;
    });
    return gid;
}

BOOL AWEnsureDirectory(NSString *path, mode_t mode) {
    if (path.length == 0) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory]) return isDirectory;
    NSError *error = nil;
    NSDictionary *attributes = @{ NSFilePosixPermissions : @(mode) };
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:&error]) {
        NSLog(@"[AudioWatch] cannot create %@: %@", path, error.localizedDescription);
        return NO;
    }
    chmod(path.fileSystemRepresentation, mode);
    if (getuid() == 0) {
        chown(path.fileSystemRepresentation, AWMobileUID(), AWMobileGID());
    }
    return YES;
}

BOOL AWEnsureSharedDirectories(void) {
    return AWEnsureDirectory(AWSharedDirectory, 0755) &&
           AWEnsureDirectory(AWConfigDirectory, 0755) &&
           AWEnsureDirectory(AWStateDirectory, 0755) &&
           AWEnsureDirectory(@"/var/mobile/Library/Logs", 0755);
}

NSData *AWReadData(NSString *path) {
    if (path.length == 0) return nil;
    return [NSData dataWithContentsOfFile:path options:0 error:nil];
}

id AWReadJSON(NSString *path) {
    NSData *data = AWReadData(path);
    if (data.length == 0) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return ([object isKindOfClass:NSDictionary.class] || [object isKindOfClass:NSArray.class]) ? object : nil;
}

BOOL AWWriteDataAtomic(NSString *path, NSData *data, mode_t mode, uid_t uid, gid_t gid) {
    if (path.length == 0 || !data) return NO;
    NSString *directory = path.stringByDeletingLastPathComponent;
    if (!AWEnsureDirectory(directory, 0755)) return NO;

    NSString *temporary = [directory stringByAppendingFormat:@"/.%@.%d.%@",
                           path.lastPathComponent, getpid(), NSUUID.UUID.UUIDString];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode);
    if (fd < 0) {
        NSLog(@"[AudioWatch] open %@ failed: %s", temporary, strerror(errno));
        return NO;
    }
    fchmod(fd, mode);
    if (uid != (uid_t)-1) fchown(fd, uid, gid);

    const uint8_t *cursor = data.bytes;
    NSUInteger remaining = data.length;
    BOOL ok = YES;
    while (remaining > 0) {
        ssize_t written = write(fd, cursor, remaining);
        if (written > 0) {
            cursor += written;
            remaining -= (NSUInteger)written;
        } else if (written < 0 && errno == EINTR) {
            continue;
        } else {
            ok = NO;
            break;
        }
    }
    if (ok && fsync(fd) != 0) ok = NO;
    if (close(fd) != 0) ok = NO;
    if (!ok) {
        unlink(temporary.fileSystemRepresentation);
        return NO;
    }
    chmod(temporary.fileSystemRepresentation, mode);
    if (uid != (uid_t)-1) chown(temporary.fileSystemRepresentation, uid, gid);
    if (rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        NSLog(@"[AudioWatch] rename %@ failed: %s", path, strerror(errno));
        unlink(temporary.fileSystemRepresentation);
        return NO;
    }
    return YES;
}

BOOL AWWriteJSONAtomic(NSString *path, id object, mode_t mode, uid_t uid, gid_t gid) {
    if (![NSJSONSerialization isValidJSONObject:object]) return NO;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data) {
        NSLog(@"[AudioWatch] JSON encode failed: %@", error.localizedDescription);
        return NO;
    }
    return AWWriteDataAtomic(path, data, mode, uid, gid);
}

void AWPostDarwinNotification(NSString *name) {
    if (name.length) notify_post(name.UTF8String);
}

NSString *AWFingerprint(NSString *server, NSString *username, NSString *password) {
    NSString *material = [NSString stringWithFormat:@"audiowatch-v1\n%@\n%@\n%@",
                          server ?: @"", username ?: @"", password ?: @""];
    NSData *bytes = [material dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

NSString *AWPercentEncodedPathComponent(NSString *component) {
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"/?#"];
    NSString *encoded = [component stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded.length ? encoded : @"";
}

NSURL *AWBaseURLFromString(NSString *raw, NSString **error) {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        if (error) *error = @"请填写服务器地址";
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if (!components || components.host.length == 0) {
        if (error) *error = @"地址格式不正确";
        return nil;
    }
    if (![components.scheme.lowercaseString isEqualToString:@"https"]) {
        if (error) *error = @"只支持 HTTPS 地址";
        return nil;
    }
    if (components.user.length || components.password.length) {
        if (error) *error = @"请不要把账号密码写进地址";
        return nil;
    }
    if (components.query.length || components.fragment.length) {
        if (error) *error = @"地址不能包含 ? 或 #";
        return nil;
    }
    NSString *path = components.percentEncodedPath ?: @"";
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    while (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }
    if (![path hasSuffix:@"/"]) path = [path stringByAppendingString:@"/"];
    components.percentEncodedPath = path;
    components.query = nil;
    components.fragment = nil;
    NSURL *url = components.URL;
    if (!url || url.host.length == 0) {
        if (error) *error = @"地址格式不正确";
        return nil;
    }
    return url;
}

NSURL *AWURLByAppendingRelativePath(NSURL *baseURL, NSString *relativePath) {
    if (!baseURL) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    if (!components) return nil;
    NSString *basePath = components.percentEncodedPath ?: @"/";
    if (![basePath hasSuffix:@"/"]) basePath = [basePath stringByAppendingString:@"/"];
    NSMutableArray<NSString *> *segments = [NSMutableArray array];
    for (NSString *segment in [relativePath componentsSeparatedByString:@"/"]) {
        if (segment.length == 0 || [segment isEqualToString:@"."]) continue;
        if ([segment isEqualToString:@".."]) return nil;
        NSString *encoded = AWPercentEncodedPathComponent(segment);
        if (encoded.length == 0) return nil;
        [segments addObject:encoded];
    }
    if (segments.count == 0) return baseURL;
    components.percentEncodedPath = [basePath stringByAppendingString:[segments componentsJoinedByString:@"/"]];
    return components.URL;
}

NSString *AWDisplayPath(NSString *path) {
    if ([path hasPrefix:@"/var/mobile/"]) {
        return [@"~/" stringByAppendingString:[path substringFromIndex:@"/var/mobile/".length]];
    }
    return path ?: @"";
}

NSString *AWFormatBytes(unsigned long long bytes) {
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    double value = (double)bytes;
    NSArray<NSString *> *units = @[ @"KB", @"MB", @"GB", @"TB" ];
    for (NSString *unit in units) {
        value /= 1024.0;
        if (value < 1024.0 || [unit isEqualToString:units.lastObject]) {
            return [NSString stringWithFormat:(value < 10.0 ? @"%.1f %@" : @"%.0f %@"), value, unit];
        }
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

NSString *AWShortTimeString(NSTimeInterval interval) {
    if (interval <= 0) return @"—";
    static NSDateFormatter *sameDay;
    static NSDateFormatter *otherDay;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sameDay = [NSDateFormatter new];
        sameDay.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        sameDay.dateFormat = @"HH:mm";
        otherDay = [NSDateFormatter new];
        otherDay.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        otherDay.dateFormat = @"MM-dd HH:mm";
    });
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:interval];
    NSDateFormatter *formatter = [NSCalendar.currentCalendar isDateInToday:date] ? sameDay : otherDay;
    return [formatter stringFromDate:date];
}
