// AFURLConnectionOperation.m
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

#import "AFURLConnectionOperation.h"

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#import <UIKit/UIKit.h>
#endif

#if !__has_feature(objc_arc)
#error AFNetworking must be built with ARC.
// You can turn on ARC for only AFNetworking files by adding -fobjc-arc to the build phase for each of its files.
#endif

// 标志着网络请求的状态
typedef NS_ENUM(NSInteger, AFOperationState) {
    AFOperationPausedState      = -1, // 暂停
    AFOperationReadyState       = 1,  // 准备就绪
    AFOperationExecutingState   = 2,  // 正在进行中
    AFOperationFinishedState    = 3,  // 完成
};

static dispatch_group_t url_request_operation_completion_group() {
    static dispatch_group_t af_url_request_operation_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_request_operation_completion_group = dispatch_group_create();
    });

    return af_url_request_operation_completion_group;
}

static dispatch_queue_t url_request_operation_completion_queue() {
    static dispatch_queue_t af_url_request_operation_completion_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_request_operation_completion_queue = dispatch_queue_create("com.alamofire.networking.operation.queue", DISPATCH_QUEUE_CONCURRENT );
    });

    return af_url_request_operation_completion_queue;
}

static NSString * const kAFNetworkingLockName = @"com.alamofire.networking.operation.lock";

NSString * const AFNetworkingOperationDidStartNotification = @"com.alamofire.networking.operation.start";
NSString * const AFNetworkingOperationDidFinishNotification = @"com.alamofire.networking.operation.finish";

typedef void (^AFURLConnectionOperationProgressBlock)(NSUInteger bytes, long long totalBytes, long long totalBytesExpected);
typedef void (^AFURLConnectionOperationAuthenticationChallengeBlock)(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge);
typedef NSCachedURLResponse * (^AFURLConnectionOperationCacheResponseBlock)(NSURLConnection *connection, NSCachedURLResponse *cachedResponse);
typedef NSURLRequest * (^AFURLConnectionOperationRedirectResponseBlock)(NSURLConnection *connection, NSURLRequest *request, NSURLResponse *redirectResponse);
typedef void (^AFURLConnectionOperationBackgroundTaskCleanupBlock)();


// 映射这个NSOperation的各个状态
static inline NSString * AFKeyPathFromOperationState(AFOperationState state) {
    switch (state) {
        case AFOperationReadyState:
            return @"isReady";
        case AFOperationExecutingState:
            return @"isExecuting";
        case AFOperationFinishedState:
            return @"isFinished";
        case AFOperationPausedState:
            return @"isPaused";
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            return @"state";
#pragma clang diagnostic pop
        }
    }
}

static inline BOOL AFStateTransitionIsValid(AFOperationState fromState, AFOperationState toState, BOOL isCancelled) {
    switch (fromState) {
        case AFOperationReadyState:
            switch (toState) {
                case AFOperationPausedState:
                case AFOperationExecutingState:
                    return YES;
                case AFOperationFinishedState:
                    return isCancelled;
                default:
                    return NO;
            }
        case AFOperationExecutingState:
            switch (toState) {
                case AFOperationPausedState:
                case AFOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        case AFOperationFinishedState:
            return NO;
        case AFOperationPausedState:
            return toState == AFOperationReadyState;
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            switch (toState) {
                case AFOperationPausedState:
                case AFOperationReadyState:
                case AFOperationExecutingState:
                case AFOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        }
#pragma clang diagnostic pop
    }
}

// 类扩展 私有的 子类 无法直接访问
@interface AFURLConnectionOperation ()

@property (readwrite, nonatomic, assign) AFOperationState state;
@property (readwrite, nonatomic, strong) NSRecursiveLock *lock;
@property (readwrite, nonatomic, strong) NSURLConnection *connection;
@property (readwrite, nonatomic, strong) NSURLRequest *request;
@property (readwrite, nonatomic, strong) NSURLResponse *response;
@property (readwrite, nonatomic, strong) NSError *error;
@property (readwrite, nonatomic, strong) NSData *responseData;
@property (readwrite, nonatomic, copy) NSString *responseString;
@property (readwrite, nonatomic, assign) NSStringEncoding responseStringEncoding;
@property (readwrite, nonatomic, assign) long long totalBytesRead;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationBackgroundTaskCleanupBlock backgroundTaskCleanup;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationProgressBlock uploadProgress;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationProgressBlock downloadProgress;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationAuthenticationChallengeBlock authenticationChallenge;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationCacheResponseBlock cacheResponse;
@property (readwrite, nonatomic, copy) AFURLConnectionOperationRedirectResponseBlock redirectResponse;

- (void)operationDidStart;
- (void)finish;
- (void)cancelConnection;
@end

@implementation AFURLConnectionOperation
// 合成setter、getter 生成成员变量_outputStream
@synthesize outputStream = _outputStream;

+ (void)networkRequestThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"AFNetworking"];

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        // 添加端口，防止runloop直接退出
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

// 这是一个单例，用NSThread创建了一个线程，并且为这个线程添加了一个runloop，并且加了一个NSMachPort，来防止runloop直接退出
/**
   这条线程就是AF用来发起网络请求，并且接受网络请求回调的线程，仅仅就这一条线程。和我们之前讲的AF3.x发起请求，并且接受请求回调时的处理方式，遥相呼应
 */
+ (NSThread *)networkRequestThread {
    static NSThread *_networkRequestThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _networkRequestThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [_networkRequestThread start];
    });

    return _networkRequestThread;
}

- (instancetype)initWithRequest:(NSURLRequest *)urlRequest {
    NSParameterAssert(urlRequest);

    self = [super init];
    if (!self) {
		return nil;
    }
    // 设置为ready 这里面有关于自定义NSOperation的学问
    _state = AFOperationReadyState;
    
    
    // 递归锁 -- 它允许同一线程多次加锁，而不会造成死锁
    // self.lock这个锁是用来提供给本类一些数据操作的线程安全，至于为什么要用递归锁，是因为有些方法可能会存在递归调用的情况，例如有些需要锁的方法可能会在一个大的操作环中，形成递归。而AF使用了递归锁，避免了这种情况下死锁的发生。
    self.lock = [[NSRecursiveLock alloc] init];
    self.lock.name = kAFNetworkingLockName;
    
    // 初始化了self.runLoopModes，默认为NSRunLoopCommonModes。
    self.runLoopModes = [NSSet setWithObject:NSRunLoopCommonModes];

    self.request = urlRequest;
    // 是否应该咨询证书存储连接
    self.shouldUseCredentialStorage = YES;
    // https认证策略
    self.securityPolicy = [AFSecurityPolicy defaultPolicy];

    return self;
    
    /**
        初始化结束后，看似这个类中的方法的都没被执行。其实不然，由于这个类继承NSOperation，当将operation添加到Queue中后,队列会调用operation。而operation的入口方法是 start 所以,要从这个类的start方法入手。
     */
}

- (instancetype)init NS_UNAVAILABLE
{
    return nil;
}

- (void)dealloc {
    if (_outputStream) {
        [_outputStream close];
        _outputStream = nil;
    }
    
    if (_backgroundTaskCleanup) {
        _backgroundTaskCleanup();
    }
}

#pragma mark -
// 网络请求结束 connection的代理方法 会触发改方法
- (void)setResponseData:(NSData *)responseData {
    
    [self.lock lock];
    if (!responseData) {
        _responseData = nil;
    } else {
        _responseData = [NSData dataWithBytes:responseData.bytes length:responseData.length];
    }
    [self.lock unlock];
}

- (NSString *)responseString {
    [self.lock lock];
    if (!_responseString && self.response && self.responseData) {
        self.responseString = [[NSString alloc] initWithData:self.responseData encoding:self.responseStringEncoding];
    }
    [self.lock unlock];

    return _responseString;
}

- (NSStringEncoding)responseStringEncoding {
    [self.lock lock];
    if (!_responseStringEncoding && self.response) {
        NSStringEncoding stringEncoding = NSUTF8StringEncoding;
        if (self.response.textEncodingName) {
            CFStringEncoding IANAEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)self.response.textEncodingName);
            if (IANAEncoding != kCFStringEncodingInvalidId) {
                stringEncoding = CFStringConvertEncodingToNSStringEncoding(IANAEncoding);
            }
        }

        self.responseStringEncoding = stringEncoding;
    }
    [self.lock unlock];

    return _responseStringEncoding;
}

- (NSInputStream *)inputStream {
    return self.request.HTTPBodyStream;
}

- (void)setInputStream:(NSInputStream *)inputStream {
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    mutableRequest.HTTPBodyStream = inputStream;
    self.request = mutableRequest;
}

- (NSOutputStream *)outputStream {
    if (!_outputStream) {
        // 一个写入到内存中的流，可以通过NSStreamDataWrittenToMemoryStreamKey拿到写入后的数据
        self.outputStream = [NSOutputStream outputStreamToMemory];
    }

    return _outputStream;
    
    /**
     这里数据请求和拼接并没有用NSMutableData，而是用了outputStream，而且把写入的数据，放到内存中。
     
     其实讲道理来说outputStream的优势在于下载大文件的时候，可以以流的形式，将文件直接保存到本地，这样可以为我们节省很多的内存，调用如下方法设置：
     [NSOutputStream outputStreamToFileAtPath:@"filePath" append:YES];
     
     但是这里是把流写入内存中，这样其实这个节省内存的意义已经不存在了。那为什么还要用呢？这里我猜测的是就是为了用它这个可以注册在某一个runloop的指定mode下。 虽然AF使用这个outputStream是肯定在这个常驻线程中的，不会有线程安全的问题。但是要注意它是被声明在.h中的：
     @property (nonatomic, strong) NSOutputStream *outputStream;
     难保外部不会在其他线程对这个数据做什么操作，所以它相对于NSMutableData作用就体现出来了，就算我们在外部其它线程中去操作它，也不会有线程安全的问题
     */
    
}

- (void)setOutputStream:(NSOutputStream *)outputStream {
    [self.lock lock];
    if (outputStream != _outputStream) {
        if (_outputStream) {
            [_outputStream close];
        }

        _outputStream = outputStream;
    }
    [self.lock unlock];
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
- (void)setShouldExecuteAsBackgroundTaskWithExpirationHandler:(void (^)(void))handler {
    [self.lock lock];
    if (!self.backgroundTaskCleanup) {
        UIApplication *application = [UIApplication sharedApplication];
        UIBackgroundTaskIdentifier __block backgroundTaskIdentifier = UIBackgroundTaskInvalid;
        __weak __typeof(self)weakSelf = self;
        
        self.backgroundTaskCleanup = ^(){
            if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
                backgroundTaskIdentifier = UIBackgroundTaskInvalid;
            }
        };
        
        backgroundTaskIdentifier = [application beginBackgroundTaskWithExpirationHandler:^{
            __strong __typeof(weakSelf)strongSelf = weakSelf;

            if (handler) {
                handler();
            }

            if (strongSelf) {
                [strongSelf cancel];
                strongSelf.backgroundTaskCleanup();
            }
        }];
    }
    [self.lock unlock];
}
#endif

#pragma mark -

- (void)setState:(AFOperationState)state {
    
    // 判断从当前状态到另一个状态是不是合理，在加上现在是否取消。。大神的框架就是屌啊，这判断严谨的。。一层层
    if (!AFStateTransitionIsValid(self.state, state, [self isCancelled])) {
        return;
    }

    [self.lock lock];
    // 获取NSOperation中需要KVO的keyPath  自定义并发NSOperation必须这样做
    // 拿到对应的父类（NSOperation）管理当前线程周期的key
    NSString *oldStateKey = AFKeyPathFromOperationState(self.state);
    NSString *newStateKey = AFKeyPathFromOperationState(state);
    
    // 发出KVO
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _state = state; // 直接访问成员变量 不能是用点语法 会死循环
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self.lock unlock];
    
    /**
     这个方法改变state的时候，并且发送了KVO。
     大家了解NSOperationQueue就知道，如果对应的operation的属性finnished被设置为YES，则代表当前operation结束了，会把operation从队列中移除，并且调用operation的completionBlock。
     */
}

- (void)pause {
    if ([self isPaused] || [self isFinished] || [self isCancelled]) {
        return;
    }

    [self.lock lock];
    if ([self isExecuting]) {
        [self performSelector:@selector(operationDidPause) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter postNotificationName:AFNetworkingOperationDidFinishNotification object:self];
        });
    }

    self.state = AFOperationPausedState;
    [self.lock unlock];
}

- (void)operationDidPause {
    [self.lock lock];
    [self.connection cancel];
    [self.lock unlock];
}

- (BOOL)isPaused {
    return self.state == AFOperationPausedState;
}

- (void)resume {
    if (![self isPaused]) {
        return;
    }

    [self.lock lock];
    self.state = AFOperationReadyState;

    [self start];
    [self.lock unlock];
}

#pragma mark -
// .h中声明的相关方法
- (void)setUploadProgressBlock:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))block {
    // 记录用户传入的block
    self.uploadProgress = block;
}

- (void)setDownloadProgressBlock:(void (^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))block {
    self.downloadProgress = block;
}

- (void)setWillSendRequestForAuthenticationChallengeBlock:(void (^)(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge))block {
    self.authenticationChallenge = block;
}

- (void)setCacheResponseBlock:(NSCachedURLResponse * (^)(NSURLConnection *connection, NSCachedURLResponse *cachedResponse))block {
    self.cacheResponse = block;
}

- (void)setRedirectResponseBlock:(NSURLRequest * (^)(NSURLConnection *connection, NSURLRequest *request, NSURLResponse *redirectResponse))block {
    self.redirectResponse = block;
}

#pragma mark - NSOperation

// 重写NSOperation的方法 在设置setCompletionBlock时加上了锁
// 为什么要加锁?
- (void)setCompletionBlock:(void (^)(void))block {
    
    [self.lock lock];
    
    if (!block) {
        
        [super setCompletionBlock:nil];
        
    } else {
        
        __weak __typeof(self)weakSelf = self;
        
        // 给父类NSOperation设置回调 当NSOperation任务完成后会执行这个传入的CompletionBlock
        [super setCompletionBlock:^ {
            
            NSLog(@"AF设置setCompletionBlock被调用 %s",__func__);
            
            __strong __typeof(weakSelf)strongSelf = weakSelf;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            // 看有没有自定义的完成组，否则用AF的组
            dispatch_group_t group = strongSelf.completionGroup ?: url_request_operation_completion_group();
            // 看有没有自定义的完成queue，否则用主队列
            dispatch_queue_t queue = strongSelf.completionQueue ?: dispatch_get_main_queue();
#pragma clang diagnostic pop

            dispatch_group_async(group, queue, ^{
            // 调用设置的Block,在这个组和队列中
                block();
            });

            dispatch_group_notify(group, url_request_operation_completion_queue(), ^{
                
                // 所有任务都完成后 清空CompletionBlock 防止循环引用
                [strongSelf setCompletionBlock:nil];
            });
        }];
    }
    [self.lock unlock];
}


// 自定义并发的NSOperation时需要重写NSOperation的部分方法

// 复写了NSOperation的这些属性的get方法，用来和自定义的state一一对应：
- (BOOL)isReady {
    return self.state == AFOperationReadyState && [super isReady];
}

- (BOOL)isExecuting {
    return self.state == AFOperationExecutingState;
}

- (BOOL)isFinished {
    return self.state == AFOperationFinishedState;
}

// 标志这个operation是并发的
- (BOOL)isConcurrent {
    return YES;
}

// 这个类为了自定义operation的各种状态，而且更好的掌控它的生命周期，复写了operation的start方法，当这个operation在一个新线程被调度执行的时候，首先就调入这个start方法中

// 重写operation的start方法
// operation就是从start方法开始执行的

- (void)start {
    
    [self.lock lock];
    // 如果被取消了就调用取消的方法
    if ([self isCancelled]) {
        // 在AF常驻线程中去执行 operation的任务
        [self performSelector:@selector(cancelConnection) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
        // 准备好了，才开始
    } else if ([self isReady]) {
        
        // 改变状态，开始执行 setter方法触发了KVO通知
        self.state = AFOperationExecutingState;
        
        
        // 在常驻线程中,并且不阻塞的方式，在我们self.runLoopModes的模式下调用 operationDidStart
        [self performSelector:@selector(operationDidStart) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
    }
    // 注意，发起请求和取消请求都是在同一个线程！！包括回调都是在一个线程
    
    [self.lock unlock];
}


// 这个operation发起了一个NSURLConnection的请求
- (void)operationDidStart {
    
    // 此时已经进入到AF的常驻子线程中了

    [self.lock lock];
    
    // 自定义NSOperation中的问题 需要经常检查operation是否取消 http://blog.leichunfeng.com/blog/2015/07/29/ios-concurrency-programming-operation-queues/
    if (![self isCancelled]) {
        
        /**
         Returns an initialized URL connection and begins to load the data for the URL request, if specified.
         During the download the connection maintains a strong reference to the delegate. It releases that strong reference when the connection finishes loading, fails, or is canceled.
         
         Parameters
         request
         The URL request to load. The request object is deep-copied as part of the initialization process. Changes made to request after this method returns do not affect the request that is used for the loading process.
         
         delegate
         The delegate object for the connection. The connection calls methods on this delegate as the load progresses.
         
         startImmediately
         YES if the connection should begin loading data immediately, otherwise NO. If you pass NO, the connection is not scheduled with a run loop. You can then schedule the connection in the run loop and mode of your choice by calling scheduleInRunLoop:forMode:
         startImmediately如果设置为NO 这个connection不会加入到runloop中 需要自己指定runloop
         */
        // 如果设置为startImmediately YES 请求发出，回调会加入到主线程的 Runloop 下，RunloopMode 会默认为 NSDefaultRunLoopMode
        
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        for (NSString *runLoopMode in self.runLoopModes) {
            
            // 把connection和outputStream注册到当前线程runloop中去，只有这样，才能在这个线程中回调
            // 此处已经是AF的常驻子线程
            [self.connection scheduleInRunLoop:runLoop forMode:runLoopMode];
            //一个写入到内存中的流，可以通过NSStreamDataWrittenToMemoryStreamKey拿到写入后的数据
            [self.outputStream scheduleInRunLoop:runLoop forMode:runLoopMode];
        }
        // 打开输入流
        [self.outputStream open];
        
        // 开始请求  -- 进入代理回调方法
        [self.connection start];
    }
    [self.lock unlock];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingOperationDidStartNotification object:self];
    });
}

- (void)finish {
    [self.lock lock];
    //
    // 修改状态 -- 会发送KVO通知
    self.state = AFOperationFinishedState;
    [self.lock unlock];
    
    //发送完成的通知
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingOperationDidFinishNotification object:self];
    });
}

- (void)cancel {
    [self.lock lock];
    if (![self isFinished] && ![self isCancelled]) {
        [super cancel];

        if ([self isExecuting]) {
            [self performSelector:@selector(cancelConnection) onThread:[[self class] networkRequestThread] withObject:nil waitUntilDone:NO modes:[self.runLoopModes allObjects]];
        }
    }
    [self.lock unlock];
}

- (void)cancelConnection {
    NSDictionary *userInfo = nil;
    if ([self.request URL]) {
        userInfo = @{NSURLErrorFailingURLErrorKey : [self.request URL]};
    }
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];

    if (![self isFinished]) {
        if (self.connection) {
            [self.connection cancel];
            [self performSelector:@selector(connection:didFailWithError:) withObject:self.connection withObject:error];
        } else {
            // Accommodate race condition where `self.connection` has not yet been set before cancellation
            self.error = error;
            [self finish];
        }
    }
}

#pragma mark -

+ (NSArray *)batchOfRequestOperations:(NSArray *)operations
                        progressBlock:(void (^)(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations))progressBlock
                      completionBlock:(void (^)(NSArray *operations))completionBlock
{
    if (!operations || [operations count] == 0) {
        return @[[NSBlockOperation blockOperationWithBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) {
                    completionBlock(@[]);
                }
            });
        }]];
    }

    __block dispatch_group_t group = dispatch_group_create();
    NSBlockOperation *batchedOperation = [NSBlockOperation blockOperationWithBlock:^{
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(operations);
            }
        });
    }];

    for (AFURLConnectionOperation *operation in operations) {
        operation.completionGroup = group;
        void (^originalCompletionBlock)(void) = [operation.completionBlock copy];
        __weak __typeof(operation)weakOperation = operation;
        operation.completionBlock = ^{
            __strong __typeof(weakOperation)strongOperation = weakOperation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_queue_t queue = strongOperation.completionQueue ?: dispatch_get_main_queue();
#pragma clang diagnostic pop
            dispatch_group_async(group, queue, ^{
                if (originalCompletionBlock) {
                    originalCompletionBlock();
                }

                NSUInteger numberOfFinishedOperations = [[operations indexesOfObjectsPassingTest:^BOOL(id op, NSUInteger __unused idx,  BOOL __unused *stop) {
                    return [op isFinished];
                }] count];

                if (progressBlock) {
                    progressBlock(numberOfFinishedOperations, [operations count]);
                }

                dispatch_group_leave(group);
            });
        };

        dispatch_group_enter(group);
        [batchedOperation addDependency:operation];
    }

    return [operations arrayByAddingObject:batchedOperation];
}

#pragma mark - NSObject

- (NSString *)description {
    [self.lock lock];
    NSString *description = [NSString stringWithFormat:@"<%@: %p, state: %@, cancelled: %@ request: %@, response: %@>", NSStringFromClass([self class]), self, AFKeyPathFromOperationState(self.state), ([self isCancelled] ? @"YES" : @"NO"), self.request, self.response];
    [self.lock unlock];
    return description;
}

#pragma mark - NSURLConnectionDelegate
// Https相关
- (void)connection:(NSURLConnection *)connection
willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (self.authenticationChallenge) {
        self.authenticationChallenge(connection, challenge);
        return;
    }

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
        } else {
            [[challenge sender] cancelAuthenticationChallenge:challenge];
        }
    } else {
        if ([challenge previousFailureCount] == 0) {
            if (self.credential) {
                [[challenge sender] useCredential:self.credential forAuthenticationChallenge:challenge];
            } else {
                [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            }
        } else {
            [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection __unused *)connection {
    return self.shouldUseCredentialStorage;
}

// 重定向相关
- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse
{
    if (self.redirectResponse) {
        return self.redirectResponse(connection, request, redirectResponse);
    } else {
        return request;
    }
}

- (void)connection:(NSURLConnection __unused *)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.uploadProgress) {
            self.uploadProgress((NSUInteger)bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        }
    });
}

//收到响应，响应头类似相关数据

- (void)connection:(NSURLConnection __unused *)connection
didReceiveResponse:(NSURLResponse *)response
{
    // 赋值
    self.response = response;
}

// 拼接获取到的数据
- (void)connection:(NSURLConnection __unused *)connection
    didReceiveData:(NSData *)data
{
    NSUInteger length = [data length];
    while (YES) {
        NSInteger totalNumberOfBytesWritten = 0;
        if ([self.outputStream hasSpaceAvailable]) {
            //创建一个buffer流缓冲区，大小为data的字节数
            const uint8_t *dataBuffer = (uint8_t *)[data bytes];

            NSInteger numberOfBytesWritten = 0;
            //当写的长度小于数据的长度，在循环里
            while (totalNumberOfBytesWritten < (NSInteger)length) {
                /**
                 - (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len;
                 
                 buffer:The data to write.
                 length:The length of the data buffer, in bytes.
                 Important:The behavior of this method is undefined if you pass a negative or zero number.
                 Returns
                     A number indicating the outcome of the operation:
                     A positive number indicates the number of bytes written.
                     0 indicates that a fixed-length stream and has reached its capacity.
                     -1 means that the operation failed; more information about the error can be obtained with streamError.
                 */
                // 往outputStream写数据，系统的方法，一次就写一部分，得循环写
                numberOfBytesWritten = [self.outputStream write:&dataBuffer[(NSUInteger)totalNumberOfBytesWritten] maxLength:(length - (NSUInteger)totalNumberOfBytesWritten)];
                if (numberOfBytesWritten == -1) {
                    break;
                }

                totalNumberOfBytesWritten += numberOfBytesWritten;
            }

            break;
        } else {
            [self.connection cancel];
            if (self.outputStream.streamError) {
                [self performSelector:@selector(connection:didFailWithError:) withObject:self.connection withObject:self.outputStream.streamError];
            }
            return;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.totalBytesRead += (long long)length;

        if (self.downloadProgress) {
            self.downloadProgress(length, self.totalBytesRead, self.response.expectedContentLength);
        }
    });
}

//完成了调用
- (void)connectionDidFinishLoading:(NSURLConnection __unused *)connection {
    
    // 从outputStream中拿到数据 NSStreamDataWrittenToMemoryStreamKey写入到内存中的流
    // 重写了responseData的setter
    self.responseData = [self.outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    // 关闭outputStream
    [self.outputStream close];
    // 如果响应数据已经有了，则outputStream置为nil
    if (self.responseData) {
       self.outputStream = nil;
    }
    // 清空connection
    self.connection = nil;
    // 调用finish  -- finish方法改变state状态为finished时会触发KVO通知 导致operation的状态为isFinished为真 从而导致触发operation完成block的回调
    // 大家了解NSOperationQueue就知道，如果对应的operation的属性finnished被设置为YES，则代表当前operation结束了，会把operation从队列中移除，并且调用operation的completionBlock。

    [self finish];
    
    /**
     这个代理是任务完成之后调用。我们从outputStream拿到了最后下载数据，然后关闭置空了outputStream。并且清空了connection。调用了finish:
     */
}


// 请求失败的回调，在cancel connection的时候，自己也主动调用了
- (void)connection:(NSURLConnection __unused *)connection
  didFailWithError:(NSError *)error
{
    
    // 唯一需要说一下的就是这里给self.error赋值，之后完成Block会根据这个error，去判断这次请求是成功还是失败。
    self.error = error;
    // 关闭outputStream
    [self.outputStream close];
    // 如果响应数据已经有了，则outputStream置为nil
    if (self.responseData) {
        self.outputStream = nil;
    }

    self.connection = nil;
    
    [self finish];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    if (self.cacheResponse) {
        return self.cacheResponse(connection, cachedResponse);
    } else {
        if ([self isCancelled]) {
            return nil;
        }

        return cachedResponse;
    }
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder {
    NSURLRequest *request = [decoder decodeObjectOfClass:[NSURLRequest class] forKey:NSStringFromSelector(@selector(request))];

    self = [self initWithRequest:request];
    if (!self) {
        return nil;
    }

    self.state = (AFOperationState)[[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(state))] integerValue];
    self.response = [decoder decodeObjectOfClass:[NSHTTPURLResponse class] forKey:NSStringFromSelector(@selector(response))];
    self.error = [decoder decodeObjectOfClass:[NSError class] forKey:NSStringFromSelector(@selector(error))];
    self.responseData = [decoder decodeObjectOfClass:[NSData class] forKey:NSStringFromSelector(@selector(responseData))];
    self.totalBytesRead = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(totalBytesRead))] longLongValue];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [self pause];

    [coder encodeObject:self.request forKey:NSStringFromSelector(@selector(request))];

    switch (self.state) {
        case AFOperationExecutingState:
        case AFOperationPausedState:
            [coder encodeInteger:AFOperationReadyState forKey:NSStringFromSelector(@selector(state))];
            break;
        default:
            [coder encodeInteger:self.state forKey:NSStringFromSelector(@selector(state))];
            break;
    }

    [coder encodeObject:self.response forKey:NSStringFromSelector(@selector(response))];
    [coder encodeObject:self.error forKey:NSStringFromSelector(@selector(error))];
    [coder encodeObject:self.responseData forKey:NSStringFromSelector(@selector(responseData))];
    [coder encodeInt64:self.totalBytesRead forKey:NSStringFromSelector(@selector(totalBytesRead))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    AFURLConnectionOperation *operation = [(AFURLConnectionOperation *)[[self class] allocWithZone:zone] initWithRequest:self.request];

    operation.uploadProgress = self.uploadProgress;
    operation.downloadProgress = self.downloadProgress;
    operation.authenticationChallenge = self.authenticationChallenge;
    operation.cacheResponse = self.cacheResponse;
    operation.redirectResponse = self.redirectResponse;
    operation.completionQueue = self.completionQueue;
    operation.completionGroup = self.completionGroup;

    return operation;
}

@end
