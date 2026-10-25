#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AWDirectoryWatcher;

@protocol AWDirectoryWatcherDelegate <NSObject>
- (void)directoryWatcher:(AWDirectoryWatcher *)watcher
          didDiscoverFile:(NSString *)path
            relativePath:(NSString *)relativePath
              attributes:(NSDictionary *)attributes
             initialScan:(BOOL)initialScan;
- (void)directoryWatcher:(AWDirectoryWatcher *)watcher
     didFinishInitialScan:(BOOL)success
                   error:(nullable NSString *)error;
- (void)directoryWatcher:(AWDirectoryWatcher *)watcher didFailWithError:(NSString *)error;
@end

@interface AWDirectoryWatcher : NSObject

@property(nonatomic, weak, nullable) id<AWDirectoryWatcherDelegate> delegate;
@property(nonatomic, copy, readonly) NSString *rootPath;

- (void)startAtPath:(NSString *)path;
- (void)stop;
- (void)requestScan;

@end

NS_ASSUME_NONNULL_END
