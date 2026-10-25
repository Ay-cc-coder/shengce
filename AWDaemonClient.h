#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AWDaemonSnapshot : NSObject
@property(nonatomic, strong) NSDictionary *status;
@property(nonatomic, strong) NSDictionary *config;
@end

@interface AWDaemonClient : NSObject

- (void)fetchSnapshot:(void (^)(AWDaemonSnapshot * _Nullable snapshot, NSError * _Nullable error))completion;
- (void)postCommand:(NSString *)path body:(nullable NSDictionary *)body completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
