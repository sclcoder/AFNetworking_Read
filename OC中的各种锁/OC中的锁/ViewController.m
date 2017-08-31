//
//  ViewController.m
//  OC中的锁
//
//  Created by mac on 2017/8/21.
//  Copyright © 2017年 yunjifen. All rights reserved.

//  http://www.jianshu.com/p/1e59f0970bf5

#import "ViewController.h"


@interface ViewController ()
{
    
    NSUInteger _tickets;
}

@property(nonatomic,strong) dispatch_queue_t concurrentQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.concurrentQueue = dispatch_queue_create("testLock", DISPATCH_QUEUE_CONCURRENT);
    
    [self testSynchronized];
    
}

- (void)testSynchronized{

    //设置票的数量为5
    _tickets = 5;
    //线程1
    dispatch_async(self.concurrentQueue, ^{
        [self saleTickets];
    });
    //线程2
    dispatch_async(self.concurrentQueue, ^{
        [self saleTickets];
    });

}

- (void)saleTickets {
    
    /**
     @synchronized 关键字加锁 互斥锁，性能较差不推荐使用

     @synchronized(这里添加一个OC对象，一般使用self) {
     这里写要加锁的代码
     }
     　注意点
     　　 1.加锁的代码尽量少
     　　 2.添加的OC对象必须在多个线程中都是同一对象
         3.优点是不需要显式的创建锁对象，便可以实现锁的机制。
         4.@synchronized块会隐式的添加一个异常处理例程来保护代码，该处理例程会在异常抛出的时候自动的释放互斥锁。所以如果不想让隐式的异常处理例程带来额外的开销，你可以考虑使用锁对象
     */
    
    while (1) {
        @synchronized(self) {
        
            [NSThread sleepForTimeInterval:1];
        
            if (_tickets > 0) {
                
                _tickets--;
                NSLog(@"剩余票数= %ld, Thread:%@",_tickets,[NSThread currentThread]);
                
            } else {
                
                NSLog(@"票卖完了 Thread:%@",[NSThread currentThread]);
                break;
            }
        }
    }
    /**
     不加锁可能出现的情况
     
     2017-08-21 12:12:39.900 OC中的锁[54592:2089593] 剩余票数= 4, Thread:<NSThread: 0x610000070000>{number = 4, name = (null)}
     2017-08-21 12:12:39.900 OC中的锁[54592:2089595] 剩余票数= 3, Thread:<NSThread: 0x608000067000>{number = 3, name = (null)}
     2017-08-21 12:12:40.902 OC中的锁[54592:2089595] 剩余票数= 2, Thread:<NSThread: 0x608000067000>{number = 3, name = (null)}
     2017-08-21 12:12:40.902 OC中的锁[54592:2089593] 剩余票数= 1, Thread:<NSThread: 0x610000070000>{number = 4, name = (null)}
     2017-08-21 12:12:41.907 OC中的锁[54592:2089595] 票卖完了 Thread:<NSThread: 0x608000067000>{number = 3, name = (null)}
     2017-08-21 12:12:41.907 OC中的锁[54592:2089593] 剩余票数= 0, Thread:<NSThread: 0x610000070000>{number = 4, name = (null)}
     2017-08-21 12:12:42.912 OC中的锁[54592:2089593] 票卖完了 Thread:<NSThread: 0x610000070000>{number = 4, name = (null)}
     */
    
    /**
     加锁后
     
     2017-08-21 12:15:28.612 OC中的锁[54616:2090965] 剩余票数= 4, Thread:<NSThread: 0x610000065980>{number = 3, name = (null)}
     2017-08-21 12:15:29.617 OC中的锁[54616:2090963] 剩余票数= 3, Thread:<NSThread: 0x600000066240>{number = 4, name = (null)}
     2017-08-21 12:15:30.620 OC中的锁[54616:2090965] 剩余票数= 2, Thread:<NSThread: 0x610000065980>{number = 3, name = (null)}
     2017-08-21 12:15:31.623 OC中的锁[54616:2090963] 剩余票数= 1, Thread:<NSThread: 0x600000066240>{number = 4, name = (null)}
     2017-08-21 12:15:32.626 OC中的锁[54616:2090965] 剩余票数= 0, Thread:<NSThread: 0x610000065980>{number = 3, name = (null)}
     2017-08-21 12:15:33.627 OC中的锁[54616:2090963] 票卖完了 Thread:<NSThread: 0x600000066240>{number = 4, name = (null)}
     2017-08-21 12:15:34.631 OC中的锁[54616:2090965] 票卖完了 Thread:<NSThread: 0x610000065980>{number = 3, name = (null)}
     
     */
}

@end
