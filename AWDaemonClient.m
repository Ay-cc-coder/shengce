#import "AWDaemonClient.h"
#import "AWShared.h"

@implementation AWDaemonSnapshot
@end

@interface AWDaemonClient ()
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation AWDaemonClient

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 3.0;
        configuration.timeoutIntervalForResource = 40.0;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCache = nil;
        configuration.waitsForConnectivity = NO;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

- (void)cancel {
    [self.session invalidateAndCancel];
    self.session = nil;
}

- (NSURL *)URLForPath:(NSString *)path {
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"http";
    components.host = @"127.0.0.1";
    components.port = @(AWAPIPort);
    components.path = path;
    return components.URL;
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path method:(NSString *)method body:(NSData *)body timeout:(NSTimeInterval)timeout {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self URLForPath:path]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:timeout];
    request.HTTPMethod = method;
    [request setValue:AWAPIToken forHTTPHeaderField:@"X-AudioWatch-Token"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        request.HTTPBody = body;
        [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    }
    return request;
}

- (void)fetchSnapshot:(void (^)(AWDaemonSnapshot *, NSError *))completion {
    if (!self.session) {
        NSError *error = [NSError errorWithDomain:@"AudioWatch" code:1 userInfo:@{NSLocalizedDescriptionKey : @"控制通道已关闭"}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
        return;
    }
    NSMutableURLRequest *request = [self requestForPath:@"/v1/status" method:@"GET" body:nil timeout:2.5];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSError *wrapped = [NSError errorWithDomain:@"AudioWatch" code:error.code userInfo:@{NSLocalizedDescriptionKey : @"守护进程未响应"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, wrapped); });
            return;
        }
        NSDictionary *json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![json isKindOfClass:NSDictionary.class] || ![json[@"ok"] boolValue]) {
            NSString *message = [json[@"error"] isKindOfClass:NSString.class] ? json[@"error"] : @"守护进程返回无效数据";
            NSError *wrapped = [NSError errorWithDomain:@"AudioWatch" code:2 userInfo:@{NSLocalizedDescriptionKey : message}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, wrapped); });
            return;
        }
        AWDaemonSnapshot *snapshot = [AWDaemonSnapshot new];
        snapshot.status = [json[@"status"] isKindOfClass:NSDictionary.class] ? json[@"status"] : @{};
        snapshot.config = [json[@"config"] isKindOfClass:NSDictionary.class] ? json[@"config"] : @{};
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot, nil); });
    }] resume];
}

- (void)postCommand:(NSString *)path body:(NSDictionary *)body completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!self.session) {
        NSError *error = [NSError errorWithDomain:@"AudioWatch" code:1 userInfo:@{NSLocalizedDescriptionKey : @"控制通道已关闭"}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
        return;
    }
    NSData *data = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
    NSTimeInterval timeout = [path isEqualToString:@"/v1/test"] ? 28.0 : 6.0;
    NSMutableURLRequest *request = [self requestForPath:path method:@"POST" body:data timeout:timeout];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
        if (error) {
            NSError *wrapped = [NSError errorWithDomain:@"AudioWatch" code:error.code userInfo:@{NSLocalizedDescriptionKey : @"无法连接守护进程"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, wrapped); });
            return;
        }
        NSDictionary *json = responseData.length ? [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil] : nil;
        if (![json isKindOfClass:NSDictionary.class] || ![json[@"ok"] boolValue]) {
            NSString *message = [json[@"error"] isKindOfClass:NSString.class] ? json[@"error"] : @"操作失败";
            NSError *wrapped = [NSError errorWithDomain:@"AudioWatch" code:3 userInfo:@{NSLocalizedDescriptionKey : message}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, wrapped); });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(json, nil); });
    }] resume];
}

@end
