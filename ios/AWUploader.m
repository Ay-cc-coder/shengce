#import "AWUploader.h"
#import "AWShared.h"

@implementation AWUploadResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _message = @"";
    }
    return self;
}

@end

@interface AWUploader () <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, copy) NSString *server;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, strong) NSURL *baseURL;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionTask *task;
@property(nonatomic, strong) NSOperationQueue *queue;
@property(nonatomic, copy) void (^completion)(AWUploadResult *);
@property(nonatomic, copy) NSString *uploadPath;
@property(nonatomic, assign) BOOL cancelled;
@property(nonatomic, assign) BOOL finished;
@end

@implementation AWUploader

- (instancetype)initWithServer:(NSString *)server username:(NSString *)username password:(NSString *)password {
    self = [super init];
    if (self) {
        _server = [server copy] ?: @"";
        _username = [username copy] ?: @"";
        _password = [password copy] ?: @"";
        NSString *error = nil;
        _baseURL = AWBaseURLFromString(_server, &error);
        _queue = [NSOperationQueue new];
        _queue.name = @"com.liseng.audiowatch.uploader";
        _queue.maxConcurrentOperationCount = 1;
    }
    return self;
}

- (void)dealloc {
    [_session invalidateAndCancel];
    [_queue cancelAllOperations];
}

- (void)cancel {
    self.cancelled = YES;
    [self.task cancel];
    self.task = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.completion = nil;
}

- (void)uploadFileAtPath:(NSString *)path
            relativePath:(NSString *)relativePath
              completion:(void (^)(AWUploadResult *))completion {
    [self.queue addOperationWithBlock:^{
        if (self.task) {
            AWUploadResult *result = [AWUploadResult new];
            result.message = @"上传器正忙";
            completion(result);
            return;
        }
        self.cancelled = NO;
        self.finished = NO;
        self.completion = completion;
        self.uploadPath = path;
        if (!self.baseURL) {
            [self finishWithResult:[self failure:@"服务器地址无效" permanent:YES network:NO status:0]];
            return;
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self finishWithResult:[self failure:@"本地文件不存在" permanent:YES network:NO status:0]];
            return;
        }
        [self ensureSession];
        NSArray<NSString *> *parts = [relativePath componentsSeparatedByString:@"/"];
        NSMutableArray<NSString *> *directories = [NSMutableArray array];
        for (NSUInteger i = 0; i + 1 < parts.count; i++) {
            if (parts[i].length) [directories addObject:parts[i]];
        }
        [self ensureDirectories:directories index:0 completion:^{
            [self startUploadWithRelativePath:relativePath];
        }];
    }];
}

- (void)ensureDirectories:(NSArray<NSString *> *)directories
                     index:(NSUInteger)index
                completion:(void (^)(void))completion {
    if (self.cancelled || self.finished) return;
    if (index >= directories.count) {
        completion();
        return;
    }
    NSMutableArray<NSString *> *prefixParts = [NSMutableArray array];
    for (NSUInteger i = 0; i <= index; i++) [prefixParts addObject:directories[i]];
    NSString *prefix = [prefixParts componentsJoinedByString:@"/"];
    NSURL *url = AWURLByAppendingRelativePath(self.baseURL, prefix);
    if (!url) {
        [self finishWithResult:[self failure:@"无法生成远端目录地址" permanent:YES network:NO status:0]];
        return;
    }
    NSMutableURLRequest *request = [self requestWithURL:url method:@"MKCOL"];
    request.HTTPBody = [NSData data];
    [request setValue:@"0" forHTTPHeaderField:@"Content-Length"];
    __weak typeof(self) weakSelf = self;
    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.cancelled || self.finished) return;
        self.task = nil;
        if (error) {
            [self finishWithResult:[self resultForNetworkError:error]];
            return;
        }
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status == 201 || status == 200 || status == 204 || status == 405) {
            [self ensureDirectories:directories index:index + 1 completion:completion];
            return;
        }
        if (status == 401 || status == 403) {
            [self finishWithResult:[self failure:@"账号没有创建远端目录的权限" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 507) {
            [self finishWithResult:[self failure:@"服务器空间不足" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 409) {
            [self finishWithResult:[self failure:@"WebDAV 根目录不存在，请检查地址" permanent:YES network:NO status:status]];
            return;
        }
        if (status >= 500 || status == 429) {
            [self finishWithResult:[self failure:[NSString stringWithFormat:@"创建远端目录失败，HTTP %ld", (long)status]
                                           permanent:NO network:NO status:status]];
            return;
        }
        [self finishWithResult:[self failure:[NSString stringWithFormat:@"创建远端目录失败，HTTP %ld", (long)status]
                                       permanent:YES network:NO status:status]];
    }];
    [self.task resume];
}

- (void)startUploadWithRelativePath:(NSString *)relativePath {
    if (self.cancelled || self.finished) return;
    NSURL *targetURL = AWURLByAppendingRelativePath(self.baseURL, relativePath);
    if (!targetURL) {
        [self finishWithResult:[self failure:@"文件名无法转换为上传地址" permanent:YES network:NO status:0]];
        return;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.uploadPath error:nil];
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    NSMutableURLRequest *request = [self requestWithURL:targetURL method:@"PUT"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%llu", size] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    request.timeoutInterval = 120.0;

    __weak typeof(self) weakSelf = self;
    self.task = [self.session uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:self.uploadPath]
                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.cancelled || self.finished) return;
        self.task = nil;
        if (error) {
            [self finishWithResult:[self resultForNetworkError:error]];
            return;
        }
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status >= 200 && status < 300) {
            AWUploadResult *result = [AWUploadResult new];
            result.success = YES;
            result.httpStatus = status;
            result.message = @"上传成功";
            [self finishWithResult:result];
            return;
        }
        if (status == 401 || status == 403) {
            [self finishWithResult:[self failure:@"账号或密码失效，或没有写入权限" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 507) {
            [self finishWithResult:[self failure:@"服务器空间不足" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 409) {
            [self finishWithResult:[self failure:@"远端目录不存在，无法保存文件" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 404) {
            // A reverse proxy can briefly answer 404 while its origin is
            // restarting. The base directory was already checked by the
            // connection test, so treating this as permanent would strand a
            // valid recording. Retry with backoff instead.
            [self finishWithResult:[self failure:@"远端暂时无法访问，稍后重试" permanent:NO network:NO status:status]];
            return;
        }
        if (status == 405) {
            [self finishWithResult:[self failure:@"服务器不允许 PUT 上传" permanent:YES network:NO status:status]];
            return;
        }
        if (status == 423) {
            [self finishWithResult:[self failure:@"远端文件被锁定，稍后重试" permanent:NO network:NO status:status]];
            return;
        }
        if (status >= 500 || status == 429 || status == 408) {
            [self finishWithResult:[self failure:[NSString stringWithFormat:@"服务器暂时不可用，HTTP %ld", (long)status]
                                           permanent:NO network:NO status:status]];
            return;
        }
        [self finishWithResult:[self failure:[NSString stringWithFormat:@"上传失败，HTTP %ld", (long)status]
                                       permanent:YES network:NO status:status]];
    }];
    [self.task resume];
}

- (void)finishWithResult:(AWUploadResult *)result {
    if (self.finished) return;
    self.finished = YES;
    void (^completion)(AWUploadResult *) = self.completion;
    self.completion = nil;
    if (completion) completion(result);
}

- (AWUploadResult *)failure:(NSString *)message permanent:(BOOL)permanent network:(BOOL)network status:(NSInteger)status {
    AWUploadResult *result = [AWUploadResult new];
    result.success = NO;
    result.permanentError = permanent;
    result.networkError = network;
    result.httpStatus = status;
    result.message = message ?: @"上传失败";
    return result;
}

- (AWUploadResult *)resultForNetworkError:(NSError *)error {
    BOOL network = [error.domain isEqualToString:NSURLErrorDomain];
    BOOL permanent = NO;
    NSString *message = error.localizedDescription ?: @"网络错误";
    if (network) {
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
                message = @"设备当前没有网络";
                break;
            case NSURLErrorCannotFindHost:
            case NSURLErrorDNSLookupFailed:
                message = @"找不到服务器";
                break;
            case NSURLErrorCannotConnectToHost:
                message = @"无法连接服务器";
                break;
            case NSURLErrorTimedOut:
                message = @"上传超时";
                break;
            case NSURLErrorNetworkConnectionLost:
                message = @"网络连接中断";
                break;
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateUntrusted:
            case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid:
                message = @"HTTPS 证书验证失败";
                permanent = YES;
                break;
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                message = @"系统拒绝非 HTTPS 连接";
                permanent = YES;
                break;
            default:
                break;
        }
    } else {
        permanent = YES;
    }
    return [self failure:message permanent:permanent network:network status:0];
}

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:60.0];
    request.HTTPMethod = method;
    [request setValue:@"AudioWatch/1.0 (iOS; WebDAV)" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:[self basicAuthorization] forHTTPHeaderField:@"Authorization"];
    return request;
}

- (NSString *)basicAuthorization {
    NSString *pair = [NSString stringWithFormat:@"%@:%@", self.username ?: @"", self.password ?: @""];
    NSData *data = [pair dataUsingEncoding:NSUTF8StringEncoding];
    return [@"Basic " stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

- (void)ensureSession {
    if (self.session) return;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120.0;
    configuration.timeoutIntervalForResource = 900.0;
    configuration.HTTPMaximumConnectionsPerHost = 1;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:self.queue];
}

#pragma mark - URLSession delegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if ([method isEqualToString:NSURLAuthenticationMethodHTTPBasic] ||
        [method isEqualToString:NSURLAuthenticationMethodHTTPDigest]) {
        NSURLCredential *credential = [NSURLCredential credentialWithUser:self.username
                                                                 password:self.password
                                                              persistence:NSURLCredentialPersistenceNone];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        return;
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSMutableURLRequest *redirect = [request mutableCopy];
    redirect.HTTPMethod = task.originalRequest.HTTPMethod;
    if ([request.URL.host isEqualToString:task.originalRequest.URL.host]) {
        [redirect setValue:[self basicAuthorization] forHTTPHeaderField:@"Authorization"];
    } else {
        [redirect setValue:nil forHTTPHeaderField:@"Authorization"];
    }
    completionHandler(redirect);
}

@end
