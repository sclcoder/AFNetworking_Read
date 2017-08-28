//
//  ViewController.m
//  NSOperation
//
//  Created by mac on 2017/8/28.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "ViewController.h"
#import "CustomOperation.h"

@interface ViewController ()


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    CustomOperation *cop = [[CustomOperation alloc] initWithData:[NSString stringWithFormat:@"我是自定义的OP"]];
    // [cop start];

    
    NSOperationQueue *OPQ = [[NSOperationQueue alloc] init];
    [OPQ addOperation:cop];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 取消op
        [cop cancel];
        
    });
}



@end
