//
//  ViewController.m
//  GCD
//
//  Created by mac on 2018/7/10.
//  Copyright © 2018年 mac. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self test4];
}

// MARK:<测试dispatch_sync在并发队列、串行队列中运行场景>
// 并发队列
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
    
    /// dispatch_sync函数将任务加入队列后需要等待任务完成后才能返回
    /// dispatch_sync会阻塞当前queue而不是阻塞当前线程，执行1的时候是在主线程上执行（官方文档：为了优化dispatch_sync会在当前线程中执行任务）

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
    
    // blockA进入队列queue中,因为是同步任务，要执行blockA后才能返回,所以执行blockA。遇到blockB，blockB进入队列queue中，又是同步任务，要执行blockB后才能返回,但是这时候blockA还没完成。
    // 为什么不发生死锁呢？这要是串行队列早就死锁了。记录我的想法：因为是并发队列,blockA没完成就垃圾霸道，我让blockB出队列,完成blockB就好了。
    // 如果是串行队列呢？在执行blockA时候遇到了blockB进入队列。因为是串行队列我必须把blockA执行完了才能调用队列中的blockB，但是这时候调用blockB的同步函数必须执行了blockB才能返回。结果就是: blockA等待dispatch_sync函数返回好继续向下执行,blockB在队列中没法被调用，因为串行队列还没执行完blcokA。所以两者互相等待就死锁了。
    
    // 这里用dispatch_sync会锁住当前的queue就无法解释了，因为没发生死锁
    
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

// 串行队列
- (void)test4{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.serial", DISPATCH_QUEUE_SERIAL);
    
    // 没有发生死锁
        dispatch_sync(queue, ^{
            sleep(2);
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });

        NSLog(@"222222222--%@",[NSThread currentThread]);
    
    
    
//    2018-07-11 10:46:46.157353+0800 GCD[69611:2051093] 1111111111--<NSThread: 0x60c00007f340>{number = 1, name = main}
//    2018-07-11 10:46:46.157490+0800 GCD[69611:2051093] 222222222--<NSThread: 0x60c00007f340>{number = 1, name = main}

}


- (void)test5{
    
    dispatch_queue_t queue = dispatch_queue_create("com.yunjifen.serial", DISPATCH_QUEUE_SERIAL);
    
    dispatch_sync(queue, ^{
        
        NSLog(@"000000000--%@",[NSThread currentThread]);
        
        dispatch_sync(queue, ^{
            
            NSLog(@"1111111111--%@",[NSThread currentThread]);
        });
        
        NSLog(@"222222222--%@",[NSThread currentThread]);
        
    });
    
    NSLog(@"333333333--%@",[NSThread currentThread]);
    
    
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



// MARK:<测试dispatch_async在并发队列、串行队列中运行场景>
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
