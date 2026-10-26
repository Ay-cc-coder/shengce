#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AWUploadResult : NSObject
@property(nonatomic, assign) BOOL success;
@property(nonatomic, assign) BOOL networkError;
@property(nonatomic, assign) BOOL permanentError;
@property(nonatomic, assign) NSInteger httpStatus;
@property(nonatomic, copy) NSString *message;
@end

@interface AWUploader : NSObject

- (instancetype)initWithServer:(NSString *)server username:(NSString *)username password:(NSString *)password;
- (void)uploadFileAtPath:(NSString *)path
            relativePath:(NSString *)relativePath
              completion:(void (^)(AWUploadResult *result))completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
