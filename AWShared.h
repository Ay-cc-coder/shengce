#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Everything the app and the root daemon share lives below this real (non-jbroot)
/// directory. The config is split from the state so the daemon can watch the
/// config directory without waking up for every status write.
extern NSString *const AWSharedDirectory;
extern NSString *const AWConfigDirectory;
extern NSString *const AWStateDirectory;
extern NSString *const AWConfigPath;
extern NSString *const AWSecretPath;
extern NSString *const AWStatusPath;
extern NSString *const AWQueuePath;
extern NSString *const AWLogPath;

/// The app talks to the daemon over loopback HTTP. RootHide can give the app
/// and root daemons different views of /var/mobile, so a filesystem handoff is
/// deliberately not used for control or status.
extern NSString *const AWAPIToken;
extern const uint16_t AWAPIPort;

/// Darwin notifications are used as a low-latency hint. Files remain the source
/// of truth, so a missed notification can never lose a queue entry.
extern NSString *const AWStatusChangedNotification;
extern NSString *const AWConfigChangedNotification;
extern NSString *const AWRescanNotification;

FOUNDATION_EXPORT NSString *AWNowISO8601(void);
FOUNDATION_EXPORT NSTimeInterval AWUnixTime(void);
FOUNDATION_EXPORT BOOL AWEnsureDirectory(NSString *path, mode_t mode);
FOUNDATION_EXPORT BOOL AWEnsureSharedDirectories(void);

FOUNDATION_EXPORT NSData * _Nullable AWReadData(NSString *path);
FOUNDATION_EXPORT id _Nullable AWReadJSON(NSString *path);
FOUNDATION_EXPORT BOOL AWWriteDataAtomic(NSString *path, NSData *data, mode_t mode, uid_t uid, gid_t gid);
FOUNDATION_EXPORT BOOL AWWriteJSONAtomic(NSString *path, id object, mode_t mode, uid_t uid, gid_t gid);

FOUNDATION_EXPORT uid_t AWMobileUID(void);
FOUNDATION_EXPORT gid_t AWMobileGID(void);
FOUNDATION_EXPORT void AWPostDarwinNotification(NSString *name);

/// Returns a SHA-256 of server + account + password. The daemon refuses to
/// monitor unless this matches the fingerprint written after a successful test.
FOUNDATION_EXPORT NSString *AWFingerprint(NSString *server, NSString *username, NSString *password);

/// HTTPS-only URL handling shared by the app and daemon.
FOUNDATION_EXPORT NSURL * _Nullable AWBaseURLFromString(NSString *raw, NSString * _Nullable * _Nullable error);
FOUNDATION_EXPORT NSURL * _Nullable AWURLByAppendingRelativePath(NSURL *baseURL, NSString *relativePath);
FOUNDATION_EXPORT NSString *AWPercentEncodedPathComponent(NSString *component);
FOUNDATION_EXPORT NSString *AWDisplayPath(NSString *path);

FOUNDATION_EXPORT NSString *AWFormatBytes(unsigned long long bytes);
FOUNDATION_EXPORT NSString *AWShortTimeString(NSTimeInterval interval);

NS_ASSUME_NONNULL_END
