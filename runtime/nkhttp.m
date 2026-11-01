// NKTouch v0.7.4 native HTTP/HTTPS helper
// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

static NSString * const NKHTTPErrorDomain = @"com.nk.nktouch.http";
static const NSUInteger NKMaxBodyBytes = 16u * 1024u * 1024u;
static const NSUInteger NKMaxResponseBytes = 32u * 1024u * 1024u;

typedef NS_ENUM(NSInteger, NKHTTPError) {
    NKHTTPInvalid = 1,
    NKHTTPIO = 2,
    NKHTTPLimit = 3,
    NKHTTPTransport = 4,
};

static NSString *sanitize(NSString *s) {
    if (!s) return @"";
    return [[s stringByReplacingOccurrencesOfString:@"\r" withString:@" "]
            stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

static NSDictionary<NSString *, NSString *> *readSpec(NSString *path, NSError **err) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:err];
    if (!text) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSSet *allowed = [NSSet setWithArray:@[@"method",@"url",@"timeout_ms",@"headers_file",@"body_file",@"response_file",@"meta_file",@"max_response_bytes"]];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (raw.length == 0) continue;
        NSRange r = [raw rangeOfString:@"="];
        if (r.location == NSNotFound || r.location == 0) {
            if (err) *err = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPInvalid userInfo:@{NSLocalizedDescriptionKey:@"invalid request spec line"}];
            return nil;
        }
        NSString *k = [raw substringToIndex:r.location];
        NSString *v = [raw substringFromIndex:r.location + 1];
        if (![allowed containsObject:k] || d[k] != nil) {
            if (err) *err = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPInvalid userInfo:@{NSLocalizedDescriptionKey:@"unknown or duplicate request spec key"}];
            return nil;
        }
        d[k] = v;
    }
    for (NSString *k in allowed) {
        if (!d[k]) {
            if (err) *err = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPInvalid userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"missing request spec key: %@", k]}];
            return nil;
        }
    }
    return d;
}

static BOOL validHeaderName(NSString *name) {
    if (name.length == 0) return NO;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    return [name rangeOfCharacterFromSet:[ok invertedSet]].location == NSNotFound;
}

static NSDictionary<NSString *, NSString *> *readHeaders(NSString *path, NSError **err) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:err];
    if (!text) return nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (raw.length == 0) continue;
        NSRange r = [raw rangeOfString:@":"];
        if (r.location == NSNotFound || r.location == 0) {
            if (err) *err = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPInvalid userInfo:@{NSLocalizedDescriptionKey:@"invalid header line"}];
            return nil;
        }
        NSString *name = [raw substringToIndex:r.location];
        NSString *value = [[raw substringFromIndex:r.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!validHeaderName(name) || [value rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) {
            if (err) *err = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPInvalid userInfo:@{NSLocalizedDescriptionKey:@"invalid header"}];
            return nil;
        }
        headers[name] = value;
    }
    return headers;
}

static void writeMeta(NSString *path, NSInteger status, NSUInteger bytes, NSString *ctype, NSString *finalURL, NSError *error) {
    NSString *msg = error ? sanitize(error.localizedDescription) : @"";
    NSInteger code = error ? error.code : 0;
    NSString *text = [NSString stringWithFormat:@"status=%ld\nbytes=%lu\ncontent_type=%@\nfinal_url=%@\nerror_code=%ld\nerror=%@\n",
                      (long)status, (unsigned long)bytes, sanitize(ctype), sanitize(finalURL), (long)code, msg];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@interface NKHTTPDelegate : NSObject <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property(nonatomic,strong) dispatch_semaphore_t sem;
@property(nonatomic,strong) NSFileHandle *handle;
@property(nonatomic,strong) NSError *error;
@property(nonatomic,strong) NSHTTPURLResponse *response;
@property(nonatomic,assign) NSUInteger bytes;
@property(nonatomic,assign) NSUInteger maxBytes;
@property(nonatomic,copy) NSString *originalScheme;
@end

@implementation NKHTTPDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    (void)session; (void)dataTask;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) self.response = (NSHTTPURLResponse *)response;
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    (void)session;
    if (self.error) return;
    if (self.bytes > self.maxBytes || data.length > self.maxBytes - self.bytes) {
        self.error = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPLimit userInfo:@{NSLocalizedDescriptionKey:@"response exceeds configured size limit"}];
        [dataTask cancel];
        return;
    }
    @try {
        [self.handle writeData:data];
        self.bytes += data.length;
    } @catch (NSException *ex) {
        self.error = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPIO userInfo:@{NSLocalizedDescriptionKey:ex.reason ?: @"response write failed"}];
        [dataTask cancel];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response;
    NSString *next = request.URL.scheme.lowercaseString;
    if ([self.originalScheme isEqualToString:@"https"] && [next isEqualToString:@"http"]) {
        completionHandler(nil); // Never downgrade HTTPS to cleartext through redirects.
    } else {
        completionHandler(request);
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;
    if (error && !self.error) self.error = error;
    if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) self.response = (NSHTTPURLResponse *)task.response;
    @try { [self.handle closeFile]; } @catch (__unused NSException *ex) {}
    dispatch_semaphore_signal(self.sem);
}
@end

static int runRequest(NSString *specPath) {
    NSError *err = nil;
    NSDictionary *spec = readSpec(specPath, &err);
    if (!spec) { fprintf(stderr, "NKHTTP: %s\n", sanitize(err.localizedDescription).UTF8String); return 2; }

    NSString *method = [spec[@"method"] uppercaseString];
    NSSet *methods = [NSSet setWithArray:@[@"GET",@"POST",@"PUT",@"PATCH",@"DELETE",@"HEAD",@"OPTIONS"]];
    if (![methods containsObject:method]) { fprintf(stderr, "NKHTTP: unsupported method\n"); return 2; }

    NSURL *url = [NSURL URLWithString:spec[@"url"]];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url || (! [scheme isEqualToString:@"https"] && ! [scheme isEqualToString:@"http"])) { fprintf(stderr, "NKHTTP: invalid URL scheme\n"); return 2; }

    NSInteger timeoutMs = [spec[@"timeout_ms"] integerValue];
    NSInteger maxBytesValue = [spec[@"max_response_bytes"] integerValue];
    if (timeoutMs < 100 || timeoutMs > 120000 || maxBytesValue < 1 || maxBytesValue > (NSInteger)NKMaxResponseBytes) { fprintf(stderr, "NKHTTP: invalid limits\n"); return 2; }

    NSDictionary *headers = readHeaders(spec[@"headers_file"], &err);
    if (!headers) { fprintf(stderr, "NKHTTP: %s\n", sanitize(err.localizedDescription).UTF8String); return 2; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:(NSTimeInterval)timeoutMs/1000.0];
    req.HTTPMethod = method;
    req.HTTPShouldHandleCookies = NO;
    for (NSString *name in headers) [req setValue:headers[name] forHTTPHeaderField:name];

    NSString *bodyPath = spec[@"body_file"];
    if (![bodyPath isEqualToString:@"-"]) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:bodyPath error:&err];
        unsigned long long bodySize = [attrs fileSize];
        if (!attrs || bodySize > NKMaxBodyBytes) { fprintf(stderr, "NKHTTP: request body missing or too large\n"); return 2; }
        NSData *body = [NSData dataWithContentsOfFile:bodyPath options:NSDataReadingMappedIfSafe error:&err];
        if (!body) { fprintf(stderr, "NKHTTP: cannot read request body\n"); return 2; }
        req.HTTPBody = body;
    }

    NSString *responsePath = spec[@"response_file"];
    [[NSFileManager defaultManager] removeItemAtPath:responsePath error:nil];
    if (![[NSFileManager defaultManager] createFileAtPath:responsePath contents:nil attributes:@{NSFilePosixPermissions:@0644}]) {
        fprintf(stderr, "NKHTTP: cannot create response file\n"); return 3;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:responsePath];
    if (!handle) { fprintf(stderr, "NKHTTP: cannot open response file\n"); return 3; }

    NKHTTPDelegate *delegate = [NKHTTPDelegate new];
    delegate.sem = dispatch_semaphore_create(0);
    delegate.handle = handle;
    delegate.bytes = 0;
    delegate.maxBytes = (NSUInteger)maxBytesValue;
    delegate.originalScheme = scheme;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.URLCache = nil;
    config.HTTPCookieStorage = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = (NSTimeInterval)timeoutMs/1000.0;
    config.timeoutIntervalForResource = (NSTimeInterval)timeoutMs/1000.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req];
    [task resume];

    dispatch_time_t until = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutMs + 3000) * NSEC_PER_MSEC);
    if (dispatch_semaphore_wait(delegate.sem, until) != 0) {
        [task cancel];
        delegate.error = [NSError errorWithDomain:NKHTTPErrorDomain code:NKHTTPTransport userInfo:@{NSLocalizedDescriptionKey:@"request timed out"}];
    }
    [session finishTasksAndInvalidate];

    NSInteger status = delegate.response.statusCode;
    NSString *ctype = delegate.response.MIMEType ?: @"";
    NSString *finalURL = delegate.response.URL.absoluteString ?: url.absoluteString ?: @"";
    writeMeta(spec[@"meta_file"], status, delegate.bytes, ctype, finalURL, delegate.error);
    if (delegate.error) {
        [[NSFileManager defaultManager] removeItemAtPath:responsePath error:nil];
        return 7;
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "version") == 0) { puts("0.7.4"); return 0; }
        if (argc != 3 || strcmp(argv[1], "request") != 0) {
            fprintf(stderr, "usage: nkhttp request <request-spec-file>\n");
            return 2;
        }
        return runRequest([NSString stringWithUTF8String:argv[2]]);
    }
}
