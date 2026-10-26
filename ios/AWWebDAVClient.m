#import "AWWebDAVClient.h"
#import "AWShared.h"

@implementation AWTestResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _failedStage = AWTestStageAddress;
        _message = @"";
        _warning = @"";
    }
    return self;
}

@end

@interface AWWebDAVClient () <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, strong) NSURL *baseURL;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionTask *currentTask;
@property(nonatomic, copy) AWTestProgressBlock progress;
@property(nonatomic, copy) void (^completion)(AWTestResult *);
@property(nonatomic, assign) BOOL finished;
@end

@implementation AWWebDAVClient

- (void)dealloc {
    [_session invalidateAndCancel];
}

- (void)cancel {
    self.finished = YES;
    [self.currentTask cancel];
    self.currentTask = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
}

- (void)testServer:(NSString *)server
          username:(NSString *)username
          password:(NSString *)password
          progress:(AWTestProgressBlock)progress
        completion:(void (^)(AWTestResult *))completion {
    [self cancel];
    self.finished = NO;
    self.username = username ?: @"";
    self.password = password ?: @"";
    self.progress = progress;
    self.completion = completion;

    NSString *error = nil;
    NSURL *baseURL = AWBaseURLFromString(server ?: @"", &error);
    if (!baseURL) {
        AWTestResult *result = [AWTestResult new];
        result.success = NO;
        result.failedStage = AWTestStageAddress;
        result.message = error ?: @"地址无效";
        [self reportStage:AWTestStageAddress state:AWTestStepStateFailed detail:result.message];
        [self finish:result];
        return;
    }
    if (self.username.length == 0 || self.password.length == 0) {
        AWTestResult *result = [AWTestResult new];
        result.success = NO;
        result.failedStage = AWTestStageAccount;
        result.message = @"请填写账号和密码";
        [self reportStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"地址格式正确"];
        [self reportStage:AWTestStageAccount state:AWTestStepStateFailed detail:result.message];
        [self finish:result];
        return;
    }

    self.baseURL = baseURL;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 35.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCache = nil;
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                 delegate:self
                                            delegateQueue:NSOperationQueue.mainQueue];

    [self reportStage:AWTestStageAddress state:AWTestStepStateRunning detail:@"检查 HTTPS 地址"];
    [self reportStage:AWTestStageAccount state:AWTestStepStatePending detail:@"等待地址检查"];
    [self reportStage:AWTestStageWrite state:AWTestStepStatePending detail:@"等待账号验证"];

    __weak typeof(self) weakSelf = self;
    [self propfindWithCompletion:^(NSInteger status, NSError *networkError, BOOL methodUnsupported) {
        typeof(self) self = weakSelf;
        if (!self || self.finished) return;
        if (networkError) {
            [self failStage:AWTestStageAddress message:[self messageForNetworkError:networkError] status:0];
            return;
        }
        if (status == 401) {
            [self passAddressThenFailAccountWithStatus:status message:@"账号或密码不正确"];
            return;
        }
        if (status == 403) {
            [self passAddressThenFailAccountWithStatus:status message:@"账号没有访问该目录的权限"];
            return;
        }
        if (status == 404 || status == 410) {
            [self failStage:AWTestStageAddress message:@"目录不存在，请检查地址中的路径" status:status];
            return;
        }
        if (status == 405 || methodUnsupported) {
            [self reportStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
            [self reportStage:AWTestStageAccount state:AWTestStepStatePassed detail:@"服务器要求用写入测试验证账号"];
            [self beginWriteTest];
            return;
        }
        if (status < 200 || status >= 300) {
            [self passAddressThenFailAccountWithStatus:status
                                               message:[NSString stringWithFormat:@"WebDAV 检查返回 HTTP %ld", (long)status]];
            return;
        }
        [self reportStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
        [self reportStage:AWTestStageAccount state:AWTestStepStateRunning detail:@"验证 WebDAV 账号"];
        [self reportStage:AWTestStageAccount state:AWTestStepStatePassed detail:@"账号验证通过"];
        [self beginWriteTest];
    }];
}

- (void)passAddressThenFailAccountWithStatus:(NSInteger)status message:(NSString *)message {
    [self reportStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
    [self reportStage:AWTestStageAccount state:AWTestStepStateFailed detail:message];
    AWTestResult *result = [AWTestResult new];
    result.success = NO;
    result.failedStage = AWTestStageAccount;
    result.httpStatus = status;
    result.message = message;
    [self finish:result];
}

- (void)failStage:(AWTestStage)stage message:(NSString *)message status:(NSInteger)status {
    if (stage == AWTestStageAddress) {
        [self reportStage:AWTestStageAddress state:AWTestStepStateFailed detail:message];
        [self reportStage:AWTestStageAccount state:AWTestStepStatePending detail:@"需要先连通服务器"];
        [self reportStage:AWTestStageWrite state:AWTestStepStatePending detail:@"需要先验证账号"];
    } else if (stage == AWTestStageAccount) {
        [self reportStage:AWTestStageAccount state:AWTestStepStateFailed detail:message];
        [self reportStage:AWTestStageWrite state:AWTestStepStatePending detail:@"需要先验证账号"];
    } else {
        [self reportStage:AWTestStageWrite state:AWTestStepStateFailed detail:message];
    }
    AWTestResult *result = [AWTestResult new];
    result.success = NO;
    result.failedStage = stage;
    result.httpStatus = status;
    result.message = message;
    [self finish:result];
}

- (void)beginWriteTest {
    [self reportStage:AWTestStageWrite state:AWTestStepStateRunning detail:@"尝试写入并清理测试文件"];
    NSString *probeName = [NSString stringWithFormat:@"audiowatch-connection-test-%@.txt", NSUUID.UUID.UUIDString.lowercaseString];
    NSURL *probeURL = AWURLByAppendingRelativePath(self.baseURL, probeName);
    if (!probeURL) {
        [self failStage:AWTestStageWrite message:@"无法生成测试文件地址" status:0];
        return;
    }
    NSMutableURLRequest *request = [self requestWithURL:probeURL method:@"PUT"];
    request.HTTPBody = [[NSString stringWithFormat:@"AudioWatch connection test\n%@\n", AWNowISO8601()]
                        dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];

    __weak typeof(self) weakSelf = self;
    self.currentTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.finished) return;
        self.currentTask = nil;
        if (error) {
            [self failStage:AWTestStageWrite message:[self messageForNetworkError:error] status:0];
            return;
        }
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status == 401 || status == 403) {
            [self failStage:AWTestStageWrite message:@"账号可以连接，但没有写入权限" status:status];
            return;
        }
        if (status == 507) {
            [self failStage:AWTestStageWrite message:@"服务器空间不足，无法写入" status:status];
            return;
        }
        if (status == 409) {
            [self failStage:AWTestStageWrite message:@"WebDAV 目录不存在，无法创建文件" status:status];
            return;
        }
        if (status == 405) {
            [self failStage:AWTestStageWrite message:@"服务器不允许 PUT 上传" status:status];
            return;
        }
        if (status < 200 || status >= 300) {
            [self failStage:AWTestStageWrite
                    message:[NSString stringWithFormat:@"试写失败，服务器返回 HTTP %ld", (long)status]
                     status:status];
            return;
        }
        [self deleteProbeAtURL:probeURL status:status];
    }];
    [self.currentTask resume];
}

- (void)deleteProbeAtURL:(NSURL *)probeURL status:(NSInteger)writeStatus {
    NSMutableURLRequest *request = [self requestWithURL:probeURL method:@"DELETE"];
    __weak typeof(self) weakSelf = self;
    self.currentTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.finished) return;
        self.currentTask = nil;
        NSInteger deleteStatus = [(NSHTTPURLResponse *)response statusCode];
        NSString *warning = @"";
        if (error || (deleteStatus >= 400 && deleteStatus != 404)) {
            warning = @"写入成功，但测试文件未能自动清理，请在服务器上删除 audiowatch-connection-test-*.txt。";
        }
        [self reportStage:AWTestStageWrite state:AWTestStepStatePassed detail:@"写入权限验证通过"];
        AWTestResult *result = [AWTestResult new];
        result.success = YES;
        result.httpStatus = writeStatus;
        result.message = @"服务器地址、账号和写入权限均正常";
        result.warning = warning;
        [self finish:result];
    }];
    [self.currentTask resume];
}

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15.0];
    request.HTTPMethod = method;
    request.networkServiceType = NSURLNetworkServiceTypeResponsiveData;
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

- (void)propfindWithCompletion:(void (^)(NSInteger status, NSError *error, BOOL methodUnsupported))completion {
    NSMutableURLRequest *request = [self requestWithURL:self.baseURL method:@"PROPFIND"];
    [request setValue:@"0" forHTTPHeaderField:@"Depth"];
    [request setValue:@"application/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    NSString *body = @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                     @"<d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    __weak typeof(self) weakSelf = self;
    self.currentTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.finished) return;
        self.currentTask = nil;
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (error) {
            completion(0, error, NO);
        } else {
            completion(status, nil, status == 405);
        }
    }];
    [self.currentTask resume];
}

- (NSString *)messageForNetworkError:(NSError *)error {
    if (![error.domain isEqualToString:NSURLErrorDomain]) {
        return error.localizedDescription ?: @"连接失败";
    }
    switch (error.code) {
        case NSURLErrorNotConnectedToInternet:
            return @"设备当前没有网络，请连接 Wi-Fi 或蜂窝网络后重试";
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed:
            return @"找不到服务器，请检查地址或网络";
        case NSURLErrorCannotConnectToHost:
            return @"无法连接服务器，请检查端口和反向代理";
        case NSURLErrorTimedOut:
            return @"连接超时，请检查服务器是否可访问";
        case NSURLErrorNetworkConnectionLost:
            return @"网络连接中断，请重试";
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
        case NSURLErrorClientCertificateRejected:
        case NSURLErrorClientCertificateRequired:
            return @"HTTPS 证书验证失败，请检查域名和证书";
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return @"系统拒绝非 HTTPS 连接";
        default:
            return error.localizedDescription ?: @"连接失败";
    }
}

- (void)reportStage:(AWTestStage)stage state:(AWTestStepState)state detail:(NSString *)detail {
    AWTestProgressBlock progress = self.progress;
    if (!progress) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(stage, state, detail ?: @"");
    });
}

- (void)finish:(AWTestResult *)result {
    if (self.finished) return;
    self.finished = YES;
    void (^completion)(AWTestResult *) = self.completion;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(result);
    });
    [self.session finishTasksAndInvalidate];
    self.session = nil;
    self.currentTask = nil;
}

#pragma mark - URLSession delegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    [self handleChallenge:challenge completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    [self handleChallenge:challenge completionHandler:completionHandler];
}

- (void)handleChallenge:(NSURLAuthenticationChallenge *)challenge
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
    redirect.HTTPBody = task.originalRequest.HTTPBody;
    if ([request.URL.host isEqualToString:task.originalRequest.URL.host]) {
        [redirect setValue:[self basicAuthorization] forHTTPHeaderField:@"Authorization"];
    } else {
        [redirect setValue:nil forHTTPHeaderField:@"Authorization"];
    }
    completionHandler(redirect);
}

@end
