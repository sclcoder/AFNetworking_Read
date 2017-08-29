//
//  CustomOperation.m
//  NSOperation
//
//  Created by mac on 2017/8/28.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

// http://blog.leichunfeng.com/blog/2015/07/29/ios-concurrency-programming-operation-queues/

#import "CustomOperation.h"

@interface CustomOperation ()

@property(nonatomic,strong) id data;

@end

// 同步执行的OP（在不适用OPQueue的情况下）
@implementation CustomOperation

- (instancetype)initWithData:(id)data{
    
    self = [super init];
    if (self) {
        self.data = data;
    }
    return self;
}


- (void)main{

    @try {
        // 检测是否取消了
        if (self.isCancelled) return;
        
        NSLog(@"Start executing %@ with data: %@, mainThread: %@, currentThread: %@", NSStringFromSelector(_cmd), self.data, [NSThread mainThread], [NSThread currentThread]);
        
            for (NSUInteger i = 0; i < 10; i++) {
                
                // 检测是否取消了
                if (self.isCancelled) return;
                
                sleep(1);
                
                NSLog(@"Loop %@, thread %@", @(i + 1),[NSThread currentThread]);
            }
        
           NSLog(@"Finish executing %@", NSStringFromSelector(_cmd));

    } @catch (NSException *exception) {
        
           NSLog(@"Exception:%@",exception);
        
    } @finally {
        
           NSLog(@"finally");
    }
    
}

@end
