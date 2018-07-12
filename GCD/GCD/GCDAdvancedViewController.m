//
//  GCDAdvancedViewController.m
//  GCD
//
//  Created by mac on 2018/7/12.
//  Copyright © 2018年 mac. All rights reserved.
//

#import "GCDAdvancedViewController.h"

@interface GCDAdvancedViewController ()


@end

@implementation GCDAdvancedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (IBAction)redo:(id)sender {

    //    [self apply];
    
    [self iterationsManunal];
}

 /*!
 * @function dispatch_apply
 *
 * @abstract
 * Submits a block to a dispatch queue for parallel invocation.
   在队列中多次执行block
 *
 * @discussion
 * Submits a block to a dispatch queue for parallel invocation. This function
 * waits for the task block to complete before returning. If the specified queue
 * is concurrent, the block may be invoked concurrently, and it must therefore
 * be reentrant safe.
   该函数在执行完所有的block后才返回
 *
 * Each invocation of the block will be passed the current index of iteration.
   每个被调用的block会接收到遍历的位置
 *
 * @param iterations 迭代次数
 * The number of iterations to perform.
 *
 * @param queue
 * The dispatch queue to which the block is submitted.
 * The preferred value to pass is DISPATCH_APPLY_AUTO to automatically use
 * a queue appropriate for the calling thread.
   可以指定自定义的队列
   最好使用DISPATCH_APPLY_AUTO这个预设的值。使用DISPATCH_APPLY_AUTO系统将自动使用一个合适的队列
  
  
 * @param block
 * The block to be invoked the specified number of iterations.
 * The result of passing NULL in this parameter is undefined.
 */


/*! 关于DISPATCH_APPLY_AUTO
 * @constant DISPATCH_APPLY_AUTO
 *
 * @abstract
 * Constant to pass to dispatch_apply() or dispatch_apply_f() to request that
 * the system automatically use worker threads that match the configuration of
 * the current thread as closely as possible.
  *
 * @discussion
 * When submitting a block for parallel invocation, passing this constant as the
 * queue argument will automatically use the global concurrent queue that
 * matches the Quality of Service of the caller most closely.
 
    在dispatch_apply()中使用该参数指定队列，系统会自动使用全局并发队列
 *
 * No assumptions should be made about which global concurrent queue will
 * actually be used.
 *
 * Using this constant deploys backward to macOS 10.9, iOS 7.0 and any tvOS or
 * watchOS version.
 */


- (void)apply{
    
    dispatch_queue_t s_queue = dispatch_queue_create("com.yunjifen.serial_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t c_queue = dispatch_queue_create("com.yunjifen.serial_queue", DISPATCH_QUEUE_CONCURRENT);
    
    // DISPATCH_APPLY_AUTO
    dispatch_apply( 300 , DISPATCH_APPLY_AUTO, ^(size_t index) {
        
        NSLog(@"apply loop: %zd --thread:%@",index,[NSThread currentThread]);
    });
    
    NSLog(@"after applly");
    /**
        1.改函数要等待队列中的任务完成才会返回--不论是串行队列or并发队列
        2.DISPATCH_APPLY_AUTO一般使用该参数自动使用全局队列-达到最优效果
        3.这个函数和自己写的循环有什么区别: 会控制线程的数量,不会造成线程爆炸(效率更高因为开启新线程是很耗性能的事情)
     
        从日志看这里迭代了300次 线程开启了10条左右
     **/
}

- (void)iterationsManunal{
    
    for (int index=0; index<300; index++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSLog(@"apply loop: %zd --thread:%@",index,[NSThread currentThread]);
        });
    }
    // 从日志看这里迭代了300次线程开启了60-70条左右。性能不如使用apply函数
}


@end
