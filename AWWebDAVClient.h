#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AWTestStage) {
    AWTestStageAddress = 0,
    AWTestStageAccount = 1,
    AWTestStageWrite = 2,
};

typedef NS_ENUM(NSInteger, AWTestStepState) {
    AWTestStepStatePending = 0,
    AWTestStepStateRunning,
    AWTestStepStatePassed,
    AWTestStepStateFailed,
};

typedef void (^AWTestProgressBlock)(AWTestStage stage, AWTestStepState state, NSString *detail);

@interface AWTestResult : NSObject
@property(nonatomic, assign) BOOL success;
@property(nonatomic, assign) AWTestStage failedStage;
@property(nonatomic, assign) NSInteger httpStatus;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *warning;
@end

@interface AWWebDAVClient : NSObject

/// Verifies the HTTPS WebDAV directory, HTTP authentication, and write access.
/// The write probe is deleted before completion. Progress is delivered on the
/// main queue; completion is called exactly once, also on the main queue.
- (void)testServer:(NSString *)server
          username:(NSString *)username
          password:(NSString *)password
          progress:(nullable AWTestProgressBlock)progress
        completion:(void (^)(AWTestResult *result))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
