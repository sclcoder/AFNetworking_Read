//
//  GCDBaseViewController.m
//  GCD
//
//  Created by mac on 2018/7/10.
//  Copyright © 2018年 mac. All rights reserved.
//

#import "GCDBaseViewController.h"

@interface GCDBaseViewController ()

@end

@implementation GCDBaseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
     dispatch_queue_t current_queue = dispatch_get_current_queue();
    
    dispatch_queue_t main_queue = dispatch_get_main_queue();

    NSLog(@"%@--%@",current_queue,main_queue);
//    [self testMain_Queue_Async];
    
}


// MARK:<主队列:特殊的串行队列>

/***************** 主队列 *******************/
/*!
 * @function dispatch_get_main_queue
 *
 * @abstract
 * Returns the default queue that is bound to the main thread.
 *
 * @discussion
 * In order to invoke blocks submitted to the main queue, the application must
 * call dispatch_main(), NSApplicationMain(), or use a CFRunLoop on the main
 * thread.
 *
 * @result
 * Returns the main queue. This queue is created automatically on behalf of
 * the main thread before main() is called.
 */

// http://jackhub.github.io/2015/09/17/dispatch/  从源码解释为什么会死锁
- (void)testMain_Queue_Sync{
    // 死锁
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"aaaaa");
    }); // 此处的整个blcok块为'任务a'即^{NSLog(@"aaaaa");}
}
/**
    首先testMain_Queue_Sync{...}这块内容为'test任务'--包含'{''}'
 死锁原因: 主队列开始执行'test任务'---'任务a'进入主队列---因为是dispatch_sync()函数,必须要执行完‘任务a’才能返回,所以要执行'任务a'---因为主队类属于串行队列,必须执行完当前的'test任务'(最后的'}'算执行完成)才能调度队列中的'任务a'--所以死锁是因为主队列无法调用'任务a'导致dispatch_sync函数无法返回。

 **/

- (void)testMain_Queue_Async{
    
    /// '{' 之间的都是test任务 '}' 包含'{' '}'
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"aaaaa-%@",[NSThread currentThread]);
    }); // 此处的整个blcok块为任务a ^{...}
    
    sleep(1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"bbbbb-%@",[NSThread currentThread]);
    });// 此处的整个blcok块为任务b ^{...}

    NSLog(@"11111");
    
    /** 主队列属于串行队列---特点:主队列上的任务都在主线程中执行
        首先整个testMain_Queue_Async方法当做任务进入到主队列中,这里把该任务称作'test任务'。'test任务'开始执行后主线程中的具体情况如下
     任务a进入主队列--执行sleep--任务b进入主队列--输入11111(直到读取到方法的'}'这个'test任务'才算执行完成)--'test任务'完成后主队列调度任务a--主队列调度任务b。执行顺序符合串行队列的原则。
     **/

//    2018-07-12 01:02:56.939857+0800 GCD[56050:941275] 11111
//    2018-07-12 01:02:58.049443+0800 GCD[56050:941275] aaaaa-<NSThread: 0x60000006ae00>{number = 1, name = main}
//    2018-07-12 01:02:58.049712+0800 GCD[56050:941275] bbbbb-<NSThread: 0x60000006ae00>{number = 1, name = main}

}

/***************** 主队列 *******************/


// MARK:<dispatch_sync()同步任务--并行、串行>
/**
 * @abstract
 * Submits a block for synchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a block to a dispatch queue like dispatch_async(), however
 * dispatch_sync() will not return until the block has finished.
   dispatch_sync()函数直到block完成才返回
 *
 * Calls to dispatch_sync() targeting the current queue will result
 * in dead-lock. Use of dispatch_sync() is also subject to the same
 * multi-party dead-lock problems that may result from the use of a mutex.
 * Use of dispatch_async() is preferred.
 
 从测试结果来看 并不是在当前队列中调用dispatch_sync()都会造成死锁,只有在当前队列为串行队列时调用dispatch_sync()才会发生死锁。如果当前队列为并发队列调用dispatch_sync()不会发生死锁
 
 * Unlike dispatch_async(), no retain is performed on the target queue. Because
 * calls to this function are synchronous, the dispatch_sync() "borrows" the
 * reference of the caller.
 *
 * As an optimization, dispatch_sync() invokes the block on the current
 * thread when possible.
   为了优化,dispatch_sync()函数执行任务的时候回尽量在当前线程中执行
 
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to be invoked on the target dispatch queue.
 * The result of passing NULL in this parameter is undefined.
 
   dispatch_sync(dispatch_queue_t queue, DISPATCH_NOESCAPE dispatch_block_t block);
 */

/**************************** dispatch_sync()中的死锁 **********************/
// 当前队列为主队列的情况下-并发队列queueA中执行同步任务
- (void)test1{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.concurrent", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_sync(queue, ^{
        
        NSLog(@"1111111111--%@",[NSThread currentThread]);
    
        sleep(5);
        
        NSLog(@"222222222--%@",[NSThread currentThread]);

    });
    
    NSLog(@"33333333--%@",[NSThread currentThread]);

    sleep(5);
    
    NSLog(@"4444444--%@",[NSThread currentThread]);
    
    /**
        dispatch_sync函数将任务加入队列后需要等待任务完成后才能返回
        dispatch_sync会阻塞当前queue而不是阻塞当前线程
        执行1的为什么是在主线程上执行？--（API官方：* As an optimization, dispatch_sync() invokes the block on the current thread when possible.)
     **/
    

//    2018-07-11 17:16:00.147262+0800 GCD[2923:1250266] 1111111111--<NSThread: 0x1c407e4c0>{number = 1, name = main}
//    2018-07-11 17:16:05.148652+0800 GCD[2923:1250266] 222222222--<NSThread: 0x1c407e4c0>{number = 1, name = main}
//    2018-07-11 17:16:05.148939+0800 GCD[2923:1250266] 33333333--<NSThread: 0x1c407e4c0>{number = 1, name = main}
//    2018-07-11 17:16:10.150259+0800 GCD[2923:1250266] 4444444--<NSThread: 0x1c407e4c0>{number = 1, name = main}
    
}


- (void)test2{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.concurrent", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_sync(queue, ^{ // blockA
        
        NSLog(@"000000000--%@",[NSThread currentThread]);

        dispatch_sync(queue, ^{ // blockB
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
        NSLog(@"222222222--%@",[NSThread currentThread]);
    });

    NSLog(@"333333333--%@",[NSThread currentThread]);
    
/***
 并发队列中的执行过程----在当前的并发队列中执行同步任务不会发生死锁
    1.blockA任务进入队列queue中,因为是同步任务，要执行blockA任务后才能返回,所以执行blockA。
    2.在执行blockA任务的过程中blockB任务进入队列queue中，又是同步任务，要执行blockB后才能返回,此时不返回不能执行后续的代码。
    3.这里正因为是并发队列,可以不用按顺序的执行队列中的任务,也就是说可以不用等待blockA的完成就可以执行blockB。于是执行blockB,之后dispatch_sync函数返回继续执行任务blockA。完美~

 
 串行队列中执行过程----在当前的串行队列中执行同步任务会发生死锁
    1.blockA任务进入队列queue中,因为是同步任务，要执行blockA任务后才能返回,所以执行blockA。
    2.在执行blockA任务的过程中blockB任务进入队列queue中，又是同步任务，要执行blockB后才能返回,此时不返回不能执行后续的代码。
    1.因为是串行队列必须把blockA执行完了才能调用队列中的任务blockB，但是这时候调用blockB的同步函数必须执行了blockB才能返回。结果就是: blockA等待dispatch_sync函数返回好继续向下执行,blockB在队列中没法被调用，因为串行队列还没执行完blcokA。所以两者互相等待就死锁了。


 **/
    
//    2018-07-11 10:42:52.497013+0800 GCD[69181:2046462] 000000000--<NSThread: 0x600000070a80>{number = 1, name = main}
//    2018-07-11 10:42:52.497143+0800 GCD[69181:2046462] 1111111111--<NSThread: 0x600000070a80>{number = 1, name = main}
//    2018-07-11 10:42:52.497284+0800 GCD[69181:2046462] 222222222--<NSThread: 0x600000070a80>{number = 1, name = main}
//    2018-07-11 10:42:52.497400+0800 GCD[69181:2046462] 333333333--<NSThread: 0x600000070a80>{number = 1, name = main}
}


- (void)test3{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.concurrent", DISPATCH_QUEUE_CONCURRENT);

    dispatch_async(queue, ^{
        
        NSLog(@"000000000--%@",[NSThread currentThread]);
        
        dispatch_sync(queue, ^{
            
            NSLog(@"1111111111--%@",[NSThread currentThread]);
            
            dispatch_sync(queue, ^{
                
                NSLog(@"222222222--%@",[NSThread currentThread]);
            });
            
            NSLog(@"3333333333--%@",[NSThread currentThread]);
            
        });
        
        NSLog(@"44444444444--%@",[NSThread currentThread]);
        
    });
    
    NSLog(@"5555555555--%@",[NSThread currentThread]);
    
//    2018-07-11 11:04:28.788654+0800 GCD[71533:2072226] 000000000--<NSThread: 0x604000260940>{number = 4, name = (null)}
//    2018-07-11 11:04:28.788658+0800 GCD[71533:2072130] 5555555555--<NSThread: 0x600000062bc0>{number = 1, name = main}
//    2018-07-11 11:04:28.788836+0800 GCD[71533:2072226] 1111111111--<NSThread: 0x604000260940>{number = 4, name = (null)}
//    2018-07-11 11:04:28.788981+0800 GCD[71533:2072226] 222222222--<NSThread: 0x604000260940>{number = 4, name = (null)}
//    2018-07-11 11:04:28.789113+0800 GCD[71533:2072226] 3333333333--<NSThread: 0x604000260940>{number = 4, name = (null)}
//    2018-07-11 11:04:28.789255+0800 GCD[71533:2072226] 44444444444--<NSThread: 0x604000260940>{number = 4, name = (null)}
    
}

// 当前队列为主队列--串行队列queueA中执行同步任务
- (void)test4{
    /*** 任务0开始**/
    dispatch_queue_t queueA = dispatch_queue_create("com.yunjifen.serial.queueA", DISPATCH_QUEUE_SERIAL);
    
    NSLog(@"00000000--%@",[NSThread currentThread]);
    
    // 没有发生死锁
    dispatch_sync(queueA, ^{
    //  block1
        NSLog(@"1111111111--%@",[NSThread currentThread]);
    });

    NSLog(@"222222222--%@",[NSThread currentThread]);
    /*** 任务0结束**/

    /**
        首先 1.当前队列是主队列(属于串行队列) 2.整个test4方法相当于一个任务被加入到了主队列中
        主队列执行任务0--任务blcok1进入queueA--因为同步任务所以queueA调度线程执行任务block1--执行完成后同步函数返回--主队列继续执行任务0
     **/

//    2018-07-11 23:43:13.200018+0800 GCD[48507:795658] 00000000--<NSThread: 0x60c000071740>{number = 1, name = main}
//    2018-07-11 23:43:13.200190+0800 GCD[48507:795658] 1111111111--<NSThread: 0x60c000071740>{number = 1, name = main}
//    2018-07-11 23:43:13.200367+0800 GCD[48507:795658] 222222222--<NSThread: 0x60c000071740>{number = 1, name = main}

}

// 串行队列
- (void)test44{
    
    dispatch_queue_t queueA = dispatch_queue_create("com.yunjifen.serial.queueA", DISPATCH_QUEUE_SERIAL);
    
    dispatch_queue_t queueB = dispatch_queue_create("com.yunjifen.serial.queueB", DISPATCH_QUEUE_SERIAL);

    dispatch_sync(queueB, ^{
        
        // block0
        
        NSLog(@"00000000--%@",[NSThread currentThread]);

        dispatch_sync(queueA, ^{
            // block1
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
        NSLog(@"222222222--%@",[NSThread currentThread]);
        
    });
    
    NSLog(@"33333333333--%@",[NSThread currentThread]);
    

    /***   不会发生死锁
        执行任务block0-任务block1进入queueA-因为是同步任务所以要完成任务block1后函数才能返回(那么此时queueA就调度线程执行任务block1,此时不会死锁是因为没有妨碍queueA调度任务block1的事情)-任务block1执行完成后同步函数返回-继续执行任务block0
     
        至于为甚都是在主线程中请看API的说明 （API官方说明：* As an optimization, dispatch_sync() invokes the block on the current thread when possible.)
     ***/
    
//    2018-07-11 23:22:05.375496+0800 GCD[46454:756803] 00000000--<NSThread: 0x60800007bb40>{number = 1, name = main}
//    2018-07-11 23:22:05.375661+0800 GCD[46454:756803] 1111111111--<NSThread: 0x60800007bb40>{number = 1, name = main}
//    2018-07-11 23:22:05.375763+0800 GCD[46454:756803] 222222222--<NSThread: 0x60800007bb40>{number = 1, name = main}
//    2018-07-11 23:22:05.375884+0800 GCD[46454:756803] 33333333333--<NSThread: 0x60800007bb40>{number = 1, name = main}


}


- (void)test5{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.serial", DISPATCH_QUEUE_SERIAL);
    
    dispatch_sync(queue, ^{
        // blockA
        NSLog(@"000000000--%@",[NSThread currentThread]);
        
        dispatch_sync(queue, ^{
            // blockB
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
//        NSLog(@"222222222--%@",[NSThread currentThread]);
    
    });
    
    NSLog(@"333333333--%@",[NSThread currentThread]);
    /**
     串行队列中执行过程----在当前的串行队列中执行同步任务会发生死锁
     1.blockA任务进入队列queue中,因为是同步任务，要执行blockA任务后才能返回,所以执行blockA。
     2.在执行blockA任务的过程中blockB任务进入队列queue中，又是同步任务，要执行blockB后才能返回,此时不返回不能执行后续的代码。
     3.因为是串行队列必须把blockA执行完了才能调用队列中的blockB任务，但是这时候调用blockB的同步函数必须执行了blockB才能返回。结果就是: blockA等待dispatch_sync函数返回好继续向下执行,blockB在队列中没法被调用，因为串行队列还没执行完blcokA。所以两者互相等待就死锁了。
     **/


//    2018-07-11 10:48:20.130852+0800 GCD[69785:2053126] 000000000--<NSThread: 0x604000072e00>{number = 1, name = main}
//    发生了死锁

}


- (void)test6{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.serial", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(queue, ^{
        
        NSLog(@"000000000--%@",[NSThread currentThread]);
        
        dispatch_sync(queue, ^{
            
            NSLog(@"1111111111--%@",[NSThread currentThread]);
            
            dispatch_sync(queue, ^{
                
                NSLog(@"222222222--%@",[NSThread currentThread]);
            });
            
            NSLog(@"3333333333--%@",[NSThread currentThread]);
            
        });
        
        NSLog(@"44444444444--%@",[NSThread currentThread]);
        
    });
    
    NSLog(@"5555555555--%@",[NSThread currentThread]);
    
    //    2018-07-11 11:00:01.367774+0800 GCD[71059:2066624] 5555555555--<NSThread: 0x604000076e00>{number = 1, name = main}
    //    2018-07-11 11:00:01.367789+0800 GCD[71059:2066746] 000000000--<NSThread: 0x608000272440>{number = 4, name = (null)}
    //    发生了死锁
    
}
/**************************** 为什么死锁的分割线 **********************/



// MARK:<dispatch_async()在并发队列、串行队列中运行场景>

/*!
 * @function dispatch_async
 *
 * @abstract
 * Submits a block for asynchronous execution on a dispatch queue.
 *
 * @discussion
 * The dispatch_async() function is the fundamental mechanism for submitting
 * blocks to a dispatch queue.
    dispatch_async() 函数是向队列提交blcok(任务)最基本的机制
 *
 * Calls to dispatch_async() always return immediately after the block has
 * been submitted, and never wait for the block to be invoked.
    dispatch_async()函数将blcok(任务)提交到队列后，会立刻返回,从不会等待任务被调用
 
 *
 * The target queue determines whether the block will be invoked serially or
 * concurrently with respect to other blocks submitted to that same queue.
 * Serial queues are processed concurrently with respect to each other.
 *
   队列的类型决定调用block(任务)是串行的还是并发的(可能有多个blocks进入同一个队列中)
   多个串行队列会被并发的进行处理？？？
 
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The system will hold a reference on the target queue until the block
 * has finished.
   系统会引用目标队列,直到任务完成
 
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to submit to the target dispatch queue. This function performs
 * Block_copy() and Block_release() on behalf of callers.
    dispatch_async()函数会为调用者对block(任务)进行Block_copy()和Block_release()
 
 * The result of passing NULL in this parameter is undefined.
 */



// 并发队列
-(void)test7{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.concurrent", DISPATCH_QUEUE_CONCURRENT);
    
    NSLog(@"aaaaaaaaaaa--%@",[NSThread currentThread]);

    dispatch_async(queue, ^{
        
        NSLog(@"1111111111--%@",[NSThread currentThread]);
    });
    
    NSLog(@"bbbbbbbbbbb--%@",[NSThread currentThread]);

    sleep(5);
    
    dispatch_async(queue, ^{
        
        NSLog(@"222222222--%@",[NSThread currentThread]);
    });
    
    NSLog(@"cccccccccc--%@",[NSThread currentThread]);

    
    dispatch_async(queue, ^{
        
        NSLog(@"333333333333--%@",[NSThread currentThread]);
    });

    NSLog(@"dddddddddd--%@",[NSThread currentThread]);

    dispatch_async(queue, ^{
        
        NSLog(@"4444444444--%@",[NSThread currentThread]);
    });

    
    NSLog(@"eeeeeeeeeeee--%@",[NSThread currentThread]);
    
//    2018-07-11 14:45:26.143883+0800 GCD[94623:2336872] aaaaaaaaaaa--<NSThread: 0x60800006fcc0>{number = 1, name = main}
//      这句执行后主线程睡了5s
//    2018-07-11 14:45:26.144164+0800 GCD[94623:2336872] bbbbbbbbbbb--<NSThread: 0x60800006fcc0>{number = 1, name = main}
//    2018-07-11 14:45:26.144210+0800 GCD[94623:2336929] 1111111111--<NSThread: 0x60c000279980>{number = 4, name = (null)}
//      主线程5s后醒来了
//    2018-07-11 14:45:31.144691+0800 GCD[94623:2336872] cccccccccc--<NSThread: 0x60800006fcc0>{number = 1, name = main}
//    2018-07-11 14:45:31.144691+0800 GCD[94623:2336929] 222222222--<NSThread: 0x60c000279980>{number = 4, name = (null)}
//    2018-07-11 14:45:31.144875+0800 GCD[94623:2336872] dddddddddd--<NSThread: 0x60800006fcc0>{number = 1, name = main}
//    2018-07-11 14:45:31.144884+0800 GCD[94623:2336929] 333333333333--<NSThread: 0x60c000279980>{number = 4, name = (null)}
//    2018-07-11 14:45:31.144988+0800 GCD[94623:2336872] eeeeeeeeeeee--<NSThread: 0x60800006fcc0>{number = 1, name = main}
//    2018-07-11 14:45:31.145001+0800 GCD[94623:2336929] 4444444444--<NSThread: 0x60c000279980>{number = 4, name = (null)}

    /** a b c d e 都是在主线程中执行 执行顺序必定是a b c d e ; test7方法中的代码相当于进入了主队列中
     主线程中执行顺序: 执行a--1入队列立刻返回--执行b--睡5s--2入队列立刻返回--执行c--3入队列立刻返回--执行d--4入队列立刻返回--执行e
     */

}

// 并发队列
-(void)test8{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.concurrent", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_async(queue, ^{
       
        NSLog(@"aaaaaaaaaaa--%@",[NSThread currentThread]);
     
        dispatch_async(queue, ^{
            
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
        NSLog(@"bbbbbbbbbbbb--%@",[NSThread currentThread]);

        sleep(5);
        
        dispatch_async(queue, ^{
            
            NSLog(@"222222222--%@",[NSThread currentThread]);
        });
        
        NSLog(@"cccccccccc--%@",[NSThread currentThread]);

        dispatch_async(queue, ^{
            
            NSLog(@"333333333333--%@",[NSThread currentThread]);
        });
        
        NSLog(@"ddddddddddd--%@",[NSThread currentThread]);

        
        dispatch_async(queue, ^{
            
            NSLog(@"4444444444--%@",[NSThread currentThread]);
        });
        
        
        NSLog(@"eeeeeeeeee--%@",[NSThread currentThread]);

        
    });
    
    NSLog(@"zzzzzzzzzzzzz--%@",[NSThread currentThread]);
    
    sleep(2);
    
    NSLog(@"xxxxxxxxx--%@",[NSThread currentThread]);


//    2018-07-11 14:03:14.821950+0800 GCD[90270:2292112] zzzzzzzzzzzzz--<NSThread: 0x60800007b500>{number = 1, name = main}
//    2018-07-11 14:03:14.821951+0800 GCD[90270:2292276] aaaaaaaaaaa--<NSThread: 0x60000026b6c0>{number = 4, name = (null)}
//      这句执行结束了后线程4睡了5秒钟
//    2018-07-11 14:03:14.822171+0800 GCD[90270:2292276] bbbbbbbbbbbb--<NSThread: 0x60000026b6c0>{number = 4, name = (null)}
//    2018-07-11 14:03:14.822200+0800 GCD[90270:2292278] 1111111111--<NSThread: 0x60400046b480>{number = 5, name = (null)}
//      主线程睡了2秒钟后醒了
//    2018-07-11 14:03:16.823156+0800 GCD[90270:2292112] xxxxxxxxx--<NSThread: 0x60800007b500>{number = 1, name = main}
//      线程4睡了5秒钟后醒了
//    2018-07-11 14:03:19.826279+0800 GCD[90270:2292278] 222222222--<NSThread: 0x60400046b480>{number = 5, name = (null)}
//    2018-07-11 14:03:19.826286+0800 GCD[90270:2292276] cccccccccc--<NSThread: 0x60000026b6c0>{number = 4, name = (null)}
//    2018-07-11 14:03:19.826603+0800 GCD[90270:2292276] ddddddddddd--<NSThread: 0x60000026b6c0>{number = 4, name = (null)}
//    2018-07-11 14:03:19.826633+0800 GCD[90270:2292278] 333333333333--<NSThread: 0x60400046b480>{number = 5, name = (null)}
//    2018-07-11 14:03:19.826753+0800 GCD[90270:2292276] eeeeeeeeee--<NSThread: 0x60000026b6c0>{number = 4, name = (null)}
//    2018-07-11 14:03:19.826788+0800 GCD[90270:2292280] 4444444444--<NSThread: 0x600000261e00>{number = 3, name = (null)}


    // 在执行外部dispatch_async时，将外部的block入队列后，立马返回了。 然后执行了z,但是z的执行顺序是不确定的，有可能a在z之前，这个是由CPU控制的。
    // 多次测试结果显示abcde的先后顺序是确定的，而且都是同一个线程中执行的。 根据日志的时间可以看到线程4睡眠后,异步任务2 3 4应该还没有进入队列之中，所以不可能执行。只有当线程4睡醒后。异步任务 2 3 4才依次进入队列中。
    // 线程4中执行顺序为:  执行a--将1入队列后立刻返回--执行b--睡5s--将2入队列立刻返回--执行c--将3入队列立刻返回--执行d--将4入队列立刻返回--执行e 其中任务1 2 3 4进入队列后按照FIFO的顺序执行,但是完成先后顺序不能确定。
}




-(void)test9{
    
    dispatch_queue_t queueSERIAL = dispatch_queue_create("com.yunjifen.serial", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(queueSERIAL, ^{
       
        NSLog(@"aaaaaaaaaaa--%@",[NSThread currentThread]);
        
        dispatch_async(queueSERIAL, ^{
            
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
        NSLog(@"bbbbbbbbbbb--%@",[NSThread currentThread]);
        
        sleep(5);
        
        dispatch_async(queueSERIAL, ^{
            
            NSLog(@"222222222--%@",[NSThread currentThread]);
        });
        
        NSLog(@"cccccccccc--%@",[NSThread currentThread]);
        
        dispatch_async(queueSERIAL, ^{
            
            NSLog(@"333333333333--%@",[NSThread currentThread]);
        });
        
        sleep(2);
        
        NSLog(@"dddddddddd--%@",[NSThread currentThread]);
        
        dispatch_async(queueSERIAL, ^{
            
            NSLog(@"4444444444--%@",[NSThread currentThread]);
        });
        
        NSLog(@"eeeeeeeeeeee--%@",[NSThread currentThread]);
        
    });
    
//    2018-07-11 15:04:44.938619+0800 GCD[96626:2359069] aaaaaaaaaaa--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:44.938821+0800 GCD[96626:2359069] bbbbbbbbbbb--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:49.942794+0800 GCD[96626:2359069] cccccccccc--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.943364+0800 GCD[96626:2359069] dddddddddd--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.943570+0800 GCD[96626:2359069] eeeeeeeeeeee--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.943711+0800 GCD[96626:2359069] 1111111111--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.943864+0800 GCD[96626:2359069] 222222222--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.943977+0800 GCD[96626:2359069] 333333333333--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
//    2018-07-11 15:04:51.944076+0800 GCD[96626:2359069] 4444444444--<NSThread: 0x608000261fc0>{number = 4, name = (null)}
    
    // 主线程: 第一个dispatch_async中的block整体进入队列queueSERIAL中
    // 线程4: 执行a--1进入队列queueSERIAL中立刻返回--执行b--睡5s--2进入队列queueSERIAL中立刻返回--执行c--3进入队列queueSERIAL中立刻返回--睡2s--执行d--4进入队列queueSERIAL中立刻返回--执行e。 当执行e结束后队列queueSERIAL中还有1 2 3 4这4个任务。按照FIFO的原则一次执行这四个任务。串行队列每次只能执行一个任务,所以执行完成的顺序和出队列顺序一致，按照1 2 3 4的顺序执行完毕。
 }


// 串行队列
-(void)test10{
    
    dispatch_queue_t queueA = dispatch_queue_create("com.yunjifen.serialA", DISPATCH_QUEUE_SERIAL);

    NSLog(@"1111111111--%@",[NSThread currentThread]);
    
    dispatch_async(queueA, ^{
        
        // 这块blockA 第一个进入queueA 然后返回了
        NSLog(@"AAAAAAA1111111--%@",[NSThread currentThread]);
        
//        sleep(1);
        dispatch_async(queueA, ^{
            // blockC进入queueA然后返回---进入的时间不能确定因为blockB有可能早一步进入queueA
            NSLog(@"AAAAAAA3333333--%@",[NSThread currentThread]);
        });
    });
    
    NSLog(@"2222222222--%@",[NSThread currentThread]);
    
    dispatch_async(queueA, ^{
        // 这块blockB进入queueA然后返回--进入queueA的时机不能确定因为blockC有可能早一步进入queueA
        NSLog(@"AAAAAAA2222222--%@",[NSThread currentThread]);
    });
    
    NSLog(@"333333333--%@",[NSThread currentThread]);
    
//    2018-07-11 16:45:24.615229+0800 GCD[2676:1231413] 1111111111--<NSThread: 0x1c006c840>{number = 1, name = main}
//    2018-07-11 16:45:24.615366+0800 GCD[2676:1231489] AAAAAAA1111111--<NSThread: 0x1c44641c0>{number = 3, name = (null)}
//    2018-07-11 16:45:24.616202+0800 GCD[2676:1231413] 2222222222--<NSThread: 0x1c006c840>{number = 1, name = main}
//    2018-07-11 16:45:24.616444+0800 GCD[2676:1231413] 333333333--<NSThread: 0x1c006c840>{number = 1, name = main}
//    2018-07-11 16:45:25.620493+0800 GCD[2676:1231489] AAAAAAA2222222--<NSThread: 0x1c44641c0>{number = 3, name = (null)}
//    2018-07-11 16:45:25.620625+0800 GCD[2676:1231489] AAAAAAA3333333--<NSThread: 0x1c44641c0>{number = 3, name = (null)}
    
//    2018-07-11 16:46:22.214741+0800 GCD[2744:1233074] 1111111111--<NSThread: 0x1c0262d40>{number = 1, name = main}
//    2018-07-11 16:46:22.215013+0800 GCD[2744:1233074] 2222222222--<NSThread: 0x1c0262d40>{number = 1, name = main}
//    2018-07-11 16:46:22.215023+0800 GCD[2744:1233164] AAAAAAA1111111--<NSThread: 0x1c0475a80>{number = 3, name = (null)}
//    2018-07-11 16:46:22.215112+0800 GCD[2744:1233164] AAAAAAA3333333--<NSThread: 0x1c0475a80>{number = 3, name = (null)}
//    2018-07-11 16:46:22.215272+0800 GCD[2744:1233164] AAAAAAA2222222--<NSThread: 0x1c0475a80>{number = 3, name = (null)}
//    2018-07-11 16:46:22.215471+0800 GCD[2744:1233074] 333333333--<NSThread: 0x1c0262d40>{number = 1, name = main}
    
}



// 串行队列
-(void)test11{
    
    // 根据进入队列的顺序 可以确定一些事情
    
    dispatch_queue_t queueA = dispatch_queue_create("com.yunjifen.serialA", DISPATCH_QUEUE_SERIAL);
    
    dispatch_queue_t queueB = dispatch_queue_create("com.yunjifen.serialB", DISPATCH_QUEUE_SERIAL);
    
    
    NSLog(@"aaaaaaaaaaa--%@",[NSThread currentThread]);
    
    dispatch_async(queueA, ^{
        
        NSLog(@"queueAAAAA1111--%@",[NSThread currentThread]);
        /// 这三个任务 进入queueB的顺序是确定的queueBBBBB4444 queueBBBBB5555 queueBBBBB6666 他们中间也可能会插入新的任务
        dispatch_async(queueB, ^{
            NSLog(@"queueBBBBB4444--%@",[NSThread currentThread]);
        });
        
        sleep(2);
        
        dispatch_async(queueB, ^{
            NSLog(@"queueBBBBB5555--%@",[NSThread currentThread]);
        });
        
        dispatch_async(queueB, ^{
            NSLog(@"queueBBBBB6666--%@",[NSThread currentThread]);
        });
        
        
    });
    
    NSLog(@"bbbbbbbbbbb--%@",[NSThread currentThread]);
    
    
    dispatch_async(queueA, ^{
        
        NSLog(@"queueAAAAA2222--%@",[NSThread currentThread]);
    });
    
    NSLog(@"cccccccccc--%@",[NSThread currentThread]);
    
    dispatch_async(queueB, ^{
        
        NSLog(@"queueBBBBB1111--%@",[NSThread currentThread]);
    });
    
    
    dispatch_async(queueA, ^{
        
        NSLog(@"queueAAAAA3333--%@",[NSThread currentThread]);
    });
    
    
    dispatch_async(queueB, ^{
        
        NSLog(@"queueBBBBB2222--%@",[NSThread currentThread]);
    });
    
    dispatch_async(queueB, ^{
        
        NSLog(@"queueBBBBB3333--%@",[NSThread currentThread]);
    });
    
    
    NSLog(@"dddddddddd--%@",[NSThread currentThread]);
    
    dispatch_async(queueA, ^{
        
        NSLog(@"queueAAAAA4444--%@",[NSThread currentThread]);
    });
    
    NSLog(@"eeeeeeeeeeee--%@",[NSThread currentThread]);
    
    //    2018-07-11 16:19:36.788889+0800 GCD[2480:1220101] aaaaaaaaaaa--<NSThread: 0x1c006cec0>{number = 1, name = main}
    //    2018-07-11 16:19:36.789013+0800 GCD[2480:1220179] queueAAAAA1111--<NSThread: 0x1c42783c0>{number = 3, name = (null)}
    //    2018-07-11 16:19:36.789096+0800 GCD[2480:1220177] queueBBBBB4444--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789139+0800 GCD[2480:1220177] queueBBBBB5555--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789180+0800 GCD[2480:1220177] queueBBBBB6666--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789227+0800 GCD[2480:1220101] bbbbbbbbbbb--<NSThread: 0x1c006cec0>{number = 1, name = main}
    //    2018-07-11 16:19:36.789277+0800 GCD[2480:1220177] queueAAAAA2222--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789309+0800 GCD[2480:1220101] cccccccccc--<NSThread: 0x1c006cec0>{number = 1, name = main}
    //    2018-07-11 16:19:36.789418+0800 GCD[2480:1220177] queueBBBBB1111--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789464+0800 GCD[2480:1220179] queueAAAAA3333--<NSThread: 0x1c42783c0>{number = 3, name = (null)}
    //    2018-07-11 16:19:36.789489+0800 GCD[2480:1220101] dddddddddd--<NSThread: 0x1c006cec0>{number = 1, name = main}
    //    2018-07-11 16:19:36.789567+0800 GCD[2480:1220177] queueBBBBB2222--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    //    2018-07-11 16:19:36.789646+0800 GCD[2480:1220179] queueAAAAA4444--<NSThread: 0x1c42783c0>{number = 3, name = (null)}
    //    2018-07-11 16:19:36.789674+0800 GCD[2480:1220101] eeeeeeeeeeee--<NSThread: 0x1c006cec0>{number = 1, name = main}
    //    2018-07-11 16:19:36.789732+0800 GCD[2480:1220177] queueBBBBB3333--<NSThread: 0x1c42781c0>{number = 4, name = (null)}
    
    
    
    //    2018-07-11 16:22:27.597333+0800 GCD[2600:1223079] aaaaaaaaaaa--<NSThread: 0x1c0261b00>{number = 1, name = main}
    //    2018-07-11 16:22:27.597470+0800 GCD[2600:1223079] bbbbbbbbbbb--<NSThread: 0x1c0261b00>{number = 1, name = main}
    //    2018-07-11 16:22:27.597710+0800 GCD[2600:1223079] cccccccccc--<NSThread: 0x1c0261b00>{number = 1, name = main}
    //    2018-07-11 16:22:27.597790+0800 GCD[2600:1223079] dddddddddd--<NSThread: 0x1c0261b00>{number = 1, name = main}
    //    2018-07-11 16:22:27.597790+0800 GCD[2600:1223166] queueAAAAA1111--<NSThread: 0x1c027f400>{number = 3, name = (null)}
    //    2018-07-11 16:22:27.597833+0800 GCD[2600:1223079] eeeeeeeeeeee--<NSThread: 0x1c0261b00>{number = 1, name = main}
    //    2018-07-11 16:22:27.597874+0800 GCD[2600:1223166] queueAAAAA2222--<NSThread: 0x1c027f400>{number = 3, name = (null)}
    //    2018-07-11 16:22:27.597918+0800 GCD[2600:1223164] queueBBBBB1111--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    //    2018-07-11 16:22:27.598001+0800 GCD[2600:1223166] queueAAAAA3333--<NSThread: 0x1c027f400>{number = 3, name = (null)}
    //    2018-07-11 16:22:27.598076+0800 GCD[2600:1223164] queueBBBBB2222--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    //    2018-07-11 16:22:27.598137+0800 GCD[2600:1223166] queueAAAAA4444--<NSThread: 0x1c027f400>{number = 3, name = (null)}
    //    2018-07-11 16:22:27.598188+0800 GCD[2600:1223164] queueBBBBB3333--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    //    2018-07-11 16:22:27.598386+0800 GCD[2600:1223164] queueBBBBB4444--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    //    2018-07-11 16:22:27.598425+0800 GCD[2600:1223164] queueBBBBB5555--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    //    2018-07-11 16:22:27.598463+0800 GCD[2600:1223164] queueBBBBB6666--<NSThread: 0x1c0460140>{number = 4, name = (null)}
    
    
    //    2018-07-11 16:34:20.987895+0800 GCD[2629:1227488] aaaaaaaaaaa--<NSThread: 0x1c406b580>{number = 1, name = main}
    //    2018-07-11 16:34:20.988011+0800 GCD[2629:1227488] bbbbbbbbbbb--<NSThread: 0x1c406b580>{number = 1, name = main}
    //    2018-07-11 16:34:20.988048+0800 GCD[2629:1227559] queueAAAAA1111--<NSThread: 0x1c00763c0>{number = 3, name = (null)}
    //    2018-07-11 16:34:20.988058+0800 GCD[2629:1227488] cccccccccc--<NSThread: 0x1c406b580>{number = 1, name = main}
    //    2018-07-11 16:34:20.988147+0800 GCD[2629:1227561] queueBBBBB4444--<NSThread: 0x1c446d800>{number = 4, name = (null)}
    //    2018-07-11 16:34:20.988191+0800 GCD[2629:1227488] dddddddddd--<NSThread: 0x1c406b580>{number = 1, name = main}
    //    2018-07-11 16:34:20.988217+0800 GCD[2629:1227561] queueBBBBB1111--<NSThread: 0x1c446d800>{number = 4, name = (null)}
    //    2018-07-11 16:34:20.988262+0800 GCD[2629:1227488] eeeeeeeeeeee--<NSThread: 0x1c406b580>{number = 1, name = main}
    //    2018-07-11 16:34:20.988285+0800 GCD[2629:1227561] queueBBBBB2222--<NSThread: 0x1c446d800>{number = 4, name = (null)}
    //    2018-07-11 16:34:20.992082+0800 GCD[2629:1227561] queueBBBBB3333--<NSThread: 0x1c446d800>{number = 4, name = (null)}
    //    2018-07-11 16:34:22.991677+0800 GCD[2629:1227559] queueAAAAA2222--<NSThread: 0x1c00763c0>{number = 3, name = (null)}
    //    2018-07-11 16:34:22.992027+0800 GCD[2629:1227558] queueBBBBB5555--<NSThread: 0x1c0075280>{number = 5, name = (null)}
    //    2018-07-11 16:34:22.992031+0800 GCD[2629:1227559] queueAAAAA3333--<NSThread: 0x1c00763c0>{number = 3, name = (null)}
    //    2018-07-11 16:34:22.992330+0800 GCD[2629:1227559] queueAAAAA4444--<NSThread: 0x1c00763c0>{number = 3, name = (null)}
    //    2018-07-11 16:34:22.992350+0800 GCD[2629:1227558] queueBBBBB6666--<NSThread: 0x1c0075280>{number = 5, name = (null)}
    
}






@end
