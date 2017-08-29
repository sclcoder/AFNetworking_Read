//
//  ViewController.m
//  NSOperation
//
//  Created by mac on 2017/8/28.
//  Copyright © 2017年 yunjifen. All rights reserved.
//

#import "ViewController.h"

#import "CustomOperation.h"
#import "ConcurrentOperation.h"

#import "Person.h"
#import "Teacher.h"

@interface ViewController ()


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self baseTest];
    
}

- (void)baseTest{
    
    Teacher * t = [[Teacher alloc] init];
    Person *p = [[Person alloc] init];
    
    NSLog(@"%@",  p->_name); // 只有是@public的成员变量才能在任何文件中都能直接访问
    NSLog(@"%@",  p.age); //  间接访问
//    NSLog(@"%@",  p->_age); 不能直接访问


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
