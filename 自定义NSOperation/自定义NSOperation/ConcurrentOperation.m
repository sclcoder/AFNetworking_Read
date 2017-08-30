//
//  ConcurrentOperation.m
//  NSOperation
//
//  Created by mac on 2017/8/29.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "ConcurrentOperation.h"

/**
 配置并发执行的 Operation
 
 在默认情况下，operation 是同步执行的，也就是说在调用它的 start 方法的线程中执行它们的任务。而在 operation 和 operation queue 结合使用时，operation queue 可以为非并发的 operation 提供线程，因此，大部分的 operation 仍然可以异步执行。但是，如果你想要手动地执行一个 operation ，又想这个 operation 能够异步执行的话，你需要做一些额外的配置来让你的 operation 支持并发执行。下面列举了一些你可能需要重写的方法：
 
 start ：必须的，所有并发执行的 operation 都必须要重写这个方法，替换掉 NSOperation 类中的默认实现。start 方法是一个 operation 的起点，我们可以在这里配置任务执行的线程或者一些其它的执行环境。另外，需要特别注意的是，在我们重写的 start 方法中一定不要调用父类的实现；
 main ：可选的，通常这个方法就是专门用来实现与该 operation 相关联的任务的。尽管我们可以直接在 start 方法中执行我们的任务，但是用 main 方法来实现我们的任务可以使设置代码和任务代码得到分离，从而使 operation 的结构更清晰；
 isExecuting 和 isFinished ：必须的，并发执行的 operation 需要负责配置它们的执行环境，并且向外界客户报告执行环境的状态。因此，一个并发执行的 operation 必须要维护一些状态信息，用来记录它的任务是否正在执行，是否已经完成执行等。此外，当这两个方法所代表的值发生变化时，我们需要生成相应的 KVO 通知，以便外界能够观察到这些状态的变化；
 isConcurrent ：必须的，这个方法的返回值用来标识一个 operation 是否是并发的 operation ，我们需要重写这个方法并返回 YES 。
 */

@interface ConcurrentOperation ()

@end

@implementation ConcurrentOperation
// 合成两个成员变量
@synthesize executing = _executing;
@synthesize finished  = _finished;


- (id)init {
    self = [super init];
    if (self) {
        _executing = NO;
        _finished  = NO;
    }
    return self;
}


- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}


@end
