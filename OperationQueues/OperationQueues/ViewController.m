//
//  ViewController.m
//  OperationQueues
//
//  Created by leichunfeng on 15/8/1.
//  Copyright (c) 2015年 leichunfeng. All rights reserved.
//

#import "ViewController.h"

#import "OQCreateInvocationOperation.h"
#import "OQCreateBlockOperation.h"


@interface ViewController ()

@property(nonatomic,strong) NSOperationQueue *opq;


@end

@implementation ViewController

- (void)viewDidLoad{

    [super viewDidLoad];
    
    [self test1];
    
    [self test2];

}

- (void)test2{
    OQCreateBlockOperation *cop = [[OQCreateBlockOperation alloc] init];
    NSBlockOperation *op = [cop blockOperation];
    
    [self.opq addOperation:op];
}

- (void)test1{
    
    NSInvocationOperation *op = [[OQCreateInvocationOperation alloc] invocationOperationWithData:self userInput:nil];
    
//    [op start];
    [self.opq addOperation:op];
    
}






- (NSOperationQueue *)opq{

    if (_opq == nil) {
        _opq = [[NSOperationQueue alloc] init];
    }
    return _opq;
}

@end
