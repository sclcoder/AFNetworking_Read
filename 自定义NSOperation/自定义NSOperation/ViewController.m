//
//  ViewController.m
//  自定义NSOperation
//
//  Created by 孙春磊 on 2017/8/30.
//  Copyright © 2017年 云积分. All rights reserved.
//

#import "ViewController.h"

#import "CustomOperation.h"
#import "ConcurrentOperation.h"


@interface ViewController ()


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self opTest];
}


- (void)opTest{
    
    CustomOperation *cop = [[CustomOperation alloc] initWithData:[NSString stringWithFormat:@"我是自定义的OP"]];
    // [cop start];
    
    
    NSOperationQueue *OPQ = [[NSOperationQueue alloc] init];
    [OPQ addOperation:cop];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 取消op
        [cop cancel];
        
    });
    
    
    ConcurrentOperation *ConOP= [[ConcurrentOperation alloc] init];
    [ConOP start];
    
}

@end
