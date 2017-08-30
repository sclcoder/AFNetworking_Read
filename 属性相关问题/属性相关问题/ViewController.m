//
//  ViewController.m
//  属性相关问题
//
//  Created by 孙春磊 on 2017/8/30.
//  Copyright © 2017年 云积分. All rights reserved.
//

#import "ViewController.h"

#import "Person.h"
#import "Teacher.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
  

    Teacher *t = [[Teacher alloc] init];
    NSLog(@"%@",t.description);
    
    
    Person *p = [[Person alloc] init];
    NSLog(@"%@",p.description);

    
}



@end
