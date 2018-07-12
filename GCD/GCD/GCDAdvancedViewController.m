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
    
//    [self iterationsManunal];
    
//    [self nastedApplySC];

//    [self nastedApplyCC];
    
//    [self nastedApplySS];
    
    [self nastedApplyCS];
    
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
    dispatch_queue_t c_queue = dispatch_queue_create("com.yunjifen.concurrent_queue", DISPATCH_QUEUE_CONCURRENT);
    
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


// 串行队列嵌套并发队列
- (void)nastedApplySC{
    
    dispatch_queue_t s_queue = dispatch_queue_create("com.yunjifen.serial_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t c_queue = dispatch_queue_create("com.yunjifen.concurrent_queue", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_apply( 3 , s_queue, ^(size_t index) { // dispatch_apply()函数必须执行完block才能返回
        
        NSLog(@"apply loop outside start: %zd--thread:%@",index,[NSThread currentThread]);
        
        dispatch_apply(3, DISPATCH_APPLY_AUTO, ^(size_t index) {
            
            NSLog(@"apply loop inside: %zd--thread:%@",index,[NSThread currentThread]);
        });
        
        NSLog(@"apply loop outside end: %zd--thread:%@",index,[NSThread currentThread]);
        
    });
    
    NSLog(@"after applly");
    
    // 这个结果是预测结果
    
    //    2018-07-12 16:58:45.965680+0800 GCD[15502:186497] apply loop outside start: 0--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.965905+0800 GCD[15502:186497] apply loop inside: 0--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.965968+0800 GCD[15502:186562] apply loop inside: 2--thread:<NSThread: 0x60000007b0c0>{number = 5, name = (null)}
    //    2018-07-12 16:58:45.965976+0800 GCD[15502:186804] apply loop inside: 1--thread:<NSThread: 0x608000071ac0>{number = 4, name = (null)}
    //    2018-07-12 16:58:45.966140+0800 GCD[15502:186497] apply loop outside end: 0--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    
    //    2018-07-12 16:58:45.966270+0800 GCD[15502:186497] apply loop outside start: 1--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.966398+0800 GCD[15502:186497] apply loop inside: 0--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.966414+0800 GCD[15502:186804] apply loop inside: 1--thread:<NSThread: 0x608000071ac0>{number = 4, name = (null)}
    //    2018-07-12 16:58:45.966428+0800 GCD[15502:186562] apply loop inside: 2--thread:<NSThread: 0x60000007b0c0>{number = 5, name = (null)}
    //    2018-07-12 16:58:45.966617+0800 GCD[15502:186497] apply loop outside end: 1--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    
    //    2018-07-12 16:58:45.966733+0800 GCD[15502:186497] apply loop outside start: 2--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.966856+0800 GCD[15502:186497] apply loop inside: 0--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    //    2018-07-12 16:58:45.966861+0800 GCD[15502:186562] apply loop inside: 1--thread:<NSThread: 0x60000007b0c0>{number = 5, name = (null)}
    //    2018-07-12 16:58:45.966863+0800 GCD[15502:186804] apply loop inside: 2--thread:<NSThread: 0x608000071ac0>{number = 4, name = (null)}
    //    2018-07-12 16:58:45.967337+0800 GCD[15502:186497] apply loop outside end: 2--thread:<NSThread: 0x608000065d00>{number = 1, name = main}
    
    //    2018-07-12 16:58:45.967468+0800 GCD[15502:186497] after applly
    
}


- (void)nastedApplyCC{
    
    NSLog(@"start applly");

    // DISPATCH_APPLY_AUTO
    dispatch_apply( 3 , DISPATCH_APPLY_AUTO, ^(size_t index) {
        
        NSLog(@"apply loop outside start: %zd--thread:%@",index,[NSThread currentThread]);
        
        dispatch_apply(3, DISPATCH_APPLY_AUTO, ^(size_t index) {
            
            NSLog(@"apply loop inside: %zd--thread:%@",index,[NSThread currentThread]);
        });
        
        NSLog(@"apply loop outside end: %zd--thread:%@",index,[NSThread currentThread]);
        
    });
    
    NSLog(@"after applly");
    
    ///   整体顺序是这个样子---之所以是这个顺序是因为是在‘同一并发队列中执行的’-----DISPATCH_APPLY_AUTO指定的是全局队列
    {     // A-start
    //    2018-07-12 16:50:40.874001+0800 GCD[14640:178170] start applly
    }
    
    {     // B-start 内部顺序不确定-因为并发队列的关系
    //    2018-07-12 16:50:40.874003+0800 GCD[14640:178170] apply loop outside start: 0 --thread:<NSThread: 0x60800007af00>{number = 1, name = main}
    //    2018-07-12 16:50:40.874005+0800 GCD[14640:178223] apply loop outside start: 1 --thread:<NSThread: 0x60c00027cf40>{number = 4, name = (null)}
    //    2018-07-12 16:50:40.874064+0800 GCD[14640:178450] apply loop outside start: 2 --thread:<NSThread: 0x60000046d3c0>{number = 5, name = (null)}
    }
    
    {     // C       内部顺序不确定-因为并发队列的关系
    //    2018-07-12 16:50:40.874212+0800 GCD[14640:178223] apply loop inside: 0 --thread:<NSThread: 0x60c00027cf40>{number = 4, name = (null)}
    //    2018-07-12 16:50:40.874223+0800 GCD[14640:178170] apply loop inside: 0 --thread:<NSThread: 0x60800007af00>{number = 1, name = main}
    //    2018-07-12 16:50:40.874244+0800 GCD[14640:178450] apply loop inside: 0 --thread:<NSThread: 0x60000046d3c0>{number = 5, name = (null)}
    //    2018-07-12 16:50:40.874303+0800 GCD[14640:178467] apply loop inside: 1 --thread:<NSThread: 0x60c000275200>{number = 6, name = (null)}
    //    2018-07-12 16:50:40.874351+0800 GCD[14640:178223] apply loop inside: 2 --thread:<NSThread: 0x60c00027cf40>{number = 4, name = (null)}
    //    2018-07-12 16:50:40.874358+0800 GCD[14640:178468] apply loop inside: 1 --thread:<NSThread: 0x60800027ac00>{number = 7, name = (null)}
    //    2018-07-12 16:50:40.874362+0800 GCD[14640:178469] apply loop inside: 1 --thread:<NSThread: 0x60c00007dcc0>{number = 8, name = (null)}
    //    2018-07-12 16:50:40.874396+0800 GCD[14640:178170] apply loop inside: 2 --thread:<NSThread: 0x60800007af00>{number = 1, name = main}
    //    2018-07-12 16:50:40.874460+0800 GCD[14640:178450] apply loop inside: 2 --thread:<NSThread: 0x60000046d3c0>{number = 5, name = (null)}
    }
    
    {     // B-end  内部顺序不确定-因为并发队列的关系
    //    2018-07-12 16:50:40.874808+0800 GCD[14640:178223] apply loop outside end: 1 --thread:<NSThread: 0x60c00027cf40>{number = 4, name = (null)}
    //    2018-07-12 16:50:40.875165+0800 GCD[14640:178450] apply loop outside end: 2 --thread:<NSThread: 0x60000046d3c0>{number = 5, name = (null)}
    //    2018-07-12 16:50:40.875352+0800 GCD[14640:178170] apply loop outside end: 0 --thread:<NSThread: 0x60800007af00>{number = 1, name = main}
    }
    {     // A-end
    //    2018-07-12 16:50:40.875921+0800 GCD[14640:178170] after applly
    }
}


- (void)nastedApplySS{
    
    dispatch_queue_t s_queue = dispatch_queue_create("com.yunjifen.serial_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t c_queue = dispatch_queue_create("com.yunjifen.concurrent_queue", DISPATCH_QUEUE_CONCURRENT);
    
    NSLog(@"start applly");
    
    dispatch_apply( 3 , s_queue, ^(size_t index) { // dispatch_apply()函数必须执行完block才能返回
        
        NSLog(@"apply loop outside start: %zd--thread:%@",index,[NSThread currentThread]);
        
        dispatch_apply(3, s_queue, ^(size_t index) {
            
            NSLog(@"apply loop inside: %zd--thread:%@",index,[NSThread currentThread]);
        });
        
        NSLog(@"apply loop outside end: %zd--thread:%@",index,[NSThread currentThread]);
        
    });
    
    NSLog(@"after applly");
    
    /// 会发生死锁:dispatch_apply()不返回和串行队列无法执行下一个任务造成死锁
//    2018-07-12 17:24:22.255196+0800 GCD[18275:212368] start applly
//    2018-07-12 17:24:22.255370+0800 GCD[18275:212368] apply loop outside start: 0--thread:<NSThread: 0x60800007c280>{number = 1, name = main}
}


- (void)nastedApplyCS{
    
    dispatch_queue_t s_queue = dispatch_queue_create("com.yunjifen.serial_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t c_queue = dispatch_queue_create("com.yunjifen.concurrent_queue", DISPATCH_QUEUE_CONCURRENT);
    
    NSLog(@"start applly");
    
    dispatch_apply( 3 , DISPATCH_APPLY_AUTO, ^(size_t index) { // dispatch_apply()函数必须执行完block才能返回
        
        NSLog(@"apply loop outside start: %zd--thread:%@",index,[NSThread currentThread]);
        
        dispatch_apply(3, s_queue, ^(size_t index) {
            
            NSLog(@"apply loop inside: %zd--thread:%@",index,[NSThread currentThread]);
        });
        
        NSLog(@"apply loop outside end: %zd--thread:%@",index,[NSThread currentThread]);
        
    });
    
    NSLog(@"after applly");
    
    /// 这个结果通过线程可以分析
    
//    2018-07-12 17:29:01.383553+0800 GCD[18790:217289] start applly
    
//    2018-07-12 17:29:01.383762+0800 GCD[18790:217289] apply loop outside start: 0--thread:<NSThread: 0x608000071280>{number = 1, name = main}
//    2018-07-12 17:29:01.383818+0800 GCD[18790:217366] apply loop outside start: 2--thread:<NSThread: 0x608000462180>{number = 5, name = (null)}
//    2018-07-12 17:29:01.383821+0800 GCD[18790:217385] apply loop outside start: 1--thread:<NSThread: 0x60800027e9c0>{number = 4, name = (null)}
    
//    2018-07-12 17:29:01.383936+0800 GCD[18790:217289] apply loop inside: 0--thread:<NSThread: 0x608000071280>{number = 1, name = main}
//    2018-07-12 17:29:01.384051+0800 GCD[18790:217289] apply loop inside: 1--thread:<NSThread: 0x608000071280>{number = 1, name = main}
//    2018-07-12 17:29:01.384168+0800 GCD[18790:217289] apply loop inside: 2--thread:<NSThread: 0x608000071280>{number = 1, name = main}
    
//    2018-07-12 17:29:01.384291+0800 GCD[18790:217289] apply loop outside end: 0--thread:<NSThread: 0x608000071280>{number = 1, name = main}
    
//    2018-07-12 17:29:01.384303+0800 GCD[18790:217366] apply loop inside: 0--thread:<NSThread: 0x608000462180>{number = 5, name = (null)}
//    2018-07-12 17:29:01.384459+0800 GCD[18790:217366] apply loop inside: 1--thread:<NSThread: 0x608000462180>{number = 5, name = (null)}
//    2018-07-12 17:29:01.384635+0800 GCD[18790:217366] apply loop inside: 2--thread:<NSThread: 0x608000462180>{number = 5, name = (null)}
    
//    2018-07-12 17:29:01.384782+0800 GCD[18790:217366] apply loop outside end: 2--thread:<NSThread: 0x608000462180>{number = 5, name = (null)}
    
//    2018-07-12 17:29:01.384783+0800 GCD[18790:217385] apply loop inside: 0--thread:<NSThread: 0x60800027e9c0>{number = 4, name = (null)}
//    2018-07-12 17:29:01.385234+0800 GCD[18790:217385] apply loop inside: 1--thread:<NSThread: 0x60800027e9c0>{number = 4, name = (null)}
//    2018-07-12 17:29:01.385431+0800 GCD[18790:217385] apply loop inside: 2--thread:<NSThread: 0x60800027e9c0>{number = 4, name = (null)}
    
//    2018-07-12 17:29:01.385618+0800 GCD[18790:217385] apply loop outside end: 1--thread:<NSThread: 0x60800027e9c0>{number = 4, name = (null)}
    
//    2018-07-12 17:29:01.385791+0800 GCD[18790:217289] after applly

    
}




@end
