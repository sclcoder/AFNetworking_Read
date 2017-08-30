// AFHTTPRequestOperation.m
// Copyright (c) 2011–2015 Alamofire Software Foundation (http://alamofire.org/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFHTTPRequestOperation.h"

// 一个GCD的并发队列
static dispatch_queue_t http_request_operation_processing_queue() {
    static dispatch_queue_t af_http_request_operation_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_http_request_operation_processing_queue = dispatch_queue_create("com.alamofire.networking.http-request.processing", DISPATCH_QUEUE_CONCURRENT);
    });

    return af_http_request_operation_processing_queue;
}

// 一个GCD调度组
static dispatch_group_t http_request_operation_completion_group() {
    static dispatch_group_t af_http_request_operation_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_http_request_operation_completion_group = dispatch_group_create();
    });

    return af_http_request_operation_completion_group;
}

#pragma mark -
// 这种用法第一次见 类扩展
@interface AFURLConnectionOperation ()
@property (readwrite, nonatomic, strong) NSURLRequest *request;
@property (readwrite, nonatomic, strong) NSURLResponse *response;
@end

@interface AFHTTPRequestOperation ()
@property (readwrite, nonatomic, strong) NSHTTPURLResponse *response;
@property (readwrite, nonatomic, strong) id responseObject;
@property (readwrite, nonatomic, strong) NSError *responseSerializationError;
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@end

@implementation AFHTTPRequestOperation
// @dynamic 就是要来告诉编译器，代码中用@dynamic修饰的属性，其getter和setter方法会在程序运行的时候或者用其他方式动态绑定，以便让编译器通过编译。
// 使用@synthesize，编译器会确实的产生getter和setter方法，而@dynamic仅仅是告诉编译器这两个方法在运行期会有的，无需产生警告。
@dynamic response;
@dynamic lock;

- (instancetype)initWithRequest:(NSURLRequest *)urlRequest {
    //  调用了父类，也是我们最核心的类AFURLConnectionOperation的初始化方法，首先我们要明确这个类是继承自NSOperation的   NSOperation是个抽象的类
    self = [super initWithRequest:urlRequest];
    if (!self) {
        return nil;
    }
    
    // 为什么要在这里设置responseSerializer 在manager中会给operation设置一次
    self.responseSerializer = [AFHTTPResponseSerializer serializer];

    return self;
}

// 设置解析器的setter
- (void)setResponseSerializer:(AFHTTPResponseSerializer <AFURLResponseSerialization> *)responseSerializer {
    NSParameterAssert(responseSerializer);

    [self.lock lock];
    _responseSerializer = responseSerializer;
    self.responseObject = nil;
    self.responseSerializationError = nil;
    [self.lock unlock];
}

- (id)responseObject {
    
    // 解析数据
    [self.lock lock];
    if (!_responseObject && [self isFinished] && !self.error) {
        NSError *error = nil;
        self.responseObject = [self.responseSerializer responseObjectForResponse:self.response data:self.responseData error:&error];
        if (error) {
            self.responseSerializationError = error;
        }
    }
    [self.lock unlock];

    return _responseObject;
}

- (NSError *)error {
    if (_responseSerializationError) {
        return _responseSerializationError;
    } else {
        return [super error];
    }
}

#pragma mark - AFHTTPRequestOperation

// 处理用户传入的block回调
- (void)setCompletionBlockWithSuccess:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                              failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    
    // 消除循环引用警告
    // completionBlock is manually nilled out in AFURLConnectionOperation to break the retain cycle.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
#pragma clang diagnostic ignored "-Wgnu"
    
    // self.completionBlock这个block是NSOperation的,当operation完成后会主动回调这个block
    
    // 给completionBlock赋值  重写了setter
    self.completionBlock = ^{
        
        NSLog(@"用户设置setCompletionBlock被调用 %s",__func__);
        
        if (self.completionGroup) {
            // 进入GCD的group
            dispatch_group_enter(self.completionGroup);
        }
        

        dispatch_async(http_request_operation_processing_queue(), ^{
            
            if (self.error) { // 如果有error说明请求失败
                
                if (failure) {
                    
                    // dispatch_group_async(,,)这种写法是一种简写方式 本质还是 dispatch_group_enter dispatch_group_leave
                    dispatch_group_async(self.completionGroup ?: http_request_operation_completion_group(), self.completionQueue ?: dispatch_get_main_queue(), ^{
                        
                        // 失败回调
                        failure(self, self.error);
                        
                    });
                }
                
            } else { // error为空 说明请求成功
                
                // 重写了self.responseObject方法--解析数据
                id responseObject = self.responseObject;
                
                if (self.error) { // 解析出错
                    
                    if (failure) {
                        dispatch_group_async(self.completionGroup ?: http_request_operation_completion_group(), self.completionQueue ?: dispatch_get_main_queue(), ^{
                            
                            // 失败回调
                            failure(self, self.error);
                        });
                    }
                    
                } else { // 没有解析错误
                    
                    if (success) {
                        dispatch_group_async(self.completionGroup ?: http_request_operation_completion_group(), self.completionQueue ?: dispatch_get_main_queue(), ^{
                            
                            // 成功回调
                            success(self, responseObject);
                        });
                    }
                }
            }

            if (self.completionGroup) {
                // 离开GCD组
                dispatch_group_leave(self.completionGroup);
            }
        });
    };
#pragma clang diagnostic pop
}

#pragma mark - AFURLRequestOperation

- (void)pause {
    [super pause];

    u_int64_t offset = 0;
    if ([self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey]) {
        offset = [(NSNumber *)[self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey] unsignedLongLongValue];
    } else {
        offset = [(NSData *)[self.outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] length];
    }

    NSMutableURLRequest *mutableURLRequest = [self.request mutableCopy];
    if ([self.response respondsToSelector:@selector(allHeaderFields)] && [[self.response allHeaderFields] valueForKey:@"ETag"]) {
        [mutableURLRequest setValue:[[self.response allHeaderFields] valueForKey:@"ETag"] forHTTPHeaderField:@"If-Range"];
    }
    [mutableURLRequest setValue:[NSString stringWithFormat:@"bytes=%llu-", offset] forHTTPHeaderField:@"Range"];
    self.request = mutableURLRequest;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (!self) {
        return nil;
    }

    self.responseSerializer = [decoder decodeObjectOfClass:[AFHTTPResponseSerializer class] forKey:NSStringFromSelector(@selector(responseSerializer))];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];

    [coder encodeObject:self.responseSerializer forKey:NSStringFromSelector(@selector(responseSerializer))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    AFHTTPRequestOperation *operation = [super copyWithZone:zone];

    operation.responseSerializer = [self.responseSerializer copyWithZone:zone];
    operation.completionQueue = self.completionQueue;
    operation.completionGroup = self.completionGroup;

    return operation;
}

@end
