// AFURLSessionManager.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
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

#import "AFURLSessionManager.h"
#import <objc/runtime.h>

#ifndef NSFoundationVersionNumber_iOS_8_0
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug 1140.11
#else
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug NSFoundationVersionNumber_iOS_8_0
#endif

static dispatch_queue_t url_session_manager_creation_queue() {
    static dispatch_queue_t af_url_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_creation_queue = dispatch_queue_create("com.alamofire.networking.session.manager.creation", DISPATCH_QUEUE_SERIAL);
    });

    return af_url_session_manager_creation_queue;
}

static void url_session_manager_create_task_safely(dispatch_block_t block) {
    
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_With_Fixed_5871104061079552_bug) {
        // Fix of bug
        // Open Radar:http://openradar.appspot.com/radar?id=5871104061079552 (status: Fixed in iOS8)
        // Issue about:https://github.com/AFNetworking/AFNetworking/issues/2093
        
        // 为什么用sync ？
        // 因为是想要主线程等在这，等执行完，在返回，因为必须执行完 dataTask才有数据，传值才有意义。
        
        // 为什么要用串行队列？
        // 因为这块是为了防止ios8以下内部的dataTaskWithRequest是并发创建的， //这样会导致taskIdentifiers这个属性值不唯一，因为后续要用taskIdentifiers来作为Key对应delegate。
        
        // 同步任务串行队列 不开线程顺序执行
        
        dispatch_sync(url_session_manager_creation_queue(), block);
        
        /**
         方法非常简单，关键是理解这么做的目的：为什么我们不直接去调用
         dataTask = [self.session dataTaskWithRequest:request];
         非要绕这么一圈，我们点进去bug日志里看看，原来这是为了适配iOS8的以下，创建session的时候，偶发的情况会出现session的属性taskIdentifier这个值不唯一，而这个taskIdentifier是我们后面来映射delegate的key,所以它必须是唯一的。
         具体原因应该是NSURLSession内部去生成task的时候是用多线程并发去执行的。想通了这一点，我们就很好解决了，我们只需要在iOS8以下同步串行的去生成task就可以防止这一问题发生（如果还是不理解同步串行的原因，可以看看注释）
         */
        
        
    } else {
        // ios8以上 直接执行block
        block();
    }
}

static dispatch_queue_t url_session_manager_processing_queue() {
    static dispatch_queue_t af_url_session_manager_processing_queue;
    static dispatch_once_t onceToken;
    // 保证了即使是在多线程的环境下，也不会创建其他队列
    dispatch_once(&onceToken, ^{
        af_url_session_manager_processing_queue = dispatch_queue_create("com.alamofire.networking.session.manager.processing", DISPATCH_QUEUE_CONCURRENT);
    });

    return af_url_session_manager_processing_queue;
}

static dispatch_group_t url_session_manager_completion_group() {
    static dispatch_group_t af_url_session_manager_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_completion_group = dispatch_group_create();
    });

    return af_url_session_manager_completion_group;
}

NSString * const AFNetworkingTaskDidResumeNotification = @"com.alamofire.networking.task.resume";
NSString * const AFNetworkingTaskDidCompleteNotification = @"com.alamofire.networking.task.complete";
NSString * const AFNetworkingTaskDidSuspendNotification = @"com.alamofire.networking.task.suspend";
NSString * const AFURLSessionDidInvalidateNotification = @"com.alamofire.networking.session.invalidate";
NSString * const AFURLSessionDownloadTaskDidFailToMoveFileNotification = @"com.alamofire.networking.session.download.file-manager-error";

NSString * const AFNetworkingTaskDidCompleteSerializedResponseKey = @"com.alamofire.networking.task.complete.serializedresponse";
NSString * const AFNetworkingTaskDidCompleteResponseSerializerKey = @"com.alamofire.networking.task.complete.responseserializer";
NSString * const AFNetworkingTaskDidCompleteResponseDataKey = @"com.alamofire.networking.complete.finish.responsedata";
NSString * const AFNetworkingTaskDidCompleteErrorKey = @"com.alamofire.networking.task.complete.error";
NSString * const AFNetworkingTaskDidCompleteAssetPathKey = @"com.alamofire.networking.task.complete.assetpath";

static NSString * const AFURLSessionManagerLockName = @"com.alamofire.networking.session.manager.lock";

static NSUInteger const AFMaximumNumberOfAttemptsToRecreateBackgroundSessionUploadTask = 3;


// 看AFUrlSessionManager的一些自定义Block
// 各自对应的还有一堆set方法  910 行
typedef void (^AFURLSessionDidBecomeInvalidBlock)(NSURLSession *session, NSError *error);
typedef NSURLSessionAuthChallengeDisposition (^AFURLSessionDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);

typedef NSURLRequest * (^AFURLSessionTaskWillPerformHTTPRedirectionBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request);
typedef NSURLSessionAuthChallengeDisposition (^AFURLSessionTaskDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);
typedef void (^AFURLSessionDidFinishEventsForBackgroundURLSessionBlock)(NSURLSession *session);

typedef NSInputStream * (^AFURLSessionTaskNeedNewBodyStreamBlock)(NSURLSession *session, NSURLSessionTask *task);
typedef void (^AFURLSessionTaskDidSendBodyDataBlock)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend);
typedef void (^AFURLSessionTaskDidCompleteBlock)(NSURLSession *session, NSURLSessionTask *task, NSError *error);

typedef NSURLSessionResponseDisposition (^AFURLSessionDataTaskDidReceiveResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response);
typedef void (^AFURLSessionDataTaskDidBecomeDownloadTaskBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask);
typedef void (^AFURLSessionDataTaskDidReceiveDataBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data);
typedef NSCachedURLResponse * (^AFURLSessionDataTaskWillCacheResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse);

typedef NSURL * (^AFURLSessionDownloadTaskDidFinishDownloadingBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location);
typedef void (^AFURLSessionDownloadTaskDidWriteDataBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
typedef void (^AFURLSessionDownloadTaskDidResumeBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t fileOffset, int64_t expectedTotalBytes);
typedef void (^AFURLSessionTaskProgressBlock)(NSProgress *);

typedef void (^AFURLSessionTaskCompletionHandler)(NSURLResponse *response, id responseObject, NSError *error);





/**
 NSURLSessionDataTask  //一般的get、post等请求
 NSURLSessionUploadTask // 用于上传文件或者数据量比较大的请求
 NSURLSessionDownloadTask //用于下载文件或者数据量比较大的请求
 NSURLSessionStreamTask //建立一个TCP / IP连接的主机名和端口或一个网络服务对象。

 */

#pragma mark -

@interface AFURLSessionManagerTaskDelegate : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
- (instancetype)initWithTask:(NSURLSessionTask *)task;
@property (nonatomic, weak) AFURLSessionManager *manager;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSProgress *uploadProgress;
@property (nonatomic, strong) NSProgress *downloadProgress;
@property (nonatomic, copy) NSURL *downloadFileURL;
@property (nonatomic, copy) AFURLSessionDownloadTaskDidFinishDownloadingBlock downloadTaskDidFinishDownloading;
@property (nonatomic, copy) AFURLSessionTaskProgressBlock uploadProgressBlock;
@property (nonatomic, copy) AFURLSessionTaskProgressBlock downloadProgressBlock;
@property (nonatomic, copy) AFURLSessionTaskCompletionHandler completionHandler;
@end

@implementation AFURLSessionManagerTaskDelegate

- (instancetype)initWithTask:(NSURLSessionTask *)task {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _mutableData = [NSMutableData data];
    _uploadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    _downloadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    
    __weak __typeof__(task) weakTask = task;
    for (NSProgress *progress in @[ _uploadProgress, _downloadProgress ])
    {
        progress.totalUnitCount = NSURLSessionTransferSizeUnknown;
        progress.cancellable = YES;
        progress.cancellationHandler = ^{
            [weakTask cancel];
        };
        progress.pausable = YES;
        progress.pausingHandler = ^{
            [weakTask suspend];
        };
        if ([progress respondsToSelector:@selector(setResumingHandler:)]) {
            progress.resumingHandler = ^{
                [weakTask resume];
            };
        }
        [progress addObserver:self
                   forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                      options:NSKeyValueObservingOptionNew
                      context:NULL];
    }
    return self;
}

- (void)dealloc {
    [self.downloadProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
    [self.uploadProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
}

#pragma mark - NSProgress Tracking

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
   if ([object isEqual:self.downloadProgress]) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(object);
        }
    }
    else if ([object isEqual:self.uploadProgress]) {
        if (self.uploadProgressBlock) {
            self.uploadProgressBlock(object);
        }
    }
}

#pragma mark - NSURLSessionTaskDelegate

//AF实现的代理！被从NSURLSession代理方法那转发到这

/*
 Tells the delegate that the task finished transferring data.
 Server errors are not reported through the error parameter. The only errors your delegate receives through the error parameter are client-side errors, such as being unable to resolve the hostname or connect to the host.
 task完成之后的回调，成功和失败都会回调这里
 函数讨论：
 注意这里的error不会报告服务期端的error，他表示的是客户端这边的eroor，比如无法解析hostname或者连不上host主机。
 */
- (void)URLSession:(__unused NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    // 所有的指针变量默认都是__strong类型,我们通常省略不写__strong
    // delegate中的AFURLSessionManager使用weak方式引用 这里使用__strong 防止被释放
    // 1）强引用self.manager，防止被提前释放；因为self.manager声明为weak,类似Block
    __strong AFURLSessionManager *manager = self.manager;

    __block id responseObject = nil;

    //  生成了一个存储这个task相关信息的字典：userInfo，这个字典是用来作为发送任务完成的通知的参数
    __block NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    // 存储responseSerializer响应解析对象
    userInfo[AFNetworkingTaskDidCompleteResponseSerializerKey] = manager.responseSerializer;

    //Performance Improvement from #2672
    //注意这行代码的用法，感觉写的很Nice...把请求到的数据data传出去，然后就不要这个值了释放内存
    NSData *data = nil;
    // 当是downloadTask时self.mutableData不会拼接下载的data的 这时 data = <>
    if (self.mutableData) {
        // 服务端返回响应数据 二进制
        data = [self.mutableData copy];
        //We no longer need the reference, so nil it out to gain back some memory.
        self.mutableData = nil;
    }
    // 继续给userinfo填数据
    if (self.downloadFileURL) {
        userInfo[AFNetworkingTaskDidCompleteAssetPathKey] = self.downloadFileURL;
    } else if (data) {
        userInfo[AFNetworkingTaskDidCompleteResponseDataKey] = data;
    }

    if (error) {// 有错误
        userInfo[AFNetworkingTaskDidCompleteErrorKey] = error;
        
        //  可以自己自定义完成组 和自定义完成queue,完成回调
        dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
            if (self.completionHandler) {
                self.completionHandler(task.response, responseObject, error);
            }
            // 主线程中发送完成通知
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
            });
        });
    } else { // 没有错误
        // 并发队列异步任务
        // url_session_manager_processing_queue AF的并行队列
        
        /**
            注意AF的优化的点，虽然代理回调是串行的(不明白可以见本文最后)。但是数据解析这种费时操作，确是用并行线程来做的。
         */
        
        dispatch_async(url_session_manager_processing_queue(), ^{
            NSError *serializationError = nil;
            // 解析数据 ---使用并发队列异步解析
            
            /**
             task.response 响应信息
             
             <NSHTTPURLResponse: 0x170031480> { URL: http://test.yunshangzuke.com:8080/api/v1/users/leases } { status code: 200, headers {
             "X-Application-Context" = application:product:8080,
             "Transfer-Encoding" = Identity,
             "Content-Type" = application/json;charset=UTF-8,
             "Date" = Mon, 14 Aug 2017 13:16:47 GMT,
             } }
             
             data : server返回二进制数据
             */

            /**
             一个协议方法，各种类型的responseSerializer类，都是遵守这个协议方法，实现了一个把我们请求得到的response和data传给解析器解析
             downloadTask请求回来的data被写到临时文件中了 在此处data是空 只有response
             */
            responseObject = [manager.responseSerializer responseObjectForResponse:task.response data:data error:&serializationError];

            // 如果是下载文件，那么responseObject为下载的路径
            if (self.downloadFileURL) {
                responseObject = self.downloadFileURL;
            }
            
            
            
            
            // 写入userInfo
            if (responseObject) {
                userInfo[AFNetworkingTaskDidCompleteSerializedResponseKey] = responseObject;
            }
            // 如果解析出错
            if (serializationError) {
                userInfo[AFNetworkingTaskDidCompleteErrorKey] = serializationError;
            }
            // 回调结果
            /**
                如果自定义了GCD完成组completionGroup和完成队列的话completionQueue，会在加入这个组和在队列中回调Block
             
                否则默认的是AF的创建的组和主队列回调。AF没有用这个GCD组做任何处理，只是提供这个接口，让我们有需求的自行调用处理。如果有对多个任务完成度的监听，可以自行处理。
                而队列的话，如果你不需要回调主线程，可以自己设置一个回调队列
             */
            dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{

                // 执行用户传入的completionHandler这个block
                if (self.completionHandler) {
                    self.completionHandler(task.response, responseObject, serializationError);
                }
                // 回到主线程，发送了任务完成的通知：
                // 这个通知这回AF有用到了，在我们对UIKit的扩展中，用到了这个通知。
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
                });
            });
        });
    }
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(__unused NSURLSession *)session
          dataTask:(__unused NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    // 进度更新
    self.downloadProgress.totalUnitCount = dataTask.countOfBytesExpectedToReceive;
    self.downloadProgress.completedUnitCount = dataTask.countOfBytesReceived;
    // 拼接数据
    // 使用downloadTask下载的时候 此方法不会调用 也就是说 self.mutableData不会拼接下载的data数据
    [self.mutableData appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend{
    
    // 进度更新
    self.uploadProgress.totalUnitCount = task.countOfBytesExpectedToSend;
    self.uploadProgress.completedUnitCount = task.countOfBytesSent;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    
    // 进度更新
    self.downloadProgress.totalUnitCount = totalBytesExpectedToWrite;
    self.downloadProgress.completedUnitCount = totalBytesWritten;
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes{
    
    // 进度更新
    self.downloadProgress.totalUnitCount = expectedTotalBytes;
    self.downloadProgress.completedUnitCount = fileOffset;
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    self.downloadFileURL = nil;
    // AFSessionManager也有个downloadTaskDidFinishDownloading 1750行
    // 这个是“AFURLSessionManagerTaskDelegate”自定义的block(内部是用户自定义的block 看 900 行)
    // 这个是对应的每个task的，每个task可以设置各自下载路径
    if (self.downloadTaskDidFinishDownloading) {
        // 得到用户自定义下载路径
        self.downloadFileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (self.downloadFileURL) {
            // 把下载路径移动到我们自定义的下载路径
            NSError *fileManagerError = nil;

            /**
             If an item with the same name already exists at dstURL, this method stops the move attempt and returns an appropriate error. If the last component of srcURL is a symbolic link, only the link is moved to the new path; the item pointed to by the link remains at its current location.
             */
            // 如果移动的‘文件名’已经存在会移动失败
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:self.downloadFileURL error:&fileManagerError]) {
                // 错误发通知
           
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:fileManagerError.userInfo];
            }
        }
    }
    
    /**
     a.之前的NSURLSession的代理和这里的AFURLSessionManagerTaskDelegate都移动了文件到下载路径，而NSUrlSession代理的下载路径是所有request公用的下载路径，一旦设置，所有的request都会下载到之前那个路径。
     
     b.而这个是对应的每个task的，每个task可以设置各自下载路径 ?? 
     解析 需要看在AFHTTPSessionManager中的一个方法
     - (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
     progress:(nullable void (^)(NSProgress *downloadProgress))downloadProgressBlock
     destination:(nullable NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
     completionHandler:(nullable void (^)(NSURLResponse *response, NSURL * _Nullable filePath, NSError * _Nullable error))completionHandler;
     
     */
    
}

@end

#pragma mark -

/**
 *  A workaround for issues related to key-value observing the `state` of an `NSURLSessionTask`.
 *
 *  See:
 *  - https://github.com/AFNetworking/AFNetworking/issues/1477
 *  - https://github.com/AFNetworking/AFNetworking/issues/2638
 *  - https://github.com/AFNetworking/AFNetworking/pull/2702
 */

static inline void af_swizzleSelector(Class theClass, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(theClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(theClass, swizzledSelector);
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

static inline BOOL af_addMethod(Class theClass, SEL selector, Method method) {
    return class_addMethod(theClass, selector,  method_getImplementation(method),  method_getTypeEncoding(method));
}

static NSString * const AFNSURLSessionTaskDidResumeNotification  = @"com.alamofire.networking.nsurlsessiontask.resume";
static NSString * const AFNSURLSessionTaskDidSuspendNotification = @"com.alamofire.networking.nsurlsessiontask.suspend";


// 这个类大概的作用就是替换掉NSUrlSession中的resume和suspend方法。正常处理原有逻辑的同时，多发送一个通知，以下是我们需要替换的新方法
@interface _AFURLSessionTaskSwizzling : NSObject

@end

@implementation _AFURLSessionTaskSwizzling

/**
 
 Invoked whenever a class or category is added to the Objective-C runtime; implement this method to perform class-specific behavior upon loading.
 The load message is sent to classes and categories that are both dynamically loaded and statically linked, but only if the newly loaded class or category implements a method that can respond.
 The order of initialization is as follows:
 All initializers in any framework you link to.
 All +load methods in your image.
 All C++ static initializers and C/C++ __attribute__(constructor) functions in your image.
 All initializers in frameworks that link to you.
 
 In addition:
 A class’s +load method is called after all of its superclasses’ +load methods.
 A category +load method is called after the class’s own +load method.
 
 In a custom implementation of load you can therefore safely message other unrelated classes from the same image, but any load methods implemented by those classes may not have run yet.
 Important
 Custom implementations of the load method for Swift classes bridged to Objective-C are not called automatically.
 
 加入runtime时(内存)调用
 */
+ (void)load {
    /**
     WARNING: Trouble Ahead
     https://github.com/AFNetworking/AFNetworking/pull/2702
     */

    if (NSClassFromString(@"NSURLSessionTask")) {
        /**
         iOS 7 and iOS 8 differ in NSURLSessionTask implementation, which makes the next bit of code a bit tricky.
         Many Unit Tests have been built to validate as much of this behavior has possible.
         Here is what we know:
            - NSURLSessionTasks are implemented with class clusters, meaning the class you request from the API isn't actually the type of class you will get back.
                NSURLSessionTasks是一组class的统称，如果你仅仅使用提供的API来获取NSURLSessionTask的class，并不一定返回的是你想要的那个（获取NSURLSessionTask的class目的是为了获取其resume方法）
         
            - Simply referencing `[NSURLSessionTask class]` will not work. You need to ask an `NSURLSession` to actually create an object, and grab the class from there.
                
                简单地使用[NSURLSessionTask class]并不起作用。你需要新建一个NSURLSession，并根据创建的session再构建出一个NSURLSessionTask对象才行。
         
         
            - On iOS 7, `localDataTask` is a `__NSCFLocalDataTask`, which inherits from `__NSCFLocalSessionTask`, which inherits from `__NSCFURLSessionTask`.
         
                iOS 7上，localDataTask（下面代码构造出的NSURLSessionDataTask类型的变量，为了获取对应Class）的类型是     NSCFLocalDataTask，NSCFLocalDataTask继承自NSCFLocalSessionTask，NSCFLocalSessionTask继承自__NSCFURLSessionTask。
         
         
            - On iOS 8, `localDataTask` is a `__NSCFLocalDataTask`, which inherits from `__NSCFLocalSessionTask`, which inherits from `NSURLSessionTask`.
         
                iOS 8上，localDataTask的类型为NSCFLocalDataTask，NSCFLocalDataTask继承自NSCFLocalSessionTask，NSCFLocalSessionTask继承自NSURLSessionTask
         
         
         
            - On iOS 7, `__NSCFLocalSessionTask` and `__NSCFURLSessionTask` are the only two classes that have their own implementations of `resume` and `suspend`, and `__NSCFLocalSessionTask` DOES NOT CALL SUPER. This means both classes need to be swizzled.
                
                iOS 7上，NSCFLocalSessionTask和NSCFURLSessionTask是仅有的两个实现了resume和suspend方法的类，另外NSCFLocalSessionTask中的resume和suspend并没有调用其父类（即NSCFURLSessionTask）方法，这也意味着两个类的方法都需要进行method swizzling。
         
         
            - On iOS 8, `NSURLSessionTask` is the only class that implements `resume` and `suspend`. This means this is the only class that needs to be swizzled.
            - Because `NSURLSessionTask` is not involved in the class hierarchy for every version of iOS, its easier to add the swizzled methods to a dummy class and manage them there.
                
                iOS 8上，NSURLSessionTask是唯一实现了resume和suspend方法的类。这也意味着其是唯一需要进行method swizzling的类
                因为NSURLSessionTask并不是在每个iOS版本中都存在，所以把这些放在此处（即load函数中），比如给一个dummy class添加swizzled方法都会变得很方便，管理起来也方便。
         
         
         Some Assumptions:
            - No implementations of `resume` or `suspend` call super. If this were to change in a future version of iOS, we'd need to handle it.
            - No background task classes override `resume` or `suspend`
         
             一些假设前提:
             目前iOS中resume和suspend的方法实现中并没有调用对应的父类方法。如果日后iOS改变了这种做法，我们还需要重新处理。
             没有哪个后台task会重写resume和suspend函数

         
         The current solution:
            1) Grab an instance of `__NSCFLocalDataTask` by asking an instance of `NSURLSession` for a data task.
            2) Grab a pointer to the original implementation of `af_resume`
            3) Check to see if the current class has an implementation of resume. If so, continue to step 4.
            4) Grab the super class of the current class.
            5) Grab a pointer for the current class to the current implementation of `resume`.
            6) Grab a pointer for the super class to the current implementation of `resume`.
            7) If the current class implementation of `resume` is not equal to the super class implementation of `resume` AND the current implementation of `resume` is not equal to the original implementation of `af_resume`, THEN swizzle the methods
            8) Set the current class to the super class, and repeat steps 3-8
         */
        
        
        // 1) 首先构建一个NSURLSession对象session，再通过session构建出一个_NSCFLocalDataTask变量
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnonnull"
        NSURLSessionDataTask *localDataTask = [session dataTaskWithURL:nil];
#pragma clang diagnostic pop
        // 2) 获取到af_resume实现的指针
        IMP originalAFResumeIMP = method_getImplementation(class_getInstanceMethod([self class], @selector(af_resume)));
        
        Class currentClass = [localDataTask class];
        // 3) 检查当前class是否实现了resume。如果实现了，继续第4步。
        // 注意：这个class_getInstanceMethod方法会寻找父类方法
        while (class_getInstanceMethod(currentClass, @selector(resume))) {
            // 最终的superClass是NSObject
            // 4) 获取到当前class的父类（superClass）
            Class superClass = [currentClass superclass];
            // 5) 获取到当前class对于resume实现的指针
            IMP classResumeIMP = method_getImplementation(class_getInstanceMethod(currentClass, @selector(resume)));
            //  6) 获取到父类对于resume实现的指针
            IMP superclassResumeIMP = method_getImplementation(class_getInstanceMethod(superClass, @selector(resume)));
            /** 7)
             a.如果当前class对于resume的实现和父类不一样（类似iOS7上的情况），并且当前class的resume实现和af_resume不一样，才进行method swizzling。
             b.在iOS8的情况是所有的都是task的resume方法都是来自父类NSURLSessionTask（继承自NSObject--没有resume方法）所以最终只会交换NSURLSessionTask这个类的方法
             c.经测试iOS10 会有当前class对于resume的实现和父类不一样(类似iOS7)
             */
            
            // 为什么加这些条件 看疑惑解析
            if (classResumeIMP != superclassResumeIMP &&
                originalAFResumeIMP != classResumeIMP) {
                //执行交换的函数
                [self swizzleResumeAndSuspendMethodForClass:currentClass];
            }
            // 8) 设置当前操作的class为其父类class，重复步骤3~8
            currentClass = [currentClass superclass];
        }
        
        [localDataTask cancel];
        [session finishTasksAndInvalidate];
    }
    
    /**
     其实这是被社区大量讨论的一个bug，之前AF因为这个替换方法，会导致偶发性的crash，如果不要这个swizzle则问题不会再出现，但是这样会导致AF中很多UIKit的扩展都不能正常使用。
     
     原来这是因为iOS7和iOS8的NSURLSessionTask的继承链不同导致的，而且在iOS7继承链中会有两个类都实现了resume和suspend方法。而且子类没有调用父类的方法，我们则需要对着两个类都进行方法替换。而iOS8只需要对一个类进行替换。iOS10和iOS7类似需要对两个类进行替换
     
     对着注释看，上述方法代码不难理解，用一个while循环，一级一级去获取父类，如果实现了resume方法，则进行替换。
     */
    
    /** ***********疑惑*************
     
     1.首先可以注意class_getInstanceMethod这个方法，它会获取到当前类继承链逐级往上，第一个实现的该方法。所以说它获取到的方法不能确定是当前类还是父类的。而且这里也没有用dispatch_once_t来保证一个方法只交换一次（之前版本的AF有用到dispatch_once_t），那万一这是父类的方法，当前类换一次，父类又换一次，不是等于没交换么？
     
        ...请注意这行判断：
        如果当前class对于resume的实现和父类不一样（类似iOS7上的情况），并且当前class的resume实现和af_resume不一样，才进行method swizzling。
        if (classResumeIMP != superclassResumeIMP && originalAFResumeIMP != classResumeIMP) {
            //执行交换的函数
            [self swizzleResumeAndSuspendMethodForClass:currentClass]; 
        }
     
        这个条件就杜绝了这种情况的发生，只有当前类实现了这个方法，才可能进入这个if块。
     
     2.那iOS7两个类都交换了af_resume，那岂不是父类换到子类方法了?
       为什么会有父类换到子类方法？
         好比两个类A和B 其中A继承B 如果两个类都各自实现了方法resume(A中的resume不会调用B的resume)
         如果A交换resume方法为af_resume  B这时候去交换af_resume时其实换的是A的resume 这就是父类换到子类方法
    
       看AF的做法

        AF是去向当前类添加af_resume方法，然后去交换当前类的af_resume。所以说根本不会出现这种情况
     */
}

+ (void)swizzleResumeAndSuspendMethodForClass:(Class)theClass {
    Method afResumeMethod = class_getInstanceMethod(self, @selector(af_resume));
    Method afSuspendMethod = class_getInstanceMethod(self, @selector(af_suspend));
    
    // 给传入的类 添加af_resume的方法 并交换af_resume和自身的resume
    /**
        为什么要先给类添加一个af_resume方法呢？
        如果不给类添加af_resume而是都使用AFURLSessionTaskSwizzling这个类的af_resume 的方法
        会出现父类方法换到子类方法的情况
        好比两个类A和B 其中A继承B 如果两个类都各自实现了方法resume(A中的resume不会调用B的resume)
        如果A交换resume方法为AFURLSessionTaskSwizzling的af_resume  B这时候去交换AFURLSessionTaskSwizzling的af_resume时其实换的是A的resume

     */
    if (af_addMethod(theClass, @selector(af_resume), afResumeMethod)) {
        af_swizzleSelector(theClass, @selector(resume), @selector(af_resume));
    }
    // af_suspend 原理同上
    if (af_addMethod(theClass, @selector(af_suspend), afSuspendMethod)) {
        af_swizzleSelector(theClass, @selector(suspend), @selector(af_suspend));
    }
}

- (NSURLSessionTaskState)state {
    NSAssert(NO, @"State method should never be called in the actual dummy class");
    return NSURLSessionTaskStateCanceling;
}

- (void)af_resume {
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    // 这里调用的是交换后的方法resume--并不会死循环
    // 实际调用的是URLSessionTask的resume实现
    [self af_resume];
    // 发送通知
    if (state != NSURLSessionTaskStateRunning) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNSURLSessionTaskDidResumeNotification object:self];
    }
}

- (void)af_suspend {
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    
    // 实际调用的是URLSessionTask的suspend实现
    [self af_suspend];
    if (state != NSURLSessionTaskStateSuspended) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNSURLSessionTaskDidSuspendNotification object:self];
    }
}
@end

#pragma mark -

@interface AFURLSessionManager ()
@property (readwrite, nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (readwrite, nonatomic, strong) NSOperationQueue *operationQueue;
@property (readwrite, nonatomic, strong) NSURLSession *session;
@property (readwrite, nonatomic, strong) NSMutableDictionary *mutableTaskDelegatesKeyedByTaskIdentifier;
@property (readonly, nonatomic, copy) NSString *taskDescriptionForSessionTasks;
@property (readwrite, nonatomic, strong) NSLock *lock;


// 看AFUrlSessionManager的一些自定义Block .h中看不到
// 各自对应的还有一堆set方法 910行
/**
    作者用@property把这个些Block属性在.m文件中声明,然后复写了set方法。
    然后在.h中去声明这些set方法：
 
    为什么要绕这么一大圈呢？原来这是为了我们这些用户使用起来方便，调用set方法去设置这些Block，能很清晰的看到Block的各个参数与返回值。大神的精髓的编程思想无处不体现...
 */

@property (readwrite, nonatomic, copy) AFURLSessionDidBecomeInvalidBlock sessionDidBecomeInvalid;
@property (readwrite, nonatomic, copy) AFURLSessionDidReceiveAuthenticationChallengeBlock sessionDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) AFURLSessionDidFinishEventsForBackgroundURLSessionBlock didFinishEventsForBackgroundURLSession;
@property (readwrite, nonatomic, copy) AFURLSessionTaskWillPerformHTTPRedirectionBlock taskWillPerformHTTPRedirection;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidReceiveAuthenticationChallengeBlock taskDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) AFURLSessionTaskNeedNewBodyStreamBlock taskNeedNewBodyStream;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidSendBodyDataBlock taskDidSendBodyData;
@property (readwrite, nonatomic, copy) AFURLSessionTaskDidCompleteBlock taskDidComplete;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidReceiveResponseBlock dataTaskDidReceiveResponse;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidBecomeDownloadTaskBlock dataTaskDidBecomeDownloadTask;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskDidReceiveDataBlock dataTaskDidReceiveData;
@property (readwrite, nonatomic, copy) AFURLSessionDataTaskWillCacheResponseBlock dataTaskWillCacheResponse;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidFinishDownloadingBlock downloadTaskDidFinishDownloading;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidWriteDataBlock downloadTaskDidWriteData;
@property (readwrite, nonatomic, copy) AFURLSessionDownloadTaskDidResumeBlock downloadTaskDidResume;
@end

@implementation AFURLSessionManager

- (instancetype)init {
    return [self initWithSessionConfiguration:nil];
}


//  AF3.x最最核心的类AFURLSessionManager。几乎所有的类都是围绕着这个类在处理业务逻辑。
- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (!configuration) {
        configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    }

    self.sessionConfiguration = configuration;

    self.operationQueue = [[NSOperationQueue alloc] init];
    
    // 这个operationQueue就是我们代理回调的queue。这里把代理回调的线程并发数设置为1了。至于这里为什么要这么做，我们先留一个坑，等我们讲完AF2.x之后再来分析这一块。
    self.operationQueue.maxConcurrentOperationCount = 1;
    
    
    /**
     + (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(nullable id <NSURLSessionDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue;
        此处的协议是 NSURLSessionDelegate
     */
    // 注意代理，代理的继承，实际上NSURLSession去判断了，你实现了哪个方法会去调用，包括子代理的方法！
    self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.operationQueue];

    // 各种响应转码
    self.responseSerializer = [AFJSONResponseSerializer serializer];
    // 设置默认安全策略
    self.securityPolicy = [AFSecurityPolicy defaultPolicy];

#if !TARGET_OS_WATCH
    self.reachabilityManager = [AFNetworkReachabilityManager sharedManager];
#endif
    // 设置存储NSURL task与AFURLSessionManagerTaskDelegate的词典（重点，在AFNet中，每一个task都会被匹配一个AFURLSessionManagerTaskDelegate 来做task的delegate事件处理）
    // 用来让每一个请求task和我们自定义的AF代理来建立映射用的，其实AF对task的代理进行了一个封装，并且转发代理到AF自定义的代理，这是AF比较重要的一部分，接下来我们会具体讲这一块
    self.mutableTaskDelegatesKeyedByTaskIdentifier = [[NSMutableDictionary alloc] init];

    //  设置AFURLSessionManagerTaskDelegate 词典的锁，确保词典在多线程访问时的线程安全
    self.lock = [[NSLock alloc] init];
    self.lock.name = AFURLSessionManagerLockName;

    
/**  ???
 
    这个方法用来异步的获取当前session的所有未完成的task。其实讲道理来说在初始化中调用这个方法应该里面一个task都不会有。我们打断点去看，也确实如此，里面的数组都是空的。
    但是想想也知道，AF大神不会把一段没用的代码放在这吧。辗转多处，终于从AF的issue中找到了结论：https://github.com/AFNetworking/AFNetworking/issues/3499 。
 
        原来这是为了从后台回来，重新初始化session，防止一些之前的后台请求任务，导致程序的crash。
    ApplicationDelegate 的代理方法里边处理未完成的后台download session
    ‘restoring a session from the background’ 这句话我理解是，有用同一个identifier 创建session的情况，一旦这种情况出现，会返回同一个session ，就需要对task进行获取和处理了
    
 关于session的文档
    https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/URLLoadingSystem/NSURLSessionConcepts/NSURLSessionConcepts.html#//apple_ref/doc/uid/10000165i-CH2-SW42
 */
    
    /**
     Asynchronously calls a completion callback with all data, upload, and download tasks in a session.
     The returned arrays contain any tasks that you have created within the session, not including any tasks that have been invalidated after completing, failing, or being cancelled.
     
     
     可以结合这两篇内容去理解下 https://realm.io/news/gwendolyn-weston-ios-background-networking/ http://stackoverflow.com/questions/23492311/nsurlsession-background-task-avoid-duplicates 在这里这个防御编程的作用是为了应对session在执行后台下载任务的情况。进入后台后在ApplicationDelegate那个方法中被唤醒，我们会去创建相同identifier的session，这个时候需要通过 getTasksWithCompletionHandler去获取未来得及执行的tasks去做一些防止崩溃的处理。
     */
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [self addDelegateForDataTask:task uploadProgress:nil downloadProgress:nil completionHandler:nil];
        }

        for (NSURLSessionUploadTask *uploadTask in uploadTasks) {
            [self addDelegateForUploadTask:uploadTask progress:nil completionHandler:nil];
        }

        for (NSURLSessionDownloadTask *downloadTask in downloadTasks) {
            [self addDelegateForDownloadTask:downloadTask progress:nil destination:nil completionHandler:nil];
        }
    }];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

- (NSString *)taskDescriptionForSessionTasks {
    // %p 内存地址
    return [NSString stringWithFormat:@"%p", self];
}

- (void)taskDidResume:(NSNotification *)notification {
    NSURLSessionTask *task = notification.object;
    if ([task respondsToSelector:@selector(taskDescription)]) {
        // task.taskDescription 之前会被赋值taskDescriptionForSessionTasks
        if ([task.taskDescription isEqualToString:self.taskDescriptionForSessionTasks]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidResumeNotification object:task];
            });
        }
    }
}

- (void)taskDidSuspend:(NSNotification *)notification {
    NSURLSessionTask *task = notification.object;
    if ([task respondsToSelector:@selector(taskDescription)]) {
        if ([task.taskDescription isEqualToString:self.taskDescriptionForSessionTasks]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidSuspendNotification object:task];
            });
        }
    }
}

#pragma mark -

- (AFURLSessionManagerTaskDelegate *)delegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);

    AFURLSessionManagerTaskDelegate *delegate = nil;
    [self.lock lock];
    delegate = self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)];
    [self.lock unlock];

    return delegate;
}

- (void)setDelegate:(AFURLSessionManagerTaskDelegate *)delegate
            forTask:(NSURLSessionTask *)task
{
    // 断言，如果没有这个参数，debug下crash在这
    NSParameterAssert(task);
    NSParameterAssert(delegate);
    // 加锁保证字典线程安全
    [self.lock lock];
    // 将AFURLSessionManagerTaskDelegate放入以taskIdentifier标记的词典中（同一个NSURLSession中的taskIdentifier是唯一的）
    self.mutableTaskDelegatesKeyedByTaskIdentifier[@(task.taskIdentifier)] = delegate;
    
    // 此版本有更改 版3.1.0此处还有个操作
    
    //添加task开始和暂停的通知
    [self addNotificationObserverForTask:task];
    
    [self.lock unlock];
    
    /**
     这个方法主要就是把AF代理和task建立映射，存在了一个我们事先声明好的字典里。
     而要加锁的原因是因为本身我们这个字典属性是mutable的，是线程不安全的。而我们对这些方法的调用，确实是会在复杂的多线程环境中，后面会仔细提到线程问题
     */
}

- (void)addDelegateForDataTask:(NSURLSessionDataTask *)dataTask
                uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
              downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
             completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    // 创建AFURLSessionManagerTaskDelegate 并初始化
    // 对task的下载和上传进度进行了KVO
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] initWithTask:dataTask];
    
    // AFURLSessionManagerTaskDelegate与AFURLSessionManager建立相互关系
    delegate.manager = self;
    
    delegate.completionHandler = completionHandler;

    // 这个taskDescriptionForSessionTasks用来发送开始和挂起通知的时候会用到,就是用这个值来Post通知，来两者对应
    dataTask.taskDescription = self.taskDescriptionForSessionTasks;
    
    // ***** 将AFURLSessionManagerTaskDelegate对象与 dataTask建立关系
    [self setDelegate:delegate forTask:dataTask];
    
    // 设置AFURLSessionManagerTaskDelegate的上传进度，下载进度块。
    delegate.uploadProgressBlock = uploadProgressBlock;
    delegate.downloadProgressBlock = downloadProgressBlock;
    
    /**
     总结一下:
     1）这个方法，生成了一个AFURLSessionManagerTaskDelegate,这个其实就是AF的自定义代理。我们请求传来的参数，都赋值给这个AF的代理了。
     2）delegate.manager = self;代理把AFURLSessionManager这个类作为属性了,我们可以看到：
     @property (nonatomic, weak) AFURLSessionManager *manager;
     这个属性是弱引用的，所以不会存在循环引用的问题。
     
     3）我们调用了[self setDelegate:delegate forTask:dataTask];
     */
}

- (void)addDelegateForUploadTask:(NSURLSessionUploadTask *)uploadTask
                        progress:(void (^)(NSProgress *uploadProgress)) uploadProgressBlock
               completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] initWithTask:uploadTask];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    uploadTask.taskDescription = self.taskDescriptionForSessionTasks;

    [self setDelegate:delegate forTask:uploadTask];

    delegate.uploadProgressBlock = uploadProgressBlock;
}

- (void)addDelegateForDownloadTask:(NSURLSessionDownloadTask *)downloadTask
                          progress:(void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                       destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                 completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    AFURLSessionManagerTaskDelegate *delegate = [[AFURLSessionManagerTaskDelegate alloc] initWithTask:downloadTask];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;

    // 如果用户设置了destination这个block   看 380 行
    if (destination) {
        
        //有点绕，就是把一个block赋值给“AF代理”的downloadTaskDidFinishDownloading，这个Block里的内部返回也是调用Block去获取到的，这里面的参数都是“AF代理”传来的。
        delegate.downloadTaskDidFinishDownloading = ^NSURL * (NSURLSession * __unused session, NSURLSessionDownloadTask *task, NSURL *location) {
            // 调用用户传入的destination这个block
            return destination(location, task.response);
        };
    }
    /**
     (lldb) po location
     file:///private/var/mobile/Containers/Data/Application/CC27F214-F815-45AF-96D4-8EA0C5C1A215/tmp/CFNetworkDownload_iykDD1.tmp
     
     (lldb) po destination(location, task.response)
     file:///var/mobile/Containers/Data/Application/CC27F214-F815-45AF-96D4-8EA0C5C1A215/Library/Caches/contractDir/25_A.pdf

     */

    downloadTask.taskDescription = self.taskDescriptionForSessionTasks;

    [self setDelegate:delegate forTask:downloadTask];

    delegate.downloadProgressBlock = downloadProgressBlock;
}

- (void)removeDelegateForTask:(NSURLSessionTask *)task {
    NSParameterAssert(task);

    [self.lock lock];
    [self removeNotificationObserverForTask:task];
    [self.mutableTaskDelegatesKeyedByTaskIdentifier removeObjectForKey:@(task.taskIdentifier)];
    [self.lock unlock];
}

#pragma mark -

- (NSArray *)tasksForKeyPath:(NSString *)keyPath {
    __block NSArray *tasks = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(dataTasks))]) {
            tasks = dataTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(uploadTasks))]) {
            tasks = uploadTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(downloadTasks))]) {
            tasks = downloadTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(tasks))]) {
            tasks = [@[dataTasks, uploadTasks, downloadTasks] valueForKeyPath:@"@unionOfArrays.self"];
        }

        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return tasks;
}

- (NSArray *)tasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)dataTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)uploadTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)downloadTasks {
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

#pragma mark -

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks {
    if (cancelPendingTasks) {
        [self.session invalidateAndCancel];
    } else {
        [self.session finishTasksAndInvalidate];
    }
}

#pragma mark -

- (void)setResponseSerializer:(id <AFURLResponseSerialization>)responseSerializer {
    NSParameterAssert(responseSerializer);

    _responseSerializer = responseSerializer;
}

#pragma mark -
- (void)addNotificationObserverForTask:(NSURLSessionTask *)task {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskDidResume:) name:AFNSURLSessionTaskDidResumeNotification object:task];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskDidSuspend:) name:AFNSURLSessionTaskDidSuspendNotification object:task];
}

- (void)removeNotificationObserverForTask:(NSURLSessionTask *)task {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AFNSURLSessionTaskDidSuspendNotification object:task];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AFNSURLSessionTaskDidResumeNotification object:task];
}

#pragma mark -
/*** NSURLSessionDataTask
 
 An NSURLSessionDataTask does not provide any additional
 functionality over an NSURLSessionTask and its presence is merely
 to provide lexical differentiation from download and upload tasks.
 
 一个NSURLSessionDataTask并不提供任何额外的功能在一个NSURLSessionTask仅仅是和它的存在从下载和上传任务提供词汇分化。
 
 
 An NSURLSessionDataTask is a concrete subclass of NSURLSessionTask. The methods in the NSURLSessionDataTask class are documented in NSURLSessionTask.
 
 A data task returns data directly to the app (in memory) as one or more NSData objects. When you use a data task:
 直接将data给内存中的app
 
 During upload of the body data (if your app provides any), the session periodically calls its delegate’s URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend: method with status information.
 
 After receiving an initial response, the session calls its delegate’s URLSession:dataTask:didReceiveResponse:completionHandler: method to let you examine the status code and headers, and optionally convert the data task into a download task.
 
 During the transfer, the session calls its delegate’s URLSession:dataTask:didReceiveData: method to provide your app with the content as it arrives.
 
 Upon completion, the session calls its delegate’s URLSession:dataTask:willCacheResponse:completionHandler: method to let you determine whether the response should be cached.
 
 */

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    return [self
            dataTaskWithRequest:request
            uploadProgress:nil
            downloadProgress:nil
            completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(nullable void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                             downloadProgress:(nullable void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                            completionHandler:(nullable void (^)(NSURLResponse *response, id _Nullable responseObject,  NSError * _Nullable error))completionHandler {

    __block NSURLSessionDataTask *dataTask = nil;
    //第一件事，创建NSURLSessionDataTask，里面适配了Ios8以下taskIdentifiers，函数创建task对象。 //其实现应该是因为iOS 8.0以下版本中会并发地创建多个task对象，而同步有没有做好，导致taskIdentifiers 不唯一…这边做了一个串行处理
    // 不是太懂？？
    
    // 调用了一个url_session_manager_create_task_safely()函数，传了一个Block进去，Block里就是iOS原生生成dataTask的方法
    url_session_manager_create_task_safely(^{
        // ios8以上直接创建dataTask
#pragma mark - dataTaskWithRequest
        dataTask = [self.session dataTaskWithRequest:request];
    });

    // 给dataTask设置代理
    [self addDelegateForDataTask:dataTask uploadProgress:uploadProgressBlock downloadProgress:downloadProgressBlock completionHandler:completionHandler];

    return dataTask;
}

#pragma mark -
/** NSURLSessionUploadTask 继承自NSURLSessionDataTask
 
 An NSURLSessionUploadTask does not currently provide any additional
 functionality over an NSURLSessionDataTask.  All delegate messages
 that may be sent referencing an NSURLSessionDataTask equally apply
 to NSURLSessionUploadTasks.
 
 The NSURLSessionUploadTask class is a subclass of NSURLSessionDataTask, which in turn is a concrete subclass of NSURLSessionTask. The methods associated with the NSURLSessionUploadTask class are documented in NSURLSessionTask.
 
 Upload tasks are used for making HTTP requests that require a request body (such as POST or PUT). They behave similarly to data tasks, but you create them by calling different methods on the session that are designed to make it easier to provide the content to upload. As with data tasks, if the server provides a response, upload tasks return that response as one or more NSData objects in memory.
 Note
 Unlike data tasks, you can use upload tasks to upload content in the background. (For details, see URL Session Programming Guide.)
 When you create an upload task, you provide an NSURLRequest or NSMutableURLRequest object that contains any additional headers that you might need to send alongside the upload, such as the content type, content disposition, and so on. In iOS, when you create an upload task for a file in a background session, the system copies that file to a temporary location and streams data from there.
 While the upload is in progress, the task calls the session delegate’s URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend: method periodically to provide you with status information.
 When the upload phase of the request finishes, the task behaves like a data task, calling methods on the session delegate to provide you with the server’s response—headers, status code, content data, and so on
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                         progress:(void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                                completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{
        // 创建uploadTask
#pragma mark - uploadTaskWithRequest

        uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
    });

    // uploadTask may be nil on iOS7 because uploadTaskWithRequest:fromFile: may return nil despite being documented as nonnull (https://devforums.apple.com/message/926113#926113)
    if (!uploadTask && self.attemptsToRecreateUploadTasksForBackgroundSessions && self.session.configuration.identifier) {
        for (NSUInteger attempts = 0; !uploadTask && attempts < AFMaximumNumberOfAttemptsToRecreateBackgroundSessionUploadTask; attempts++) {
            uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
        }
    }

    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];

    return uploadTask;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                         progress:(void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                                completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{

#pragma mark - uploadTaskWithRequest
        uploadTask = [self.session uploadTaskWithRequest:request fromData:bodyData];
    });

    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];

    return uploadTask;
}

// formData的方式上传
- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request
                                                 progress:(void (^)(NSProgress *uploadProgress)) uploadProgressBlock
                                        completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler
{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{
        
#pragma mark - uploadTaskWithRequest
        uploadTask = [self.session uploadTaskWithStreamedRequest:request];
    });

    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];

    return uploadTask;
}

#pragma mark -

/** NSURLSessionDownloadTask 继承NSURLSessionTask
 
 An NSURLSessionDownloadTask is a concrete subclass of NSURLSessionTask. Most of the methods associated with this class are documented in NSURLSessionTask.
 
 // Download tasks直接将服务器的Response Data写到一个临时文件中
 Download tasks directly write the server’s response data to a temporary file, providing your app with progress updates as data arrives from the server. When you use download tasks in background sessions, these downloads continue even when your app is suspended or is otherwise not running.
 
 You can pause (cancel) download tasks and resume them later (assuming the server supports doing so). You can also resume downloads that failed because of network connectivity problems.
 
 When you use download tasks:
 
 During download, the session periodically calls the delegate’s URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite: method with status information.
 Upon successful completion, the session calls the delegate’s URLSession:downloadTask:didFinishDownloadingToURL: method or completion handler. In that method, you must either open the file for reading or move it to a permanent location in your app’s sandbox container directory.
 Upon unsuccessful completion, the session calls the delegate’s URLSession:task:didCompleteWithError: method or completion handler. Unlike NSURLSessionDataTask or NSURLSessionUploadTask, NSURLSessionDownloadTask reports server-side errors reported through HTTP status codes into corresponding NSError objects:

 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                                          destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    url_session_manager_create_task_safely(^{
        downloadTask = [self.session downloadTaskWithRequest:request];
    });

    [self addDelegateForDownloadTask:downloadTask progress:downloadProgressBlock destination:destination completionHandler:completionHandler];

    return downloadTask;
}

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                                progress:(void (^)(NSProgress *downloadProgress)) downloadProgressBlock
                                             destination:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                       completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler
{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    url_session_manager_create_task_safely(^{
        downloadTask = [self.session downloadTaskWithResumeData:resumeData];
    });

    [self addDelegateForDownloadTask:downloadTask progress:downloadProgressBlock destination:destination completionHandler:completionHandler];

    return downloadTask;
}

#pragma mark -
- (NSProgress *)uploadProgressForTask:(NSURLSessionTask *)task {
    return [[self delegateForTask:task] uploadProgress];
}

- (NSProgress *)downloadProgressForTask:(NSURLSessionTask *)task {
    return [[self delegateForTask:task] downloadProgress];
}

#pragma mark -

- (void)setSessionDidBecomeInvalidBlock:(void (^)(NSURLSession *session, NSError *error))block {
    self.sessionDidBecomeInvalid = block;
}

- (void)setSessionDidReceiveAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential))block {
    self.sessionDidReceiveAuthenticationChallenge = block;
}

- (void)setDidFinishEventsForBackgroundURLSessionBlock:(void (^)(NSURLSession *session))block {
    self.didFinishEventsForBackgroundURLSession = block;
}

#pragma mark -

- (void)setTaskNeedNewBodyStreamBlock:(NSInputStream * (^)(NSURLSession *session, NSURLSessionTask *task))block {
    self.taskNeedNewBodyStream = block;
}

- (void)setTaskWillPerformHTTPRedirectionBlock:(NSURLRequest * (^)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request))block {
    self.taskWillPerformHTTPRedirection = block;
}

- (void)setTaskDidReceiveAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential))block {
    self.taskDidReceiveAuthenticationChallenge = block;
}

- (void)setTaskDidSendBodyDataBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend))block {
    self.taskDidSendBodyData = block;
}

- (void)setTaskDidCompleteBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, NSError *error))block {
    self.taskDidComplete = block;
}

#pragma mark -

- (void)setDataTaskDidReceiveResponseBlock:(NSURLSessionResponseDisposition (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response))block {
    self.dataTaskDidReceiveResponse = block;
}

- (void)setDataTaskDidBecomeDownloadTaskBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask))block {
    self.dataTaskDidBecomeDownloadTask = block;
}

- (void)setDataTaskDidReceiveDataBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data))block {
    self.dataTaskDidReceiveData = block;
}

- (void)setDataTaskWillCacheResponseBlock:(NSCachedURLResponse * (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse))block {
    self.dataTaskWillCacheResponse = block;
}

#pragma mark -

- (void)setDownloadTaskDidFinishDownloadingBlock:(NSURL * (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location))block {
    self.downloadTaskDidFinishDownloading = block;
}

- (void)setDownloadTaskDidWriteDataBlock:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))block {
    self.downloadTaskDidWriteData = block;
}

- (void)setDownloadTaskDidResumeBlock:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t fileOffset, int64_t expectedTotalBytes))block {
    self.downloadTaskDidResume = block;
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, session: %@, operationQueue: %@>", NSStringFromClass([self class]), self, self.session, self.operationQueue];
}

// 复写了selector的方法，这几个方法是在本类有实现的，但是如果外面的Block没赋值的话，则返回NO，相当于没有实现！
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)) {
        return self.taskWillPerformHTTPRedirection != nil;
    } else if (selector == @selector(URLSession:dataTask:didReceiveResponse:completionHandler:)) {
        return self.dataTaskDidReceiveResponse != nil;
    } else if (selector == @selector(URLSession:dataTask:willCacheResponse:completionHandler:)) {
        return self.dataTaskWillCacheResponse != nil;
    } else if (selector == @selector(URLSessionDidFinishEventsForBackgroundURLSession:)) {
        return self.didFinishEventsForBackgroundURLSession != nil;
    }
    // 响应本类能响应的方法
    return [[self class] instancesRespondToSelector:selector];
}


/**
    在初始化话sessionManager的时候我们之遵守了NSURLSessionDelegate协议 为什么这里实现了
    NSURLSessionDelegate
    NSURLSessionTaskDelegate
    NSURLSessionDataDelegate
    NSURLSessionDownloadDelegate
    四种协议的方法呢？
 
 @protocol NSURLSessionDelegate <NSObject>
 @protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
 @protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate> 
 @protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate> 
 @protocol NSURLSessionStreamDelegate <NSURLSessionTaskDelegate>
 我们可以看到这些代理都是继承关系，而在NSURLSession实现中，只要设置了这个代理，它会去判断这些所有的代理，是否respondsToSelector这些代理中的方法，如果响应了就会去调用。
 
 AF还重写了respondsToSelector方法: 这几个方法是在本类有实现的，但是如果外面的Block没赋值的话，则返回NO，相当于没有实现！

 */
#pragma mark - NSURLSessionDelegate

// 当前这个session已经失效时，该代理方法被调用。
/* 如果你使用finishTasksAndInvalidate函数使该session失效， 那么session首先会先完成最后一个task，然后再调用URLSession:didBecomeInvalidWithError:代理方法， 如果你调用invalidateAndCancel方法来使session失效，那么该session会立即调用上面的代理方法。
*/

/** 代理方法1
 
    当前这个session已经失效时，该代理方法被调用。
    
    如果你使用finishTasksAndInvalidate函数使该session失效， 那么session首先会先完成最后一个task，然后再调用URLSession:didBecomeInvalidWithError:代理方法， 如果你调用invalidateAndCancel方法来使session失效，那么该session会立即调用上面的代理方法。
 */

- (void)URLSession:(NSURLSession *)session
didBecomeInvalidWithError:(NSError *)error
{
    if (self.sessionDidBecomeInvalid) {
        self.sessionDidBecomeInvalid(session, error);
    }

    // AFN本身并没有监听这个通知 有可能是给用户使用的
    [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDidInvalidateNotification object:session];
}

/** 代理方法2 https
    
    函数作用：
        web服务器接收到客户端请求时，有时候需要先验证客户端是否为正常用户，再决定是够返回真实数据。这种情况称之为服务端要求客户端接收挑战（NSURLAuthenticationChallenge challenge）。接收到挑战后，客户端要根据服务端传来的challenge来生成completionHandler所需的NSURLSessionAuthChallengeDisposition disposition和NSURLCredential credential（disposition指定应对这个挑战的方法，而credential是客户端生成的挑战证书，注意只有challenge中认证方法为NSURLAuthenticationMethodServerTrust的时候，才需要生成挑战证书）。最后调用completionHandler回应服务器端的挑战
     
 函数讨论：
     该代理方法会在下面两种情况调用：
     
     当服务器端要求客户端提供证书时或者进行NTLM认证（Windows NT LAN Manager，微软提出的WindowsNT挑战/响应验证机制）时，此方法允许你的app提供正确的挑战证书。
     当某个session使用SSL/TLS协议，第一次和服务器端建立连接的时候，服务器会发送给iOS客户端一个证书，此方法允许你的app验证服务期端的证书链（certificate keychain）
     注：如果你没有实现该方法，该session会调用其NSURLSessionTaskDelegate的代理方法URLSession:task:didReceiveChallenge:completionHandler: 。
 
 */

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    
    
    //挑战处理类型为 默认
    
    /*  NSURLSessionAuthChallengePerformDefaultHandling：默认方式处理 NSURLSessionAuthChallengeUseCredential：使用指定的证书 NSURLSessionAuthChallengeCancelAuthenticationChallenge：取消挑战
     */

    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    // 凭据、证书
    __block NSURLCredential *credential = nil;

    // sessionDidReceiveAuthenticationChallenge是自定义方法，用来如何应对服务器端的认证挑战
    if (self.sessionDidReceiveAuthenticationChallenge) {
        // 执行传入的block
        disposition = self.sessionDidReceiveAuthenticationChallenge(session, challenge, &credential);
    } else {
        
        // 此处服务器要求客户端的接收认证挑战方法是NSURLAuthenticationMethodServerTrust
        // 也就是说服务器端需要客户端返回一个根据认证挑战的保护空间提供的信任（即challenge.protectionSpace.serverTrust）产生的挑战证书。
        // 而这个证书就需要使用credentialForTrust:来创建一个NSURLCredential对象
        
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            
            // 基于客户端的安全策略来决定是否信任该服务器，不信任的话，也就没必要响应挑战
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                
                // 创建挑战证书（注：挑战方式为UseCredential和PerformDefaultHandling都需要新建挑战证书）
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                // 确定挑战的方式
                if (credential) {
                    // 证书挑战
                    disposition = NSURLSessionAuthChallengeUseCredential;
                } else {
                    // 默认挑战  唯一区别，下面少了这一步！
                    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                // 取消挑战
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            // 默认挑战方式
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }
    // 完成挑战
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
    
/**
 函数作用：
 web服务器接收到客户端请求时，有时候需要先验证客户端是否为正常用户，再决定是够返回真实数据。这种情况称之为服务端要求客户端接收挑战（NSURLAuthenticationChallenge challenge）。接收到挑战后，客户端要根据服务端传来的challenge来生成completionHandler所需的NSURLSessionAuthChallengeDisposition disposition和NSURLCredential credential（disposition指定应对这个挑战的方法，而credential是客户端生成的挑战证书，注意只有challenge中认证方法为NSURLAuthenticationMethodServerTrust的时候，才需要生成挑战证书）。最后调用completionHandler回应服务器端的挑战。
 函数讨论：
 该代理方法会在下面两种情况调用：
 
 当服务器端要求客户端提供证书时或者进行NTLM认证（Windows NT LAN Manager，微软提出的WindowsNT挑战/响应验证机制）时，此方法允许你的app提供正确的挑战证书。
 当某个session使用SSL/TLS协议，第一次和服务器端建立连接的时候，服务器会发送给iOS客户端一个证书，此方法允许你的app验证服务期端的证书链（certificate keychain）
 注：如果你没有实现该方法，该session会调用其NSURLSessionTaskDelegate的代理方法URLSession:task:didReceiveChallenge:completionHandler: 。
 
 */
    
}


/**
 代理3：
 //  当session中所有已经入队的消息被发送出去后，会调用该代理方法。
 
 // 此版本AFN没实现该方法
 - (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
 if (self.didFinishEventsForBackgroundURLSession) {
 dispatch_async(dispatch_get_main_queue(), ^{
 self.didFinishEventsForBackgroundURLSession(session);
 });
 }
 }

 */

/**
 官方文档翻译：
 
 函数讨论：
 在iOS中，当一个后台传输任务完成或者后台传输时需要证书，而此时你的app正在后台挂起，那么你的app在后台会自动重新启动运行，并且这个app的UIApplicationDelegate会发送一个application:handleEventsForBackgroundURLSession:completionHandler:消息。该消息包含了对应后台的session的identifier，而且这个消息会导致你的app启动。你的app随后应该先存储completion handler，然后再使用相同的identifier创建一个background configuration，并根据这个background configuration创建一个新的session。这个新创建的session会自动与后台任务重新关联在一起。
 当你的app获取了一个URLSessionDidFinishEventsForBackgroundURLSession:消息，这就意味着之前这个session中已经入队的所有消息都转发出去了，这时候再调用先前存取的completion handler是安全的，或者因为内部更新而导致调用completion handler也是安全的。
 
 */



#pragma mark - NSURLSessionTaskDelegate

// 被服务器重定向的时候调用
//  An HTTP request is attempting to perform a redirection to a different
//* URL. You must invoke the completion routine to allow the
//* redirection, allow the redirection with a modified request, or
//* pass nil to the completionHandler to cause the body of the redirection
//* response to be delivered as the payload of this request. The default
//* is to follow redirections.

// 注意 ： 这个方法是在服务器去重定向的时候，才会被调用

/**
 关于这个代理还有一些需要注意的地方：
    此方法只会在default session或者ephemeral session中调用，而在background session中，session task会自动重定向。
 
 这个模式总共分为3种：
 
     对于NSURLSession对象的初始化需要使用NSURLSessionConfiguration，而NSURLSessionConfiguration有三个类工厂方法：
     +defaultSessionConfiguration 返回一个标准的 configuration，这个配置实际上与 NSURLConnection 的网络堆栈（networking stack）是一样的，具有相同的共享 NSHTTPCookieStorage，共享 NSURLCache 和共享NSURLCredentialStorage。
     +ephemeralSessionConfiguration 返回一个预设配置，这个配置中不会对缓存，Cookie 和证书进行持久性的存储。这对于实现像秘密浏览这种功能来说是很理想的。
     +backgroundSessionConfiguration:(NSString *)identifier 的独特之处在于，它会创建一个后台 session。后台 session 不同于常规的，普通的 session，它甚至可以在应用程序挂起，退出或者崩溃的情况下运行上传和下载任务。初始化时指定的标识符，被用于向任何可能在进程外恢复后台传输的守护进程（daemon）提供上下文。
 
 
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSURLRequest *redirectRequest = request;
    // step1. 看是否有对应的user block 有的话转发出去，通过这4个参数，返回一个NSURLRequest类型参数，request转发、网络重定向.
    if (self.taskWillPerformHTTPRedirection) {
        // 用自己自定义的一个重定向的block实现，返回一个新的request。
        redirectRequest = self.taskWillPerformHTTPRedirection(session, task, response, request);
    }

    if (completionHandler) {
        // step2. 用request重新请求
        completionHandler(redirectRequest);
    }
    
    // 当我们服务器重定向的时候，代理就被调用了，我们可以去重新定义这个重定向的request
    
    /**
     关于这个代理还有一些需要注意的地方：
     
     此方法只会在default session或者ephemeral session中调用，而在background session中，session task会自动重定向。
     
     这里指的模式是我们一开始Init的模式：
     
     if (!configuration) {
     configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
     }
     self.sessionConfiguration = configuration;
     
     这个模式总共分为3种：
     
     对于NSURLSession对象的初始化需要使用NSURLSessionConfiguration，而NSURLSessionConfiguration有三个类工厂方法：
     +defaultSessionConfiguration 返回一个标准的 configuration，这个配置实际上与 NSURLConnection 的网络堆栈（networking stack）是一样的，具有相同的共享 NSHTTPCookieStorage，共享 NSURLCache 和共享NSURLCredentialStorage。
     +ephemeralSessionConfiguration 返回一个预设配置，这个配置中不会对缓存，Cookie 和证书进行持久性的存储。这对于实现像秘密浏览这种功能来说是很理想的。
     +backgroundSessionConfiguration:(NSString *)identifier 的独特之处在于，它会创建一个后台 session。后台 session 不同于常规的，普通的 session，它甚至可以在应用程序挂起，退出或者崩溃的情况下运行上传和下载任务。初始化时指定的标识符，被用于向任何可能在进程外恢复后台传输的守护进程（daemon）提供上下文。
 
     */
}


/**
     之前我们也有一个https认证，功能一样，执行的内容也完全一样。
     区别在于这个是non-session-level级别的认证，而之前的是session-level级别的。
     相对于它，多了一个参数task,然后调用我们自定义的Block会多回传这个task作为参数，这样我们就可以根据每个task去自定义我们需要的https认证方式
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;

    if (self.taskDidReceiveAuthenticationChallenge) {
        disposition = self.taskDidReceiveAuthenticationChallenge(session, task, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                disposition = NSURLSessionAuthChallengeUseCredential;
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }

    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}


//当一个session task需要发送一个新的request body stream到服务器端的时候，调用该代理方法。
/**
     该代理方法会在下面两种情况被调用：
     
     如果task是由uploadTaskWithStreamedRequest:创建的，那么提供初始的request body stream时候会调用该代理方法。
     因为认证挑战或者其他可恢复的服务器错误，而导致需要客户端重新发送一个含有body stream的request，这时候会调用该代理。
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler
{
    NSInputStream *inputStream = nil;
    
    // 有自定义的taskNeedNewBodyStream,用自定义的，不然用task里原始的stream
    if (self.taskNeedNewBodyStream) {
        inputStream = self.taskNeedNewBodyStream(session, task);
    } else if (task.originalRequest.HTTPBodyStream && [task.originalRequest.HTTPBodyStream conformsToProtocol:@protocol(NSCopying)]) {
        inputStream = [task.originalRequest.HTTPBodyStream copy];
    }

    if (completionHandler) {
        completionHandler(inputStream);
    }
}

/*
    周期性地通知代理发送到服务器端数据的进度。
 
 
 */

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{

    // 如果totalUnitCount获取失败，就使用HTTP header中的Content-Length作为totalUnitCount
    int64_t totalUnitCount = totalBytesExpectedToSend;
    // 如果totalUnitCount获取失败，就使用HTTP header中的Content-Length作为totalUnitCount
    if(totalUnitCount == NSURLSessionTransferSizeUnknown) {
        NSString *contentLength = [task.originalRequest valueForHTTPHeaderField:@"Content-Length"];
        if(contentLength) {
            totalUnitCount = (int64_t) [contentLength longLongValue];
        }
    }
    
    // 获取task的代理
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];
    
    if (delegate) {
        // 代理回调
        [delegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
    }

    // 调用了我们自定义的Block
    if (self.taskDidSendBodyData) {
        self.taskDidSendBodyData(session, task, bytesSent, totalBytesSent, totalUnitCount);
    }
}


/*
 Tells the delegate that the task finished transferring data.
 Server errors are not reported through the error parameter. The only errors your delegate receives through the error parameter are client-side errors, such as being unable to resolve the hostname or connect to the host.
 task完成之后的回调，成功和失败都会回调这里
 函数讨论：
 注意这里的error不会报告服务期端的error，他表示的是客户端这边的eroor，比如无法解析hostname或者连不上host主机。
 */

// 在子线程回调的
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];
    // delegate may be nil when completing a task in the background
    if (delegate) {
        //把代理转发给我们绑定的delegate
        [delegate URLSession:session task:task didCompleteWithError:error];
        //转发完移除delegate
        [self removeDelegateForTask:task];
    }
    //自定义Block回调
    if (self.taskDidComplete) {
        self.taskDidComplete(session, task, error);
    }
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    // 设置默认为继续进行
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;

    // 自定义去设置
    if (self.dataTaskDidReceiveResponse) {
        disposition = self.dataTaskDidReceiveResponse(session, dataTask, response);
    }

    if (completionHandler) {
        completionHandler(disposition);
    }
    
    /**
     官方文档翻译如下：
     
     函数作用：
     告诉代理，该data task获取到了服务器端传回的最初始回复（response）。注意其中的completionHandler这个block，通过传入一个类型为NSURLSessionResponseDisposition的变量来决定该传输任务接下来该做什么：
     NSURLSessionResponseAllow 该task正常进行
     NSURLSessionResponseCancel 该task会被取消
     NSURLSessionResponseBecomeDownload 会调用URLSession:dataTask:didBecomeDownloadTask:方法来新建一个download task以代替当前的data task
     NSURLSessionResponseBecomeStream 转成一个StreamTask
     
     函数讨论：
     该方法是可选的，除非你必须支持“multipart/x-mixed-replace”类型的content-type。因为如果你的request中包含了这种类型的content-type，服务器会将数据分片传回来，而且每次传回来的数据会覆盖之前的数据。每次返回新的数据时，session都会调用该函数，你应该在这个函数中合理地处理先前的数据，否则会被新数据覆盖。如果你没有提供该方法的实现，那么session将会继续任务，也就是说会覆盖之前的数据。
     
     总结一下：
     
     当你把添加content-type的类型为multipart/x-mixed-replace那么服务器的数据会分片的传回来。然后这个方法是每次接受到对应片响应的时候会调被调用。你可以去设置上述4种对这个task的处理。
     如果我们实现了自定义Block，则调用一下，不然就用默认的NSURLSessionResponseAllow方式。
     
     */
}


/**
 Tells the delegate that the data task was changed to a download task.
 When the delegate’s URLSession:dataTask:didReceiveResponse:completionHandler: method decides to change the disposition from a data request to a download, the session calls this delegate method to provide you with the new download task. After this call, the session delegate receives no further delegate method calls related to the original data task
 
 //上面的代理如果设置为NSURLSessionResponseBecomeDownload，则会调用这个方法
 
 
 这个代理方法是被上面的代理方法触发的，作用就是新建一个downloadTask，替换掉当前的dataTask。所以我们在这里做了AF自定义代理的重新绑定操作。
 调用自定义Block。
 
 按照顺序来，其实还有个AF没有去实现的代理：
 
 //AF没实现的代理
 - (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
 didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask;
 
 这个也是之前的那个代理，设置为NSURLSessionResponseBecomeStream则会调用到这个代理里来。会新生成一个NSURLSessionStreamTask来替换掉之前的dataTask。 
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask
{
    // 因为转变了task，所以要对task做一个重新绑定
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    if (delegate) {
        [self removeDelegateForTask:dataTask];
        [self setDelegate:delegate forTask:downloadTask];
    }

    if (self.dataTaskDidBecomeDownloadTask) {
        self.dataTaskDidBecomeDownloadTask(session, dataTask, downloadTask);
    }
}

/**
 Tells the delegate that the data task has received some of the expected data.
 Because the NSData object is often pieced together from a number of different data objects, whenever possible, use NSData’s enumerateByteRangesUsingBlock: method to iterate through the data rather than using the bytes method (which flattens the NSData object into a single memory block).
 This delegate method may be called more than once, and each call provides only data received since the previous call. The app is responsible for accumulating this data if needed
 
 这个方法和上面didCompleteWithError算是NSUrlSession的代理中最重要的两个方法了。
 我们转发了这个方法到AF的代理中去，所以数据的拼接都是在AF的代理中进行的。这也是情理中的，毕竟每个响应数据都是对应各个task，各个AF代理的。在AFURLSessionManager都只是做一些公共的处理。
 
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{

    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    [delegate URLSession:session dataTask:dataTask didReceiveData:data];

    if (self.dataTaskDidReceiveData) {
        self.dataTaskDidReceiveData(session, dataTask, data);
    }
}

/*当task接收到所有期望的数据后，session会调用此代理方法。
 
 Asks the delegate whether the data (or upload) task should store the response in the cache.
 
 The session calls this delegate method after the task finishes receiving all of the expected data. If you do not implement this method, the default behavior is to use the caching policy specified in the session’s configuration object. The primary purpose（最重要的目的） of this method is to prevent caching of specific URLs or to modify the userInfo dictionary associated with the URL response.
 This method is called only if the NSURLProtocol handling the request decides to cache the response. 
 
 As a rule, responses are cached only when all of the following are true:
 The request is for an HTTP or HTTPS URL (or your own custom networking protocol that supports caching).
 The request was successful (with a status code in the 200–299 range).
 The provided response came from the server, rather than out of the cache.
 The session configuration’s cache policy allows caching.
 The provided NSURLRequest object's cache policy (if applicable) allows caching.
 The cache-related headers in the server’s response (if present) allow caching.
 The response size is small enough to reasonably fit within the cache. (For example, if you provide a disk cache, the response must be no larger than about 5% of the disk cache size.)
 
 官方文档翻译如下：
 
 函数作用：
 询问data task或上传任务（upload task）是否缓存response。
 
 函数讨论：
 当task接收到所有期望的数据后，session会调用此代理方法。如果你没有实现该方法，那么就会使用创建session时使用的configuration对象决定缓存策略。这个代理方法最初的目的是为了阻止缓存特定的URLs或者修改NSCacheURLResponse对象相关的userInfo字典。
 该方法只会当request决定缓存response时候调用。作为准则，responses只会当以下条件都成立的时候返回缓存：
 该request是HTTP或HTTPS URL的请求（或者你自定义的网络协议，并且确保该协议支持缓存）
 确保request请求是成功的（返回的status code为200-299）
 返回的response是来自服务器端的，而非缓存中本身就有的
 提供的NSURLRequest对象的缓存策略要允许进行缓存
 服务器返回的response中与缓存相关的header要允许缓存
 该response的大小不能比提供的缓存空间大太多（比如你提供了一个磁盘缓存，那么response大小一定不能比磁盘缓存空间还要大5%）
 
 总结一下就是一个用来缓存response的方法，方法中调用了我们自定义的Block，自定义一个response用来缓存。
 
 */
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    NSCachedURLResponse *cachedResponse = proposedResponse;

    if (self.dataTaskWillCacheResponse) {
        cachedResponse = self.dataTaskWillCacheResponse(session, dataTask, proposedResponse);
    }

    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}

/* If an application has received an
 * -application:handleEventsForBackgroundURLSession:completionHandler:
 * message, the session delegate will receive this message to indicate
 * that all messages previously enqueued for this session have been
 * delivered.  At this time it is safe to invoke the previously stored
 * completion handler, or to begin any internal updates that will
 * result in invoking the completion handler.
 
 
 官方文档翻译：
 
 函数讨论：
 
 在iOS中，当一个后台传输任务完成或者后台传输时需要证书，而此时你的app正在后台挂起，那么你的app在后台会自动重新启动运行，并且这个app的UIApplicationDelegate会发送一个application:handleEventsForBackgroundURLSession:completionHandler:消息。该消息包含了对应后台的session的identifier，而且这个消息会导致你的app启动。你的app随后应该先存储completion handler，然后再使用相同的identifier创建一个background configuration，并根据这个background configuration创建一个新的session。这个新创建的session会自动与后台任务重新关联在一起。
 当你的app获取了一个URLSessionDidFinishEventsForBackgroundURLSession:消息，这就意味着之前这个session中已经入队的所有消息都转发出去了，这时候再调用先前存取的completion handler是安全的，或者因为内部更新而导致调用completion handler也是安全的。
 
 */

//3、 当session中所有已经入队的消息被发送出去后，会调用该代理方法。

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    
    if (self.didFinishEventsForBackgroundURLSession) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.didFinishEventsForBackgroundURLSession(session);
        });
    }
}

#pragma mark - NSURLSessionDownloadDelegate

// AFN使用的是NSURLSession 而在URLSession中的downloadTask任务中 下载的文件被NSURLSession存在一个临时文件中了 所以当下载完成时 需要将文件移走
/* Sent when a download task that has completed a download.  The delegate should
 * copy or move the file at the given location to a new location as it will be
 * removed when the delegate message returns. URLSession:task:didCompleteWithError: will
 * still be called.
 */

/**
 location:
 
 A file URL for the temporary file. Because the file is temporary, you must either open the file for reading or move it to a permanent location in your app’s sandbox container directory before returning from this delegate method.
 If you choose to open the file for reading, you should do the actual reading in another thread to avoid blocking the delegate queue.
 */

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    // URLSession回调的location是下载文件的一个临时路径
    // file:///private/var/mobile/Containers/Data/Application/481DECA5-C005-40C0-8A5D-DC842F56F999/tmp/CFNetworkDownload_DgB44u.tmp
    
    
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    // 这个downloadTaskDidFinishDownloading的block是AFURLSessionManger的
    // 后面的AF代理也有个downloadTaskDidFinishDownloading的block
    if (self.downloadTaskDidFinishDownloading) {
        
        // 调用AFURLSessionManger的downloadTaskDidFinishDownloading的block
        // 需要设置setDownloadTaskDidFinishDownloadingBlock才会有值
        // NSUrlSession代理的下载路径是所有request公用的下载路径，一旦设置，所有的request都会下载到之前那个路径
        NSURL *fileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        
        // https://github.com/AFNetworking/AFNetworking/issues/3775 AFN存在的问题
        if (fileURL) {
            delegate.downloadFileURL = fileURL;
            NSError *error = nil;
            //从临时的下载路径移动至我们需要的路径
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:fileURL error:&error]) {
                // 如果移动出错
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:error.userInfo];
            }
            return;
        }
    }
    //转发代理方法
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
    
}



/**
 Periodically informs the delegate about the download’s progress.
 session
 
 @param session  The session containing the download task.
 @param downloadTask downloadTask
 @param bytesWritten  The number of bytes transferred since the last time this delegate method was called.
 @param totalBytesWritten  The total number of bytes transferred so far.
 
 @param totalBytesExpectedToWrite  The expected length of the file, as provided by the Content-Length header. If this header was not provided, the value is NSURLSessionTransferSizeUnknown
 
 简单说一下这几个参数:
 bytesWritten 表示自上次调用该方法后，接收到的数据字节数
 totalBytesWritten表示目前已经接收到的数据字节数
 totalBytesExpectedToWrite 表示期望收到的文件总字节数，是由Content-Length header提供。如果没有提供，默认是NSURLSessionTransferSizeUnknown
 */
// 多条线程回调 从断点上看会有不同的线程会回调此方法

// NSURLSessionDownloadTask :  Download tasks directly write the server’s response data to a temporary file
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    
    // NSURLSessionDownloadTask :  Download tasks directly write the server’s response data to a temporary file
    // 下载任务会将服务器的response data写入一个临时文件中 内存不会爆炸
    
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    // 转发代理方法
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }

    if (self.downloadTaskDidWriteData) {
        self.downloadTaskDidWriteData(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    }
}


//当下载被取消或者失败后重新恢复下载时调用


/**
 
 Tells the delegate that the download task has resumed downloading.
 If a resumable download task is canceled or fails, you can request a resumeData object that provides enough information to restart the download in the future. Later, you can call downloadTaskWithResumeData: or downloadTaskWithResumeData:completionHandler: with that data.
 When you call those methods, you get a new download task. As soon as you resume that task, the session calls its delegate’s URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes: method with that new task to indicate that the download is resumed.
 
 @param session  The session containing the download task that finished.

 @param downloadTask  The download task that resumed. See explanation in the discussion.

 @param fileOffset  If the file's cache policy or last modified date prevents reuse of the existing content, then this value is zero. Otherwise, this value is an integer representing the number of bytes on disk that do not need to be retrieved again.
 Note
 In some situations, it may be possible for the transfer to resume earlier in the file than where the previous transfer ended.

 @param expectedTotalBytes  The expected length of the file, as provided by the Content-Length header. If this header was not provided, the value is NSURLSessionTransferSizeUnknown.
 官方文档翻译：
 
 函数作用：
 告诉代理，下载任务重新开始下载了。
 
 函数讨论：
 如果一个正在下载任务被取消或者失败了，你可以请求一个resumeData对象（比如在userInfo字典中通过NSURLSessionDownloadTaskResumeData这个键来获取到resumeData）并使用它来提供足够的信息以重新开始下载任务。
 随后，你可以使用resumeData作为downloadTaskWithResumeData:或downloadTaskWithResumeData:completionHandler:的参数。当你调用这些方法时，你将开始一个新的下载任务。一旦你继续下载任务，session会调用它的代理方法URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:其中的downloadTask参数表示的就是新的下载任务，这也意味着下载重新开始了。
 
 
 总结一下：
 
 其实这个就是用来做断点续传的代理方法。可以在下载失败的时候，拿到我们失败的拼接的部分resumeData，然后用去调用downloadTaskWithResumeData：就会调用到这个代理方法来了。
 其中注意：fileOffset这个参数，如果文件缓存策略或者最后文件更新日期阻止重用已经存在的文件内容，那么该值为0。否则，该值表示当前已经下载data的偏移量。
 
 */
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    
    AFURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    // 转发代理方法
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];
    }

    if (self.downloadTaskDidResume) {
        self.downloadTaskDidResume(session, downloadTask, fileOffset, expectedTotalBytes);
    }
}

/**
 至此NSUrlSesssion的delegate讲完了。大概总结下：
 
 每个代理方法对应一个我们自定义的Block,如果Block被赋值了，那么就调用它。
 在这些代理方法里，我们做的处理都是相对于这个sessionManager所有的request的。是公用的处理。
 转发了 6(1-2-3) 个代理方法到AF的deleagate中去了，AF中的deleagate是需要对应每个task去私有化处理的。
  */

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    NSURLSessionConfiguration *configuration = [decoder decodeObjectOfClass:[NSURLSessionConfiguration class] forKey:@"sessionConfiguration"];

    self = [self initWithSessionConfiguration:configuration];
    if (!self) {
        return nil;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.session.configuration forKey:@"sessionConfiguration"];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithSessionConfiguration:self.session.configuration];
}

@end
