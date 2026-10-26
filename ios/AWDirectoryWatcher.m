#import "AWDirectoryWatcher.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/event.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger AWMaxWatchedDirectories = 4096;

static BOOL AWShouldIgnoreName(NSString *name) {
    if (name.length == 0) return YES;
    if ([name hasPrefix:@"."]) return YES;
    NSString *lower = name.lowercaseString;
    static NSArray<NSString *> *suffixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        suffixes = @[ @".tmp", @".part", @".download", @".crdownload", @".uploading",
                      @".filepart", @".icloud", @".swp", @".sb-", @".ds_store" ];
    });
    for (NSString *suffix in suffixes) {
        if ([lower hasSuffix:suffix]) return YES;
    }
    return NO;
}

@interface AWDirectoryWatcher ()
@property(nonatomic, copy, readwrite) NSString *rootPath;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, dispatch_source_t> *sources;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL scanScheduled;
@property(nonatomic, assign) BOOL initialScanDone;
@property(nonatomic, assign) BOOL destroyed;
@property(nonatomic, assign) NSUInteger scanGeneration;
@end

@implementation AWDirectoryWatcher

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.liseng.audiowatch.watcher", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, "com.liseng.audiowatch.watcher.key", (void *)"com.liseng.audiowatch.watcher.key", NULL);
        _sources = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    if (dispatch_get_specific("com.liseng.audiowatch.watcher.key")) {
        [self stopOnQueue];
    } else {
        [self stop];
    }
}

- (void)startAtPath:(NSString *)path {
    dispatch_async(self.queue, ^{
        if (self.started) [self stopOnQueue];
        self.rootPath = path.stringByStandardizingPath;
        self.started = YES;
        self.destroyed = NO;
        self.initialScanDone = NO;
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.rootPath isDirectory:&isDir] || !isDir) {
            [self reportInitialFailure:@"监控文件夹不存在或不可访问"];
            return;
        }
        if (![self addSourceForDirectory:self.rootPath]) {
            [self reportInitialFailure:@"无法监听这个文件夹"];
            return;
        }
        [self performScanInitial:YES];
    });
}

- (void)stop {
    if (dispatch_get_specific("com.liseng.audiowatch.watcher.key")) {
        [self stopOnQueue];
        return;
    }
    dispatch_sync(self.queue, ^{
        [self stopOnQueue];
    });
}

- (void)stopOnQueue {
    self.started = NO;
    self.destroyed = YES;
    self.scanGeneration++;
    for (dispatch_source_t source in self.sources.allValues) {
        dispatch_source_cancel(source);
    }
    [self.sources removeAllObjects];
    self.rootPath = nil;
}

- (void)requestScan {
    dispatch_async(self.queue, ^{
        if (!self.started) return;
        [self scheduleScan];
    });
}

- (void)scheduleScan {
    if (self.scanScheduled || !self.started) return;
    self.scanScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), self.queue, ^{
        typeof(self) self = weakSelf;
        if (!self || !self.started || self.destroyed) return;
        self.scanScheduled = NO;
        [self performScanInitial:NO];
    });
}

- (void)performScanInitial:(BOOL)initial {
    if (!self.started || self.destroyed) return;
    __weak typeof(self) weakSelf = self;
    NSString *root = self.rootPath;
    if (!root) return;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] || !isDir) {
        if (initial) {
            [self reportInitialFailure:@"监控文件夹不存在或不可访问"];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self) return;
                [self.delegate directoryWatcher:self didFailWithError:@"监控文件夹不存在或不可访问"];
            });
        }
        return;
    }

    NSUInteger generation = ++self.scanGeneration;
    NSMutableSet<NSString *> *seenDirectories = [NSMutableSet setWithObject:root];
    NSDirectoryEnumerator<NSString *> *enumerator = [[NSFileManager defaultManager]
        enumeratorAtPath:root];
    // enumeratorAtPath does not expose per-entry options reliably; hidden
    // entries are filtered explicitly below and their descendants skipped.
    for (NSString *relative in enumerator) {
        if (!self.started || self.destroyed || generation != self.scanGeneration) return;
        NSString *name = relative.lastPathComponent;
        NSString *fullPath = [root stringByAppendingPathComponent:relative];
        struct stat st;
        if (lstat(fullPath.fileSystemRepresentation, &st) != 0) continue;
        if (S_ISLNK(st.st_mode)) continue;

        if (AWShouldIgnoreName(name)) {
            if (S_ISDIR(st.st_mode)) [enumerator skipDescendants];
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            if (seenDirectories.count >= AWMaxWatchedDirectories) continue;
            [seenDirectories addObject:fullPath];
            if (![self addSourceForDirectory:fullPath]) continue;
            continue;
        }
        if (!S_ISREG(st.st_mode)) continue;

        NSDictionary *attributes = @{
            @"size": @((unsigned long long)st.st_size),
            @"mtime": @((double)st.st_mtimespec.tv_sec),
            @"mtimeNsec": @((long)st.st_mtimespec.tv_nsec),
        };
        NSString *relativeCopy = [relative copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            [self.delegate directoryWatcher:self
                            didDiscoverFile:fullPath
                              relativePath:relativeCopy
                                attributes:attributes
                               initialScan:initial];
        });
    }

    // Drop watchers for directories that no longer exist.
    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    for (NSString *directory in self.sources.allKeys) {
        if (![seenDirectories containsObject:directory]) [stale addObject:directory];
    }
    for (NSString *directory in stale) {
        dispatch_source_t source = self.sources[directory];
        if (source) dispatch_source_cancel(source);
        [self.sources removeObjectForKey:directory];
    }

    if (initial && !self.initialScanDone) {
        self.initialScanDone = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            [self.delegate directoryWatcher:self didFinishInitialScan:YES error:nil];
        });
    }
}

- (BOOL)addSourceForDirectory:(NSString *)directory {
    if (self.sources[directory]) return YES;
    int fd = open(directory.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return NO;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND | NOTE_ATTRIB | NOTE_LINK, self.queue);
    if (!source) {
        close(fd);
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        typeof(self) self = weakSelf;
        if (!self || self.destroyed) return;
        [self scheduleScan];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    self.sources[directory] = source;
    dispatch_resume(source);
    return YES;
}

- (void)reportInitialFailure:(NSString *)message {
    self.initialScanDone = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        [self.delegate directoryWatcher:self didFinishInitialScan:NO error:message];
    });
}

@end
