#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "AWDirectoryWatcher.h"
#import "AWShared.h"
#import "AWUploader.h"
#import "AWWebDAVClient.h"

#include <notify.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/event.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

static NSString * const AWDomain = @"AudioWatchDaemon";

static void AWReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);

static NSDictionary *AWStatForPath(NSString *path) {
    if (path.length == 0) return nil;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return nil;
    if (!S_ISREG(st.st_mode)) return nil;
    return @{
        @"size": @((unsigned long long)st.st_size),
        @"mtime": @((double)st.st_mtimespec.tv_sec),
        @"mtimeNsec": @((long)st.st_mtimespec.tv_nsec),
    };
}

static BOOL AWSameFingerprint(NSDictionary *a, NSDictionary *b) {
    return [a[@"size"] isEqualToNumber:b[@"size"]] &&
           [a[@"mtime"] isEqualToNumber:b[@"mtime"]] &&
           [a[@"mtimeNsec"] isEqualToNumber:b[@"mtimeNsec"]];
}

static NSDictionary *AWHistoryItem(NSDictionary *entry, NSString *status, NSString *error, NSTimeInterval time) {
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"name"] = entry[@"name"] ?: entry[@"relativePath"] ?: @"未命名文件";
    item[@"relativePath"] = entry[@"relativePath"] ?: @"";
    item[@"status"] = status ?: @"uploaded";
    item[@"size"] = entry[@"size"] ?: @0;
    item[@"time"] = @(time);
    if (error.length) item[@"error"] = error;
    return item;
}

@interface AWDaemon : NSObject <AWDirectoryWatcherDelegate>
@property(nonatomic, strong) dispatch_queue_t stateQueue;
@property(nonatomic, strong) AWDirectoryWatcher *watcher;
@property(nonatomic, strong) AWUploader *uploader;
@property(nonatomic, strong) NSString *uploaderServer;
@property(nonatomic, strong) NSString *uploaderUsername;
@property(nonatomic, strong) NSString *uploaderPassword;

@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *pending;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *ledger;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *history;
@property(nonatomic, assign) NSUInteger uploadedTotal;

@property(nonatomic, copy) NSString *watchPath;
@property(nonatomic, copy) NSString *server;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, copy) NSString *testFingerprint;
@property(nonatomic, assign) NSTimeInterval testedAt;
@property(nonatomic, assign) NSTimeInterval updatedAt;
@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, assign) BOOL valid;
@property(nonatomic, assign) BOOL hasConfig;
@property(nonatomic, assign) BOOL initialScanComplete;
@property(nonatomic, assign) BOOL uploading;
@property(nonatomic, assign) BOOL storeDirty;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) NSUInteger checkToken;
@property(nonatomic, copy) NSString *activePath;
@property(nonatomic, copy) NSString *activeRoot;
@property(nonatomic, copy) NSString *watchError;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, assign) NSTimeInterval lastErrorAt;
@property(nonatomic, copy) NSString *lastUploadName;
@property(nonatomic, assign) NSTimeInterval lastUploadAt;
@property(nonatomic, copy) NSString *networkState;
@property(nonatomic, assign) NSTimeInterval retryDelay;
@property(nonatomic, assign) NSTimeInterval startedAt;

@property(nonatomic, assign) SCNetworkReachabilityRef reachability;
@property(nonatomic, copy) NSString *reachabilityHost;
@property(nonatomic, strong) dispatch_source_t configSource;
@property(nonatomic, strong) dispatch_source_t retryTimer;
@property(nonatomic, strong) dispatch_source_t listenSource;
@property(nonatomic, strong) dispatch_queue_t apiQueue;
@property(nonatomic, assign) int listenFD;
@property(nonatomic, assign) BOOL retryScheduled;
@property(nonatomic, assign) BOOL configReloadScheduled;
@property(nonatomic, assign) int configToken;
@property(nonatomic, assign) int rescanToken;
@property(nonatomic, assign) BOOL registeredNotifications;
- (void)handleReachabilityFlags:(SCNetworkReachabilityFlags)flags;
@end

@implementation AWDaemon

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.liseng.audiowatch.daemon.state", DISPATCH_QUEUE_SERIAL);
        _apiQueue = dispatch_queue_create("com.liseng.audiowatch.daemon.api", DISPATCH_QUEUE_SERIAL);
        _listenFD = -1;
        dispatch_queue_set_specific(_stateQueue, "com.liseng.audiowatch.daemon.key",
                                    (void *)"com.liseng.audiowatch.daemon.key", NULL);
        _pending = [NSMutableArray array];
        _ledger = [NSMutableDictionary dictionary];
        _history = [NSMutableArray array];
        _networkState = @"unknown";
        _retryDelay = 15.0;
        _startedAt = AWUnixTime();
    }
    return self;
}

- (void)dealloc {
    if (_reachability) CFRelease(_reachability);
    if (_configSource) dispatch_source_cancel(_configSource);
    if (_retryTimer) dispatch_source_cancel(_retryTimer);
    if (_listenSource) dispatch_source_cancel(_listenSource);
    if (_registeredNotifications) {
        notify_cancel(_configToken);
        notify_cancel(_rescanToken);
    }
}

- (void)run {
    dispatch_async(self.stateQueue, ^{
        [self startOnQueue];
    });
}

- (void)startOnQueue {
    AWEnsureSharedDirectories();
    NSLog(@"[AudioWatch] daemon starting pid=%d", getpid());
    [self loadStore];
    [self loadConfigOnQueue];
    [self setupConfigWatch];
    [self registerNotifications];
    [self startAPIServer];
    [self publishStatus];
}

#pragma mark - Config

- (void)loadConfigOnQueue {
    NSDictionary *json = AWReadJSON(AWConfigPath);
    NSData *secretData = AWReadData(AWSecretPath);
    NSString *secret = secretData.length ? [[NSString alloc] initWithData:secretData encoding:NSUTF8StringEncoding] : @"";
    secret = [secret stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]];

    BOOL newHasConfig = [json isKindOfClass:NSDictionary.class];
    BOOL newEnabled = newHasConfig ? [json[@"enabled"] boolValue] : NO;
    NSString *newWatch = newHasConfig && [json[@"watchPath"] isKindOfClass:NSString.class] ? json[@"watchPath"] : @"";
    NSString *newServer = newHasConfig && [json[@"server"] isKindOfClass:NSString.class] ? json[@"server"] : @"";
    NSString *newUsername = newHasConfig && [json[@"username"] isKindOfClass:NSString.class] ? json[@"username"] : @"";
    NSString *newFingerprint = newHasConfig && [json[@"testFingerprint"] isKindOfClass:NSString.class] ? json[@"testFingerprint"] : @"";
    NSTimeInterval newTestedAt = newHasConfig ? [json[@"testedAt"] doubleValue] : 0;
    NSTimeInterval newUpdatedAt = newHasConfig ? [json[@"updatedAt"] doubleValue] : 0;
    newWatch = [newWatch stringByStandardizingPath];

    BOOL valid = NO;
    NSString *validationError = nil;
    if (!newHasConfig) {
        validationError = @"尚未配置";
    } else if (newWatch.length == 0) {
        validationError = @"尚未选择监控文件夹";
    } else if (newServer.length == 0 || newUsername.length == 0 || secret.length == 0) {
        validationError = @"服务器、账号或密码缺失";
    } else if (newTestedAt <= 0 || newFingerprint.length == 0) {
        validationError = @"尚未通过连接测试";
    } else if (![newFingerprint isEqualToString:AWFingerprint(newServer, newUsername, secret)]) {
        validationError = @"连接测试已失效，请重新测试";
    } else {
        NSString *urlError = nil;
        NSURL *base = AWBaseURLFromString(newServer, &urlError);
        BOOL isDir = NO;
        if (!base) {
            validationError = urlError ?: @"服务器地址无效";
        } else if (![[NSFileManager defaultManager] fileExistsAtPath:newWatch isDirectory:&isDir] || !isDir) {
            validationError = @"监控文件夹不存在或不可访问";
        } else {
            valid = YES;
            newServer = base.absoluteString;
        }
    }

    BOOL changed = (newHasConfig != self.hasConfig) ||
                   (newEnabled != self.enabled) ||
                   ![newWatch isEqualToString:(self.watchPath ?: @"")] ||
                   ![newServer isEqualToString:(self.server ?: @"")] ||
                   ![newUsername isEqualToString:(self.username ?: @"")] ||
                   ![secret isEqualToString:(self.password ?: @"")] ||
                   ![newFingerprint isEqualToString:(self.testFingerprint ?: @"")] ||
                   newTestedAt != self.testedAt;

    self.hasConfig = newHasConfig;
    self.enabled = newEnabled;
    self.watchPath = newWatch;
    self.server = newServer;
    self.username = newUsername;
    self.password = secret ?: @"";
    self.testFingerprint = newFingerprint;
    self.testedAt = newTestedAt;
    self.updatedAt = newUpdatedAt;
    self.valid = valid;

    if (newEnabled && valid) {
        [self updateReachabilityIfNeeded];
    }

    if (changed) {
        if (valid && newEnabled) {
            self.lastError = nil;
            [self activateMonitoring];
        } else {
            [self stopMonitoringOnQueue];
            if (newEnabled && !valid) {
                self.watchError = validationError ?: @"配置校验失败";
            } else {
                self.watchError = nil;
            }
        }
    } else if (newEnabled && !valid) {
        [self stopMonitoringOnQueue];
        self.watchError = validationError ?: @"配置校验失败";
    }
    [self publishStatus];
}

- (void)scheduleConfigReload {
    if (self.configReloadScheduled) return;
    self.configReloadScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), self.stateQueue, ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        self.configReloadScheduled = NO;
        [self loadConfigOnQueue];
    });
}

#pragma mark - Monitoring lifecycle

- (void)activateMonitoring {
    if (!self.enabled || !self.valid) return;
    [self stopWatcherAndUploaderOnQueue];
    self.generation++;
    NSUInteger generation = self.generation;
    self.uploading = NO;
    self.activePath = nil;
    self.initialScanComplete = NO;
    self.watchError = nil;
    [self pruneQueueForCurrentRoot];
    for (NSMutableDictionary *entry in self.pending) {
        if ([entry[@"state"] isEqualToString:@"failed"]) {
            entry[@"state"] = @"waiting";
            entry[@"ready"] = @YES;
            entry[@"error"] = @"";
        }
    }

    self.watcher = [AWDirectoryWatcher new];
    self.watcher.delegate = self;
    self.activeRoot = self.watchPath;
    NSLog(@"[AudioWatch] watching %@", self.watchPath);
    [self.watcher startAtPath:self.watchPath];
    [self saveStore];
    [self publishStatus];
    (void)generation;
}

- (void)stopMonitoringOnQueue {
    [self stopWatcherAndUploaderOnQueue];
    self.generation++;
    self.uploading = NO;
    self.activePath = nil;
    self.initialScanComplete = NO;
    self.activeRoot = nil;
    [self cancelRetry];
    [self saveStore];
}

- (void)stopWatcherAndUploaderOnQueue {
    if (self.watcher) {
        [self.watcher stop];
        self.watcher.delegate = nil;
        self.watcher = nil;
    }
    if (self.uploader) {
        [self.uploader cancel];
        self.uploader = nil;
        self.uploaderServer = nil;
        self.uploaderUsername = nil;
        self.uploaderPassword = nil;
    }
    for (NSMutableDictionary *entry in self.pending) {
        if ([entry[@"state"] isEqualToString:@"uploading"]) {
            entry[@"state"] = @"waiting";
            entry[@"ready"] = @YES;
        }
    }
    [self cancelRetry];
}

- (void)pruneQueueForCurrentRoot {
    if (self.activeRoot.length && [self.activeRoot isEqualToString:self.watchPath]) return;
    if (self.watchPath.length == 0) return;
    NSString *prefix = [self.watchPath stringByAppendingString:@"/"];
    NSMutableArray *removed = [NSMutableArray array];
    for (NSMutableDictionary *entry in self.pending) {
        NSString *path = entry[@"path"];
        if (![path isKindOfClass:NSString.class] || ![path hasPrefix:prefix]) [removed addObject:entry];
    }
    if (removed.count) {
        [self.pending removeObjectsInArray:removed];
        self.storeDirty = YES;
    }
    self.activeRoot = self.watchPath;
}

#pragma mark - Watcher delegate

- (void)directoryWatcher:(AWDirectoryWatcher *)watcher
          didDiscoverFile:(NSString *)path
            relativePath:(NSString *)relativePath
              attributes:(NSDictionary *)attributes
             initialScan:(BOOL)initialScan {
    dispatch_async(self.stateQueue, ^{
        if (!self.enabled || !self.valid) return;
        BOOL changed = [self considerFile:path relativePath:relativePath attributes:attributes];
        if (changed && !initialScan) {
            [self saveStore];
            [self publishStatus];
        }
    });
}

- (void)directoryWatcher:(AWDirectoryWatcher *)watcher didFinishInitialScan:(BOOL)success error:(NSString *)error {
    dispatch_async(self.stateQueue, ^{
        if (watcher != self.watcher) return;
        self.initialScanComplete = success;
        if (!success) {
            self.watchError = error ?: @"无法扫描监控文件夹";
            self.lastError = self.watchError;
            self.lastErrorAt = AWUnixTime();
            NSLog(@"[AudioWatch] initial scan failed: %@", self.watchError);
        } else {
            self.watchError = nil;
            NSLog(@"[AudioWatch] initial scan complete, pending=%lu", (unsigned long)self.pending.count);
        }
        [self saveStore];
        [self publishStatus];
        if (success) [self uploadNextOnQueue];
    });
}

- (void)directoryWatcher:(AWDirectoryWatcher *)watcher didFailWithError:(NSString *)error {
    dispatch_async(self.stateQueue, ^{
        if (watcher != self.watcher) return;
        self.watchError = error ?: @"监控文件夹不可访问";
        self.lastError = self.watchError;
        self.lastErrorAt = AWUnixTime();
        [self publishStatus];
    });
}

- (BOOL)considerFile:(NSString *)path relativePath:(NSString *)relativePath attributes:(NSDictionary *)attributes {
    if (![path hasPrefix:[self.watchPath stringByAppendingString:@"/"]]) return NO;
    if (relativePath.length == 0) return NO;
    if (self.uploading && [self.activePath isEqualToString:path]) return NO;

    NSDictionary *existingLedger = self.ledger[path];
    if (existingLedger && AWSameFingerprint(existingLedger, attributes)) {
        NSMutableDictionary *queued = [self pendingEntryForPath:path];
        if (queued) {
            [self.pending removeObject:queued];
            return YES;
        }
        return NO;
    }

    NSMutableDictionary *entry = [self pendingEntryForPath:path];
    if (entry) {
        if (AWSameFingerprint(entry, attributes)) return NO;
        entry[@"size"] = attributes[@"size"];
        entry[@"mtime"] = attributes[@"mtime"];
        entry[@"mtimeNsec"] = attributes[@"mtimeNsec"];
        entry[@"state"] = @"waiting";
        entry[@"error"] = @"";
        entry[@"ready"] = @NO;
        [self scheduleStabilityForPath:path];
        return YES;
    }

    entry = [@{
        @"path": path,
        @"relativePath": relativePath,
        @"name": relativePath.lastPathComponent ?: path.lastPathComponent,
        @"size": attributes[@"size"] ?: @0,
        @"mtime": attributes[@"mtime"] ?: @0,
        @"mtimeNsec": attributes[@"mtimeNsec"] ?: @0,
        @"discoveredAt": @(AWUnixTime()),
        @"attempts": @0,
        @"state": @"waiting",
        @"ready": @NO,
        @"error": @"",
    } mutableCopy];
    [self.pending addObject:entry];
    [self scheduleStabilityForPath:path];
    return YES;
}

- (NSMutableDictionary *)pendingEntryForPath:(NSString *)path {
    for (NSMutableDictionary *entry in self.pending) {
        if ([entry[@"path"] isEqualToString:path]) return entry;
    }
    return nil;
}

- (void)scheduleStabilityForPath:(NSString *)path {
    NSMutableDictionary *entry = [self pendingEntryForPath:path];
    if (!entry) return;
    entry[@"checkToken"] = @(++self.checkToken);
    NSNumber *token = entry[@"checkToken"];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), self.stateQueue, ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        NSMutableDictionary *current = [self pendingEntryForPath:path];
        if (!current || ![current[@"checkToken"] isEqualToNumber:token]) return;
        if ([current[@"state"] isEqualToString:@"uploading"]) return;
        NSDictionary *stat = AWStatForPath(path);
        if (!stat) {
            [self.pending removeObject:current];
            [self saveStore];
            [self publishStatus];
            return;
        }
        if (!AWSameFingerprint(current, stat)) {
            current[@"size"] = stat[@"size"];
            current[@"mtime"] = stat[@"mtime"];
            current[@"mtimeNsec"] = stat[@"mtimeNsec"];
            current[@"state"] = @"waiting";
            current[@"ready"] = @NO;
            [self scheduleStabilityForPath:path];
            return;
        }
        current[@"ready"] = @YES;
        current[@"state"] = @"waiting";
        [self saveStore];
        [self uploadNextOnQueue];
    });
}

#pragma mark - Upload queue

- (void)uploadNextOnQueue {
    if (!self.enabled || !self.valid || !self.initialScanComplete || self.uploading) return;
    if (self.pending.count == 0) {
        [self cancelRetry];
        [self publishStatus];
        return;
    }
    if ([self.networkState isEqualToString:@"offline"]) {
        [self markQueueWaitingForNetwork];
        [self publishStatus];
        return;
    }

    NSMutableDictionary *candidate = nil;
    NSArray<NSMutableDictionary *> *sorted = [self.pending sortedArrayUsingComparator:^NSComparisonResult(NSMutableDictionary *a, NSMutableDictionary *b) {
        double ta = [a[@"discoveredAt"] doubleValue];
        double tb = [b[@"discoveredAt"] doubleValue];
        if (ta < tb) return NSOrderedAscending;
        if (ta > tb) return NSOrderedDescending;
        return [a[@"path"] compare:b[@"path"]];
    }];
    for (NSMutableDictionary *entry in sorted) {
        NSString *state = entry[@"state"];
        if ([state isEqualToString:@"failed"]) continue;
        if (![entry[@"ready"] boolValue]) continue;
        if ([state isEqualToString:@"uploading"]) continue;
        candidate = entry;
        break;
    }
    if (!candidate) {
        [self publishStatus];
        return;
    }

    [self ensureUploader];
    if (!self.uploader) {
        [self failQueueWithMessage:@"无法创建上传器" permanent:YES];
        return;
    }

    self.uploading = YES;
    self.activePath = candidate[@"path"];
    candidate[@"state"] = @"uploading";
    candidate[@"attempts"] = @([candidate[@"attempts"] integerValue] + 1);
    candidate[@"error"] = @"";
    [self publishStatus];

    NSUInteger generation = self.generation;
    NSString *path = candidate[@"path"];
    NSString *relative = candidate[@"relativePath"];
    __weak typeof(self) weakSelf = self;
    [self.uploader uploadFileAtPath:path relativePath:relative completion:^(AWUploadResult *result) {
        dispatch_async(self.stateQueue, ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            if (generation != self.generation || !self.enabled) return;
            [self handleUploadResult:result forPath:path];
        });
    }];
}

- (void)ensureUploader {
    if (self.uploader &&
        [self.uploaderServer isEqualToString:self.server] &&
        [self.uploaderUsername isEqualToString:self.username] &&
        [self.uploaderPassword isEqualToString:self.password]) return;
    if (self.uploader) [self.uploader cancel];
    self.uploader = [[AWUploader alloc] initWithServer:self.server username:self.username password:self.password];
    self.uploaderServer = self.server;
    self.uploaderUsername = self.username;
    self.uploaderPassword = self.password;
}

- (void)handleUploadResult:(AWUploadResult *)result forPath:(NSString *)path {
    self.uploading = NO;
    self.activePath = nil;
    NSMutableDictionary *entry = [self pendingEntryForPath:path];
    if (!entry) {
        [self publishStatus];
        [self uploadNextOnQueue];
        return;
    }

    if (result.success) {
        NSDictionary *stat = AWStatForPath(path);
        if (!stat) {
            [self.pending removeObject:entry];
            [self saveStore];
            [self publishStatus];
            [self uploadNextOnQueue];
            return;
        }
        if (!AWSameFingerprint(entry, stat)) {
            entry[@"size"] = stat[@"size"];
            entry[@"mtime"] = stat[@"mtime"];
            entry[@"mtimeNsec"] = stat[@"mtimeNsec"];
            entry[@"state"] = @"waiting";
            entry[@"ready"] = @NO;
            entry[@"error"] = @"文件在上传过程中发生变化，准备重传";
            [self scheduleStabilityForPath:path];
            [self saveStore];
            [self publishStatus];
            return;
        }
        [self.pending removeObject:entry];
        self.ledger[path] = @{
            @"size": stat[@"size"],
            @"mtime": stat[@"mtime"],
            @"mtimeNsec": stat[@"mtimeNsec"],
            @"at": @(AWUnixTime()),
        };
        self.uploadedTotal++;
        self.lastUploadName = entry[@"name"] ?: entry[@"relativePath"];
        self.lastUploadAt = AWUnixTime();
        self.lastError = nil;
        self.retryDelay = 15.0;
        NSDictionary *historyItem = AWHistoryItem(entry, @"uploaded", @"", self.lastUploadAt);
        [self.history insertObject:historyItem atIndex:0];
        if (self.history.count > 40) [self.history removeLastObject];
        NSLog(@"[AudioWatch] uploaded %@", entry[@"relativePath"]);
        [self saveStore];
        [self publishStatus];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), self.stateQueue, ^{
            [weakSelf uploadNextOnQueue];
        });
        return;
    }

    entry[@"error"] = result.message ?: @"上传失败";
    self.lastError = entry[@"error"];
    self.lastErrorAt = AWUnixTime();
    if (result.permanentError) {
        entry[@"state"] = @"failed";
        entry[@"ready"] = @YES;
        NSLog(@"[AudioWatch] permanent upload error for %@: %@", entry[@"relativePath"], result.message);
        [self cancelRetry];
        [self saveStore];
        [self publishStatus];
        return;
    }

    entry[@"state"] = result.networkError ? @"waiting_network" : @"waiting";
    entry[@"ready"] = @YES;
    [self saveStore];
    [self publishStatus];

    [self scheduleRetry];
}

- (void)failQueueWithMessage:(NSString *)message permanent:(BOOL)permanent {
    self.uploading = NO;
    self.activePath = nil;
    self.lastError = message;
    self.lastErrorAt = AWUnixTime();
    if (permanent) {
        for (NSMutableDictionary *entry in self.pending) {
            if (![entry[@"state"] isEqualToString:@"failed"]) {
                entry[@"state"] = @"failed";
                entry[@"error"] = message;
            }
        }
    }
    [self saveStore];
    [self publishStatus];
}

- (void)markQueueWaitingForNetwork {
    BOOL changed = NO;
    for (NSMutableDictionary *entry in self.pending) {
        NSString *state = entry[@"state"];
        if ([state isEqualToString:@"failed"] || [state isEqualToString:@"uploading"]) continue;
        if (![state isEqualToString:@"waiting_network"]) {
            entry[@"state"] = @"waiting_network";
            changed = YES;
        }
    }
    if (changed) [self saveStore];
}

#pragma mark - Retry & reachability

- (void)scheduleRetry {
    if (!self.enabled || !self.valid || self.pending.count == 0) return;
    if ([self.networkState isEqualToString:@"offline"]) return;
    if (self.retryScheduled) return;
    self.retryScheduled = YES;
    NSTimeInterval delay = MAX(5.0, self.retryDelay);
    self.retryDelay = MIN(300.0, self.retryDelay * 1.8);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self.stateQueue, ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        self.retryScheduled = NO;
        if (!self.enabled || !self.valid) return;
        if ([self.networkState isEqualToString:@"offline"]) return;
        [self uploadNextOnQueue];
    });
}

- (void)cancelRetry {
    self.retryScheduled = NO;
    if (self.retryTimer) {
        dispatch_source_cancel(self.retryTimer);
        self.retryTimer = nil;
    }
}

- (void)updateReachabilityIfNeeded {
    NSString *host = nil;
    NSURL *url = AWBaseURLFromString(self.server ?: @"", nil);
    host = url.host;
    if (!host.length) return;
    if ([host isEqualToString:self.reachabilityHost]) {
        [self readCurrentReachability];
        return;
    }
    if (self.reachability) {
        SCNetworkReachabilitySetCallback(self.reachability, NULL, NULL);
        SCNetworkReachabilitySetDispatchQueue(self.reachability, NULL);
        CFRelease(self.reachability);
        self.reachability = NULL;
    }
    self.reachabilityHost = host;
    self.reachability = SCNetworkReachabilityCreateWithName(NULL, host.UTF8String);
    if (!self.reachability) {
        self.networkState = @"unknown";
        return;
    }
    SCNetworkReachabilityContext context = { 0, (__bridge void *)self, NULL, NULL, NULL };
    SCNetworkReachabilitySetCallback(self.reachability, AWReachabilityCallback, &context);
    SCNetworkReachabilitySetDispatchQueue(self.reachability, self.stateQueue);
    [self readCurrentReachability];
}

static void AWReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    AWDaemon *daemon = (__bridge AWDaemon *)info;
    [daemon handleReachabilityFlags:flags];
}

- (void)readCurrentReachability {
    if (!self.reachability) return;
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self.reachability, &flags)) {
        [self handleReachabilityFlags:flags];
    }
}

- (void)handleReachabilityFlags:(SCNetworkReachabilityFlags)flags {
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    BOOL online = reachable && !needsConnection;
    dispatch_async(self.stateQueue, ^{
        NSString *newState = online ? @"online" : @"offline";
        if ([newState isEqualToString:self.networkState]) return;
        self.networkState = newState;
        if (online) {
            self.retryDelay = 15.0;
            for (NSMutableDictionary *entry in self.pending) {
                if ([entry[@"state"] isEqualToString:@"waiting_network"]) {
                    entry[@"state"] = @"waiting";
                    entry[@"ready"] = @YES;
                }
            }
            [self saveStore];
            [self publishStatus];
            [self cancelRetry];
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), self.stateQueue, ^{
                [weakSelf uploadNextOnQueue];
            });
        } else {
            [self cancelRetry];
            [self markQueueWaitingForNetwork];
            [self publishStatus];
        }
    });
}

#pragma mark - Store

- (void)loadStore {
    NSDictionary *json = AWReadJSON(AWQueuePath);
    if ([json isKindOfClass:NSDictionary.class]) {
        NSArray *pending = [json[@"pending"] isKindOfClass:NSArray.class] ? json[@"pending"] : @[];
        for (id item in pending) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *entry = [item mutableCopy];
            if (![entry[@"path"] isKindOfClass:NSString.class] ||
                ![entry[@"relativePath"] isKindOfClass:NSString.class]) continue;
            entry[@"state"] = @"waiting";
            entry[@"ready"] = @YES;
            entry[@"checkToken"] = @0;
            [self.pending addObject:entry];
        }
        NSDictionary *ledger = [json[@"uploaded"] isKindOfClass:NSDictionary.class] ? json[@"uploaded"] : @{};
        [ledger enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSDictionary.class]) {
                self.ledger[key] = obj;
            }
        }];
        NSArray *history = [json[@"history"] isKindOfClass:NSArray.class] ? json[@"history"] : @[];
        for (id item in history) {
            if ([item isKindOfClass:NSDictionary.class]) [self.history addObject:item];
            if (self.history.count >= 40) break;
        }
        self.uploadedTotal = [json[@"uploadedTotal"] unsignedIntegerValue];
        self.lastUploadName = [json[@"lastUploadName"] isKindOfClass:NSString.class] ? json[@"lastUploadName"] : @"";
        self.lastUploadAt = [json[@"lastUploadAt"] doubleValue];
        if (self.lastUploadAt <= 0 && self.history.count) {
            NSDictionary *latest = self.history.firstObject;
            self.lastUploadName = [latest[@"name"] isKindOfClass:NSString.class] ? latest[@"name"] : @"";
            self.lastUploadAt = [latest[@"time"] doubleValue];
        }
    }
    [self reconcileLoadedQueue];
    [self cleanLedger];
    [self saveStore];
}

- (void)reconcileLoadedQueue {
    NSMutableArray *remove = [NSMutableArray array];
    for (NSMutableDictionary *entry in self.pending) {
        NSDictionary *stat = AWStatForPath(entry[@"path"]);
        if (!stat) {
            [remove addObject:entry];
            continue;
        }
        NSDictionary *ledger = self.ledger[entry[@"path"]];
        if (ledger && AWSameFingerprint(ledger, stat)) {
            [remove addObject:entry];
            continue;
        }
        entry[@"size"] = stat[@"size"];
        entry[@"mtime"] = stat[@"mtime"];
        entry[@"mtimeNsec"] = stat[@"mtimeNsec"];
        entry[@"ready"] = @YES;
        entry[@"state"] = @"waiting";
    }
    [self.pending removeObjectsInArray:remove];
}

- (void)cleanLedger {
    NSTimeInterval cutoff = AWUnixTime() - 30 * 24 * 60 * 60;
    NSMutableArray *remove = [NSMutableArray array];
    [self.ledger enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        if ([obj[@"at"] doubleValue] < cutoff) [remove addObject:key];
    }];
    [self.ledger removeObjectsForKeys:remove];
    if (self.ledger.count > 5000) {
        NSArray *sorted = [self.ledger.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSNumber *ta = self.ledger[a][@"at"] ?: @0;
            NSNumber *tb = self.ledger[b][@"at"] ?: @0;
            return [ta compare:tb];
        }];
        NSUInteger removeCount = sorted.count - 5000;
        for (NSUInteger i = 0; i < removeCount; i++) [self.ledger removeObjectForKey:sorted[i]];
    }
}

- (void)saveStore {
    NSMutableArray *pending = [NSMutableArray array];
    for (NSMutableDictionary *entry in self.pending) {
        NSMutableDictionary *copy = [entry mutableCopy];
        [copy removeObjectForKey:@"checkToken"];
        [pending addObject:copy];
    }
    NSDictionary *store = @{
        @"version": @1,
        @"pending": pending,
        @"uploaded": self.ledger,
        @"history": self.history,
        @"uploadedTotal": @(self.uploadedTotal),
        @"lastUploadName": self.lastUploadName ?: @"",
        @"lastUploadAt": @(self.lastUploadAt),
    };
    if (!AWWriteJSONAtomic(AWQueuePath, store, 0600, AWMobileUID(), AWMobileGID())) {
        NSLog(@"[AudioWatch] failed to save queue");
    }
    self.storeDirty = NO;
}

#pragma mark - Status

- (NSString *)currentState {
    if (!self.hasConfig) return @"disabled";
    if (!self.enabled) return @"disabled";
    if (self.watchError.length || !self.valid) return @"error";
    if (self.uploading) return @"uploading";
    BOOL hasFailed = NO;
    BOOL hasWaitingNetwork = NO;
    for (NSDictionary *entry in self.pending) {
        NSString *entryState = entry[@"state"];
        if ([entryState isEqualToString:@"failed"]) hasFailed = YES;
        if ([entryState isEqualToString:@"waiting_network"]) hasWaitingNetwork = YES;
    }
    if (hasFailed) return @"error";
    if ((hasWaitingNetwork || [self.networkState isEqualToString:@"offline"]) && self.pending.count > 0) {
        return @"waiting_network";
    }
    if (self.pending.count > 0) return @"queued";
    return @"watching";
}

- (NSDictionary *)composeConfig {
    return @{
        @"server": self.server ?: @"",
        @"username": self.username ?: @"",
        @"watchPath": self.watchPath ?: @"",
        @"enabled": @(self.enabled),
        @"testedAt": @(self.testedAt),
        @"updatedAt": @(self.updatedAt),
        @"hasPassword": @(self.password.length > 0),
        @"verified": @(self.valid),
    };
}

- (NSDictionary *)composeStatus {
    NSMutableArray *queue = [NSMutableArray array];
    NSArray *sorted = [self.pending sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"discoveredAt"] compare:b[@"discoveredAt"]];
    }];
    for (NSDictionary *entry in sorted) {
        if (queue.count >= 100) break;
        NSString *state = entry[@"state"] ?: @"waiting";
        NSString *displayState = state;
        if ([state isEqualToString:@"waiting"] || [state isEqualToString:@"ready"]) displayState = @"queued";
        [queue addObject:@{
            @"name": entry[@"name"] ?: entry[@"relativePath"] ?: @"未命名文件",
            @"relativePath": entry[@"relativePath"] ?: @"",
            @"size": entry[@"size"] ?: @0,
            @"time": entry[@"discoveredAt"] ?: @0,
            @"status": displayState,
            @"error": entry[@"error"] ?: @"",
            @"attempts": entry[@"attempts"] ?: @0,
        }];
    }
    NSUInteger failed = 0;
    for (NSDictionary *entry in self.pending) {
        if ([entry[@"state"] isEqualToString:@"failed"]) failed++;
    }
    NSString *error = self.watchError.length ? self.watchError : self.lastError;
    return @{
        @"version": @1,
        @"pid": @(getpid()),
        @"startedAt": @(self.startedAt),
        @"updatedAt": @(AWUnixTime()),
        @"enabled": @(self.enabled),
        @"state": [self currentState],
        @"watchPath": self.watchPath ?: @"",
        @"network": self.networkState ?: @"unknown",
        @"initialScanComplete": @(self.initialScanComplete),
        @"pending": @(self.pending.count),
        @"failed": @(failed),
        @"uploading": self.activePath.length ? self.activePath.lastPathComponent : @"",
        @"lastError": error ?: @"",
        @"lastErrorAt": @(self.lastErrorAt),
        @"lastUploadName": self.lastUploadName ?: @"",
        @"lastUploadAt": @(self.lastUploadAt),
        @"uploadedTotal": @(self.uploadedTotal),
        @"queue": queue,
        @"recent": self.history,
    };
}

- (void)publishStatus {
    NSDictionary *status = [self composeStatus];
    if (!AWWriteJSONAtomic(AWStatusPath, status, 0600, AWMobileUID(), AWMobileGID())) {
        NSLog(@"[AudioWatch] failed to write status");
    }
    AWPostDarwinNotification(AWStatusChangedNotification);
}

#pragma mark - Config watch & notifications

- (void)setupConfigWatch {
    if (self.configSource) return;
    AWEnsureSharedDirectories();
    int fd = open(AWConfigDirectory.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) {
        NSLog(@"[AudioWatch] config watch open failed: %s", strerror(errno));
        return;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND | NOTE_ATTRIB, self.stateQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf scheduleConfigReload];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    self.configSource = source;
    dispatch_resume(source);
}

- (void)registerNotifications {
    if (self.registeredNotifications) return;
    self.registeredNotifications = YES;
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(AWConfigChangedNotification.UTF8String, &_configToken,
                             dispatch_get_main_queue(), ^(int token) {
        [weakSelf scheduleConfigReload];
    });
    notify_register_dispatch(AWRescanNotification.UTF8String, &_rescanToken,
                             dispatch_get_main_queue(), ^(int token) {
        AWDaemon *strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(strongSelf.stateQueue, ^{
            if (!strongSelf.enabled || !strongSelf.valid) return;
            [strongSelf.watcher requestScan];
            if (strongSelf.initialScanComplete) [strongSelf uploadNextOnQueue];
        });
    });
}


#pragma mark - Loopback API

- (void)startAPIServer {
    if (self.listenFD >= 0) return;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        NSLog(@"[AudioWatch] API socket failed: %s", strerror(errno));
        return;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    fcntl(fd, F_SETFL, O_NONBLOCK);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(AWAPIPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        NSLog(@"[AudioWatch] API bind 127.0.0.1:%u failed: %s", AWAPIPort, strerror(errno));
        close(fd);
        return;
    }
    if (listen(fd, 8) != 0) {
        NSLog(@"[AudioWatch] API listen failed: %s", strerror(errno));
        close(fd);
        return;
    }
    self.listenFD = fd;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.apiQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        while (YES) {
            int client = accept(self.listenFD, NULL, NULL);
            if (client < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) break;
                break;
            }
            int flags = fcntl(client, F_GETFL, 0);
            if (flags >= 0) fcntl(client, F_SETFL, flags & ~O_NONBLOCK);
            struct timeval timeout = { 5, 0 };
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
            int one = 1;
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
            [self handleAPIClient:client];
        }
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    self.listenSource = source;
    dispatch_resume(source);
    NSLog(@"[AudioWatch] API listening on 127.0.0.1:%u", AWAPIPort);
}

- (void)sendAPIResponse:(int)fd status:(NSInteger)status object:(NSDictionary *)object {
    NSData *body = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:nil];
    NSString *reason = status == 200 ? @"OK" : (status == 400 ? @"Bad Request" : (status == 401 ? @"Unauthorized" : (status == 404 ? @"Not Found" : @"Error")));
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                      (long)status, reason, (unsigned long)body.length];
    NSMutableData *response = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:body];
    const uint8_t *cursor = response.bytes;
    NSUInteger remaining = response.length;
    while (remaining > 0) {
        ssize_t written = send(fd, cursor, remaining, 0);
        if (written > 0) {
            cursor += written;
            remaining -= (NSUInteger)written;
        } else if (written < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
    close(fd);
}

- (void)handleAPIClient:(int)fd {
    NSMutableData *input = [NSMutableData data];
    char buffer[4096];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange headerRange = NSMakeRange(NSNotFound, 0);
    while (input.length < 64 * 1024) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n <= 0) break;
        [input appendBytes:buffer length:(NSUInteger)n];
        headerRange = [input rangeOfData:separator options:0 range:NSMakeRange(0, input.length)];
        if (headerRange.location != NSNotFound) break;
    }
    if (headerRange.location == NSNotFound) {
        [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": @"请求头无效" }];
        return;
    }
    NSUInteger headerLength = NSMaxRange(headerRange);
    NSString *headerText = [[NSString alloc] initWithData:[input subdataWithRange:NSMakeRange(0, headerLength)] encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [headerText componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": @"请求行无效" }];
        return;
    }
    NSArray<NSString *> *requestParts = [lines.firstObject componentsSeparatedByString:@" "];
    if (requestParts.count < 2) {
        [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": @"请求行无效" }];
        return;
    }
    NSString *method = requestParts[0].uppercaseString;
    NSString *path = requestParts[1];
    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) path = [path substringToIndex:queryRange.location];

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSRange colon = [lines[i] rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [[lines[i] substringToIndex:colon.location] lowercaseString];
        NSString *value = [[lines[i] substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        headers[key] = value;
    }
    if (![headers[@"x-audiowatch-token"] isEqualToString:AWAPIToken]) {
        [self sendAPIResponse:fd status:401 object:@{ @"ok": @NO, @"error": @"未授权" }];
        return;
    }
    NSUInteger contentLength = [headers[@"content-length"] integerValue];
    if (contentLength > 128 * 1024) {
        [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": @"请求体过大" }];
        return;
    }
    while (input.length < headerLength + contentLength) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n <= 0) break;
        [input appendBytes:buffer length:(NSUInteger)n];
    }
    NSData *bodyData = contentLength && input.length >= headerLength + contentLength
        ? [input subdataWithRange:NSMakeRange(headerLength, contentLength)]
        : [NSData data];
    NSDictionary *body = bodyData.length ? [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil] : @{};
    if (![body isKindOfClass:NSDictionary.class]) body = @{};

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/v1/status"]) {
        dispatch_async(self.stateQueue, ^{
            [self sendAPIResponse:fd status:200 object:@{
                @"ok": @YES,
                @"status": [self composeStatus],
                @"config": [self composeConfig],
            }];
        });
        return;
    }
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/v1/health"]) {
        [self sendAPIResponse:fd status:200 object:@{ @"ok": @YES, @"pid": @(getpid()), @"version": @1 }];
        return;
    }
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/v1/config"]) {
        dispatch_async(self.stateQueue, ^{
            [self applyAPIConfig:body completion:^(BOOL success, NSString *message) {
                if (success) {
                    [self sendAPIResponse:fd status:200 object:@{ @"ok": @YES, @"config": [self composeConfig], @"status": [self composeStatus] }];
                } else {
                    [self sendAPIResponse:fd status:409 object:@{ @"ok": @NO, @"error": message ?: @"配置未保存" }];
                }
            }];
        });
        return;
    }
    if ([method isEqualToString:@"POST"] && ([path isEqualToString:@"/v1/enable"] || [path isEqualToString:@"/v1/disable"])) {
        BOOL enable = [path isEqualToString:@"/v1/enable"];
        dispatch_async(self.stateQueue, ^{
            [self applyAPIEnabled:enable completion:^(BOOL success, NSString *message) {
                if (success) {
                    [self sendAPIResponse:fd status:200 object:@{ @"ok": @YES, @"config": [self composeConfig], @"status": [self composeStatus] }];
                } else {
                    [self sendAPIResponse:fd status:409 object:@{ @"ok": @NO, @"error": message ?: @"操作失败" }];
                }
            }];
        });
        return;
    }
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/v1/test"]) {
        NSString *server = [body[@"server"] isKindOfClass:NSString.class] ? body[@"server"] : @"";
        NSString *username = [body[@"username"] isKindOfClass:NSString.class] ? body[@"username"] : @"";
        NSString *password = [body[@"password"] isKindOfClass:NSString.class] ? body[@"password"] : @"";
        NSString *urlError = nil;
        NSURL *base = AWBaseURLFromString(server, &urlError);
        if (!base) {
            [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": urlError ?: @"服务器地址无效" }];
            return;
        }
        server = base.absoluteString;
        if (username.length == 0) {
            [self sendAPIResponse:fd status:400 object:@{ @"ok": @NO, @"error": @"请填写账号" }];
            return;
        }
        if (password.length == 0) {
            if (self.password.length && [server isEqualToString:(self.server ?: @"")] &&
                [username isEqualToString:(self.username ?: @"")]) {
                password = self.password;
            } else {
                [self sendAPIResponse:fd status:409 object:@{ @"ok": @NO, @"error": @"请输入密码" }];
                return;
            }
        }
        AWWebDAVClient *client = [AWWebDAVClient new];
        [client testServer:server username:username password:password progress:nil completion:^(AWTestResult *result) {
            [self sendAPIResponse:fd status:200 object:@{
                @"ok": @YES,
                @"success": @(result.success),
                @"failedStage": @(result.failedStage),
                @"httpStatus": @(result.httpStatus),
                @"message": result.message ?: @"",
                @"warning": result.warning ?: @"",
                @"testedAt": @(AWUnixTime()),
            }];
        }];
        return;
    }
    if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/v1/scan"]) {
        dispatch_async(self.stateQueue, ^{
            if (self.enabled && self.valid) {
                [self.watcher requestScan];
                [self sendAPIResponse:fd status:200 object:@{ @"ok": @YES, @"status": [self composeStatus] }];
            } else {
                [self sendAPIResponse:fd status:409 object:@{ @"ok": @NO, @"error": @"监控未启用" }];
            }
        });
        return;
    }
    [self sendAPIResponse:fd status:404 object:@{ @"ok": @NO, @"error": @"接口不存在" }];
}

- (void)applyAPIConfig:(NSDictionary *)body completion:(void (^)(BOOL success, NSString *message))completion {
    NSString *server = [body[@"server"] isKindOfClass:NSString.class] ? [body[@"server"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    NSString *username = [body[@"username"] isKindOfClass:NSString.class] ? [body[@"username"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    NSString *watchPath = [body[@"watchPath"] isKindOfClass:NSString.class] ? [body[@"watchPath"] stringByStandardizingPath] : @"";
    BOOL enabled = [body[@"enabled"] boolValue];
    BOOL useStored = [body[@"useStoredPassword"] boolValue];
    NSString *password = [body[@"password"] isKindOfClass:NSString.class] ? body[@"password"] : @"";

    NSString *urlError = nil;
    NSURL *base = AWBaseURLFromString(server, &urlError);
    if (!base) {
        completion(NO, urlError ?: @"服务器地址无效");
        return;
    }
    server = base.absoluteString;
    if (username.length == 0) {
        completion(NO, @"请填写账号");
        return;
    }
    BOOL isDir = NO;
    if (watchPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:watchPath isDirectory:&isDir] || !isDir) {
        completion(NO, @"监控文件夹不存在或不可访问");
        return;
    }

    BOOL passwordReused = NO;
    if (password.length == 0 && useStored) {
        if (self.password.length &&
            [server isEqualToString:(self.server ?: @"")] &&
            [username isEqualToString:(self.username ?: @"")]) {
            password = self.password;
            passwordReused = YES;
        }
    }
    if (password.length == 0) {
        completion(NO, @"请输入密码并先测试连接");
        return;
    }

    NSTimeInterval testedAt = [body[@"testedAt"] doubleValue];
    NSString *fingerprint = [body[@"testFingerprint"] isKindOfClass:NSString.class] ? body[@"testFingerprint"] : @"";
    if (passwordReused && self.valid) {
        if (testedAt > self.testedAt) self.testedAt = testedAt;
        testedAt = self.testedAt;
        fingerprint = self.testFingerprint;
    } else {
        if (testedAt <= 0 || fingerprint.length == 0 ||
            ![fingerprint isEqualToString:AWFingerprint(server, username, password)]) {
            completion(NO, @"请先测试连接，确认地址、账号和写入权限");
            return;
        }
    }

    NSDictionary *config = @{
        @"version": @1,
        @"enabled": @(enabled),
        @"watchPath": watchPath,
        @"server": server,
        @"username": username,
        @"testedAt": @(testedAt),
        @"testFingerprint": fingerprint,
        @"updatedAt": @(AWUnixTime()),
    };
    NSData *secret = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!AWWriteDataAtomic(AWSecretPath, secret, 0600, AWMobileUID(), AWMobileGID())) {
        completion(NO, @"无法保存密码");
        return;
    }
    if (!AWWriteJSONAtomic(AWConfigPath, config, 0600, AWMobileUID(), AWMobileGID())) {
        completion(NO, @"无法保存监控配置");
        return;
    }
    self.lastError = nil;
    [self loadConfigOnQueue];
    if (enabled && (!self.valid || self.watchError.length)) {
        completion(NO, self.watchError ?: @"配置校验失败");
        return;
    }
    completion(YES, nil);
}

- (void)applyAPIEnabled:(BOOL)enabled completion:(void (^)(BOOL success, NSString *message))completion {
    if (enabled && !self.valid) {
        completion(NO, @"配置尚未通过测试");
        return;
    }
    NSMutableDictionary *config = [AWReadJSON(AWConfigPath) mutableCopy];
    if (![config isKindOfClass:NSMutableDictionary.class] || config.count == 0) {
        completion(NO, @"尚未配置");
        return;
    }
    config[@"enabled"] = @(enabled);
    config[@"updatedAt"] = @(AWUnixTime());
    if (!AWWriteJSONAtomic(AWConfigPath, config, 0600, AWMobileUID(), AWMobileGID())) {
        completion(NO, @"无法保存配置");
        return;
    }
    [self loadConfigOnQueue];
    completion(YES, nil);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        AWDaemon *daemon = [AWDaemon new];
        [daemon run];
        dispatch_main();
    }
    return 0;
}
